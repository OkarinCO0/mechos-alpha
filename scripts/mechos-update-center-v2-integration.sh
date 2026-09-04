#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
SOURCE_UI="/workspace/src/mechos_ui/update_shell.py"

log(){ printf '[MechOS Update Center v2] %s\n' "$*"; }
fail(){ printf '[MechOS Update Center v2] ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$SOURCE_UI" ] || fail "Update Center source UI missing"

owner_file(){
  local tree="$1"
  local public="$tree/usr/local/bin/mechos-update-center"
  local libexec="$tree/usr/local/libexec/mechos-update-center-v5.py"
  if [ -f "$public" ] && grep -Fq 'class UpdateCenter(' "$public"; then printf '%s\n' "$public"; return 0; fi
  if [ -f "$public.real" ] && grep -Fq 'class UpdateCenter(' "$public.real"; then printf '%s\n' "$public.real"; return 0; fi
  if [ -f "$libexec" ] && grep -Fq 'class UpdateCenter(' "$libexec"; then printf '%s\n' "$libexec"; return 0; fi
  return 1
}

install_ui(){
  local tree="$1"
  mkdir -p "$tree/usr/local/share/mechos/ui"
  install -m 0644 "$SOURCE_UI" "$tree/usr/local/share/mechos/ui/update_shell.py"
}

patch_helper(){
  local helper="$1/usr/local/bin/mechos-update-helper"
  [ -f "$helper" ] || fail "Update helper missing in $1"
  python3 - "$helper" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')
marker='# MECHOS_UPDATE_CENTER_V2_SAFE_ARCHIVE'
if marker in t:
    raise SystemExit(0)
start=t.find('validate_bundle_archive(){')
end=t.find('\n}\n\napply_mechos_bundle(){',start)
if start < 0 or end < 0:
    raise SystemExit('[MechOS Update Center v2] validate_bundle_archive block missing')
end += 3
new=r'''validate_bundle_archive(){
  # MECHOS_UPDATE_CENTER_V2_SAFE_ARCHIVE
  python3 - "$1" <<'PYV2'
from pathlib import PurePosixPath
import subprocess,sys
bundle=sys.argv[1]
p=subprocess.run(['tar','--zstd','-tf',bundle],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
if p.returncode: raise SystemExit('unable to list update bundle')
allowed=(
 'usr/local/', 'usr/share/mechos/', 'usr/share/applications/',
 'usr/share/wayland-sessions/', 'usr/lib/systemd/', 'etc/mechos/',
 'etc/systemd/', 'etc/xdg/'
)
parents=set()
for prefix in allowed:
    parts=prefix.rstrip('/').split('/')
    for i in range(1,len(parts)):
        parents.add('/'.join(parts[:i]))
count=0
for raw in p.stdout.splitlines():
    name=raw.strip()
    while name.startswith('./'): name=name[2:]
    if not name or name=='.': continue
    path=PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts:
        raise SystemExit(f'unsafe bundle path: {name}')
    normalized=name.rstrip('/')
    if name.endswith('/') and normalized in parents:
        continue
    if not any(normalized==x.rstrip('/') or normalized.startswith(x) for x in allowed):
        raise SystemExit(f'path outside MechOS update allowlist: {name}')
    count += 1
if count == 0: raise SystemExit('empty MechOS update bundle')
PYV2
}
'''
p.write_text(t[:start]+new+t[end:],encoding='utf-8')
PY
  chmod 0755 "$helper"
  bash -n "$helper" || fail "Update helper syntax failed after v2 archive patch"
}

patch_backend(){
  local tree="$1" owner
  owner="$(owner_file "$tree")" || fail "Update Center owner missing in $tree"
  python3 - "$owner" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')
marker='# MECHOS_UPDATE_CENTER_V2_BACKEND'
if marker in t:
    raise SystemExit(0)
anchor='\ndef main():'
pos=t.find(anchor)
if pos < 0:
    raise SystemExit('[MechOS Update Center v2] main anchor missing')
block=r'''
# MECHOS_UPDATE_CENTER_V2_BACKEND
_mechos_v2_original_finished = UpdateCenter.finished
_mechos_v2_original_load_status = UpdateCenter.load_status
_mechos_v2_original_apply_updates = UpdateCenter.apply_updates


def _mechos_v2_values(output):
    values={}
    for line in output.splitlines():
        if '=' not in line:
            continue
        key,value=line.split('=',1)
        if key in {
            'CURRENT_MECHOS_VERSION','LATEST_MECHOS_VERSION','MECHOS_UPDATE_AVAILABLE',
            'MECHOS_RELEASE_NOTES','MECHOS_COUNT','PACMAN_COUNT','FLATPAK_COUNT',
            'TOTAL_COUNT','CHANNEL','REBOOT_REQUIRED','ROLLBACK_PENDING'
        }:
            values[key]=value
    return values


def _mechos_v2_int(values,key):
    try:
        return max(0,int(values.get(key,'0')))
    except Exception:
        return 0


def _mechos_v2_cards(self,values):
    ui=getattr(self,'_mechos_source_ui',None)
    if ui is None:
        return
    mechos=_mechos_v2_int(values,'MECHOS_COUNT')
    arch=_mechos_v2_int(values,'PACMAN_COUNT')
    flatpak=_mechos_v2_int(values,'FLATPAK_COUNT')
    if values.get('MECHOS_UPDATE_AVAILABLE')=='1':
        mechos=max(1,mechos)
    ui.mechos_count_label.setText('READY' if mechos else 'CURRENT')
    ui.arch_count_label.setText(f'{arch} UPDATE' + ('' if arch==1 else 'S'))
    ui.flatpak_count_label.setText(f'{flatpak} UPDATE' + ('' if flatpak==1 else 'S'))


def _mechos_v2_finished(self,mode,code):
    snapshot=self.check_buffer if mode=='check' else ''
    values=_mechos_v2_values(snapshot)
    _mechos_v2_original_finished(self,mode,code)

    if mode=='check':
        if code != 0:
            self.update_count=0
            self.update_button.setEnabled(False)
            return
        total=_mechos_v2_int(values,'TOTAL_COUNT')
        if values.get('MECHOS_UPDATE_AVAILABLE')=='1':
            total=max(1,total)
        self.update_count=total
        self.update_button.setEnabled(total > 0)
        _mechos_v2_cards(self,values)
        if total > 0:
            latest=values.get('LATEST_MECHOS_VERSION','available')
            self.status_label.setText('UPDATES READY')
            self.details_label.setText(f'{total} verified update group(s) are ready. MechOS target: {latest}.')
            self.progress.setRange(0,1); self.progress.setValue(1); self.progress.setFormat('Ready to install')
        else:
            self.status_label.setText('SYSTEM CURRENT')
            self.details_label.setText('MechOS, Arch packages and Flatpaks are up to date.')
            self.progress.setRange(0,1); self.progress.setValue(1); self.progress.setFormat('System is current')

    elif mode=='apply':
        self.update_button.setEnabled(False)
        if code == 0:
            ui=getattr(self,'_mechos_source_ui',None)
            if ui is not None:
                ui.mechos_count_label.setText('CURRENT')
                ui.arch_count_label.setText('0 UPDATES')
                ui.flatpak_count_label.setText('0 UPDATES')


UpdateCenter.finished=_mechos_v2_finished


def _mechos_v2_apply_updates(self):
    if self.proc is not None:
        return
    if self.update_count <= 0:
        QMessageBox.information(
            self,
            'MechOS Update Center',
            'No installable update is currently selected. Update Center will check again now.'
        )
        self.check_updates()
        return
    _mechos_v2_original_apply_updates(self)


UpdateCenter.apply_updates=_mechos_v2_apply_updates


def _mechos_v2_load_status(self):
    _mechos_v2_original_load_status(self)
    try:
        out=subprocess.check_output([HELPER,'status'],text=True,stderr=subprocess.STDOUT)
    except Exception:
        return
    values=_mechos_v2_values(out)
    ui=getattr(self,'_mechos_source_ui',None)
    if ui is not None:
        if values.get('ROLLBACK_PENDING')=='1':
            ui.recovery_state_label.setText('ROLLBACK READY')
        else:
            ui.recovery_state_label.setText('PROTECTED')
        if values.get('REBOOT_REQUIRED')=='1':
            self.reboot_label.setText('RESTART REQUIRED')
        else:
            self.reboot_label.setText('RESTART NOT REQUIRED')


UpdateCenter.load_status=_mechos_v2_load_status
'''
t=t[:pos]+block+t[pos:]
compile(t,str(p),'exec')
p.write_text(t,encoding='utf-8')
PY
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$owner" || fail "Update Center v2 backend Python validation failed"
  grep -Fq 'MECHOS_UPDATE_CENTER_V2_BACKEND' "$owner" || fail "Update Center v2 backend marker missing"
}

patch_tree(){
  local tree="$1"
  install_ui "$tree"
  patch_helper "$tree"
  patch_backend "$tree"
}

patch_tree "$ROOT"

if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xpf "$ARCHIVE" -C "$tmp"
  patch_tree "$tmp"
  replacement="$ARCHIVE.update-center-v2"
  tar --zstd -cpf "$replacement" -C "$tmp" .
  mv -f "$replacement" "$ARCHIVE"
  rm -rf "$tmp"; trap - EXIT
fi

log 'Update Center v2 visual shell, reliable install-button state, category cards and safe verified-bundle archive handling are final'
