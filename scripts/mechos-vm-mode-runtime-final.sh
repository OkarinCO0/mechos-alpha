#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log(){ printf '[MechOS VM Mode Runtime] %s\n' "$*"; }
fail(){ printf '[MechOS VM Mode Runtime] ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$ROOT" ] || fail "ArchISO rootfs missing"
[ -s "$ARCHIVE" ] || fail "installed-system payload missing"

install_runtime(){
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local units="$tree/usr/lib/systemd/user"
  local autostart="$tree/etc/xdg/autostart"
  mkdir -p "$bin" "$units" "$autostart"

  cat > "$bin/mechos-vm-mode-runtime" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:-boot}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
MODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mechos"
MODE_FILE="$MODE_DIR/session-mode"
LOG="$STATE_DIR/vm-mode-runtime.log"
mkdir -p "$STATE_DIR" "$MODE_DIR"

log(){ printf '[%s] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"; }

is_live(){
  [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null
}

virt="$(systemd-detect-virt 2>/dev/null || true)"
if [ -z "$virt" ] || [ "$virt" = "none" ]; then
  log "not a virtual machine; VM runtime declined mode=$MODE"
  exit 3
fi
if is_live; then
  log "Live ISO detected; installed VM mode runtime is disabled"
  exit 0
fi

export MECHOS_VM_MODE=1
export MECHOS_DISABLE_GAMESCOPE=1
export QT_OPENGL=software
export LIBGL_ALWAYS_SOFTWARE=1
export QT_QUICK_BACKEND=software
export QSG_RHI_BACKEND=software

wait_for_graphics(){
  local i
  for i in $(seq 1 40); do
    if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
      return 0
    fi
    if [ -n "${DISPLAY:-}" ]; then
      return 0
    fi
    sleep 0.25
  done
  log "graphical session did not become ready; wayland=${WAYLAND_DISPLAY:-} display=${DISPLAY:-}"
  return 1
}

import_graphics(){
  systemctl --user import-environment \
    DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS \
    XDG_SESSION_TYPE XDG_CURRENT_DESKTOP KDE_FULL_SESSION KDE_SESSION_VERSION \
    MECHOS_VM_MODE MECHOS_DISABLE_GAMESCOPE QT_OPENGL LIBGL_ALWAYS_SOFTWARE \
    QT_QUICK_BACKEND QSG_RHI_BACKEND >/dev/null 2>&1 || true
}

write_mode(){
  printf '%s\n' "$1" > "$MODE_FILE"
}

start_unit(){
  local unit="$1"
  systemctl --user reset-failed "$unit" >/dev/null 2>&1 || true
  systemctl --user start "$unit"
  local i
  for i in $(seq 1 30); do
    systemctl --user is-active --quiet "$unit" && return 0
    sleep 0.1
  done
  log "$unit failed to become active"
  systemctl --user status "$unit" --no-pager >>"$LOG" 2>&1 || true
  return 1
}

stop_unit_async(){
  local unit="$1"
  # This helper may be called from inside the service being stopped. Put the
  # delayed stop in a separate transient user unit so it survives that cgroup.
  local transient="mechos-vm-stop-${unit//./-}-$$"
  systemd-run --user --quiet --collect --unit="$transient" \
    /bin/sh -c "sleep 0.35; systemctl --user stop '$unit' >/dev/null 2>&1 || true" \
    >/dev/null 2>&1 || true
}

first_run_tutorial(){
  [ -e /var/lib/mechos/installed ] || return 0
  [ -e /var/lib/mechos/oobe-complete ] || return 0
  [ ! -e "$MODE_DIR/tutorial-v1-complete" ] || return 0
  [ -x /usr/local/bin/mechos-tutorial ] || return 0
  log "launching first-run tutorial before MechScope"
  /usr/local/bin/mechos-tutorial --mode all --first-run >>"$LOG" 2>&1 || true
}

run_mode(){
  local requested="$1"
  case "$requested" in
    start|gaming|mechscope)
      write_mode gaming
      first_run_tutorial
      if start_unit mechos-vm-mechscope.service; then
        stop_unit_async mechos-vm-creator.service
        log "MechScope active inside Plasma VM session"
        return 0
      fi
      return 1
      ;;
    creator)
      write_mode creator
      if start_unit mechos-vm-creator.service; then
        stop_unit_async mechos-vm-mechscope.service
        log "Creator Mode active inside Plasma VM session"
        return 0
      fi
      return 1
      ;;
    desktop)
      write_mode desktop
      stop_unit_async mechos-vm-mechscope.service
      stop_unit_async mechos-vm-creator.service
      log "Desktop Mode active; Plasma compositor retained"
      return 0
      ;;
    stop)
      stop_unit_async mechos-vm-mechscope.service
      stop_unit_async mechos-vm-creator.service
      log "VM fullscreen mode apps stopped"
      return 0
      ;;
    *)
      log "invalid mode: $requested"
      return 2
      ;;
  esac
}

wait_for_graphics || exit 4
import_graphics

if [ "$MODE" = "boot" ]; then
  MODE="gaming"
  if [ -r "$MODE_FILE" ]; then
    MODE="$(tr -d '[:space:]' < "$MODE_FILE")"
  fi
  case "$MODE" in gaming|creator|desktop) ;; *) MODE=gaming ;; esac
  log "Plasma autostart handoff virtualization=$virt remembered_mode=$MODE"
fi

run_mode "$MODE"
EOF
  chmod 755 "$bin/mechos-vm-mode-runtime"

  cat > "$units/mechos-vm-mechscope.service" <<'EOF'
