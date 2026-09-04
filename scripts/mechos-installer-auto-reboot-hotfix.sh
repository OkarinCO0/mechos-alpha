#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${MECHOS_ARCHLIVE_ROOT:-/workspace/archlive/airootfs}"
DISPATCHER="$ROOT/usr/local/bin/mechos-install"
NATIVE="$ROOT/usr/local/bin/mechos-native-install"
MARKER="# MECHOS_NATIVE_INSTALL_AUTO_REBOOT_V1"

log(){ printf '[MechOS Installer Auto Reboot] %s\n' "$*"; }
fail(){ printf '[MechOS Installer Auto Reboot] ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$DISPATCHER" ] || fail "installer dispatcher missing: $DISPATCHER"
[ -f "$NATIVE" ] || fail "native installer missing: $NATIVE"

grep -Fq '/usr/local/bin/mechos-native-install' "$DISPATCHER" \
  || fail "final installer dispatcher does not route Clean Install to mechos-native-install"

validate_native_policy(){
  grep -Fq "$MARKER" "$NATIVE" || return 1
  grep -Fq 'QTimer.singleShot(10000,self.reboot_system)' "$NATIVE" || return 1
  grep -Fq 'def reboot_system(self):' "$NATIVE" || return 1
  grep -Fq "['sudo','-n','systemctl','reboot']" "$NATIVE" || return 1
  grep -Fq "if code == 0:" "$NATIVE" || return 1
  return 0
}

if validate_native_policy; then
  log "native Clean Install success-only reboot policy already installed"
  exit 0
fi

# The final /usr/local/bin/mechos-install path is intentionally a dispatcher.
# Clean Install is owned by the PyQt native installer, whose finished() callback
# is the only correct place to schedule an automatic reboot after a verified
# successful native helper exit. Do not patch or search for Archinstall here.
python3 - "$NATIVE" <<'PY'
from pathlib import Path
import sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
marker='# MECHOS_NATIVE_INSTALL_AUTO_REBOOT_V1'

if marker in text:
    raise SystemExit('[MechOS Installer Auto Reboot] existing native reboot marker is incomplete or invalid')

old_import='from PyQt6.QtCore import QProcess, Qt\n'
new_import='from PyQt6.QtCore import QProcess, Qt, QTimer\n'
if old_import in text:
    text=text.replace(old_import,new_import,1)
elif 'from PyQt6.QtCore import QProcess, Qt, QTimer' not in text:
    raise SystemExit('[MechOS Installer Auto Reboot] native installer Qt import block not found')

old_success="""        if code == 0:\n            self.progress.setValue(100)\n            self.status.setText('MechOS is installed. Remove the Live USB and reboot into the installed system.')\n            QMessageBox.information(self,'MechOS Installed','Installation completed successfully.\\n\\nRemove the Live USB and reboot. First boot will open MechOS account setup.')\n        else:\n"""
new_success="""        if code == 0:\n            # MECHOS_NATIVE_INSTALL_AUTO_REBOOT_V1\n            self.progress.setValue(100)\n            self.status.setText('MechOS is installed. Restarting automatically in 10 seconds...')\n            self.close_btn.setEnabled(False)\n            QTimer.singleShot(10000,self.reboot_system)\n        else:\n"""
if old_success not in text:
    raise SystemExit('[MechOS Installer Auto Reboot] native installer success callback not found')
text=text.replace(old_success,new_success,1)

anchor='''    def closeEvent(self,event):\n'''
method="""    def reboot_system(self):\n        self.status.setText('Restarting MechOS now...')\n        try:\n            subprocess.Popen(['sudo','-n','systemctl','reboot'])\n        except Exception as exc:\n            self.close_btn.setEnabled(True)\n            self.status.setText(f'Automatic restart failed: {exc}. Use the system power menu to reboot.')\n\n"""
if anchor not in text:
    raise SystemExit('[MechOS Installer Auto Reboot] native installer closeEvent anchor not found')
text=text.replace(anchor,method+anchor,1)

compile(text,str(path),'exec')
path.write_text(text,encoding='utf-8')
PY

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$NATIVE" \
  || fail "native installer failed Python syntax validation after reboot patch"
validate_native_policy \
  || fail "native Clean Install success-only reboot policy validation failed"

log "successful native Clean Installs restart automatically after 10 seconds; failed/cancelled installs remain in Live"
