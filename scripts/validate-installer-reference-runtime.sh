#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL="$ROOT/src/mechos_ui/installer_shell.py"

fail(){ echo "[validate-installer-reference-runtime] ERROR: $*" >&2; exit 1; }

[ -f "$SHELL" ] || fail "installer shell missing"
python3 -m py_compile "$SHELL" || fail "installer shell Python syntax failed"

grep -Fq "mechos-installer-reference.png" "$SHELL" || fail "approved installer reference is not loaded"
grep -Fq "RELEASE = Path('/etc/mechos/release')" "$SHELL" || fail "runtime release source missing"
grep -Fq "SYSTEM SUMMARY" "$SHELL" || fail "real system summary overlay missing"
grep -Fq "SELECT INSTALL TARGET" "$SHELL" || fail "real install target overlay missing"
grep -Fq "INSTALLATION OPTIONS" "$SHELL" || fail "real install-mode overlay missing"
grep -Fq "QTimer.singleShot(0, self.owner.showFullScreen)" "$SHELL" || fail "immediate fullscreen reassertion missing"
grep -Fq "QTimer.singleShot(1000, self.owner.showFullScreen)" "$SHELL" || fail "delayed VM fullscreen reassertion missing"
grep -Fq "virtual/test storage" "$SHELL" || fail "VM storage labeling missing"
grep -Fq "Mask only the demo-data regions" "$SHELL" || fail "reference demo-data masking missing"

if grep -Fq "QLabel[role=\"live\"]" "$SHELL"; then
  fail "legacy floating live overlay style returned"
fi
if grep -Fq "Selected drive: detecting" "$SHELL"; then
  fail "legacy top-right selected-drive overlay returned"
fi
if grep -Fq "#a88cff" "$SHELL"; then
  fail "legacy purple debug focus outline returned"
fi

echo "[validate-installer-reference-runtime] OK: approved reference chrome is retained while fake demo hardware/drives/version are replaced by real runtime data and fullscreen is enforced"
