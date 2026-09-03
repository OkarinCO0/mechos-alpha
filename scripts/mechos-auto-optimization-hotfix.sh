#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log(){ printf '[MechOS Auto Optimization] %s\n' "$*"; }
fail(){ printf '[MechOS Auto Optimization] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Auto Optimization] ERROR line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ -d "$ROOT" ] || fail "ArchISO rootfs missing: $ROOT"
[ -s "$ARCHIVE" ] || fail "installed-system payload missing: $ARCHIVE"

patch_tree(){
  local tree="$1"
  local public="$tree/usr/local/bin/mechos-performance-center"
  local real="$public.real"
  local perf=""

  # Patch the implementation that actually owns Perf. Reference/UI wrapper
  # passes are free to leave both public and .real files behind.
  if [ -f "$public" ] && grep -Fq 'class Perf(' "$public"; then
    perf="$public"
  elif [ -f "$real" ] && grep -Fq 'class Perf(' "$real"; then
    perf="$real"
  else
    fail "final Performance Center implementation not found in $tree"
  fi

  log "patching hardware-aware profile backend: ${perf#$tree}"

  python3 - "$perf" <<'PY'
from pathlib import Path
import ast
import sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
marker='# MECHOS_PROFILE_BACKEND_V5'
if marker in text:
    raise SystemExit(0)

try:
    tree=ast.parse(text,str(path))
except SyntaxError as exc:
    raise SystemExit(f'[MechOS Auto Optimization] Performance Center is invalid before backend patch: {exc}')

profile_fn=None
for node in ast.walk(tree):
    if isinstance(node,(ast.FunctionDef,ast.AsyncFunctionDef)) and node.name=='set_profile':
        profile_fn=node
        break
if profile_fn is None or not hasattr(profile_fn,'end_lineno'):
    raise SystemExit('[MechOS Auto Optimization] set_profile backend not found in final Performance Center')

replacement=r'''# MECHOS_PROFILE_BACKEND_V5
def set_profile(profile, parent=None):
    """Set the requested profile without treating unsupported hardware as an error."""
    import re as _re
    import shutil as _shutil
    import subprocess as _sp
    from pathlib import Path as _Path
    from PyQt6.QtWidgets import QMessageBox as _QMessageBox

    requested=str(profile or '').strip() or 'balanced'
    notes=[]
    chosen=None
    virt=''
    try:
        virt=_sp.check_output(
            ['systemd-detect-virt'], text=True, stderr=_sp.DEVNULL, timeout=2
        ).strip()
    except Exception:
        virt=''
    virtual=bool(virt and virt != 'none')

    available=[]
    if _shutil.which('powerprofilesctl'):
        probe=_sp.run(['powerprofilesctl','list'], text=True, capture_output=True)
        if probe.returncode == 0:
            available=_re.findall(r'^\s*\*?\s*([a-z][a-z0-9-]+):', probe.stdout, _re.M)
        current=_sp.run(['powerprofilesctl','get'], text=True, capture_output=True)
        current_name=current.stdout.strip() if current.returncode == 0 else ''
        if current_name and current_name not in available:
            available.append(current_name)

        if requested == 'performance':
            candidates=(['balanced','power-saver'] if virtual else ['performance','balanced','power-saver'])
        else:
            candidates=[requested]
            for fallback in ['balanced','power-saver'] + ([] if virtual else ['performance']):
                if fallback not in candidates:
                    candidates.append(fallback)

        chosen=next((candidate for candidate in candidates if candidate in available),None)
        if chosen:
            result=_sp.run(['powerprofilesctl','set',chosen], text=True, capture_output=True)
            if result.returncode == 0:
                if chosen == requested:
                    notes.append(f'Power profile: {chosen}')
                else:
                    notes.append(f'Requested {requested}; using supported profile: {chosen}')
            else:
                detail=(result.stderr or result.stdout).strip()
                notes.append('Power profile unchanged' + (f' ({detail})' if detail else ''))
                chosen=None
        elif available:
            notes.append('No compatible requested profile; supported profiles: '+', '.join(available))
        else:
            notes.append('This hardware exposes no selectable power profiles')
    else:
        notes.append('Power profile control is unavailable on this hardware')

    if virtual:
        notes.append(f'VM-safe mode: {virt}; physical performance tuning skipped')
    notes.append('GameMode available' if _shutil.which('gamemoderun') else 'GameMode unavailable')
    notes.append('MangoHud available' if _shutil.which('mangohud') else 'MangoHud unavailable')

    try:
        state=_Path.home()/'.local/state/mechos'
        state.mkdir(parents=True,exist_ok=True)
        with (state/'auto-optimization.log').open('a',encoding='utf-8') as handle:
            handle.write(f'requested={requested} chosen={chosen or "unchanged"} virtual={virt or "none"}\n')
            handle.write('\n'.join(notes)+'\n---\n')
    except Exception:
        pass

    _QMessageBox.information(parent,'MechOS Performance','\n'.join(notes))
    return chosen
'''

lines=text.splitlines(keepends=True)
start=profile_fn.lineno-1
end=profile_fn.end_lineno
new_text=''.join(lines[:start])+replacement+'\n'+''.join(lines[end:])
compile(new_text,str(path),'exec')
path.write_text(new_text,encoding='utf-8')
PY

  chmod 755 "$perf"
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$perf" \
    || fail "Performance Center Python validation failed in $tree"
  grep -Fq '# MECHOS_PROFILE_BACKEND_V5' "$perf" || fail "hardware-aware profile backend marker missing"
  grep -Fq "def set_profile(profile, parent=None):" "$perf" || fail "hardware-aware set_profile signature missing"
  grep -Fq 'systemd-detect-virt' "$perf" || fail "VM detection missing from profile backend"
}

patch_tree "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xpf "$ARCHIVE" -C "$tmp"
patch_tree "$tmp"
replacement="$ARCHIVE.auto-opt"
tar --zstd -cpf "$replacement" -C "$tmp" .
mv -f "$replacement" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

log 'Performance Center profile backend is hardware-aware; Auto Optimization no longer depends on UI button rewriting'
