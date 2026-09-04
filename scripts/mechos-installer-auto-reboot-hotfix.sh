#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${MECHOS_ARCHLIVE_ROOT:-/workspace/archlive/airootfs}"
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
  log "success-only reboot policy already installed"
  exit 0
fi

# FINAL INSTALLER TAIL AUTHORITY
#
# The ISO build can materialize more than one mechos-install implementation.
# Do not depend on the wording of the old success messages. The full generated
# installer is identified by its payload/HTTP-server state, then its final real
# Archinstall command is replaced through EOF. Everything before Archinstall —
# disk warnings, payload server, hardware scan, logging and cleanup trap — is
# intentionally preserved byte-for-byte.
python3 - "$INSTALLER" <<'PY'
from pathlib import Path
import re,sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
marker='# MECHOS_INSTALL_SUCCESS_AUTO_REBOOT_V1'
if marker in text:
    raise SystemExit('[MechOS Installer Auto Reboot] existing marker is incomplete or invalid')

common_success=r'''if [[ "$install_rc" -ne 0 ]]; then
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

patched=False

# Full generated installer used by build-mechos-archiso.sh. Previous final UI
# guards may alter the informational text after Archinstall, so locate the
# actual command line rather than any particular completion sentence.
full_generated=(
    'PAYLOAD_DIR=' in text and
    'SERVER_PID=' in text and
    'mechos-postinstall-target' in text
)
if full_generated:
    lines=text.splitlines(keepends=True)
    candidates=[]
    command_re=re.compile(r'^\s*(?:exec\s+)?archinstall(?:\s+.*)?$')
    for i,line in enumerate(lines):
        if command_re.match(line.rstrip('\r\n')):
            candidates.append(i)
    if candidates:
        idx=candidates[-1]
        original=lines[idx].strip()
        original=re.sub(r'^exec\s+','',original,count=1)
        generated='set +e\n'+original+'\ninstall_rc=$?\nset -e\n\n'+common_success
        text=''.join(lines[:idx])+generated
        patched=True

# Compatibility fallback for the small source-overlay/stale launcher form.
if not patched:
    pattern=re.compile(r'''if \[\[ -s "\$CONFIG" \]\]; then\n\s*exec archinstall --config "\$CONFIG"\nfi\n\nexec archinstall\s*\n?''')
    canonical=r'''set +e
if [[ -s "$CONFIG" ]]; then
  archinstall --config "$CONFIG"
  install_rc=$?
else
  archinstall
  install_rc=$?
fi
set -e

'''+common_success
    text,count=pattern.subn(canonical,text,count=1)
    patched=(count == 1)

if not patched:
    tail='\n'.join(text.splitlines()[-30:])
    raise SystemExit('[MechOS Installer Auto Reboot] no supported Archinstall execution path found; final installer tail follows:\n'+tail)

path.write_text(text,encoding='utf-8')
PY

bash -n "$INSTALLER" || fail "patched installer backend failed shell syntax validation"
validate_policy || fail "success-only reboot policy validation failed after final installer repair"

log "successful installs restart automatically; failed/cancelled installs remain in Live"
