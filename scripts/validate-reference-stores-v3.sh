#!/usr/bin/env bash
set -Eeuo pipefail

BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INTEGRATION="$BASE/scripts/mechos-reference-stores-v3-integration.sh"
PATCHER="$BASE/scripts/patch-mechos-current.py"

fail() { echo "Reference Stores v3 validation error: $*" >&2; exit 1; }

[ -f "$INTEGRATION" ] || fail "Reference Stores v3 integration is missing"
[ -f "$PATCHER" ] || fail "cumulative patcher is missing"

bash -n "$INTEGRATION" || fail "Reference Stores v3 integration shell syntax failed"
python3 -m py_compile "$PATCHER" || fail "cumulative patcher Python syntax failed"

# Bash syntax checking does not parse Python here-doc bodies. Compile every
# embedded Python generator so nested quote mistakes fail source validation
# before an expensive ArchISO build starts.
python3 - "$INTEGRATION" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding='utf-8')
blocks = re.findall(r"<<'PY'\n(.*?)\nPY(?:\n|$)", text, flags=re.S)
if not blocks:
    raise SystemExit('Reference Stores v3 validation error: no embedded Python blocks found')
for index, block in enumerate(blocks, 1):
    try:
        compile(block, f'reference-stores-v3-heredoc-{index}', 'exec')
    except SyntaxError as exc:
        raise SystemExit(f'Reference Stores v3 validation error: embedded Python block {index} is invalid: {exc}')
print(f'Reference Stores v3 embedded Python syntax passed: {len(blocks)} blocks')
PY

grep -Fq 'MECHOS_REFERENCE_UNIFIED_STORE_V3' "$INTEGRATION" || fail "Unified Store v3 marker is missing"
grep -Fq 'Every game store. One MechOS view.' "$INTEGRATION" || fail "Unified Store hero layout is missing"
grep -Fq 'MECHOS_REFERENCE_CREATOR_STORE_V3' "$INTEGRATION" || fail "Creator Store v3 marker is missing"
grep -Fq 'ONE-CLICK CREATOR BUNDLES' "$INTEGRATION" || fail "Creator Store bundle section is missing"
grep -Fq 'Game Engines' "$INTEGRATION" || fail "Creator Store engine category is missing"
grep -Fq '3D & Art' "$INTEGRATION" || fail "Creator Store art category is missing"
grep -Fq 'Streaming' "$INTEGRATION" || fail "Creator Store streaming category is missing"
grep -Fq 'Windows Tools' "$INTEGRATION" || fail "Creator Store Windows tools category is missing"
grep -Fq 'MECHOS_CREATOR_RETURN_TO_MECHSCOPE_V2' "$INTEGRATION" || fail "Creator return-to-MechScope fix is missing"
grep -Fq 'MECHOS_CREATOR_READINESS_HANDOFF_V2' "$INTEGRATION" || fail "Creator readiness handoff is missing"
grep -Fq 'mechos-reference-stores-v3-integration.sh final' "$PATCHER" || fail "Reference Stores v3 is not wired into the ISO build"

echo "Reference Store and Creator Store v3 source validation passed."
