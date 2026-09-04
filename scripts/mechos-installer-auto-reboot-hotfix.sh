#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
INSTALLER="$ROOT/usr/local/bin/mechos-install"
MARKER="# MECHOS_INSTALL_SUCCESS_AUTO_REBOOT_V1"

log(){ printf '[MechOS Installer Auto Reboot] %s\n' "$*"; }
fail(){ printf '[MechOS Installer Auto Reboot] ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$INSTALLER" ] || fail "installer backend missing: $INSTALLER"

validate_policy(){
  grep -Fq "$MARKER" "$INSTALLER" || return 1
  grep -Fq 'archinstall --config "$CONFIG"' "$INSTALLER" || return 1
  grep -Fq 'install_rc=$?' "$INSTALLER" || return 1
  grep -Fq 'if [[ "$install_rc" -ne 0 ]]' "$INSTALLER" || return 1
  grep -Fq 'for remaining in 10 9 8 7 6 5 4 3 2 1' "$INSTALLER" || return 1
  grep -Fq 'Press Ctrl+C' "$INSTALLER" || return 1
  grep -Fq 'systemctl reboot' "$INSTALLER" || return 1
  if grep -Eq '^[[:space:]]*exec[[:space:]]+archinstall([[:space:]]|$)' "$INSTALLER"; then
    return 1
  fi
  return 0
}

if validate_policy; then
  log "canonical success-only reboot policy already installed"
  exit 0
fi

# Compatibility repair for older Live overlays that still replace the shell
# with `exec archinstall`. The canonical overlay now owns this policy, so this
# is only a final-build guard for stale or externally supplied installer files.
python3 - "$INSTALLER" <<'PY'
from pathlib import Path
import re,sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
marker='# MECHOS_INSTALL_SUCCESS_AUTO_REBOOT_V1'
if marker in text:
    raise SystemExit('[MechOS Installer Auto Reboot] existing marker is incomplete or invalid')

pattern=re.compile(r'''if \[\[ -s "\$CONFIG" \]\]; then\n\s*exec archinstall --config "\$CONFIG"\nfi\n\nexec archinstall\s*\n?''')
replacement=r'''set +e
if [[ -s "$CONFIG" ]]; then
  archinstall --config "$CONFIG"
  install_rc=$?
else
  archinstall
  install_rc=$?
fi
set -e

if [[ "$install_rc" -ne 0 ]]; then
  echo
  echo "MechOS installation did not complete successfully (archinstall exit $install_rc)."
  echo "The Live environment will remain open so you can review the installer output and try again."
  exit "$install_rc"
fi

# MECHOS_INSTALL_SUCCESS_AUTO_REBOOT_V1
echo
echo "MechOS installation completed successfully."
echo "The system will restart into the installed OS in 10 seconds."
echo "Press Ctrl+C now only if you need to remain in the Live environment."
echo
sync || true
for remaining in 10 9 8 7 6 5 4 3 2 1; do
  printf "\rRestarting MechOS in %2d seconds... " "$remaining"
  sleep 1
done
printf "\nRestarting now.\n"
systemctl reboot
'''
new,count=pattern.subn(replacement,text,count=1)
if count != 1:
    raise SystemExit('[MechOS Installer Auto Reboot] canonical archinstall execution block not found in mechos-install')
path.write_text(new,encoding='utf-8')
PY

bash -n "$INSTALLER" || fail "patched installer backend failed shell syntax validation"
validate_policy || fail "success-only reboot policy validation failed after compatibility repair"

log "successful installs restart automatically; failed/cancelled installs remain in Live"
