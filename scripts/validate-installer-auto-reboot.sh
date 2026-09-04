#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOTFIX="$ROOT/scripts/mechos-installer-auto-reboot-hotfix.sh"
NATIVE_INTEGRATION="$ROOT/scripts/mechos-native-installer-integration.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"

fail(){ echo "[validate-installer-auto-reboot] ERROR: $*" >&2; exit 1; }

[ -f "$HOTFIX" ] || fail "auto-reboot hotfix missing"
[ -f "$NATIVE_INTEGRATION" ] || fail "native installer integration missing"
bash -n "$HOTFIX" || fail "auto-reboot hotfix shell syntax failed"
bash -n "$NATIVE_INTEGRATION" || fail "native installer integration shell syntax failed"

grep -Fq 'mechos-native-install' "$NATIVE_INTEGRATION" || fail "native Clean Install owner missing"
grep -Fq 'def finished(self, code, _status):' "$NATIVE_INTEGRATION" || fail "native installer completion callback missing"
grep -Fq 'MECHOS_INSTALL_COMPLETE=1' "$NATIVE_INTEGRATION" || fail "native helper completion marker missing"

grep -Fq 'MECHOS_ARCHLIVE_ROOT' "$HOTFIX" || fail "final reboot guard cannot be tested against an isolated root"
grep -Fq 'MECHOS_NATIVE_INSTALL_AUTO_REBOOT_V1' "$HOTFIX" || fail "native reboot authority marker missing"
grep -Fq 'QTimer.singleShot(10000,self.reboot_system)' "$HOTFIX" || fail "10-second native reboot scheduling missing"
grep -Fq "['sudo','-n','systemctl','reboot']" "$HOTFIX" || fail "native reboot command missing"
grep -Fq '/usr/local/bin/mechos-native-install' "$HOTFIX" || fail "dispatcher-to-native validation missing"
if grep -Fqi 'archinstall' "$HOTFIX"; then
  # The final reboot authority must not regress to patching Archinstall or the
  # dispatcher. The only tolerated occurrence is the explanatory comment that
  # explicitly says not to search for it.
  count="$(grep -Fic 'archinstall' "$HOTFIX")"
  [ "$count" -eq 1 ] || fail "final reboot authority still contains Archinstall patch logic"
fi

grep -Fq 'mechos-installer-auto-reboot-hotfix.sh' "$PATCHER" || fail "auto-reboot guard is not wired into final build chain"

# Reproduce the exact final architecture seen in ISO builds: mechos-install is
# a dispatcher, while mechos-native-install owns the real clean-install success
# callback. The guard must patch the native app and leave the dispatcher alone.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/usr/local/bin"
cat > "$tmp/usr/local/bin/mechos-install" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case " $* " in
  *" --preserve-home "*) exec /usr/local/bin/mechos-live-update-keep-home ;;
esac
if [ -s /tmp/mechos-install-target.json ]; then
  exec /usr/local/bin/mechos-native-install
fi
exec /usr/local/bin/mechos-live-setup
EOF
chmod 0755 "$tmp/usr/local/bin/mechos-install"

cat > "$tmp/usr/local/bin/mechos-native-install" <<'PYEOF'
#!/usr/bin/env python3
import subprocess
from PyQt6.QtCore import QProcess, Qt
from PyQt6.QtWidgets import QMessageBox

class NativeInstall:
    def __init__(self):
        self.progress=None
        self.status=None
        self.close_btn=None

    def finished(self, code, _status):
        self.close_btn.setEnabled(True)
        if code == 0:
            self.progress.setValue(100)
            self.status.setText('MechOS is installed. Remove the Live USB and reboot into the installed system.')
            QMessageBox.information(self,'MechOS Installed','Installation completed successfully.\n\nRemove the Live USB and reboot. First boot will open MechOS account setup.')
        else:
            self.status.setText(f'Installation stopped with error code {code}. The log is shown below.')
            QMessageBox.critical(self,'MechOS Installer',f'Installation did not complete (error {code}).\n\nReview the installer log before rebooting.')

    def closeEvent(self,event):
        event.accept()
PYEOF
chmod 0755 "$tmp/usr/local/bin/mechos-native-install"

cp "$tmp/usr/local/bin/mechos-install" "$tmp/dispatcher.before"
MECHOS_ARCHLIVE_ROOT="$tmp" bash "$HOTFIX" >/tmp/mechos-auto-reboot-native-validation.log
NATIVE="$tmp/usr/local/bin/mechos-native-install"
DISPATCHER="$tmp/usr/local/bin/mechos-install"

cmp -s "$DISPATCHER" "$tmp/dispatcher.before" || fail "final reboot guard modified the installer dispatcher"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$NATIVE" || fail "patched native installer Python syntax failed"
grep -Fq 'MECHOS_NATIVE_INSTALL_AUTO_REBOOT_V1' "$NATIVE" || fail "native installer reboot marker missing after patch"
grep -Fq 'QTimer.singleShot(10000,self.reboot_system)' "$NATIVE" || fail "native installer does not schedule automatic restart"
grep -Fq "subprocess.Popen(['sudo','-n','systemctl','reboot'])" "$NATIVE" || fail "native installer reboot command missing after patch"
grep -Fq 'Installation stopped with error code' "$NATIVE" || fail "failed-install handling was overwritten"
if grep -Fq 'Remove the Live USB and reboot into the installed system.' "$NATIVE"; then
  fail "old manual-reboot success flow survived native patch"
fi

# Must be safe to run again after the final native app is already patched.
MECHOS_ARCHLIVE_ROOT="$tmp" bash "$HOTFIX" >/tmp/mechos-auto-reboot-native-idempotent.log
grep -Fq 'native Clean Install success-only reboot policy already installed' /tmp/mechos-auto-reboot-native-idempotent.log \
  || fail "native reboot guard is not idempotent"

python3 - "$PATCHER" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
a=text.find('mechos-update-center-v2-integration.sh')
b=text.find('mechos-installer-auto-reboot-hotfix.sh')
c=text.find('mechos-installed-mechscope-launch-hotfix.sh')
if min(a,b,c) < 0 or not (a < b < c):
    raise SystemExit('[validate-installer-auto-reboot] native reboot guard must run after updater v2 and before installed-session finalization')
PY

echo '[validate-installer-auto-reboot] OK: final mechos-install remains a dispatcher; native Clean Install alone owns success-triggered automatic reboot'
