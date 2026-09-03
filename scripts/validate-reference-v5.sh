#!/usr/bin/env bash
set -euo pipefail

V5_SCRIPTS=(
  scripts/mechos-reference-v5-postinstall-stage.sh
  scripts/mechos-reference-v5-integration.sh
  scripts/mechos-reference-v5-store-layout.sh
  scripts/mechos-reference-v5-mechscope-layout.sh
  scripts/mechos-reference-v5-creator-layout.sh
  scripts/mechos-reference-v5-controls-layout.sh
  scripts/mechos-reference-v5-controls-compat.sh
  scripts/mechos-reference-v5-installer-layout.sh
  scripts/mechos-finalize-install-payload.sh
)
for f in "${V5_SCRIPTS[@]}"; do bash -n "$f"; done
python3 -m py_compile scripts/patch-mechos-reference-v5.py

# Reproduce the exact cumulative patch order used by the ISO workflow against a
# disposable builder copy. This catches ordering/anchor failures before the
# expensive ArchISO build begins.
TMP_BUILDER="$(mktemp)"
trap 'rm -f "$TMP_BUILDER"' EXIT
cp scripts/build-mechos-archiso.sh "$TMP_BUILDER"
python3 scripts/patch-mechos-current.py "$TMP_BUILDER"
python3 scripts/patch-mechos-partition-screen.py "$TMP_BUILDER"
python3 scripts/patch-mechos-safe-mode-switching.py "$TMP_BUILDER"
python3 scripts/patch-mechos-default-wallpaper.py "$TMP_BUILDER"
python3 scripts/patch-mechos-substance-painter.py "$TMP_BUILDER"
python3 scripts/patch-mechos-creator-postinstall.py "$TMP_BUILDER"
python3 scripts/patch-mechos-rgb-quick-actions.py "$TMP_BUILDER"
bash scripts/patch-mechos-live-autologin-partitionmanager.sh "$TMP_BUILDER"
python3 scripts/patch-mechos-reference-v5.py "$TMP_BUILDER"
bash -n "$TMP_BUILDER"
test "$(grep -c '^# MECHOS_REFERENCE_UI_V5_FINAL$' "$TMP_BUILDER")" -eq 1
grep -Fq 'mechos-reference-v5-postinstall-stage.sh prepare' "$TMP_BUILDER"
grep -Fq 'mechos-reference-v5-integration.sh final' "$TMP_BUILDER"
grep -Fq 'mechos-reference-v5-postinstall-stage.sh commit' "$TMP_BUILDER"
grep -Fq 'mechos-finalize-install-payload.sh final' "$TMP_BUILDER"
python3 - "$TMP_BUILDER" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
v5=text.rfind('# MECHOS_REFERENCE_UI_V5_FINAL')
mk=text.rfind('\nmkarchiso -v \\\n')
if v5 < 0 or mk < 0 or v5 >= mk:
    raise SystemExit('Reference UI v5 is not immediately upstream of the final ArchISO build stage')
required=(
    'mechos-reference-v5-postinstall-stage.sh prepare',
    'mechos-reference-v5-store-layout.sh',
    'mechos-reference-v5-mechscope-layout.sh',
    'mechos-reference-v5-creator-layout.sh',
    'mechos-reference-v5-controls-layout.sh',
    'mechos-reference-v5-controls-compat.sh',
    'mechos-reference-v5-installer-layout.sh',
    'mechos-reference-v5-postinstall-stage.sh commit',
    'mechos-finalize-install-payload.sh final',
)
positions=[]
for item in required:
    p=text.find(item,v5,mk)
    if p < 0:
        raise SystemExit(f'missing final v5 build stage: {item}')
    positions.append(p)
if positions != sorted(positions):
    raise SystemExit('Reference UI v5 post-install staging order is incorrect')
print('Reference UI v5 cumulative patch-chain simulation passed.')
PY

# Compile every quoted PY heredoc used by the v5 generators. This catches the
# nested-quote/parser class of bug before the expensive ArchISO workflow.
python3 - <<'PY'
from pathlib import Path
import re
scripts=[
 'scripts/mechos-reference-v5-store-layout.sh',
 'scripts/mechos-reference-v5-mechscope-layout.sh',
 'scripts/mechos-reference-v5-creator-layout.sh',
 'scripts/mechos-reference-v5-controls-layout.sh',
 'scripts/mechos-reference-v5-controls-compat.sh',
 'scripts/mechos-reference-v5-installer-layout.sh',
]
for name in scripts:
    text=Path(name).read_text(encoding='utf-8')
    blocks=re.findall(r"<<'PY'\n(.*?)\nPY(?:\n|$)",text,re.S)
    if not blocks:
        raise SystemExit(f'No Python heredoc found in {name}')
    for i,block in enumerate(blocks,1):
        compile(block,f'{name}:PY{i}','exec')
print('Reference UI v5 embedded Python syntax passed.')
PY

grep -Fq 'POSTINSTALL_SURFACES' scripts/mechos-reference-v5-postinstall-stage.sh
grep -Fq 'mechos-creator-mode' scripts/mechos-reference-v5-postinstall-stage.sh
grep -Fq 'mechos-quick-actions' scripts/mechos-reference-v5-postinstall-stage.sh
grep -Fq 'removed temporary Live copy' scripts/mechos-reference-v5-postinstall-stage.sh

