#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INTEGRATION="$ROOT/scripts/mechos-vm-mode-runtime-final.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"
fail(){ echo "[validate-vm-mode-runtime-final] ERROR: $*" >&2; exit 1; }

[ -f "$INTEGRATION" ] || fail "VM mode runtime integration missing"
bash -n "$INTEGRATION" || fail "VM mode runtime integration shell syntax failed"
grep -Fq 'MECHOS_VM_MODE_RUNTIME_ROUTER_V1' "$INTEGRATION" || fail "gaming-layer VM router missing"
grep -Fq 'MECHOS_VM_PLASMA_HOST_V2' "$INTEGRATION" || fail "mechscope-session VM Plasma host patch missing"
grep -Fq 'mechos-vm-mode-runtime boot' "$INTEGRATION" || fail "KDE graphical autostart handoff missing"
grep -Fq 'mechos-vm-mechscope.service' "$INTEGRATION" || fail "VM MechScope user service missing"
grep -Fq 'mechos-vm-creator.service' "$INTEGRATION" || fail "VM Creator user service missing"
grep -Fq 'first_run_tutorial' "$INTEGRATION" || fail "first-run tutorial handoff missing"
grep -Fq 'systemd-detect-virt' "$INTEGRATION" || fail "virtualization detection missing"
grep -Fq 'MECHOS_DISABLE_GAMESCOPE=1' "$INTEGRATION" || fail "VM Gamescope bypass missing"
grep -Fq 'exec /usr/bin/startplasma-wayland' "$INTEGRATION" || fail "VM session no longer anchored to Plasma"
grep -Fq 'mechos-vm-mode-runtime-final.sh' "$PATCHER" || fail "VM mode runtime is not wired into final build chain"

python3 - "$PATCHER" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
a=text.find('mechos-installed-mechscope-launch-hotfix.sh')
b=text.find('mechos-vm-mode-runtime-final.sh')
c=text.find('mechos-reference-splash-integration.sh')
if min(a,b,c) < 0 or not (a < b < c):
    raise SystemExit('[validate-vm-mode-runtime-final] VM runtime must follow installed session generation and precede final splash')
PY

echo '[validate-vm-mode-runtime-final] OK: VMs retain Plasma, launch modes after graphical readiness, route shortcuts/internal controller calls through VM runtime, and preserve the physical Gamescope path'
