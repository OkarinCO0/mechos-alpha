#!/usr/bin/env bash
set -Eeuo pipefail

SRC="scripts/mechos-aur-helper-integration.sh"
PATCHER="scripts/patch-mechos-reference-v5.py"

fail() { printf '[MechOS AUR validation] ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$SRC" ] || fail "AUR integration script is missing"
[ -f "$PATCHER" ] || fail "Reference v5 patcher is missing"
bash -n "$SRC" || fail "AUR integration shell syntax failed"

grep -Fq 'Do not run mechos-aur as root' "$SRC" || fail "root build guard missing"
grep -Fq 'PKGBUILD review is required' "$SRC" || fail "PKGBUILD review step missing"
grep -Fq 'makepkg -si --needed' "$SRC" || fail "makepkg install path missing"
grep -Fq 'https://aur.archlinux.org/rpc/v5' "$SRC" || fail "AUR RPC search/info path missing"
grep -Fq 'https://aur.archlinux.org' "$SRC" || fail "AUR git source missing"
grep -Fq 'MechOS AUR Packages' "$SRC" || fail "AUR GUI/desktop entry missing"
grep -Fq 'MECHOS_AUR_UPDATE_CENTER_V1' "$SRC" || fail "Update Center integration marker missing"
grep -Fq 'mechos-aur-helper-integration.sh' "$PATCHER" || fail "AUR helper is not wired into final v5 build"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
python3 - "$SRC" "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text(encoding='utf-8')
out=Path(sys.argv[2])

def extract(start,end,name):
    if start not in src:
        raise SystemExit(f'missing start marker for {name}')
    block=src.split(start,1)[1]
    if end not in block:
        raise SystemExit(f'missing end marker for {name}')
    return block.split(end,1)[0]

aur=extract("cat > \"$bin/mechos-aur\" <<'EOF'\n","\nEOF\n",'mechos-aur')
gui=extract("cat > \"$bin/mechos-aur-gui\" <<'PY'\n","\nPY\n",'mechos-aur-gui')
(out/'mechos-aur').write_text(aur,encoding='utf-8')
(out/'mechos-aur-gui.py').write_text(gui,encoding='utf-8')
PY
bash -n "$TMP/mechos-aur" || fail "generated mechos-aur shell syntax failed"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$TMP/mechos-aur-gui.py" || fail "generated AUR GUI Python syntax failed"

python3 - <<'PY'
from pathlib import Path
text=Path('scripts/patch-mechos-reference-v5.py').read_text()
controls=text.find('mechos-reference-v5-controls-compat.sh')
aur=text.find('mechos-aur-helper-integration.sh')
installer=text.find('mechos-reference-v5-installer-layout.sh')
if min(controls,aur,installer) < 0 or not (controls < aur < installer):
    raise SystemExit('AUR helper must run after final controls/update UI and before installer/final payload')
PY

printf '[MechOS AUR validation] passed\n'
