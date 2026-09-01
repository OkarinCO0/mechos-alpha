#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"

log() { printf '[MechOS Mode Switch] %s\n' "$*"; }
fail() { printf '[MechOS Mode Switch] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Mode Switch] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -s "$ARCHIVE" ] || fail "installed-system payload archive is missing: $ARCHIVE"

install_runtime() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local user_units="$tree/usr/lib/systemd/user"
  local autostart="$tree/etc/xdg/autostart"

  mkdir -p "$bin" "$user_units" "$autostart"

  cat > "$bin/mechos-gaming-layer" <<'LAYER_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

MODE_FILE="/tmp/mechos-next-mode-$(id -u)"
LOCK_DIR="/tmp/mechos-gaming-layer-$(id -u).lock"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG_FILE="$STATE_DIR/gaming-layer.log"
CREATOR_LOG="$STATE_DIR/creator-mode.log"
mkdir -p "$STATE_DIR"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  # A gaming layer is already running for this user.
  exit 0
fi
cleanup() {
  rm -rf "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM HUP

rm -f "$MODE_FILE"
printf '\n===== MechOS gaming layer %s =====\n' "$(date -Is)" >>"$LOG_FILE"
printf 'Session=%s Wayland=%s Display=%s\n' \
  "${XDG_SESSION_TYPE:-unknown}" "${WAYLAND_DISPLAY:-}" "${DISPLAY:-}" >>"$LOG_FILE"

run_mechscope() {
  local rc=0

  if command -v gamescope >/dev/null 2>&1 && [ "${MECHOS_DISABLE_GAMESCOPE:-0}" != "1" ]; then
    printf '[MechOS] Starting nested Gamescope + MechScope over the Plasma session.\n' >>"$LOG_FILE"
    set +e
    gamescope -e -f --mangoapp -- /usr/local/bin/mechscope >>"$LOG_FILE" 2>&1
    rc=$?
    set -e

    if [ "$rc" -eq 0 ]; then
      return 0
    fi

    printf '[MechOS] Gamescope exited rc=%s; falling back to fullscreen MechScope.\n' "$rc" >>"$LOG_FILE"
  fi

  set +e
  /usr/local/bin/mechscope >>"$LOG_FILE" 2>&1
  rc=$?
  set -e
  return "$rc"
}

set +e
run_mechscope
RC=$?
set -e

NEXT="$(cat "$MODE_FILE" 2>/dev/null || true)"
rm -f "$MODE_FILE"

case "$NEXT" in
  desktop)
    printf '[MechOS] Desktop requested; leaving the existing Plasma session running.\n' >>"$LOG_FILE"
    exit 0
    ;;
  creator)
    printf '[MechOS] Creator Mode requested inside the existing Plasma session.\n' >>"$LOG_FILE"
    if [ -x /usr/local/bin/mechos-creator-mode ]; then
      nohup /usr/local/bin/mechos-creator-mode >>"$CREATOR_LOG" 2>&1 </dev/null &
    fi
    exit 0
    ;;
  gaming|"")
    # A clean close without a mode request intentionally leaves the user on the
    # desktop. A crash is returned to systemd so Restart=on-failure can recover.
    if [ "$RC" -ne 0 ]; then
      exit "$RC"
    fi
    exit 0
    ;;
  *)
    printf '[MechOS] Unknown requested mode: %s\n' "$NEXT" >>"$LOG_FILE"
    exit 0
    ;;
esac
LAYER_EOF
  chmod 755 "$bin/mechos-gaming-layer"

  cat > "$bin/mechos-gaming-layer-control" <<'CONTROL_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

ACTION="${1:-status}"
UNIT="mechos-gaming-layer.service"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
mkdir -p "$STATE_DIR"

unit_available() {
  systemctl --user cat "$UNIT" >/dev/null 2>&1
}

fallback_stop() {
  pkill -TERM -u "$(id -u)" -f '/usr/local/bin/mechos-gaming-layer([[:space:]]|$)' 2>/dev/null || true
  pkill -TERM -u "$(id -u)" -f 'gamescope.*(/usr/local/bin/mechscope|mechscope)' 2>/dev/null || true
  pkill -TERM -u "$(id -u)" -f '/usr/local/bin/mechscope([[:space:]]|$)' 2>/dev/null || true
}

start_layer() {
  if unit_available; then
    systemctl --user start "$UNIT"
  else
    nohup /usr/local/bin/mechos-gaming-layer >>"$STATE_DIR/gaming-layer-launch.log" 2>&1 </dev/null &
  fi
}

