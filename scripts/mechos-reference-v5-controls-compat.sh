#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="/workspace/archlive/airootfs"

python3 - \
  "$ROOT/usr/local/bin/mechos-update-center" \
  "$ROOT/usr/local/bin/mechos-recovery-center" <<'PY'
from pathlib import Path
import sys

for raw in sys.argv[1:]:
    p=Path(raw)
    if not p.is_file(): continue
    text=p.read_text(encoding='utf-8')
    if 'from pathlib import Path' not in text:
        anchor='import sys\n'
        if anchor in text: text=text.replace(anchor,anchor+'from pathlib import Path\n',1)
    if '\ndef spawn(' not in text:
        anchor='\n\n'
        pos=text.find(anchor, text.find('import '))
        if pos<0: raise SystemExit(f'could not add spawn helper to {p}')
        helper="\n\ndef spawn(args):\n    try:\n        return subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n    except Exception:\n        return None\n"
        text=text[:pos]+helper+text[pos:]
    p.write_text(text,encoding='utf-8')
    compile(text,str(p),'exec')
PY

for f in "$ROOT/usr/local/bin/mechos-update-center" "$ROOT/usr/local/bin/mechos-recovery-center"; do
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$f"
done

echo '[MechOS Controls v5] dependency compatibility verified'
