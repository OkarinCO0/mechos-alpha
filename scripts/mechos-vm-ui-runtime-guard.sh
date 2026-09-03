#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log() { printf '[MechOS VM UI Guard] %s\n' "$*"; }
fail() { printf '[MechOS VM UI Guard] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS VM UI Guard] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ -d "$ROOT" ] || fail "ArchISO rootfs is missing"
[ -s "$ARCHIVE" ] || fail "installed payload is missing"

patch_python_ui() {
  local public="$1"
  local label="$2"
  local file="$public"
  [ -f "$public.real" ] && file="$public.real"
  [ -f "$file" ] || fail "$label implementation is missing: $file"

  python3 - "$file" "$label" <<'PY'
from pathlib import Path
import sys

path=Path(sys.argv[1]); label=sys.argv[2]
text=path.read_text(encoding='utf-8')
marker='# MECHOS_VM_UI_RUNTIME_GUARD_V2'
if marker not in text:
    candidates=['app = QApplication(', 'app=QApplication(']
    positions=[text.find(x) for x in candidates if text.find(x) >= 0]
    if not positions:
        raise SystemExit(f'[MechOS VM UI Guard] QApplication startup not found in {path}')
    pos=min(positions)
    block=r'''# MECHOS_VM_UI_RUNTIME_GUARD_V2
# Keep the exact same MechOS UI in VMs, but avoid virtual-GPU Qt/GL stalls.
def _mechos_vm_safe_runtime():
    import os as _os
    import subprocess as _sp
    from pathlib import Path as _Path
    try:
        _virt=_sp.check_output(['systemd-detect-virt'],text=True,stderr=_sp.DEVNULL,timeout=2).strip()
    except Exception:
        _virt=''
    if _virt and _virt != 'none':
        _os.environ['MECHOS_VM_MODE']='1'
        _os.environ['MECHOS_DISABLE_GAMESCOPE']='1'
        _os.environ['QT_OPENGL']='software'
        _os.environ['LIBGL_ALWAYS_SOFTWARE']='1'
        _os.environ['QT_QUICK_BACKEND']='software'
        _os.environ['QSG_RHI_BACKEND']='software'
        try:
            _state=_Path(_os.environ.get('XDG_STATE_HOME',str(_Path.home()/'.local/state')))/'mechos'
            _state.mkdir(parents=True,exist_ok=True)
            with (_state/'vm-ui.log').open('a',encoding='utf-8') as _f:
                _f.write(f'{__file__}: virtualization={_virt}; VM-safe Qt rendering enabled\n')
        except Exception:
            pass
_mechos_vm_safe_runtime()

'''
    text=text[:pos]+block+text[pos:]
compile(text,str(path),'exec')
path.write_text(text,encoding='utf-8')
PY

  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$file" \
    || fail "$label failed Python validation after VM runtime patch"
  grep -Fq '# MECHOS_VM_UI_RUNTIME_GUARD_V2' "$file" \
    || fail "$label VM runtime marker is missing"
}

patch_mode_runtime() {
  local tree="$1"
  local layer="$tree/usr/local/bin/mechos-gaming-layer"
  local control="$tree/usr/local/bin/mechos-gaming-layer-control"

  if [ -f "$layer" ] && grep -Fq 'is_virtual_gpu_environment() {' "$layer"; then
    python3 - "$layer" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_VM_SYSTEMD_DETECT_VIRT_V2'
if marker not in t:
    needle='is_virtual_gpu_environment() {\n'
    insert='''is_virtual_gpu_environment() {\n  # MECHOS_VM_SYSTEMD_DETECT_VIRT_V2\n  local virt\n  virt="$(systemd-detect-virt 2>/dev/null || true)"\n  if [ -n "$virt" ] && [ "$virt" != "none" ]; then\n    printf '[MechOS] Virtual machine detected by systemd-detect-virt: %s\\n' "$virt" >>"$LOG_FILE"\n    return 0\n  fi\n'''
    if needle not in t:
        raise SystemExit('[MechOS VM UI Guard] VM detector function not found')
    t=t.replace(needle,insert,1)

# Before Creator Mode is started as a user service, push the active Plasma
# display/session environment into the systemd user manager. This matters in
# VM fallback sessions where the graphical environment was created after the
# user manager itself started.
start='systemctl --user start --no-block mechos-creator-mode.service'
if start in t and 'MECHOS_CREATOR_GRAPHICAL_ENV_V1' not in t:
    repl='''# MECHOS_CREATOR_GRAPHICAL_ENV_V1\n        systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XDG_SESSION_TYPE XDG_CURRENT_DESKTOP >/dev/null 2>&1 || true\n        '''+start
    t=t.replace(start,repl)
p.write_text(t,encoding='utf-8')
PY
    chmod 755 "$layer"
    bash -n "$layer" || fail "gaming layer syntax failed after VM patch"
    grep -Fq '# MECHOS_VM_SYSTEMD_DETECT_VIRT_V2' "$layer" \
      || fail "gaming layer lacks systemd VM detection"
    grep -Fq 'run_direct_mechscope' "$layer" \
      || fail "gaming layer has no direct MechScope fallback"
  fi

  if [ -f "$control" ]; then
    python3 - "$control" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
start='systemctl --user start --no-block mechos-creator-mode.service'
if start in t and 'MECHOS_CREATOR_GRAPHICAL_ENV_V1' not in t:
    repl='''# MECHOS_CREATOR_GRAPHICAL_ENV_V1\n      systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XDG_SESSION_TYPE XDG_CURRENT_DESKTOP >/dev/null 2>&1 || true\n      '''+start
    t=t.replace(start,repl)
p.write_text(t,encoding='utf-8')
PY
    chmod 755 "$control"
    bash -n "$control" || fail "gaming layer control syntax failed after Creator VM patch"
  fi
}

# The v5 post-install staging step has already materialized Creator Mode here.
# Patch the actual Python implementations in place so Creator remains
# post-install-only and no extra Live launcher is introduced.
patch_python_ui "$ROOT/usr/local/bin/mechscope" "MechScope 2.0"
patch_python_ui "$ROOT/usr/local/bin/mechos-creator-mode" "Creator Mode"
patch_mode_runtime "$ROOT"

# The gaming-layer/control files are not post-install-only UI surfaces, so make
# the VM detector + graphical-environment fix directly in the installed payload
# as well. The later final payload rebuild preserves these changes.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xpf "$ARCHIVE" -C "$tmp"
patch_mode_runtime "$tmp"
replacement="$ARCHIVE.vm-ui"
tar --zstd -cpf "$replacement" -C "$tmp" .
mv -f "$replacement" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

# Creator Mode's installed user service must continue launching the public
# entrypoint; the VM-safe code is inside its real Python implementation.
CREATOR_UNIT="$ROOT/usr/lib/systemd/user/mechos-creator-mode.service"
if [ -f "$CREATOR_UNIT" ]; then
  grep -Fq 'ExecStart=/usr/local/bin/mechos-creator-mode' "$CREATOR_UNIT" \
    || fail "Creator Mode service entrypoint is invalid"
fi

log "VM startup hardened: Gamescope bypass detection, MechScope safe Qt path, Creator safe Qt path and graphical session environment handoff are installed"
