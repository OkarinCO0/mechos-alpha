#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOTFIX="$ROOT/scripts/mechos-installer-auto-reboot-hotfix.sh"
INSTALLER="$ROOT/overlay/rootfs/usr/local/bin/mechos-install"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"

fail(){ echo "[validate-installer-auto-reboot] ERROR: $*" >&2; exit 1; }

[ -f "$HOTFIX" ] || fail "auto-reboot hotfix missing"
[ -f "$INSTALLER" ] || fail "canonical Live installer backend missing"
bash -n "$HOTFIX" || fail "auto-reboot hotfix shell syntax failed"
bash -n "$INSTALLER" || fail "canonical Live installer shell syntax failed"

for file in "$HOTFIX" "$INSTALLER"; do
  grep -Fq 'MECHOS_INSTALL_SUCCESS_AUTO_REBOOT_V1' "$file" || fail "success-only reboot marker missing from $file"
  grep -Fq 'systemctl reboot' "$file" || fail "reboot command missing from $file"
  grep -Fq 'Press Ctrl+C' "$file" || fail "Live-session escape notice missing from $file"
  grep -Fq 'for remaining in 10 9 8 7 6 5 4 3 2 1' "$file" || fail "visible reboot countdown missing from $file"
done

grep -Fq 'install_rc=$?' "$INSTALLER" || fail "canonical installer does not capture archinstall result"
grep -Fq 'if [[ "$install_rc" -ne 0 ]]' "$INSTALLER" || fail "canonical installer has no failure/cancel guard"
grep -Fq 'archinstall --config "$CONFIG"' "$INSTALLER" || fail "canonical configured archinstall path missing"
if grep -Eq '^[[:space:]]*exec[[:space:]]+archinstall([[:space:]]|$)' "$INSTALLER"; then
  fail "canonical installer still execs archinstall and cannot run post-success policy"
fi

grep -Fq 'canonical success-only reboot policy already installed' "$HOTFIX" || fail "late hotfix does not validate canonical source policy"
grep -Fq 'canonical archinstall execution block not found' "$HOTFIX" || fail "legacy compatibility repair diagnostic missing"
grep -Fq 'mechos-installer-auto-reboot-hotfix.sh' "$PATCHER" || fail "auto-reboot hotfix is not wired into final build chain"

python3 - "$PATCHER" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
a=text.find('mechos-update-center-v2-integration.sh')
b=text.find('mechos-installer-auto-reboot-hotfix.sh')
c=text.find('mechos-installed-mechscope-launch-hotfix.sh')
if min(a,b,c) < 0 or not (a < b < c):
    raise SystemExit('[validate-installer-auto-reboot] success reboot policy must be final after updater and before installed-session finalization')
PY

echo '[validate-installer-auto-reboot] OK: canonical installer retains control after archinstall; only rc=0 reaches the visible restart countdown and failed/cancelled installs remain in Live'