[Unit]
Description=MechOS MechScope inside VM Plasma session
After=graphical-session.target

[Service]
Type=simple
Environment=MECHOS_VM_MODE=1
Environment=MECHOS_DISABLE_GAMESCOPE=1
Environment=QT_OPENGL=software
Environment=LIBGL_ALWAYS_SOFTWARE=1
Environment=QT_QUICK_BACKEND=software
Environment=QSG_RHI_BACKEND=software
ExecStart=/usr/local/bin/mechscope
Restart=no
TimeoutStopSec=5

[Install]
WantedBy=default.target
EOF

  cat > "$units/mechos-vm-creator.service" <<'EOF'
[Unit]
Description=MechOS Creator Mode inside VM Plasma session
After=graphical-session.target

[Service]
Type=simple
Environment=MECHOS_VM_MODE=1
Environment=MECHOS_DISABLE_GAMESCOPE=1
Environment=QT_OPENGL=software
Environment=LIBGL_ALWAYS_SOFTWARE=1
Environment=QT_QUICK_BACKEND=software
Environment=QSG_RHI_BACKEND=software
ExecStart=/usr/local/bin/mechos-creator-mode
Restart=no
TimeoutStopSec=5

[Install]
WantedBy=default.target
EOF

  cat > "$autostart/mechos-vm-mode-runtime.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS VM Mode Runtime
Comment=Start the selected MechOS fullscreen mode after Plasma/Wayland is ready in a virtual machine
Exec=/usr/local/bin/mechos-vm-mode-runtime boot
TryExec=/usr/local/bin/mechos-vm-mode-runtime
Terminal=false
NoDisplay=true
OnlyShowIn=KDE;
X-KDE-autostart-after=panel
EOF
}

patch_control(){
  local tree="$1"
  local control="$tree/usr/local/bin/mechos-gaming-layer-control"
  [ -f "$control" ] || fail "gaming layer control missing in $tree"
  python3 - "$control" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')
marker='# MECHOS_VM_MODE_RUNTIME_ROUTER_V1'
if marker in t:
    raise SystemExit(0)
lines=t.splitlines(True)
insert=1
if len(lines)>1 and lines[1].lstrip().startswith('set '):
    insert=2
block=r'''# MECHOS_VM_MODE_RUNTIME_ROUTER_V1
# VirtualBox/VMware/QEMU keep Plasma as the compositor. Route mode requests to
# the VM app handoff instead of starting/stopping the physical Gamescope layer.
_mechos_virt="$(systemd-detect-virt 2>/dev/null || true)"
if [ -n "$_mechos_virt" ] && [ "$_mechos_virt" != "none" ] && \
   [ ! -e /run/archiso/bootmnt ] && ! grep -q 'archiso' /proc/cmdline 2>/dev/null; then
  exec /usr/local/bin/mechos-vm-mode-runtime "${1:-start}"
fi

'''
lines.insert(insert,block)
p.write_text(''.join(lines),encoding='utf-8')
PY
  chmod 755 "$control"
  bash -n "$control" || fail "gaming control syntax failed after VM router patch"
}

patch_session(){
  local tree="$1"
  local session="$tree/usr/local/bin/mechscope-session"
  [ -f "$session" ] || fail "mechscope-session missing in $tree"
  python3 - "$session" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_VM_PLASMA_HOST_V2'
if marker in t:
    raise SystemExit(0)
pat=re.compile(r'''VIRT="\$\(systemd-detect-virt 2>/dev/null \|\| true\)"\nif \[\[ -n "\$VIRT" && "\$VIRT" != "none" \]\]; then\n.*?\n  start_plasma_mechscope\nfi''',re.S)
replacement=r'''VIRT="$(systemd-detect-virt 2>/dev/null || true)"
if [[ -n "$VIRT" && "$VIRT" != "none" ]]; then
  # MECHOS_VM_PLASMA_HOST_V2
  # Plasma owns the VM compositor. Do not launch MechScope before Wayland is
  # ready; KDE autostart invokes mechos-vm-mode-runtime after session startup.
  export MECHOS_VM_MODE=1
  export MECHOS_DISABLE_GAMESCOPE=1
  export QT_OPENGL=software
  export LIBGL_ALWAYS_SOFTWARE=1
  export QT_QUICK_BACKEND=software
  export QSG_RHI_BACKEND=software
  printf '[MechOS] virtualization=%s; Plasma hosts VM modes; waiting for graphical autostart.\n' "$VIRT" >>"$LOG_FILE"
  exec /usr/bin/startplasma-wayland
fi'''
new,n=pat.subn(replacement,t,count=1)
if n != 1:
    raise SystemExit('[MechOS VM Mode Runtime] VM session block not found')
p.write_text(new,encoding='utf-8')
PY
  chmod 755 "$session"
  bash -n "$session" || fail "mechscope-session syntax failed after VM host patch"
}

patch_tree(){
  local tree="$1"
  install_runtime "$tree"
  patch_control "$tree"
  patch_session "$tree"
}

patch_tree "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xpf "$ARCHIVE" -C "$tmp"
patch_tree "$tmp"
replacement="$ARCHIVE.vm-mode-runtime"
tar --zstd -cpf "$replacement" -C "$tmp" .
mv -f "$replacement" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

log 'VMs now keep Plasma as compositor; MechScope/Creator switch as fullscreen apps after graphical-session readiness; physical Gamescope behavior is preserved'
