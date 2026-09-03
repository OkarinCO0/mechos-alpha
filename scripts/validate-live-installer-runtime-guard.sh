#!/usr/bin/env bash
set -euo pipefail

GUARD=scripts/mechos-live-installer-runtime-guard.sh
PATCHER=scripts/patch-mechos-reference-v5.py

bash -n "$GUARD"
python3 -m py_compile "$PATCHER"

grep -Fq 'MECHOS_LIVE_INSTALLER_RUNTIME_IMPORTS_V1' "$GUARD"
grep -Fq 'from PyQt6.QtCore import Qt, QTimer' "$GUARD"
grep -Fq 'from PyQt6.QtGui import QPixmap' "$GUARD"
grep -Fq 'QButtonGroup' "$GUARD"
grep -Fq 'QListWidgetItem' "$GUARD"
grep -Fq 'PYTHONFAULTHANDLER=1' "$GUARD"
grep -Fq 'QT_OPENGL=software' "$GUARD"
grep -Fq 'LIBGL_ALWAYS_SOFTWARE=1' "$GUARD"
grep -Fq '/tmp/mechos-live-setup.log' "$GUARD"
grep -Fq '/usr/local/libexec/mechos-live-setup-v5.py' "$GUARD"
grep -Fq 'mechos-live-installer-runtime-guard.sh' "$PATCHER"

# Simulate the same source-patcher chain used by the Build MechOS workflow and
# require the runtime guard to run after the final installer layout, but before
# post-install staging is committed and before mkarchiso starts.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cp scripts/build-mechos-archiso.sh "$tmp"
python3 scripts/patch-mechos-current.py "$tmp"
python3 scripts/patch-mechos-partition-screen.py "$tmp"
python3 scripts/patch-mechos-safe-mode-switching.py "$tmp"
python3 scripts/patch-mechos-default-wallpaper.py "$tmp"
python3 scripts/patch-mechos-substance-painter.py "$tmp"
python3 scripts/patch-mechos-creator-postinstall.py "$tmp"
python3 scripts/patch-mechos-rgb-quick-actions.py "$tmp"
bash scripts/patch-mechos-live-autologin-partitionmanager.sh "$tmp"
python3 scripts/patch-mechos-reference-v5.py "$tmp"
bash -n "$tmp"

python3 - "$tmp" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
items=[
 'mechos-reference-v5-installer-layout.sh',
 'mechos-live-installer-runtime-guard.sh',
 'mechos-reference-v5-postinstall-stage.sh commit',
 'mechos-finalize-install-payload.sh final',
]
pos=[text.find(x) for x in items]
if any(p < 0 for p in pos):
    raise SystemExit('Live installer runtime guard build stage is missing')
if pos != sorted(pos):
    raise SystemExit('Live installer runtime guard is in the wrong v5 build order')
mk=text.rfind('\nmkarchiso -v \\\n')
if mk < 0 or pos[-1] >= mk:
    raise SystemExit('Live installer finalization no longer happens before mkarchiso')
print('Live installer runtime guard build-order validation passed.')
PY

echo 'MechOS Live installer runtime guard validation passed.'