grep -Fq 'MECHOS_REFERENCE_UI_V5' scripts/mechos-reference-v5-integration.sh
grep -Fq 'Reference UI v5 applied as final Live UI authority' scripts/mechos-reference-v5-integration.sh
grep -Fq 'postinstall_matches_live_reference_runtime' scripts/mechos-reference-v5-integration.sh
grep -Fq 'powerprofilesctl' scripts/mechos-reference-v5-integration.sh
grep -Eq 'checkupdates|mechos-update-helper' scripts/mechos-reference-v5-integration.sh
grep -Eq 'wpctl|nmcli' scripts/mechos-reference-v5-integration.sh
grep -Fq 'repair-boot' scripts/mechos-reference-v5-integration.sh

grep -Fq 'MECHOS_REFERENCE_UNIFIED_STORE_V5' scripts/mechos-reference-v5-store-layout.sh
grep -Fq 'ONE LIBRARY.' scripts/mechos-reference-v5-store-layout.sh
grep -Fq 'COMPATIBILITY GUIDE' scripts/mechos-reference-v5-store-layout.sh
grep -Fq 'steam_games()' scripts/mechos-reference-v5-store-layout.sh

grep -Fq 'MECHOS_REFERENCE_MECHSCOPE_V5' scripts/mechos-reference-v5-mechscope-layout.sh
grep -Fq 'RECENT GAMES' scripts/mechos-reference-v5-mechscope-layout.sh
grep -Fq 'QUICK MODES' scripts/mechos-reference-v5-mechscope-layout.sh
grep -Fq 'SYSTEM STATUS' scripts/mechos-reference-v5-mechscope-layout.sh

grep -Fq 'MECHOS_REFERENCE_CREATOR_V5_DASHBOARD' scripts/mechos-reference-v5-creator-layout.sh
grep -Fq 'PROJECT PROFILES' scripts/mechos-reference-v5-creator-layout.sh
grep -Fq 'ASSET PIPELINES' scripts/mechos-reference-v5-creator-layout.sh
grep -Fq 'PLUGINS & TOOLKITS' scripts/mechos-reference-v5-creator-layout.sh
grep -Fq 'MECHOS_REFERENCE_CREATOR_STORE_V5' scripts/mechos-reference-v5-creator-layout.sh
grep -Fq 'ONE-CLICK WORKFLOWS' scripts/mechos-reference-v5-creator-layout.sh

grep -Fq 'MECHOS_REFERENCE_PERFORMANCE_V5' scripts/mechos-reference-v5-controls-layout.sh
grep -Fq 'MECHOS_REFERENCE_UPDATE_V5' scripts/mechos-reference-v5-controls-layout.sh
grep -Fq 'MECHOS_REFERENCE_QUICK_ACTIONS_V5' scripts/mechos-reference-v5-controls-layout.sh
grep -Fq 'MECHOS_REFERENCE_RECOVERY_V5' scripts/mechos-reference-v5-controls-layout.sh
grep -Fq 'mechos-rgb-keyboard' scripts/mechos-reference-v5-controls-layout.sh
grep -Fq 'wpctl' scripts/mechos-reference-v5-controls-layout.sh
grep -Fq 'mechos-stream-control' scripts/mechos-reference-v5-controls-layout.sh

grep -Fq 'MECHOS_REFERENCE_INSTALLER_V5' scripts/mechos-reference-v5-installer-layout.sh
grep -Fq 'CHOOSE INSTALLATION OPTION' scripts/mechos-reference-v5-installer-layout.sh
grep -Fq 'QButtonGroup' scripts/mechos-reference-v5-installer-layout.sh
grep -Fq 'Install Alongside Existing OS' scripts/mechos-reference-v5-installer-layout.sh
grep -Fq 'mechos-native-install' scripts/mechos-reference-v5-installer-layout.sh
grep -Fq 'mechos-live-update-keep-home' scripts/mechos-reference-v5-installer-layout.sh
grep -Fq 'mechos-alongside-assistant' scripts/mechos-reference-v5-installer-layout.sh
grep -Fq -- '--preserve-home' scripts/mechos-reference-v5-installer-layout.sh

grep -Fq 'POSTINSTALL_STAGE' scripts/mechos-finalize-install-payload.sh
grep -Fq 'MECHOS_REFERENCE_CREATOR_V5' scripts/mechos-finalize-install-payload.sh
grep -Fq 'MECHOS_REFERENCE_QUICK_ACTIONS_V5' scripts/mechos-finalize-install-payload.sh
grep -Fq 'mechos-rootfs.tar.zst' scripts/mechos-finalize-install-payload.sh
grep -Fq 'reference-ui-v5.json' scripts/mechos-finalize-install-payload.sh
grep -Fq 'MECHOS_REFERENCE_UI_V5_FINAL' scripts/patch-mechos-reference-v5.py
grep -Fq 'mechos-reference-v5-postinstall-stage.sh prepare' scripts/patch-mechos-reference-v5.py
grep -Fq 'mechos-reference-v5-postinstall-stage.sh commit' scripts/patch-mechos-reference-v5.py
grep -Fq 'mechos-reference-v5-store-layout.sh' scripts/patch-mechos-reference-v5.py
grep -Fq 'mechos-reference-v5-mechscope-layout.sh' scripts/patch-mechos-reference-v5.py
grep -Fq 'mechos-reference-v5-creator-layout.sh' scripts/patch-mechos-reference-v5.py
grep -Fq 'mechos-reference-v5-controls-layout.sh' scripts/patch-mechos-reference-v5.py
grep -Fq 'mechos-reference-v5-installer-layout.sh' scripts/patch-mechos-reference-v5.py

echo 'MechOS Reference UI v5 source validation passed.'
