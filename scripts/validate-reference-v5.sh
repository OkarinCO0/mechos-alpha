#!/usr/bin/env bash
set -euo pipefail

bash -n scripts/mechos-reference-v5-integration.sh
bash -n scripts/mechos-finalize-install-payload.sh
python3 -m py_compile scripts/patch-mechos-reference-v5.py

grep -Fq 'MECHOS_REFERENCE_UI_V5' scripts/mechos-reference-v5-integration.sh
grep -Fq 'Reference UI v5 applied as final Live UI authority' scripts/mechos-reference-v5-integration.sh
grep -Fq 'postinstall_matches_live_reference_runtime' scripts/mechos-reference-v5-integration.sh
grep -Fq 'QButtonGroup' scripts/mechos-reference-v5-integration.sh
grep -Fq 'powerprofilesctl' scripts/mechos-reference-v5-integration.sh
grep -Eq 'checkupdates|mechos-update-helper' scripts/mechos-reference-v5-integration.sh
grep -Eq 'wpctl|nmcli' scripts/mechos-reference-v5-integration.sh
grep -Fq 'repair-boot' scripts/mechos-reference-v5-integration.sh
grep -Fq 'mechos-rootfs.tar.zst' scripts/mechos-finalize-install-payload.sh
grep -Fq 'reference-ui-v5.json' scripts/mechos-finalize-install-payload.sh
grep -Fq 'MECHOS_REFERENCE_UI_V5_FINAL' scripts/patch-mechos-reference-v5.py

echo 'MechOS Reference UI v5 source validation passed.'
