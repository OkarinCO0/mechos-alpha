#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
INSTALLER="$ROOT/usr/local/bin/mechos-install"
MARKER="# MECHOS_INSTALL_SUCCESS_AUTO_REBOOT_V1"

log(){ printf '[MechOS Installer Auto Reboot] %s\n' "$*"; }
fail(){ printf '[MechOS Installer Auto Reboot] ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$INSTALLER" ] || fail "installer backend missing: $INSTALLER"

if grep -Fq "$MARKER" "$INSTALLER"; then
  log "successful-install reboot policy already installed"
  exit 0
fi

python3 - "$INSTALLER" <<'PY'
from pathlib import Path
import sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
marker='# MECHOS_INSTALL_SUCCESS_AUTO_REBOOT_V1'

# This block is deliberately attached to the successful return from archinstall.
# With set -e enabled above it, a failed/cancelled archinstall exits before this
# code and therefore can never reboot the machine.
needle='''echo\necho "Archinstall exited."\necho "If installation completed successfully, the MechOS post-install"\necho "stage should have created /var/lib/mechos/installed in the new system."'''
replacement='''# MECHOS_INSTALL_SUCCESS_AUTO_REBOOT_V1\necho\necho "MechOS installation completed successfully."\necho "The system will restart into the installed OS in 10 seconds."\necho "Press Ctrl+C now only if you need to remain in the Live environment."\necho\nsync || true\nfor remaining in 10 9 8 7 6 5 4 3 2 1; do\n  printf "\\rRestarting MechOS in %2d seconds... " "$remaining"\n  sleep 1\ndone\nprintf "\\nRestarting now.\\n"\nsystemctl reboot\n'''

if needle not in text:
    raise SystemExit('[MechOS Installer Auto Reboot] success anchor not found in mechos-install')
text=text.replace(needle,replacement,1)
path.write_text(text,encoding='utf-8')
PY

bash -n "$INSTALLER" || fail "patched installer backend failed shell syntax validation"
grep -Fq "$MARKER" "$INSTALLER" || fail "auto reboot marker missing after patch"
grep -Fq 'systemctl reboot' "$INSTALLER" || fail "reboot command missing after patch"

log "successful installs now restart automatically; failed/cancelled installs remain in Live"
