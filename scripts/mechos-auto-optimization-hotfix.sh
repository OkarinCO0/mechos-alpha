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
  local perf="$tree/usr/local/bin/mechos-performance-center"
  [ -f "$perf" ] || fail "Performance Center missing from $tree"

  python3 - "$perf" <<'PY'
from pathlib import Path
import sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
marker='# MECHOS_AUTO_OPTIMIZATION_V2'
if marker in text:
    raise SystemExit(0)

cls=text.find('class Perf(QMainWindow):')
if cls < 0:
    raise SystemExit('[MechOS Auto Optimization] Perf class not found')

helper=r'''# MECHOS_AUTO_OPTIMIZATION_V2
def mechos_auto_optimize(parent):
    """Apply the best safe runtime profile exposed by the current hardware.

    Virtual machines normally do not expose physical CPU platform profiles, so
    requesting `performance` unconditionally is an expected failure there. This
    routine chooses a supported profile, records skipped capabilities, and never
    turns normal hardware limitations into an error popup.
    """
    import re as _re
    from pathlib import Path as _Path

    notes=[]
    chosen=None
    virt=''
    try:
        virt=subprocess.check_output(
            ['systemd-detect-virt'], text=True, stderr=subprocess.DEVNULL, timeout=2
        ).strip()
    except Exception:
        virt=''
    virtual=bool(virt and virt != 'none')

    available=[]
    if shutil.which('powerprofilesctl'):
        probe=subprocess.run(['powerprofilesctl','list'], text=True, capture_output=True)
        if probe.returncode == 0:
            available=_re.findall(r'^\\s*\\*?\\s*([a-z][a-z0-9-]+):', probe.stdout, _re.M)
        # Some versions/backends expose get/set correctly even when list is
        # sparse. Preserve the current profile as a fallback candidate.
        current=subprocess.run(['powerprofilesctl','get'], text=True, capture_output=True)
        current_name=current.stdout.strip() if current.returncode == 0 else ''
        if current_name and current_name not in available:
            available.append(current_name)

        candidates=['balanced','power-saver'] if virtual else ['performance','balanced','power-saver']
        chosen=next((p for p in candidates if p in available), None)
        if chosen:
            result=subprocess.run(['powerprofilesctl','set',chosen], text=True, capture_output=True)
            if result.returncode == 0:
                notes.append(f'Power profile: {chosen}')
            else:
                detail=(result.stderr or result.stdout).strip()
                notes.append('Power profile unchanged' + (f' ({detail})' if detail else ''))
                chosen=None
        elif available:
            notes.append('Power profile unchanged; supported profiles: '+', '.join(available))
        else:
            notes.append('Power profile control is present, but this hardware exposes no selectable profiles')
    else:
        notes.append('Power profile control is unavailable on this hardware')

    if virtual:
        notes.append(f'VM-safe optimization enabled ({virt}); physical CPU/GPU power tuning skipped')
    else:
        notes.append('Physical hardware detected; best supported MechOS power profile selected')

    notes.append('GameMode: available for game launches' if shutil.which('gamemoderun') else 'GameMode: not installed')
    notes.append('MangoHud: available for performance monitoring' if shutil.which('mangohud') else 'MangoHud: not installed')

    try:
        state=_Path.home()/'.local/state/mechos'
        state.mkdir(parents=True, exist_ok=True)
        with (state/'auto-optimization.log').open('a', encoding='utf-8') as f:
            f.write('\\n'.join(notes)+'\\n---\\n')
    except Exception:
        pass

    title='MechOS Auto Optimization'
    message='Optimization completed with hardware-aware settings.\\n\\n'+'\\n'.join('• '+n for n in notes)
    QMessageBox.information(parent,title,message)
    return chosen

'''
text=text[:cls]+helper+text[cls:]

old="self.action('Auto Optimization','Use MechOS performance profile',lambda:set_profile('performance',self))"
new="self.action('Auto Optimization','Choose the best profile for this hardware',lambda:mechos_auto_optimize(self))"
if old not in text:
    raise SystemExit('[MechOS Auto Optimization] Auto Optimization action not found')
text=text.replace(old,new,1)

old2="self.action('Optimize Now','Set gaming performance profile',lambda:set_profile('performance',self))"
new2="self.action('Optimize Now','Apply hardware-aware gaming settings',lambda:mechos_auto_optimize(self))"
if old2 in text:
    text=text.replace(old2,new2,1)

compile(text,str(path),'exec')
path.write_text(text,encoding='utf-8')
PY

  chmod 755 "$perf"
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$perf" \
    || fail "Performance Center Python validation failed in $tree"
  grep -Fq '# MECHOS_AUTO_OPTIMIZATION_V2' "$perf" || fail "auto optimization helper marker missing"
  grep -Fq 'lambda:mechos_auto_optimize(self)' "$perf" || fail "Auto Optimization is not wired to hardware-aware helper"
  grep -Fq 'systemd-detect-virt' "$perf" || fail "VM detection missing from Auto Optimization"
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

log 'Auto Optimization now selects supported physical/VM profiles and treats unsupported tuning as informational'
