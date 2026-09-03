#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit('usage: patch-mechos-reference-v5.py <build-script>')

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_REFERENCE_UI_V5_FINAL'
if marker in text:
    raise SystemExit(0)

needle = 'bash /workspace/scripts/mechos-current-integration.sh final\n\nmkarchiso -v'
insert = '''bash /workspace/scripts/mechos-current-integration.sh final

# MECHOS_REFERENCE_UI_V5_FINAL
# The approved visual reference is the last UI authority. The richer Store v5
# layout runs after all older store/theme patches, then the finished runtime is
# repacked so post-install and Live receive the same UI.
bash /workspace/scripts/mechos-reference-v5-integration.sh final
bash /workspace/scripts/mechos-reference-v5-store-layout.sh
bash /workspace/scripts/mechos-finalize-install-payload.sh final

mkarchiso -v'''
if needle not in text:
    raise SystemExit('[MechOS Reference UI v5] late build insertion point not found')

text = text.replace(needle, insert, 1)
path.write_text(text, encoding='utf-8')
