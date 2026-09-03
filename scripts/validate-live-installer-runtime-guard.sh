#!/usr/bin/env bash
set -euo pipefail

GUARD=scripts/mechos-live-installer-runtime-guard.sh
RADIO=scripts/mechos-installer-radio-signal-hotfix.sh
FALLBACK=scripts/mechos-live-installer-crash-fallback.sh
PATCHER=scripts/patch-mechos-reference-v5.py
INSTALLER=scripts/mechos-reference-v5-installer-layout.sh

bash -n "$GUARD"
bash -n "$RADIO"
bash -n "$FALLBACK"
bash -n "$INSTALLER"
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

grep -Fq 'MECHOS_INSTALLER_RADIO_SIGNAL_GUARD_V1' "$RADIO"
grep -Fq "default_button.blockSignals(True)" "$RADIO"
grep -Fq "default_button.setChecked(True)" "$RADIO"
grep -Fq "default_button.blockSignals(False)" "$RADIO"
grep -Fq 'def mode_toggled(self,mode,checked):' "$RADIO"
grep -Fq 'except Exception as exc:' "$RADIO"
grep -Fq 'self.mode_checks[mode]=check' "$RADIO"
grep -Fq 'for m,c in self.mode_checks.items()' "$RADIO"

grep -Fq 'MECHOS_LIVE_INSTALLER_SAFE_FALLBACK_V1' "$FALLBACK"
grep -Fq 'MECHOS_LIVE_INSTALLER_CRASH_FALLBACK_V1' "$FALLBACK"
grep -Fq '/usr/local/bin/mechos-native-install' "$FALLBACK"
grep -Fq 'mechos-live-update-keep-home' "$FALLBACK"
grep -Fq 'mechos-alongside-assistant' "$FALLBACK"
grep -Fq -- '--preserve-home' "$FALLBACK"
grep -Fq 'coredumpctl info /usr/bin/python3' "$FALLBACK"
grep -Fq 'mechos-installer-radio-signal-hotfix.sh' "$PATCHER"
grep -Fq 'mechos-live-installer-runtime-guard.sh' "$PATCHER"
grep -Fq 'mechos-live-installer-crash-fallback.sh' "$PATCHER"

# Reference v5 must not choose Clean Install until all UI state targets exist.
# The later radio guard then changes this raw setChecked call into signal-blocked
# initialization before the ISO is packed.
python3 - "$INSTALLER" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
select=text.find("self.mode_buttons['clean'].setChecked(True)")
required=[
    text.find('self.warning_text='),
    text.find('self.ov_drive='),
    text.find('self.ov_mode='),
    text.find('self.ov_partition='),
    text.find('self.ov_fs='),
]
if select < 0 or any(p < 0 for p in required):
    raise SystemExit('v5 installer default-mode initialization markers are missing')
if select <= max(required):
    raise SystemExit('v5 installer selects Clean Install before state widgets exist')
print('v5 installer pre-guard initialization order passed.')
PY

# Simulate the same source-patcher chain used by the Build MechOS workflow and
# require radio guard -> runtime guard -> fallback ordering after the final v5
# installer layout, before post-install staging and mkarchiso.
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
 'mechos-installer-radio-signal-hotfix.sh',
 'mechos-live-installer-runtime-guard.sh',
 'mechos-live-installer-crash-fallback.sh',
 'mechos-reference-v5-postinstall-stage.sh commit',
 'mechos-finalize-install-payload.sh final',
]
pos=[text.find(x) for x in items]
if any(p < 0 for p in pos):
    raise SystemExit('Live installer radio/runtime/fallback build stage is missing')
if pos != sorted(pos):
    raise SystemExit('Live installer radio/runtime/fallback stages are in the wrong v5 build order')
mk=text.rfind('\nmkarchiso -v \\\n')
if mk < 0 or pos[-1] >= mk:
    raise SystemExit('Live installer finalization no longer happens before mkarchiso')
print('Live installer radio/runtime/fallback build-order validation passed.')
PY

echo 'MechOS Live installer radio/runtime/fallback validation passed.'
