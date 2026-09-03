#!/usr/bin/env bash
set -euo pipefail

FIX=scripts/mechos-vm-shortcut-launch-hotfix.sh
PATCHER=scripts/patch-mechos-reference-v5.py

bash -n "$FIX"
python3 -m py_compile "$PATCHER"

grep -Fq 'mechos-mode-launch' "$FIX"
grep -Fq 'systemd-detect-virt' "$FIX"
grep -Fq 'export MECHOS_DISABLE_GAMESCOPE=1' "$FIX"
grep -Fq 'export QT_OPENGL=software' "$FIX"
grep -Fq 'systemctl --user import-environment' "$FIX"
grep -Fq 'DBUS_SESSION_BUS_ADDRESS' "$FIX"
grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch creator' "$FIX"
grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch gaming' "$FIX"
grep -Fq 'Creator-Mode.desktop' "$FIX"
grep -Fq 'Return-to-MechScope.desktop' "$FIX"
grep -Fq 'mode-shortcut.log' "$FIX"
grep -Fq 'purge_legacy_shortcuts' "$FIX"
grep -Fq 'mechos-return-to-mechscope.desktop' "$FIX"
grep -Fq 'mechscope.desktop' "$FIX"
grep -Fq 'mechos-return-gaming.desktop' "$FIX"
grep -Fq 'patch_postinstall_shortcuts' "$FIX"

grep -Fq 'mechos-vm-shortcut-launch-hotfix.sh' "$PATCHER"

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
    'mechos-vm-ui-runtime-guard.sh',
    'mechos-vm-shortcut-launch-hotfix.sh',
    'mechos-reference-v5-postinstall-stage.sh commit',
    'mechos-finalize-install-payload.sh final',
]
pos=[text.find(item) for item in items]
if any(p < 0 for p in pos):
    raise SystemExit('VM shortcut launch stage is missing from final build chain')
if pos != sorted(pos):
    raise SystemExit('VM shortcut launch stage is in the wrong final build order')
print('VM shortcut final build-order validation passed.')
PY

echo 'MechOS VM Creator/MechScope shortcut cleanup validation passed.'
