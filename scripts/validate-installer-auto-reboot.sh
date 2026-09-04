#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOTFIX="$ROOT/scripts/mechos-installer-auto-reboot-hotfix.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"

fail(){ echo "[validate-installer-auto-reboot] ERROR: $*" >&2; exit 1; }

[ -f "$HOTFIX" ] || fail "auto-reboot hotfix missing"
bash -n "$HOTFIX" || fail "auto-reboot hotfix shell syntax failed"
grep -Fq 'MECHOS_INSTALL_SUCCESS_AUTO_REBOOT_V1' "$HOTFIX" || fail "success-only reboot marker missing"
grep -Fq 'systemctl reboot' "$HOTFIX" || fail "reboot command missing"
grep -Fq 'Press Ctrl+C' "$HOTFIX" || fail "Live-session escape notice missing"
grep -Fq 'for remaining in 10 9 8 7 6 5 4 3 2 1' "$HOTFIX" || fail "visible reboot countdown missing"
grep -Fq 'archinstall' "$HOTFIX" || fail "success-path relationship to archinstall is undocumented"
grep -Fq 'mechos-installer-auto-reboot-hotfix.sh' "$PATCHER" || fail "auto-reboot hotfix is not wired into final build chain"

python3 - "$PATCHER" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
a=text.find('mechos-update-center-v1-runtime-guard.sh')
b=text.find('mechos-installer-auto-reboot-hotfix.sh')
c=text.find('mechos-installed-mechscope-launch-hotfix.sh')
if min(a,b,c) < 0 or not (a < b < c):
    raise SystemExit('[validate-installer-auto-reboot] success reboot policy must be final after updater and before installed-session finalization')
PY

echo '[validate-installer-auto-reboot] OK: successful installs get a visible 10-second restart countdown; failed/cancelled installs cannot reach the reboot block'
