#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UI="$ROOT/src/mechos_ui/update_shell.py"
INTEGRATION="$ROOT/scripts/mechos-update-center-v2-integration.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"
fail(){ echo "[validate-update-center-v2] ERROR: $*" >&2; exit 1; }

[ -f "$UI" ] || fail "Update Center v2 source UI missing"
[ -f "$INTEGRATION" ] || fail "Update Center v2 integration missing"
python3 -m py_compile "$UI" || fail "Update Center v2 UI Python syntax failed"
bash -n "$INTEGRATION" || fail "Update Center v2 integration shell syntax failed"

grep -Fq 'SYSTEM UPDATE CONTROL' "$UI" || fail "MechOS Update Center v2 title missing"
grep -Fq 'INSTALL UPDATES' "$UI" || fail "Install Updates action missing"
grep -Fq 'AVAILABLE UPDATE GROUPS' "$UI" || fail "update group cards missing"
grep -Fq 'VERIFIED + RECOVERABLE' "$UI" || fail "update protection panel missing"
grep -Fq 'mechos_count_label' "$UI" || fail "MechOS count/status card missing"
grep -Fq 'arch_count_label' "$UI" || fail "Arch package card missing"
grep -Fq 'flatpak_count_label' "$UI" || fail "Flatpak card missing"
grep -Fq 'recovery_state_label' "$UI" || fail "Recovery state card missing"
! grep -Eq 'QHBoxLayout|QVBoxLayout|QGridLayout|QFormLayout' "$UI" || fail "Update Center v2 regressed to layout-manager developer UI"

grep -Fq 'MECHOS_UPDATE_CENTER_V2_SAFE_ARCHIVE' "$INTEGRATION" || fail "safe archive parent-directory patch missing"
grep -Fq 'MECHOS_UPDATE_CENTER_V2_BACKEND' "$INTEGRATION" || fail "v2 backend patch missing"
grep -Fq "values.get('MECHOS_UPDATE_AVAILABLE')=='1'" "$INTEGRATION" || fail "MechOS hotfix availability is not part of Install button state"
grep -Fq 'self.update_count=total' "$INTEGRATION" || fail "reliable update_count assignment missing"
grep -Fq 'self.update_button.setEnabled(total > 0)' "$INTEGRATION" || fail "Install button enable rule missing"
grep -Fq '_mechos_v2_original_apply_updates' "$INTEGRATION" || fail "existing privileged apply path not preserved"
grep -Fq 'No installable update is currently selected' "$INTEGRATION" || fail "dead-click guard missing"
grep -Fq 'parents=set()' "$INTEGRATION" || fail "archive parent-directory compatibility missing"
grep -Fq 'mechos-update-center-v2-integration.sh' "$PATCHER" || fail "v2 integration is not wired into final build chain"

python3 - "$PATCHER" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
items=[
 'mechos-update-center-v1-integration.sh',
 'mechos-update-center-v1-runtime-guard.sh',
 'mechos-update-center-v2-integration.sh',
 'mechos-installer-auto-reboot-hotfix.sh',
]
pos=[text.find(x) for x in items]
if any(p < 0 for p in pos):
    raise SystemExit('[validate-update-center-v2] final updater stages incomplete')
if pos != sorted(pos):
    raise SystemExit('[validate-update-center-v2] v2 must run after v1 runtime guard and before later finalization stages')
PY

echo '[validate-update-center-v2] OK: Update Center uses native MechOS visual hierarchy, hotfix availability controls Install Updates, and verified bundles accept safe tar parent directories'
