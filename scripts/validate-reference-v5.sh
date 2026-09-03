#!/usr/bin/env bash
set -euo pipefail

bash -n scripts/mechos-reference-v5-integration.sh
bash -n scripts/mechos-reference-v5-store-layout.sh
bash -n scripts/mechos-reference-v5-creator-layout.sh
bash -n scripts/mechos-reference-v5-controls-layout.sh
bash -n scripts/mechos-reference-v5-controls-compat.sh
bash -n scripts/mechos-reference-v5-installer-layout.sh
bash -n scripts/mechos-finalize-install-payload.sh
python3 -m py_compile scripts/patch-mechos-reference-v5.py

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
grep -Fq 'mechos-reference-v5-creator-layout.sh' scripts/patch-mechos-reference-v5.py
grep -Fq 'mechos-reference-v5-controls-layout.sh' scripts/patch-mechos-reference-v5.py
grep -Fq 'mechos-reference-v5-installer-layout.sh' scripts/patch-mechos-reference-v5.py

echo 'MechOS Reference UI v5 source validation passed.'
