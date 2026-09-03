#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
PROFILE="/workspace/archlive/profiledef.sh"
POSTINSTALL="$ROOT/usr/share/mechos/install-payload/mechos-postinstall-target"

log() { printf '[MechOS VM Shortcut Launch] %s\n' "$*"; }
fail() { printf '[MechOS VM Shortcut Launch] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS VM Shortcut Launch] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ -d "$ROOT" ] || fail "ArchISO rootfs is missing"
[ -s "$ARCHIVE" ] || fail "installed-system payload is missing"

install_helper() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  mkdir -p "$bin"

  cat > "$bin/mechos-mode-launch" <<'LAUNCH_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:-}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG="$STATE_DIR/mode-shortcut.log"
mkdir -p "$STATE_DIR"

log() {
  printf '[%s] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"
}

notify_error() {
  local message="$1"
  log "ERROR: $message"
  if command -v kdialog >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    kdialog --title "MechOS Mode Launcher" --error "$message\n\nLog: $LOG" >/dev/null 2>&1 || true
  fi
}

case "$MODE" in
  gaming|mechscope|creator|desktop) ;;
  *)
    echo "Usage: mechos-mode-launch {gaming|mechscope|creator|desktop}" >&2
    exit 2
    ;;
esac

virt="$(systemd-detect-virt 2>/dev/null || true)"
if [ -n "$virt" ] && [ "$virt" != "none" ]; then
  export MECHOS_VM_MODE=1
  export MECHOS_DISABLE_GAMESCOPE=1
  export QT_OPENGL=software
  export LIBGL_ALWAYS_SOFTWARE=1
  export QT_QUICK_BACKEND=software
  export QSG_RHI_BACKEND=software
  log "virtualization=$virt; Gamescope disabled; software Qt rendering enabled"
else
  log "physical/non-virtual session; normal accelerated runtime preserved"
fi

log "mode=$MODE session=${XDG_SESSION_TYPE:-unknown} wayland=${WAYLAND_DISPLAY:-} display=${DISPLAY:-}"

if systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user import-environment \
    DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS \
    XDG_SESSION_TYPE XDG_CURRENT_DESKTOP KDE_FULL_SESSION KDE_SESSION_VERSION \
    MECHOS_VM_MODE MECHOS_DISABLE_GAMESCOPE QT_OPENGL LIBGL_ALWAYS_SOFTWARE \
    QT_QUICK_BACKEND QSG_RHI_BACKEND >/dev/null 2>&1 || true
  log "graphical environment imported into systemd --user"
else
  log "systemd --user unavailable; controller fallback will be used"
fi

CONTROL=/usr/local/bin/mechos-gaming-layer-control
if [ ! -x "$CONTROL" ]; then
  notify_error "MechOS mode controller is missing."
  exit 1
fi

case "$MODE" in
  gaming|mechscope)
    if "$CONTROL" start >>"$LOG" 2>&1; then
      log "MechScope launch request accepted"
      exit 0
    fi
    notify_error "MechScope could not be started."
    exit 1
    ;;
  creator)
    if [ ! -x /usr/local/bin/mechos-creator-mode ]; then
      notify_error "Creator Mode is not installed in this environment."
      exit 1
    fi
    if "$CONTROL" creator >>"$LOG" 2>&1; then
      log "Creator Mode launch request accepted"
      exit 0
    fi
    notify_error "Creator Mode could not be started."
    exit 1
    ;;
  desktop)
    if "$CONTROL" desktop >>"$LOG" 2>&1; then
      log "Desktop Mode request accepted"
      exit 0
    fi
    notify_error "Desktop Mode could not be restored."
    exit 1
    ;;
esac
LAUNCH_EOF
  chmod 755 "$bin/mechos-mode-launch"
  bash -n "$bin/mechos-mode-launch" || fail "mode launcher shell syntax failed in $tree"
}

purge_legacy_shortcuts() {
  local tree="$1"
  local d f
  for d in \
    "$tree/usr/share/applications" \
    "$tree/etc/skel/Desktop" \
    "$tree/home/mechos/Desktop"
  do
    [ -d "$d" ] || continue
    while IFS= read -r -d '' f; do
      if grep -Eq '^Exec=/usr/local/bin/(mechos-return-to-mechscope|mechscope|mechos-creator-mode)([[:space:]]|$)' "$f" 2>/dev/null; then
        rm -f "$f"
      fi
    done < <(find "$d" -maxdepth 1 -type f -name '*.desktop' -print0 2>/dev/null)
  done

  # Known legacy names from older builds. Removing by name as well prevents a
  # stale desktop file with an edited Exec line from surviving an upgrade.
  rm -f \
    "$tree/usr/share/applications/mechos-return-to-mechscope.desktop" \
    "$tree/usr/share/applications/mechscope.desktop" \
    "$tree/usr/share/applications/mechos-gaming.desktop" \
    "$tree/etc/skel/Desktop/MechScope.desktop" \
    "$tree/etc/skel/Desktop/Gaming-Mode.desktop" \
    "$tree/home/mechos/Desktop/MechScope.desktop" \
    "$tree/home/mechos/Desktop/Gaming-Mode.desktop" 2>/dev/null || true
}

write_gaming_shortcut() {
  local apps="$1"
  cat > "$apps/mechos-return-gaming.desktop" <<'GAMING_DESKTOP'
[Desktop Entry]
Type=Application
Name=Return to MechScope
Comment=Open MechScope / Gaming Mode using the current VM-safe MechOS launcher
Exec=/usr/local/bin/mechos-mode-launch gaming
TryExec=/usr/local/bin/mechos-mode-launch
Icon=applications-games
Terminal=false
StartupNotify=true
Categories=Game;System;
GAMING_DESKTOP
  chmod 644 "$apps/mechos-return-gaming.desktop"
}

