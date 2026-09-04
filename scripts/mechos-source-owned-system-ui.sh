#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
SRC="/workspace/src/mechos_ui"

log(){ printf '[MechOS Source UI] %s\n' "$*"; }
fail(){ printf '[MechOS Source UI] ERROR: %s\n' "$*" >&2; exit 1; }
[ -d "$SRC" ] || fail "source UI directory missing: $SRC"

install_sources(){
  local tree="$1"
  local dst="$tree/usr/local/share/mechos/ui"
  mkdir -p "$dst"
  for f in fixed_canvas.py creator_shell.py performance_shell.py update_shell.py recovery_shell.py quick_actions_shell.py installer_shell.py oobe_shell.py; do
    [ -f "$SRC/$f" ] || fail "source UI file missing: $f"
    install -m 0644 "$SRC/$f" "$dst/$f"
  done
}

owner_file(){
  # Keep dependent local assignments separate under `set -u`.
  # Some guarded apps move their real Python implementation to libexec rather
  # than using the historical /usr/local/bin/<name>.real convention.
  local tree="$1"
  local name="$2"
  local cls="$3"
  local public="$tree/usr/local/bin/$name"
  local libexec_v5="$tree/usr/local/libexec/${name}-v5.py"
  if [ -f "$public" ] && grep -Fq "class $cls(" "$public"; then printf '%s\n' "$public"; return 0; fi
  if [ -f "$public.real" ] && grep -Fq "class $cls(" "$public.real"; then printf '%s\n' "$public.real"; return 0; fi
  if [ -f "$libexec_v5" ] && grep -Fq "class $cls(" "$libexec_v5"; then printf '%s\n' "$libexec_v5"; return 0; fi
  return 1
}

