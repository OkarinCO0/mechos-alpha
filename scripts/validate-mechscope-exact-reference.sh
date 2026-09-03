#!/usr/bin/env bash
set -euo pipefail

LAYOUT=scripts/mechos-reference-v5-mechscope-exact-layout.sh
PATCHER=scripts/patch-mechos-reference-v5.py

bash -n "$LAYOUT"
python3 -m py_compile "$PATCHER"

# Compile every Python heredoc in the exact-reference patcher. This catches
# nested quote mistakes before an ArchISO build reaches the generated UI.
python3 - "$LAYOUT" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); text=p.read_text(encoding='utf-8')
blocks=re.findall(r"<<'PY'\n(.*?)\nPY(?:\n|$)",text,re.S)
if not blocks:
    raise SystemExit('exact MechScope patch has no Python heredoc')
for i,block in enumerate(blocks,1):
    compile(block,f'{p}:PY{i}','exec')
print('Exact MechScope embedded Python syntax passed.')
PY

grep -Fq 'MECHOS_REFERENCE_MECHSCOPE_EXACT_V1' "$LAYOUT"
grep -Fq 'class MechReferenceGauge' "$LAYOUT"
grep -Fq 'mechos_gpu_load_percent' "$LAYOUT"
grep -Fq 'RECENT GAMES' "$LAYOUT"
grep -Fq 'QUICK MODES' "$LAYOUT"
grep -Fq 'SYSTEM STATUS' "$LAYOUT"
grep -Fq 'QUICK ACTIONS' "$LAYOUT"
grep -Fq 'LAUNCHERS' "$LAYOUT"
grep -Fq 'Creator Store' "$LAYOUT"
grep -Fq 'Recovery Center' "$LAYOUT"
grep -Fq 'showFullScreen()' "$LAYOUT"
grep -Fq 'reference-hero-v5.svg' "$LAYOUT"
grep -Fq 'self.games[:6]' "$LAYOUT"
grep -Fq 'gpu_name()' "$LAYOUT"
grep -Fq 'cpu_percent()' "$LAYOUT"
grep -Fq 'ram_percent()' "$LAYOUT"
grep -Fq 'disk_percent()' "$LAYOUT"

# Ensure the exact composition is applied after the base MechScope v5 layout
# but before Creator/controls/VM runtime stages and before the ISO is packed.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cp scripts/build-mechos-archiso.sh "$tmp"
python3 scripts/patch-mechos-current.py "$tmp"
python3 scripts/patch-mechos-reference-v5.py "$tmp"
bash -n "$tmp"

python3 - "$tmp" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
items=[
 'mechos-reference-v5-mechscope-layout.sh',
 'mechos-reference-v5-mechscope-exact-layout.sh',
 'mechos-reference-v5-creator-layout.sh',
 'mechos-reference-v5-controls-layout.sh',
 'mechos-vm-ui-runtime-guard.sh',
 'mechos-finalize-install-payload.sh final',
]
pos=[text.find(x) for x in items]
if any(x < 0 for x in pos):
    raise SystemExit('exact MechScope final build chain is incomplete')
if pos != sorted(pos):
    raise SystemExit('exact MechScope layout is in the wrong final build order')
print('Exact MechScope final build-order validation passed.')
PY

grep -Fq 'mechos-reference-v5-mechscope-exact-layout.sh' "$PATCHER"

echo 'MechOS exact MechScope reference validation passed.'
