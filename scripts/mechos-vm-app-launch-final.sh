#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log(){ printf '[MechOS VM App Launch] %s\n' "$*"; }
fail(){ printf '[MechOS VM App Launch] ERROR: %s\n' "$*" >&2; exit 1; }

patch_runtime(){
  local tree="$1"
  local runtime="$tree/usr/local/bin/mechos-vm-mode-runtime"
  [ -f "$runtime" ] || fail "VM mode runtime missing in $tree"
  python3 - "$runtime" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_VM_DIRECT_APP_FALLBACK_V1'
if marker in t:
    raise SystemExit(0)
needle='''stop_unit_async(){\n'''
pos=t.find(needle)
if pos < 0:
    raise SystemExit('[MechOS VM App Launch] stop-unit anchor missing')
block=r'''# MECHOS_VM_DIRECT_APP_FALLBACK_V1
start_mode_app(){
  local unit="$1"
  local executable="$2"
  local label="$3"

  if start_unit "$unit"; then
    log "$label started through systemd --user"
    return 0
  fi

  [ -x "$executable" ] || {
    log "$label executable missing: $executable"
    return 1
  }

  log "$label user service failed; trying direct graphical-session fallback"
  systemctl --user import-environment \
    DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS \
    XDG_SESSION_TYPE XDG_CURRENT_DESKTOP KDE_FULL_SESSION KDE_SESSION_VERSION \
    MECHOS_VM_MODE MECHOS_DISABLE_GAMESCOPE QT_OPENGL LIBGL_ALWAYS_SOFTWARE \
    QT_QUICK_BACKEND QSG_RHI_BACKEND >/dev/null 2>&1 || true

  nohup "$executable" >>"$LOG" 2>&1 </dev/null &
  local pid=$!
  sleep 1
  if kill -0 "$pid" >/dev/null 2>&1; then
    log "$label direct fallback active pid=$pid"
    return 0
  fi
  wait "$pid" >/dev/null 2>&1 || true
  log "$label direct fallback exited immediately"
  return 1
}

'''
t=t[:pos]+block+t[pos:]
t=t.replace('if start_unit mechos-vm-mechscope.service; then',
            'if start_mode_app mechos-vm-mechscope.service /usr/local/bin/mechscope "MechScope"; then')
t=t.replace('if start_unit mechos-vm-creator.service; then',
            'if start_mode_app mechos-vm-creator.service /usr/local/bin/mechos-creator-mode "Creator Mode"; then')
p.write_text(t,encoding='utf-8')
PY
  chmod 0755 "$runtime"
  bash -n "$runtime" || fail "VM runtime syntax failed after direct fallback patch"
  grep -Fq 'MECHOS_VM_DIRECT_APP_FALLBACK_V1' "$runtime" || fail "direct app fallback marker missing"
  grep -Fq 'nohup "$executable"' "$runtime" || fail "direct app launch fallback missing"
  grep -Fq 'start_mode_app mechos-vm-mechscope.service' "$runtime" || fail "MechScope does not use fallback launcher"
  grep -Fq 'start_mode_app mechos-vm-creator.service' "$runtime" || fail "Creator Mode does not use fallback launcher"
}

patch_runtime "$ROOT"
if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xpf "$ARCHIVE" -C "$tmp"
  patch_runtime "$tmp"
  replacement="$ARCHIVE.vm-app-launch"
  tar --zstd -cpf "$replacement" -C "$tmp" .
  mv -f "$replacement" "$ARCHIVE"
  rm -rf "$tmp"; trap - EXIT
fi

log 'VM MechScope and Creator Mode now fall back to direct Plasma-session launch if their user service fails'