patch_python(){
  local path="$1"
  local cls="$2"
  local kind="$3"
  python3 - "$path" "$cls" "$kind" <<'PY'
from pathlib import Path
import sys

path=Path(sys.argv[1]); cls=sys.argv[2]; kind=sys.argv[3]
text=path.read_text(encoding='utf-8')
marker=f'# MECHOS_SOURCE_SYSTEM_UI_V1_{kind.upper()}'
if marker in text:
    raise SystemExit(0)
classpos=text.find('class '+cls+'(')
if classpos < 0:
    raise SystemExit(f'[MechOS Source UI] {cls} class not found in {path}')
anchors=['\ndef main():','\nif __name__','\napp = QApplication','\napp=QApplication']
anchor=-1
for item in anchors:
    p=text.find(item,classpos)
    if p >= 0 and (anchor < 0 or p < anchor):
        anchor=p
if anchor < 0:
    raise SystemExit(f'[MechOS Source UI] startup anchor not found for {path}')

loader=r'''
def _mechos_ui_module(filename, module_name):
    import importlib.util as _ilu
    import sys as _sys
    from pathlib import Path as _Path
    current=_sys.modules.get(module_name)
    if current is not None: return current
    source=_Path('/usr/local/share/mechos/ui')/filename
    parent=str(source.parent)
    if parent not in _sys.path: _sys.path.insert(0,parent)
    spec=_ilu.spec_from_file_location(module_name,source)
    if spec is None or spec.loader is None: raise RuntimeError(f'Unable to load MechOS UI source: {source}')
    module=_ilu.module_from_spec(spec); _sys.modules[module_name]=module; spec.loader.exec_module(module); return module
'''

if kind=='performance':
    override=r'''
# MECHOS_SOURCE_SYSTEM_UI_V1_PERFORMANCE
'''+loader+r'''
def _mechos_performance_build(self):
    from pathlib import Path as _Path
    shell=_mechos_ui_module('performance_shell.py','mechos_performance_shell')
    def _spawn(args):
        try: run(args)
        except Exception: pass
    actions={
      'report': (lambda:_spawn(['/usr/local/bin/mechos-optimization-report'])) if _Path('/usr/local/bin/mechos-optimization-report').exists() else (lambda:None),
      'auto': lambda:set_profile('performance',self), 'performance':lambda:set_profile('performance',self),
      'balanced':lambda:set_profile('balanced',self), 'battery':lambda:set_profile('power-saver',self),
      'gpu': getattr(self,'gpu_info',lambda:None), 'diagnostics':lambda:_spawn(['/usr/local/bin/mechos-hardware-scan']),
      'monitor':lambda:_spawn(['konsole','-e','btop']), 'storage':getattr(self,'storage_info',lambda:None),
      'hud':getattr(self,'toggle_hud',lambda:None), 'recorder':getattr(self,'recorder',lambda:None),
      'radarai':getattr(self,'launch_radarai',lambda:None), 'updates':lambda:_spawn(['/usr/local/bin/mechos-update-center']),
    }
    ui=shell.PerformanceShell(self,actions,self); self.setCentralWidget(ui); self._mechos_source_ui=ui
    self.profile_badge=ui.profile_badge; self.gpu_label=ui.gpu_label; self.gpu_summary=ui.gpu_summary
    self.cpu_card=ui.cpu_card; self.ram_card=ui.ram_card; self.disk_card=ui.disk_card; self.zram_card=ui.zram_card
    self.health_label=ui.health_label; self.radar=ui.radar
    self.setWindowFlag(Qt.WindowType.FramelessWindowHint,True); self.setWindowState(Qt.WindowState.WindowFullScreen)
Perf.build=_mechos_performance_build
'''
elif kind=='update':
    override=r'''
# MECHOS_SOURCE_SYSTEM_UI_V1_UPDATE
'''+loader+r'''
def _mechos_update_build(self):
    shell=_mechos_ui_module('update_shell.py','mechos_update_shell')
    def _spawn(args):
        try: subprocess.Popen(args)
        except Exception: pass
    actions={'check':self.check_updates,'install':self.apply_updates,'history':self.load_history,'reboot':self.reboot,
      'performance':lambda:_spawn(['/usr/local/bin/mechos-performance-center']),
      'creator':lambda:_spawn(['/usr/local/bin/mechos-mode-launch','creator']) if __import__('pathlib').Path('/usr/local/bin/mechos-mode-launch').exists() else _spawn(['/usr/local/bin/mechos-creator-mode'])}
    ui=shell.UpdateShell(self,actions,self); self.setCentralWidget(ui); self._mechos_source_ui=ui
    for n in ('channel','status_label','details_label','version_label','reboot_label','reboot_button','check_button','update_button','history_button','progress','log','history'): setattr(self,n,getattr(ui,n))
    self.setWindowFlag(Qt.WindowType.FramelessWindowHint,True); self.setWindowState(Qt.WindowState.WindowFullScreen)
UpdateCenter.build_ui=_mechos_update_build
'''
elif kind=='recovery':
    override=r'''
# MECHOS_SOURCE_SYSTEM_UI_V1_RECOVERY
'''+loader+r'''
def _mechos_recovery_build(self):
    shell=_mechos_ui_module('recovery_shell.py','mechos_recovery_shell')
    def _spawn(args):
        try: subprocess.Popen(args)
        except Exception: pass
    actions={'rescan':self.rescan,'hardware':self.hardware,'repair':self.repair_boot,'rollback':self.rollback,'logs':self.load_logs,
      'keep-home':lambda:_spawn(['/usr/local/bin/mechos-preserve-home']), 'disk':self.hardware,
      'mechscope':lambda:_spawn(['/usr/local/bin/mechos-mode-launch','gaming']) if __import__('pathlib').Path('/usr/local/bin/mechos-mode-launch').exists() else _spawn(['/usr/local/bin/mechos-return-to-mechscope'])}
    ui=shell.RecoveryShell(self,actions,self); self.setCentralWidget(ui); self._mechos_source_ui=ui
    self.root_combo=ui.root_combo; self.esp_combo=ui.esp_combo; self.output=ui.output
    self.setWindowFlag(Qt.WindowType.FramelessWindowHint,True); self.setWindowState(Qt.WindowState.WindowFullScreen)
Recovery.build_ui=_mechos_recovery_build
'''
elif kind=='quick':
    override=r'''
# MECHOS_SOURCE_SYSTEM_UI_V1_QUICK
'''+loader+r'''
def _mechos_quick_build(self):
    shell=_mechos_ui_module('quick_actions_shell.py','mechos_quick_shell')
    def _spawn(args):
        try: spawn(args)
        except Exception: pass
    actions={'close':self.close,'performance':lambda:self.profile('performance'),'balanced':lambda:self.profile('balanced'),'battery':lambda:self.profile('power-saver'),
      'performance-center':lambda:_spawn(['/usr/local/bin/mechos-performance-center']),'wifi':self.toggle_wifi,'bluetooth':self.toggle_bt,
      'display':lambda:_spawn(['systemsettings']),'vol-down':lambda:self.wpctl('5%-'),'mute':self.mute,'vol-up':lambda:self.wpctl('5%+'),
      'go-live':lambda:_spawn(['/usr/local/bin/mechos-stream-control','start-stream']),'end-stream':lambda:_spawn(['/usr/local/bin/mechos-stream-control','stop-stream']),
      'record':lambda:_spawn(['/usr/local/bin/mechos-stream-control','toggle-record']),'stream-center':lambda:_spawn(['/usr/local/bin/mechos-stream-center']),
      'updates':lambda:_spawn(['/usr/local/bin/mechos-update-center']),'creator':lambda:_spawn(['/usr/local/bin/mechos-mode-launch','creator']),
      'system-info':lambda:_spawn(['systemsettings','kcm_about-distro']),'recovery':lambda:_spawn(['/usr/local/bin/mechos-recovery-center'])}
    ui=shell.QuickActionsShell(self,actions,self); self.setCentralWidget(ui); self._mechos_source_ui=ui
QuickActions.build=_mechos_quick_build
'''
elif kind=='creator':
    override=r'''
# MECHOS_SOURCE_SYSTEM_UI_V1_CREATOR
'''+loader+r'''
def _mechos_creator_build(self):
    from PyQt6.QtCore import QTimer as _QTimer
    shell=_mechos_ui_module('creator_shell.py','mechos_creator_shell')
    ui=shell.CreatorShell(self,self); self.setCentralWidget(ui); self._mechos_source_ui=ui
    self.setWindowFlag(Qt.WindowType.FramelessWindowHint,True); self.setWindowState(Qt.WindowState.WindowFullScreen)
    _QTimer.singleShot(0,self.showFullScreen); _QTimer.singleShot(250,self.showFullScreen)
Creator.build=_mechos_creator_build
'''
elif kind=='oobe':
    override=r'''
# MECHOS_SOURCE_SYSTEM_UI_V1_OOBE
'''+loader+r'''
def _mechos_oobe_build(self):
    shell=_mechos_ui_module('oobe_shell.py','mechos_oobe_shell')
    ui=shell.OOBEShell(self,timezones(),COMMON_LOCALES,KEYMAPS,self)
    self.setCentralWidget(ui); self._mechos_source_ui=ui
    for n in ('stack','back','next','username','password','confirm','zone','locale','keyboard','hostname','review'): setattr(self,n,getattr(ui,n))
    self.setWindowFlag(Qt.WindowType.FramelessWindowHint,True); self.setWindowState(Qt.WindowState.WindowFullScreen)
OOBE.build_ui=_mechos_oobe_build
'''
elif kind=='installer':
    override=r'''
# MECHOS_SOURCE_SYSTEM_UI_V1_INSTALLER
'''+loader+r'''
def _mechos_installer_build(self):
    shell=_mechos_ui_module('installer_shell.py','mechos_installer_shell')
    ui=shell.InstallerShell(self,self); self.setCentralWidget(ui); self._mechos_source_ui=ui
    self.mode_buttons=ui.mode_buttons; self.progress=ui.progress
    self.setWindowFlag(Qt.WindowType.FramelessWindowHint,True); self.setWindowState(Qt.WindowState.WindowFullScreen)
    ui.set_drive(getattr(self,'selected_disk',''),getattr(self,'selected_model',''),getattr(self,'selected_size',''))
    ui.set_mode(getattr(self,'install_mode','clean'))

def _mechos_installer_set_mode(self,mode,checked=True,check=None):
    if not checked: return
    self.install_mode=mode
    ui=getattr(self,'_mechos_source_ui',None)
    if ui is not None: ui.set_mode(mode)

def _mechos_installer_refresh_target_labels(self):
    ui=getattr(self,'_mechos_source_ui',None)
    if ui is not None: ui.set_drive(getattr(self,'selected_disk',''),getattr(self,'selected_model',''),getattr(self,'selected_size',''))

Installer.build_ui=_mechos_installer_build
Installer.set_mode=_mechos_installer_set_mode
Installer.refresh_target_labels=_mechos_installer_refresh_target_labels
'''
else:
    raise SystemExit('unknown UI kind: '+kind)

text=text[:anchor]+override+text[anchor:]
compile(text,str(path),'exec')
path.write_text(text,encoding='utf-8')
PY
  chmod 755 "$path"
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$path" || fail "Python validation failed: $path"
}

