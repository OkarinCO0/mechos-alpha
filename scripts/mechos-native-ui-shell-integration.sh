#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
SOURCE="/workspace/src/mechscope/mechscope_shell.py"

log(){ printf '[MechOS Native UI Shell] %s\n' "$*"; }
fail(){ printf '[MechOS Native UI Shell] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Native UI Shell] ERROR line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ -f "$SOURCE" ] || fail "source-owned MechScope shell missing: $SOURCE"
[ -d "$ROOT" ] || fail "ArchISO rootfs missing: $ROOT"
[ -s "$PAYLOAD" ] || fail "installed-system payload missing: $PAYLOAD"

install_tree(){
  local tree="$1"
  local target="$tree/usr/local/share/mechos/ui/mechscope_shell.py"
  local public="$tree/usr/local/bin/mechscope"
  local impl="$public"
  [ -f "$public.real" ] && impl="$public.real"

  [ -f "$impl" ] || fail "MechScope runtime missing from $tree"
  mkdir -p "$(dirname "$target")"
  install -m 0644 "$SOURCE" "$target"

  # The accumulated generated MechScope must be valid before we add the final
  # source-owned visual authority. This catches an earlier patch-chain problem
  # without allowing the native shell step to hide or worsen it.
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$impl" \
    || fail "MechScope runtime is invalid before native UI activation: $impl"

  python3 - "$impl" <<'PY'
from pathlib import Path
import sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
marker='# MECHOS_SOURCE_OWNED_SHELL_V3'
if marker in text:
    raise SystemExit(0)

cls=text.find('class MechScope(QMainWindow):')
if cls < 0:
    raise SystemExit('[MechOS Native UI Shell] MechScope class not found')

# Do not replace text inside the generated MechScope class. Older integration
# used string-based method surgery and could cut through the controller event
# handler when later patches changed method boundaries. Instead, define clean
# overrides after the class and attach them before the application starts.
anchor=text.find('\ndef main():', cls)
if anchor < 0:
    anchor=text.find('\nif __name__', cls)
if anchor < 0:
    anchor=text.find('\napp = QApplication', cls)
if anchor < 0:
    anchor=text.find('\napp=QApplication', cls)
if anchor < 0:
    raise SystemExit('[MechOS Native UI Shell] application startup anchor not found')

override=r'''
# MECHOS_SOURCE_OWNED_SHELL_V3
def _mechos_source_shell_module():
    import importlib.util
    import sys as _sys
    from pathlib import Path as _Path
    module_name='mechos_source_shell'
    existing=_sys.modules.get(module_name)
    if existing is not None:
        return existing
    shell_path=_Path('/usr/local/share/mechos/ui/mechscope_shell.py')
    spec=importlib.util.spec_from_file_location(module_name,shell_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f'Unable to load MechScope source shell: {shell_path}')
    module=importlib.util.module_from_spec(spec)
    _sys.modules[module_name]=module
    spec.loader.exec_module(module)
    return module


def _mechos_force_true_fullscreen(self):
    # Qt/KWin can translate a pre-show FullScreen state into a maximized Plasma
    # window on VM fallback sessions. Reassert real fullscreen after the event
    # loop starts so no title bar, panel or maximized-window chrome remains.
    self.setWindowFlag(Qt.WindowType.FramelessWindowHint, True)
    self.showFullScreen()


def _mechos_native_build_ui(self):
    from PyQt6.QtCore import QTimer as _MechQTimer
    self.setWindowTitle('MechOS • MechScope 2.0')
    self.setWindowFlag(Qt.WindowType.FramelessWindowHint, True)
    self.setWindowState(Qt.WindowState.WindowFullScreen)
    actions={
        'steam': self.open_steam,
        'store': self.open_store,
        'performance': lambda: spawn(['/usr/local/bin/mechos-performance-center']),
        'updates': lambda: spawn(['/usr/local/bin/mechos-update-center']),
        'drivers': lambda: spawn(['/usr/local/bin/mechos-update-center']),
        'systeminfo': lambda: spawn(['systemsettings','kcm_about-distro']),
        'network': lambda: spawn(['systemsettings','kcm_networkmanagement']),
        'gaming': lambda: None,
        'desktop': lambda: self.switch_mode('desktop'),
        'creator': lambda: self.switch_mode('creator'),
        'vr': self.open_vr,
        'recovery': lambda: spawn(['/usr/local/bin/mechos-recovery-center']),
        'shutdown': lambda: spawn(['/usr/local/bin/mechos-power-menu']) if __import__('pathlib').Path('/usr/local/bin/mechos-power-menu').exists() else spawn(['systemctl','poweroff']),
    }
    shell_mod=_mechos_source_shell_module()
    self.native_shell=shell_mod.MechScopeShell(self,actions,self)
    self.setCentralWidget(self.native_shell)
    self.cpu_gauge=self.native_shell.cpu_gauge
    self.ram_gauge=self.native_shell.ram_gauge
    self.disk_gauge=self.native_shell.disk_gauge
    self.gpu_status=self.native_shell.gpu_status
    self.temp_label=self.native_shell.temp_label
    self.net_label=self.native_shell.net_label
    self.time_label=self.native_shell.time_label
    self.pad_label=self.native_shell.pad_label
    self.stats_label=QLabel(self)
    self.stats_label.hide()
    self.native_shell.set_recent_games(getattr(self,'games',[]), self.launch_game)
    if getattr(self,'focusables',None):
        self.focusables[0].setFocus()

    # The original application startup can still call show()/showMaximized().
    # These post-show assertions always win, on both Gamescope and Plasma/VM.
    _MechQTimer.singleShot(0, lambda: _mechos_force_true_fullscreen(self))
    _MechQTimer.singleShot(150, lambda: _mechos_force_true_fullscreen(self))
    _MechQTimer.singleShot(750, lambda: _mechos_force_true_fullscreen(self))


def _mechos_native_refresh_stats(self):
    cpu=cpu_percent(); ram=ram_percent(); disk=disk_percent()
    self.cpu_gauge.setValue(cpu); self.ram_gauge.setValue(ram); self.disk_gauge.setValue(disk)
    gpu=None
    gpu_probe=globals().get('mechos_gpu_load_percent')
    if callable(gpu_probe):
        try:
            gpu=gpu_probe()
        except Exception:
            gpu=None
    gpu_text=gpu_name()
    if gpu is not None:
        gpu_text+=f'  •  {gpu}% load'
    self.gpu_status.setText('GPU  '+gpu_text)
    self.net_label.setText('NET  '+network_name())
    self.time_label.setText(time.strftime('%I:%M %p'))
    try:
        temp=output(['bash','-lc','for f in /sys/class/thermal/thermal_zone*/temp; do [ -r "$f" ] || continue; v=$(cat "$f"); [ "$v" -gt 1000 ] && v=$((v/1000)); [ "$v" -gt 0 ] && [ "$v" -lt 120 ] && { echo "${v}°C"; break; }; done'])
    except Exception:
        temp=''
    self.temp_label.setText('Temperature: '+(temp or 'sensor dependent'))


MechScope.build_ui=_mechos_native_build_ui
MechScope.refresh_stats=_mechos_native_refresh_stats
'''

text=text[:anchor]+override+text[anchor:]
compile(text,str(path),'exec')
path.write_text(text,encoding='utf-8')
PY

  chmod 755 "$impl"
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$impl" "$target" \
    || fail "source-owned UI Python validation failed in $tree"
  grep -Fq '# MECHOS_SOURCE_OWNED_SHELL_V3' "$impl" || fail "runtime did not receive source-shell marker"
  grep -Fq 'MechScope.build_ui=_mechos_native_build_ui' "$impl" || fail "runtime is not using safe native UI override"
  grep -Fq '_mechos_force_true_fullscreen' "$impl" || fail "runtime is not enforcing true fullscreen"
}

install_tree "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xpf "$PAYLOAD" -C "$tmp"
install_tree "$tmp"
replacement="$PAYLOAD.native-ui"
tar --zstd -cpf "$replacement" -C "$tmp" .
mv -f "$replacement" "$PAYLOAD"
rm -rf "$tmp"
trap - EXIT

log 'MechScope visual authority uses safe runtime overrides and enforces true fullscreen after application startup'
