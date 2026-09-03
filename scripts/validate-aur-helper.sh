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
grep -Fq 'pl.addWidget(self.update_button)' "$SRC" || fail "Reference v5 Update Center anchor missing"
grep -Fq 'spawn(["/usr/local/bin/mechos-aur-gui"])' "$SRC" || fail "AUR Update Center launch path missing"
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
update_patch=extract("  if [ -f \"$update\" ]; then\n    python3 - \"$update\" <<'PY'\n","\nPY\n  fi\n",'Update Center AUR patch')
(out/'mechos-aur').write_text(aur,encoding='utf-8')
(out/'mechos-aur-gui.py').write_text(gui,encoding='utf-8')
(out/'patch-update.py').write_text(update_patch,encoding='utf-8')
PY
bash -n "$TMP/mechos-aur" || fail "generated mechos-aur shell syntax failed"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$TMP/mechos-aur-gui.py" || fail "generated AUR GUI Python syntax failed"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$TMP/patch-update.py" || fail "Update Center patch Python syntax failed"

# Reproduce the exact Reference v5 Update Center structure that broke the ISO
# build: Install Updates is placed into the UPDATE PROGRESS panel with `pl`.
cat > "$TMP/mechos-update-center" <<'PY'
#!/usr/bin/env python3
class UpdateCenter:
    def build_ui(self):
        lower=object()
        prog=self.panel()
        pl=QVBoxLayout(prog)
        self.progress=QProgressBar()
        pl.addWidget(self.progress)
        self.update_button=QPushButton('Install Updates'); self.update_button.setObjectName('primary'); self.update_button.clicked.connect(self.apply_updates); self.update_button.setEnabled(False); pl.addWidget(self.update_button)
        self.reboot_button=QPushButton('Schedule / Restart MechOS')
PY
python3 "$TMP/patch-update.py" "$TMP/mechos-update-center" || fail "AUR patch rejected Reference v5 Update Center"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$TMP/mechos-update-center" || fail "patched Reference v5 Update Center is not valid Python"
grep -Fq '# MECHOS_AUR_UPDATE_CENTER_V1' "$TMP/mechos-update-center" || fail "AUR marker was not injected into Reference v5 Update Center"
grep -Fq 'self.aur_button=QPushButton("AUR Packages")' "$TMP/mechos-update-center" || fail "AUR Packages button was not injected"
grep -Fq 'spawn(["/usr/local/bin/mechos-aur-gui"])' "$TMP/mechos-update-center" || fail "AUR Packages button launch command is wrong"
grep -Fq 'pl.addWidget(self.aur_button)' "$TMP/mechos-update-center" || fail "AUR button is not attached to the Reference v5 progress panel"

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
