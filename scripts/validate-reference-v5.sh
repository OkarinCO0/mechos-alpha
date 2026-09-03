#!/usr/bin/env bash
set -euo pipefail

V5_SCRIPTS=(
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

grep -Fq 'mechos-rootfs.tar.zst' scripts/mechos-finalize-install-payload.sh
grep -Fq 'reference-ui-v5.json' scripts/mechos-finalize-install-payload.sh
grep -Fq 'MECHOS_REFERENCE_UI_V5_FINAL' scripts/patch-mechos-reference-v5.py
grep -Fq 'mechos-reference-v5-store-layout.sh' scripts/patch-mechos-reference-v5.py
grep -Fq 'mechos-reference-v5-mechscope-layout.sh' scripts/patch-mechos-reference-v5.py
grep -Fq 'mechos-reference-v5-creator-layout.sh' scripts/patch-mechos-reference-v5.py
grep -Fq 'mechos-reference-v5-controls-layout.sh' scripts/patch-mechos-reference-v5.py
grep -Fq 'mechos-reference-v5-installer-layout.sh' scripts/patch-mechos-reference-v5.py

echo 'MechOS Reference UI v5 source validation passed.'