stop_layer() {
  if unit_available; then
    systemctl --user stop "$UNIT" 2>/dev/null || true
  fi
  fallback_stop
  rm -f "/tmp/mechos-next-mode-$(id -u)"
}

case "$ACTION" in
  start|gaming|mechscope)
    start_layer
    ;;
  stop|desktop)
    stop_layer
    ;;
  restart)
    stop_layer
    start_layer
    ;;
  creator)
    stop_layer
    if [ -x /usr/local/bin/mechos-creator-mode ]; then
      nohup /usr/local/bin/mechos-creator-mode >>"$STATE_DIR/creator-mode.log" 2>&1 </dev/null &
    fi
    ;;
  status)
    if unit_available; then
      systemctl --user --no-pager --full status "$UNIT" || true
    else
      pgrep -af '/usr/local/bin/mechos-gaming-layer([[:space:]]|$)' || true
    fi
    ;;
  *)
    echo "Usage: mechos-gaming-layer-control {start|stop|restart|desktop|gaming|creator|status}" >&2
    exit 2
    ;;
esac
CONTROL_EOF
  chmod 755 "$bin/mechos-gaming-layer-control"

  cat > "$bin/mechos-gaming-layer-autostart" <<'AUTOSTART_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

# The Live ISO remains a desktop-first test environment.
if [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null; then
  exit 0
fi

# Only an installed, fully configured MechOS account should auto-enter MechScope.
[ -e /var/lib/mechos/installed ] || exit 0
[ -e /var/lib/mechos/oobe-complete ] || exit 0

# Let Plasma finish bringing up the user session/portals before Gamescope starts.
sleep 2
exec /usr/local/bin/mechos-gaming-layer-control start
AUTOSTART_EOF
  chmod 755 "$bin/mechos-gaming-layer-autostart"

  cat > "$user_units/mechos-gaming-layer.service" <<'UNIT_EOF'
[Unit]
Description=MechOS fullscreen gaming layer
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mechos-gaming-layer
Restart=on-failure
RestartSec=2
TimeoutStopSec=8
KillMode=control-group

[Install]
WantedBy=default.target
UNIT_EOF

  cat > "$autostart/mechos-gaming-layer.desktop" <<'DESKTOP_EOF'
[Desktop Entry]
Type=Application
Name=MechOS Gaming Layer
Comment=Open MechScope over the persistent Plasma session after login
Exec=/usr/local/bin/mechos-gaming-layer-autostart
OnlyShowIn=KDE;
X-KDE-autostart-after=panel
Terminal=false
NoDisplay=true
DESKTOP_EOF

  # Keep the public mode-switch commands, but make them control the nested
  # gaming layer instead of replacing or terminating the whole graphical login.
  cat > "$bin/mechos-session-select" <<'SELECT_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:-menu}"

choose_mode() {
  if command -v kdialog >/dev/null 2>&1; then
    kdialog --title "MechOS Mode Switcher" --menu "Choose a MechOS mode" \
      gaming "MechScope / Gaming Mode" \
      desktop "Desktop Mode" \
      creator "Creator Mode" \
      performance "Performance Center" 2>/dev/null || true
  else
    printf 'desktop\n'
  fi
}

if [ "$MODE" = "menu" ]; then
  MODE="$(choose_mode)"
  [ -n "$MODE" ] || exit 0
fi

case "$MODE" in
  gaming|mechscope)
    exec /usr/local/bin/mechos-gaming-layer-control start
    ;;
  desktop)
    exec /usr/local/bin/mechos-gaming-layer-control stop
    ;;
  creator)
    exec /usr/local/bin/mechos-gaming-layer-control creator
    ;;
  performance)
    exec /usr/local/bin/mechos-performance-center
    ;;
  *)
    echo "Usage: mechos-session-select {gaming|creator|desktop|performance|menu}" >&2
    exit 2
    ;;
esac
SELECT_EOF
  chmod 755 "$bin/mechos-session-select"

  cat > "$bin/mechos-return-to-mechscope" <<'RETURN_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

# Desktop -> MechScope is now an in-session operation. Do not log out, restart
# SDDM, or terminate the user's Plasma/Wayland session.
exec /usr/local/bin/mechos-gaming-layer-control start
RETURN_EOF
  chmod 755 "$bin/mechos-return-to-mechscope"

  # Compatibility session: selecting the old "MechOS Gaming Mode" entry now
  # starts a normal Plasma session. KDE autostart then adds the gaming layer.
  cat > "$bin/mechos-gaming-session" <<'SESSION_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

