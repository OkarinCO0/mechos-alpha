#!/usr/bin/env bash
set -Eeuo pipefail

HOTFIX=scripts/mechos-live-update-pacman-sandbox-hotfix.sh
PATCHER=scripts/patch-mechos-reference-v5.py

[ -f "$HOTFIX" ] || { echo 'Live Update pacman sandbox hotfix missing' >&2; exit 1; }
[ -f "$PATCHER" ] || { echo 'Reference v5 patcher missing' >&2; exit 1; }

bash -n "$HOTFIX"
python3 -m py_compile "$PATCHER"

grep -Fq 'MECHOS_LIVE_UPDATE_PACMAN_SANDBOX_V1' "$HOTFIX"
grep -Fq 'systemd-sysusers' "$HOTFIX"
grep -Fq 'pacman-conf DownloadUser' "$HOTFIX"
grep -Fq "chmod 755" "$HOTFIX"
grep -Fq -- "-name 'download-*'" "$HOTFIX"
grep -Fq 'pacman_live_update()' "$HOTFIX"
grep -Fq -- '--disable-sandbox' "$HOTFIX"
grep -Fq 'never edit the target' "$HOTFIX"
grep -Fq 'mechos-live-update-pacman-sandbox-hotfix.sh' "$PATCHER"

# Compile every embedded Python heredoc in the hotfix so nested quoting errors
# are caught before the ArchISO build starts.
python3 - <<'PY'
from pathlib import Path
import re
p=Path('scripts/mechos-live-update-pacman-sandbox-hotfix.sh')
text=p.read_text(encoding='utf-8')
blocks=re.findall(r"<<'PY'\n(.*?)\nPY(?:\n|$)",text,re.S)
if not blocks:
    raise SystemExit('No embedded Python block found in Live Update pacman hotfix')
for i,block in enumerate(blocks,1):
    compile(block,f'{p}:PY{i}','exec')
print('Live Update pacman hotfix embedded Python syntax passed.')
PY

# Reconstruct enough of the real build chain to prove the Keep-Home helper is
# generated before the late Pacman sandbox patch and both run before mkarchiso.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
cp scripts/build-mechos-archiso.sh "$TMP"
python3 scripts/patch-mechos-current.py "$TMP"
python3 scripts/patch-mechos-reference-v5.py "$TMP"
bash -n "$TMP"
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
items=(
    'mechos-live-update-keep-home-integration.sh final',
    'mechos-live-update-pacman-sandbox-hotfix.sh',
    'mkarchiso -v',
)
pos=[]
for item in items:
    p=text.find(item)
    if p < 0:
        raise SystemExit(f'missing Live Update build stage: {item}')
    pos.append(p)
if pos != sorted(pos):
    raise SystemExit('Live Update pacman sandbox hotfix build order is incorrect')
print('Live Update pacman sandbox build order passed.')
PY

echo 'MechOS Live Update pacman sandbox validation passed.'