patch_shared_tree(){
  local tree="$1"
  local p
  install_sources "$tree"
  p="$(owner_file "$tree" mechos-performance-center Perf)" || fail "Performance Center owner missing"; patch_python "$p" Perf performance
  p="$(owner_file "$tree" mechos-update-center UpdateCenter)" || fail "Update Center owner missing"; patch_python "$p" UpdateCenter update
  p="$(owner_file "$tree" mechos-recovery-center Recovery)" || fail "Recovery Center owner missing"; patch_python "$p" Recovery recovery
  p="$(owner_file "$tree" mechos-quick-actions QuickActions)" || fail "Quick Actions owner missing"; patch_python "$p" QuickActions quick
  p="$(owner_file "$tree" mechos-creator-mode Creator)" || fail "Creator Mode owner missing"; patch_python "$p" Creator creator
  p="$(owner_file "$tree" mechos-oobe OOBE)" || fail "OOBE owner missing"; patch_python "$p" OOBE oobe
}

# Live/root system surfaces.
patch_shared_tree "$ROOT"
p="$(owner_file "$ROOT" mechos-live-setup Installer)" || fail "Live Installer owner missing"
patch_python "$p" Installer installer

# Installed-system payload receives every shared surface, including OOBE, but
# not the Live-only installer.
if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xpf "$ARCHIVE" -C "$tmp"
  patch_shared_tree "$tmp"
  replacement="$ARCHIVE.source-ui"
  tar --zstd -cpf "$replacement" -C "$tmp" .
  mv -f "$replacement" "$ARCHIVE"
  rm -rf "$tmp"; trap - EXIT
fi

log 'Creator, Quick Actions, Performance, Update, Recovery, OOBE and Live Installer use source-owned final GUI authority'