write_creator_shortcut() {
  local apps="$1"
  cat > "$apps/mechos-creator-mode.desktop" <<'CREATOR_DESKTOP'
[Desktop Entry]
Type=Application
Name=MechOS Creator Mode
Comment=Open the MechOS creator workstation using the current VM-safe launcher
Exec=/usr/local/bin/mechos-mode-launch creator
TryExec=/usr/local/bin/mechos-mode-launch
Icon=applications-graphics
Terminal=false
StartupNotify=true
Categories=Graphics;AudioVideo;Development;
Keywords=MechOS;Creator;Blender;Unity;Unreal;VRChat;MechClip;
CREATOR_DESKTOP
  chmod 644 "$apps/mechos-creator-mode.desktop"
}

install_shortcuts() {
  local tree="$1"
  local installed="$2"
  local apps="$tree/usr/share/applications"
  local skel="$tree/etc/skel/Desktop"
  mkdir -p "$apps"

  purge_legacy_shortcuts "$tree"
  write_gaming_shortcut "$apps"

  if [ "$installed" = "yes" ]; then
    write_creator_shortcut "$apps"
    mkdir -p "$skel"
    cp -f "$apps/mechos-creator-mode.desktop" "$skel/Creator-Mode.desktop"
    cp -f "$apps/mechos-return-gaming.desktop" "$skel/Return-to-MechScope.desktop"
    chmod 755 "$skel/Creator-Mode.desktop" "$skel/Return-to-MechScope.desktop"
  else
    rm -f \
      "$apps/mechos-creator-mode.desktop" \
      "$tree/etc/skel/Desktop/Creator-Mode.desktop" \
      "$tree/home/mechos/Desktop/Creator-Mode.desktop" 2>/dev/null || true
  fi
}

patch_postinstall_shortcuts() {
  [ -f "$POSTINSTALL" ] || return 0
  python3 - "$POSTINSTALL" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')
t=t.replace('/usr/share/applications/mechos-return-to-mechscope.desktop',
            '/usr/share/applications/mechos-return-gaming.desktop')
needle='cp -f /usr/share/applications/mechos-return-gaming.desktop \\\n  "$HOME_DIR/Desktop/Return-to-MechScope.desktop" 2>/dev/null || true\n'
creator='cp -f /usr/share/applications/mechos-creator-mode.desktop \\\n  "$HOME_DIR/Desktop/Creator-Mode.desktop" 2>/dev/null || true\n'
if needle in t and creator not in t:
    t=t.replace(needle, needle+creator)
p.write_text(t,encoding='utf-8')
PY
  bash -n "$POSTINSTALL" || fail "post-install target syntax failed after shortcut cleanup"
}

validate_tree() {
  local tree="$1"
  local installed="$2"
  local launch="$tree/usr/local/bin/mechos-mode-launch"
  local creator="$tree/usr/share/applications/mechos-creator-mode.desktop"
  local gaming="$tree/usr/share/applications/mechos-return-gaming.desktop"

  [ -x "$launch" ] || fail "mode launcher missing in $tree"
  bash -n "$launch" || fail "mode launcher invalid in $tree"
  grep -Fq 'systemd-detect-virt' "$launch" || fail "VM detection missing in launcher"
  grep -Fq 'export MECHOS_DISABLE_GAMESCOPE=1' "$launch" || fail "VM Gamescope bypass missing"
  grep -Fq 'systemctl --user import-environment' "$launch" || fail "graphical environment handoff missing"
  grep -Fq 'mechos-gaming-layer-control' "$launch" || fail "mode controller handoff missing"
  grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch gaming' "$gaming" || fail "MechScope shortcut bypasses shared launcher"

  [ ! -e "$tree/usr/share/applications/mechos-return-to-mechscope.desktop" ] || fail "legacy return shortcut still present"
  [ ! -e "$tree/usr/share/applications/mechscope.desktop" ] || fail "legacy direct MechScope shortcut still present"

  if [ "$installed" = "yes" ]; then
    grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch creator' "$creator" || fail "Creator shortcut bypasses shared launcher"
    [ -x "$tree/etc/skel/Desktop/Creator-Mode.desktop" ] || fail "installed Creator desktop shortcut missing"
    [ -x "$tree/etc/skel/Desktop/Return-to-MechScope.desktop" ] || fail "installed MechScope desktop shortcut missing"
    grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch creator' "$tree/etc/skel/Desktop/Creator-Mode.desktop" || fail "installed Creator desktop copy is legacy"
    grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch gaming' "$tree/etc/skel/Desktop/Return-to-MechScope.desktop" || fail "installed MechScope desktop copy is legacy"
  else
    [ ! -e "$creator" ] || fail "Creator shortcut leaked back into Live"
  fi
}

install_helper "$ROOT"
install_shortcuts "$ROOT" no
patch_postinstall_shortcuts
validate_tree "$ROOT" no

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xpf "$ARCHIVE" -C "$tmp"
install_helper "$tmp"
install_shortcuts "$tmp" yes
validate_tree "$tmp" yes
replacement="$ARCHIVE.vm-shortcuts"
tar --zstd -cpf "$replacement" -C "$tmp" .
mv -f "$replacement" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

if [ -f "$PROFILE" ]; then
  if ! grep -Fq 'file_permissions["/usr/local/bin/mechos-mode-launch"]' "$PROFILE"; then
    printf '\nfile_permissions["/usr/local/bin/mechos-mode-launch"]="0:0:755"\n' >> "$PROFILE"
  fi
fi

log "Only the newest VM-safe MechScope and Creator Mode shortcuts remain; legacy direct launchers were removed"