export MECHOS_MODE=desktop
if command -v startplasma-wayland >/dev/null 2>&1; then
  exec /usr/bin/startplasma-wayland
fi
if command -v startplasma-x11 >/dev/null 2>&1; then
  exec /usr/bin/startplasma-x11
fi
exec /usr/local/bin/mechscope
SESSION_EOF
  chmod 755 "$bin/mechos-gaming-session"
}

patch_session_handoff() {
  local tree="$1"

  # OOBE previously rewrote SDDM to a dedicated Gamescope/MechScope session.
  # Keep SDDM on Plasma and let the user-level gaming layer provide MechScope.
  if [ -d "$tree/etc/sddm.conf.d" ]; then
    while IFS= read -r -d '' file; do
      sed -i \
        -e 's/Session=mechos-gaming\.desktop/Session=plasma.desktop/g' \
        -e 's/Relogin=true/Relogin=false/g' \
        "$file"
    done < <(find "$tree/etc/sddm.conf.d" -type f -print0)
  fi

  for file in \
    "$tree/usr/local/libexec/mechos-oobe-apply" \
    "$tree/usr/local/bin/mechos-firstboot" \
    "$tree/usr/local/bin/mechos-postinstall"; do
    [ -f "$file" ] || continue
    sed -i \
      -e 's/Session=mechos-gaming\.desktop/Session=plasma.desktop/g' \
      -e 's/Relogin=true/Relogin=false/g' \
      "$file"
  done
}

patch_payload_target() {
  local target="$1"
  [ -f "$target" ] || return 0
  sed -i \
    -e 's/Session=mechos-gaming\.desktop/Session=plasma.desktop/g' \
    -e 's/Relogin=true/Relogin=false/g' \
    "$target"
}

validate_tree() {
  local tree="$1"

  for file in \
    "$tree/usr/local/bin/mechos-gaming-layer" \
    "$tree/usr/local/bin/mechos-gaming-layer-control" \
    "$tree/usr/local/bin/mechos-gaming-layer-autostart" \
    "$tree/usr/local/bin/mechos-session-select" \
    "$tree/usr/local/bin/mechos-return-to-mechscope" \
    "$tree/usr/local/bin/mechos-gaming-session"; do
    [ -f "$file" ] || fail "safe mode-switch runtime is missing: $file"
    bash -n "$file" || fail "shell syntax failed: $file"
  done

  [ -f "$tree/usr/lib/systemd/user/mechos-gaming-layer.service" ] \
    || fail "gaming-layer user service is missing"
  [ -f "$tree/etc/xdg/autostart/mechos-gaming-layer.desktop" ] \
    || fail "gaming-layer KDE autostart is missing"

  grep -Fq 'mechos-gaming-layer-control start' "$tree/usr/local/bin/mechos-return-to-mechscope" \
    || fail "Return to MechScope still uses a session logout"

  if [ -f "$tree/usr/local/libexec/mechos-oobe-apply" ]; then
    if grep -Fq 'Session=mechos-gaming.desktop' "$tree/usr/local/libexec/mechos-oobe-apply"; then
      fail "OOBE still hands off to the unsafe dedicated gaming session"
    fi
    grep -Fq 'Session=plasma.desktop' "$tree/usr/local/libexec/mechos-oobe-apply" \
      || fail "OOBE no longer has a Plasma session handoff"
  fi
}

# Patch the finished Live tree. Autostart intentionally does nothing on the
# Live ISO, but the runtime is present for testing and for installed payloads.
install_runtime "$ROOT"
patch_session_handoff "$ROOT"
patch_payload_target "$PAYLOAD/mechos-postinstall-target"
validate_tree "$ROOT"

# Patch the installed-system payload used by the graphical installer.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xf "$ARCHIVE" -C "$tmp"
install_runtime "$tmp"
patch_session_handoff "$tmp"
validate_tree "$tmp"

new_archive="$ARCHIVE.safe-mode-switch"
tar --zstd -cpf "$new_archive" -C "$tmp" .
mv -f "$new_archive" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

bash -n "$PAYLOAD/mechos-postinstall-target" \
  || fail "post-install target syntax failed after safe mode-switch patch"
if grep -Fq 'Session=mechos-gaming.desktop' "$PAYLOAD/mechos-postinstall-target"; then
  fail "post-install target still configures the unsafe dedicated gaming session"
fi

log "Desktop, Creator Mode and MechScope now switch inside one persistent Plasma session"
