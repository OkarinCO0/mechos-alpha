#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit('usage: patch-mechos-reference-v5.py <build-script>')

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_REFERENCE_UI_V5_FINAL'
if marker in text:
    raise SystemExit(0)

anchor = '\nmkarchiso -v \\\n'
pos = text.rfind(anchor)
if pos < 0:
    raise SystemExit('[MechOS Reference UI v5] final mkarchiso insertion point not found')
late = text.rfind('# MECHOS_CURRENT_INTEGRATION_LATE', 0, pos)
if late < 0:
    raise SystemExit('[MechOS Reference UI v5] current late integration stage not found before mkarchiso')

insert = '''

# MECHOS_REFERENCE_UI_V5_FINAL
bash /workspace/scripts/mechos-reference-v5-postinstall-stage.sh prepare
bash /workspace/scripts/mechos-reference-v5-integration.sh final
bash /workspace/scripts/mechos-reference-v5-store-layout.sh
bash /workspace/scripts/mechos-reference-v5-mechscope-layout.sh
bash /workspace/scripts/mechos-reference-v5-mechscope-exact-layout.sh
bash /workspace/scripts/mechos-reference-v5-creator-layout.sh
bash /workspace/scripts/mechos-reference-v5-controls-layout.sh
bash /workspace/scripts/mechos-reference-v5-controls-compat.sh
bash /workspace/scripts/mechos-aur-helper-integration.sh
bash /workspace/scripts/mechos-reference-v5-installer-layout.sh
bash /workspace/scripts/mechos-live-update-pacman-sandbox-hotfix.sh
bash /workspace/scripts/mechos-installer-radio-signal-hotfix.sh
bash /workspace/scripts/mechos-live-installer-runtime-guard.sh
bash /workspace/scripts/mechos-live-installer-crash-fallback.sh
bash /workspace/scripts/mechos-vm-ui-runtime-guard.sh
bash /workspace/scripts/mechos-vm-shortcut-launch-hotfix.sh
bash /workspace/scripts/mechos-native-ui-shell-integration.sh
bash /workspace/scripts/mechos-auto-optimization-hotfix.sh
bash /workspace/scripts/mechos-source-owned-system-ui.sh
bash /workspace/scripts/mechos-update-center-v1-integration.sh
bash /workspace/scripts/mechos-update-center-v1-runtime-guard.sh
bash /workspace/scripts/mechos-update-center-v2-integration.sh
bash /workspace/scripts/mechos-installer-auto-reboot-hotfix.sh
bash /workspace/scripts/mechos-installed-mechscope-launch-hotfix.sh
bash /workspace/scripts/mechos-vm-mode-runtime-final.sh
# FINAL FIRST-BOOT SESSION AUTHORITY. Before OOBE completion, installed systems
# are forced into the temporary setup account/Plasma session and VM fullscreen
# modes are blocked. After OOBE, normal MechScope/Creator routing resumes.
bash /workspace/scripts/mechos-firstboot-session-authority.sh
# FINAL VM APP FALLBACK. After the OOBE gate, MechScope and Creator first try
# their user service and then fall back to direct launch in the same Plasma VM
# graphical session if the user service cannot stay active.
bash /workspace/scripts/mechos-vm-app-launch-final.sh
# Install approved Plymouth artwork/theme first, then enforce the actual Live
# ArchISO + native Clean Install boot chain that consumes it.
bash /workspace/scripts/mechos-reference-splash-integration.sh
bash /workspace/scripts/mechos-plymouth-boot-final.sh
bash /workspace/scripts/mechos-reference-v5-postinstall-stage.sh commit
bash /workspace/scripts/mechos-finalize-install-payload.sh final
'''

text = text[:pos] + insert + text[pos:]
path.write_text(text, encoding='utf-8')
