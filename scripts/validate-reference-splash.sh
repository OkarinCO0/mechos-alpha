#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPLASH="$ROOT/branding/mechos-splash-reference.png"
INTEGRATION="$ROOT/scripts/mechos-reference-splash-integration.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"
fail(){ echo "[validate-reference-splash] ERROR: $*" >&2; exit 1; }

[ -s "$SPLASH" ] || fail "branding/mechos-splash-reference.png missing"
[ -f "$INTEGRATION" ] || fail "reference splash integration missing"
bash -n "$INTEGRATION" || fail "reference splash integration shell syntax failed"
grep -Fq 'MECHOS_REFERENCE_SPLASH_V1' "$INTEGRATION" || fail "reference Plymouth marker missing"
grep -Fq 'Image("mechos-splash-reference.png")' "$INTEGRATION" || fail "Plymouth is not loading the approved reference image"
grep -Fq 'reference.original.Scale' "$INTEGRATION" || fail "reference image is not scaled for the active display"
grep -Fq 'scale.y < scale.x' "$INTEGRATION" || fail "aspect-preserving letterbox logic missing"
grep -Fq 'Theme=mechos' "$INTEGRATION" || fail "Plymouth theme selection missing"
grep -Fq 'MECHOS_REFERENCE_SPLASH_POSTINSTALL_V1' "$INTEGRATION" || fail "installed-system splash reassertion missing"
grep -Fq 'mkinitcpio -P' "$INTEGRATION" || fail "installed initramfs refresh missing"
grep -Fq 'mechos-reference-splash-integration.sh' "$PATCHER" || fail "reference splash is not wired into final build chain"
python3 - "$PATCHER" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text()
a=text.find('mechos-source-owned-system-ui.sh')
b=text.find('mechos-reference-splash-integration.sh')
c=text.find('mechos-reference-v5-postinstall-stage.sh commit')
if min(a,b,c)<0 or not (a < b < c):
    raise SystemExit('[validate-reference-splash] splash must be final visual authority before postinstall commit')
PY

echo '[validate-reference-splash] OK: approved mechos-splash-reference.png is final Plymouth boot visual authority'
