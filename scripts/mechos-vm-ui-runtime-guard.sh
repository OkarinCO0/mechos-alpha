#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
BIN="$ROOT/usr/local/bin"
LIBEXEC="$ROOT/usr/local/libexec"
PROFILE="/workspace/archlive/profiledef.sh"

log() { printf '[MechOS VM UI Guard] %s\n' "$*"; }
fail() { printf '[MechOS VM UI Guard] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS VM UI Guard] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

mkdir -p "$LIBEXEC"

wrap_ui() {
  local public="$1"
  local real="$2"
  local label="$3"
  local logfile="$4"

  [ -x "$public" ] || fail "$label executable is missing: $public"

  if grep -Fq '# MECHOS_VM_UI_RUNTIME_GUARD_V1' "$public" 2>/dev/null; then
    log "$label is already VM guarded"
    return 0
  fi

  mv -f "$public" "$real"
  chmod 755 "$real"

  cat > "$public" <<WRAPPER
#!/usr/bin/env bash
# MECHOS_VM_UI_RUNTIME_GUARD_V1
set -Eeuo pipefail

REAL="$real"
STATE_DIR="\${XDG_STATE_HOME:-\$HOME/.local/state}/mechos"
LOG="\$STATE_DIR/$logfile"
mkdir -p "\$STATE_DIR"

virt=""
if command -v systemd-detect-virt >/dev/null 2>&1; then
  virt="\$(systemd-detect-virt 2>/dev/null || true)"
fi

{
  printf '\n===== $label %s =====\n' "\$(date -Is 2>/dev/null || date)"
  printf 'virt=%s session=%s desktop=%s wayland=%s display=%s\n' \
    "\${virt:-none}" "\${XDG_SESSION_TYPE:-unknown}" "\${XDG_CURRENT_DESKTOP:-unknown}" \
    "\${WAYLAND_DISPLAY:-}" "\${DISPLAY:-}"

  if [ -n "\$virt" ] && [ "\$virt" != "none" ]; then
    # QWidget-based MechOS surfaces do not need accelerated Qt rendering in a
    # VM. VirtualBox/VMware/QEMU graphics stacks have repeatedly crashed or
    # stalled compositor/UI startup, so use the same safe path as the Live
    # installer while preserving normal acceleration on physical hardware.
    export MECHOS_VM_MODE=1
    export MECHOS_DISABLE_GAMESCOPE=1
    export QT_OPENGL=software
    export LIBGL_ALWAYS_SOFTWARE=1
    export QT_QUICK_BACKEND=software
    export QSG_RHI_BACKEND=software
    printf 'VM-safe UI rendering enabled.\n'
  fi

  export PYTHONFAULTHANDLER=1
  exec "\$REAL" "\$@"
} >>"\$LOG" 2>&1
WRAPPER

  chmod 755 "$public"
  bash -n "$public" || fail "$label VM wrapper shell syntax failed"
  grep -Fq '# MECHOS_VM_UI_RUNTIME_GUARD_V1' "$public" || fail "$label VM guard marker missing"
  [ -x "$real" ] || fail "$label real executable was not preserved"
}

# Reference v5 post-install staging materializes Creator Mode temporarily before
# this guard runs, so both applications can be wrapped here and then Creator
# Mode is captured back into the installed payload by the normal v5 commit step.
wrap_ui "$BIN/mechscope" "$LIBEXEC/mechscope-vm-real" "MechScope 2.0" "mechscope-vm.log"
wrap_ui "$BIN/mechos-creator-mode" "$LIBEXEC/mechos-creator-mode-vm-real" "Creator Mode" "creator-mode-vm.log"

# Strengthen the gaming-layer VM detector. Older versions relied on DMI/PCI
# strings only. systemd-detect-virt is already available on MechOS and is the
# most reliable first test in VirtualBox, VMware and QEMU/KVM guests.
LAYER="$BIN/mechos-gaming-layer"
if [ -f "$LAYER" ] && grep -Fq 'is_virtual_gpu_environment() {' "$LAYER"; then
  python3 - "$LAYER" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')
marker='# MECHOS_VM_SYSTEMD_DETECT_VIRT_V1'
if marker not in t:
    needle='is_virtual_gpu_environment() {\n'
    insert='''is_virtual_gpu_environment() {\n  # MECHOS_VM_SYSTEMD_DETECT_VIRT_V1\n  local virt\n  virt="$(systemd-detect-virt 2>/dev/null || true)"\n  if [ -n "$virt" ] && [ "$virt" != "none" ]; then\n    printf '[MechOS] Virtual machine detected by systemd-detect-virt: %s\\n' "$virt" >>"$LOG_FILE"\n    return 0\n  fi\n'''
    if needle not in t:
        raise SystemExit('[MechOS VM UI Guard] gaming-layer VM detector function not found')
    t=t.replace(needle,insert,1)
    p.write_text(t,encoding='utf-8')
PY
  chmod 755 "$LAYER"
  bash -n "$LAYER" || fail "gaming layer failed syntax after VM detector hardening"
  grep -Fq '# MECHOS_VM_SYSTEMD_DETECT_VIRT_V1' "$LAYER" || fail "systemd VM detection was not added to gaming layer"
  grep -Fq 'run_direct_mechscope' "$LAYER" || fail "gaming layer has no direct MechScope fallback"
fi

# Creator Mode is a user service on installed systems. Keep the service pointed
# at the public wrapper so it automatically receives the VM-safe environment.
CREATOR_UNIT="$ROOT/usr/lib/systemd/user/mechos-creator-mode.service"
if [ -f "$CREATOR_UNIT" ]; then
  grep -Fq 'ExecStart=/usr/local/bin/mechos-creator-mode' "$CREATOR_UNIT" \
    || fail "Creator Mode service no longer launches the guarded public entrypoint"
fi

if [ -f "$PROFILE" ]; then
  for path in \
    /usr/local/bin/mechscope \
    /usr/local/libexec/mechscope-vm-real \
    /usr/local/bin/mechos-creator-mode \
    /usr/local/libexec/mechos-creator-mode-vm-real; do
    if ! grep -Fq "file_permissions[\"$path\"]" "$PROFILE"; then
      printf '\nfile_permissions["%s"]="0:0:755"\n' "$path" >> "$PROFILE"
    fi
  done
fi

log "MechScope and Creator Mode now use VM-safe Qt rendering in virtual machines while physical hardware keeps the normal accelerated path"
