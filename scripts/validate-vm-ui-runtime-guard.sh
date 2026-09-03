#!/usr/bin/env bash
set -euo pipefail

GUARD=scripts/mechos-vm-ui-runtime-guard.sh
PATCHER=scripts/patch-mechos-reference-v5.py

bash -n "$GUARD"
python3 -m py_compile "$PATCHER"

grep -Fq 'MECHOS_VM_UI_RUNTIME_GUARD_V2' "$GUARD"
grep -Fq 'systemd-detect-virt' "$GUARD"
grep -Fq "QT_OPENGL']='software'" "$GUARD"
grep -Fq "MECHOS_DISABLE_GAMESCOPE']='1'" "$GUARD"
grep -Fq 'MECHOS_VM_SYSTEMD_DETECT_VIRT_V2' "$GUARD"
grep -Fq 'run_direct_mechscope' "$GUARD"
grep -Fq 'MECHOS_CREATOR_GRAPHICAL_ENV_V1' "$GUARD"
grep -Fq 'systemctl --user import-environment DISPLAY WAYLAND_DISPLAY' "$GUARD"
grep -Fq 'mechos-vm-ui-runtime-guard.sh' "$PATCHER"

# The VM guard must run only after the final MechScope/Creator layouts exist,
# while Creator Mode is still temporarily materialized for post-install capture.
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
 'mechos-reference-v5-postinstall-stage.sh prepare',
 'mechos-reference-v5-mechscope-layout.sh',
 'mechos-reference-v5-creator-layout.sh',
 'mechos-vm-ui-runtime-guard.sh',
 'mechos-reference-v5-postinstall-stage.sh commit',
 'mechos-finalize-install-payload.sh final',
]
pos=[text.find(x) for x in items]
if any(p < 0 for p in pos):
    raise SystemExit('VM UI runtime build stage is incomplete')
if pos != sorted(pos):
    raise SystemExit('VM UI runtime guard is in the wrong build order')
print('MechScope/Creator VM runtime build-order validation passed.')
PY

echo 'MechOS VM UI runtime guard validation passed.'
