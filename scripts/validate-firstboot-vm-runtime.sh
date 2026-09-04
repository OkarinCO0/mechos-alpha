#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIRSTBOOT="$ROOT/scripts/mechos-firstboot-session-authority.sh"
VMAPP="$ROOT/scripts/mechos-vm-app-launch-final.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"
fail(){ echo "[validate-firstboot-vm-runtime] ERROR: $*" >&2; exit 1; }

for f in "$FIRSTBOOT" "$VMAPP"; do
  [ -f "$f" ] || fail "missing $f"
  bash -n "$f" || fail "shell syntax failed: $f"
done

grep -Fq 'Before=sddm.service display-manager.service' "$FIRSTBOOT" || fail "firstboot authority is not before SDDM"
grep -Fq 'User=mechos-setup' "$FIRSTBOOT" || fail "temporary OOBE account autologin missing"
grep -Fq 'Session=plasma.desktop' "$FIRSTBOOT" || fail "OOBE is not forced into Plasma"
grep -Fq 'mechos-oobe-start' "$FIRSTBOOT" || fail "OOBE launcher missing"
grep -Fq 'MECHOS_VM_OOBE_GATE_V1' "$FIRSTBOOT" || fail "VM OOBE gate missing"
grep -Fq 'OOBE incomplete; VM mode launch blocked' "$FIRSTBOOT" || fail "MechScope/Creator firstboot block missing"
grep -Fq 'ln -sfn /usr/lib/systemd/system/mechos-firstboot-authority.service' "$FIRSTBOOT" || fail "firstboot service symlink creation missing"
grep -Fq '"$wants/mechos-firstboot-authority.service"' "$FIRSTBOOT" || fail "firstboot service is not statically enabled in graphical.target.wants"

grep -Fq 'MECHOS_VM_DIRECT_APP_FALLBACK_V1' "$VMAPP" || fail "VM direct app fallback missing"
grep -Fq 'nohup "$executable"' "$VMAPP" || fail "direct Plasma-session fallback missing"
grep -Fq 'start_mode_app mechos-vm-mechscope.service' "$VMAPP" || fail "MechScope does not use fallback"
grep -Fq 'start_mode_app mechos-vm-creator.service' "$VMAPP" || fail "Creator Mode does not use fallback"

python3 - "$PATCHER" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
items=[
 'mechos-vm-mode-runtime-final.sh',
 'mechos-firstboot-session-authority.sh',
 'mechos-vm-app-launch-final.sh',
 'mechos-reference-splash-integration.sh',
]
pos=[text.find(x) for x in items]
if any(p < 0 for p in pos):
    raise SystemExit('[validate-firstboot-vm-runtime] final session stages missing')
if pos != sorted(pos):
    raise SystemExit('[validate-firstboot-vm-runtime] VM/OOBE/app fallback order is wrong')
PY

echo '[validate-firstboot-vm-runtime] OK: installed first boot is gated by OOBE and VM MechScope/Creator have direct Plasma fallback'
