#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
THEME_DIR="$ROOT/usr/share/mechos/theme"
BRAND_DIR="$ROOT/usr/share/mechos/branding"

log() { printf '[MechOS Reference UI v5] %s\n' "$*"; }
fail() { printf '[MechOS Reference UI v5] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Reference UI v5] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
mkdir -p "$THEME_DIR" "$BRAND_DIR"

# Final visual token set. This is intentionally applied after Store v3,
# Surfaces v4, RadarAI, RGB and the cumulative current integration so older
# generators cannot restore the utility-style layouts.
cat > "$THEME_DIR/reference-v5.qss" <<'QSS'
/* MECHOS_REFERENCE_UI_V5
 * Final visual authority for the approved MechOS reference screens.
 */
QMainWindow,QDialog,QWidget {
  color:#f7f9ff;
  background:#030611;
  font-family:"Noto Sans","Sans Serif";
  font-size:14px;
}
QLabel { background:transparent; }
QLabel#brand { color:#ffffff; font-size:24px; font-weight:900; letter-spacing:1px; }
QLabel#scope,QLabel#purple { color:#c86cff; font-size:24px; font-weight:900; letter-spacing:2px; }
QLabel#title,QLabel#heroTitle,QLabel#surfaceTitle { color:#ffffff; font-size:34px; font-weight:900; }
QLabel#section,QLabel#surfaceSection { color:#48dfff; font-size:13px; font-weight:900; }
QLabel#muted,QLabel#body,QLabel#sub,QLabel#surfaceMuted { color:#9cacbf; }
QLabel#metric,QLabel#surfaceMetric { color:#ffffff; font-size:24px; font-weight:900; }

QFrame#top,QFrame#header,QFrame#bottom {
  background:#060915; border:1px solid #20284a; border-radius:12px;
}
QFrame#hero,QFrame#storeHero,QFrame#surfaceHero {
  background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #070a18,stop:.52 #120b28,stop:1 #061b31);
  border:1px solid #7550c4; border-radius:18px;
}
QFrame#panel,QFrame#card,QFrame#surfaceCard,QFrame#metricCard,QFrame#sourceCard,QFrame#gameCard {
  background:qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 #091326,stop:1 #060b16);
  border:1px solid #243b61; border-radius:14px;
}
QFrame#panel:hover,QFrame#card:hover,QFrame#surfaceCard:hover,QFrame#sourceCard:hover,QFrame#gameCard:hover {
  border:1px solid #7f61d8;
}
QPushButton,QToolButton {
  color:#f7f9ff; font-weight:750; min-height:40px; padding:8px 14px;
  background:qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #0d172a,stop:1 #17132c);
  border:1px solid #324b77; border-radius:10px;
}
QPushButton:hover,QToolButton:hover { border:1px solid #8d72e9; background:#172447; }
QPushButton:focus,QToolButton:focus { border:2px solid #bd7cff; background:#24184b; }
QPushButton:checked,QPushButton#primary,QPushButton#action,QPushButton#profile {
  background:qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #6b32c7,stop:.55 #8147e4,stop:1 #aa45dc);
  border:1px solid #cf91ff; color:white; font-weight:900;
}
QPushButton#danger { background:#351019; border:1px solid #dc3851; color:#ffbec8; }
QLineEdit,QComboBox,QSpinBox,QDoubleSpinBox,QTextEdit,QPlainTextEdit {
  color:#f7f9ff; background:#060d1a; border:1px solid #30486f; border-radius:10px; padding:10px;
}
QLineEdit:focus,QComboBox:focus,QTextEdit:focus,QPlainTextEdit:focus { border:2px solid #a45fff; }
QListWidget,QTreeWidget,QTableWidget,QScrollArea {
  background:#050a14; border:1px solid #223758; border-radius:11px; outline:0;
}
QListWidget::item,QTreeWidget::item,QTableWidget::item { padding:8px; }
QListWidget::item:selected,QTreeWidget::item:selected,QTableWidget::item:selected { background:#2b1d57; color:white; }
QProgressBar { background:#070d18; border:1px solid #27395a; border-radius:7px; text-align:center; min-height:14px; }
QProgressBar::chunk { border-radius:6px; background:qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #22b8ff,stop:.5 #7655ef,stop:1 #b94cff); }
QSlider::groove:horizontal { height:6px; background:#111a2b; border-radius:3px; }
QSlider::sub-page:horizontal { background:qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #24b8ff,stop:1 #a34fff); border-radius:3px; }
QSlider::handle:horizontal { width:18px; margin:-6px 0; background:#e0c8ff; border:2px solid #7444c4; border-radius:9px; }
QRadioButton,QCheckBox { color:#dbe6f8; spacing:9px; }
QRadioButton::indicator,QCheckBox::indicator { width:18px; height:18px; background:#07101f; border:1px solid #536b91; }
QRadioButton::indicator { border-radius:9px; }
QCheckBox::indicator { border-radius:4px; }
QRadioButton::indicator:checked,QCheckBox::indicator:checked { background:#7b46db; border:2px solid #c18fff; }
QScrollBar:vertical { width:9px; background:#040812; }
QScrollBar::handle:vertical { min-height:30px; background:#435881; border-radius:4px; }
QMenu { background:#07101e; color:white; border:1px solid #493a77; padding:5px; }
QMenu::item { padding:8px 20px; border-radius:6px; }
QMenu::item:selected { background:#34245f; }
QToolTip { background:#101a2e; color:white; border:1px solid #8e65df; padding:6px; }
QSS

# Procedural hero art matching the approved purple/blue MechOS command-center
# references without bundling third-party game artwork.
cat > "$BRAND_DIR/reference-hero-v5.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="420" viewBox="0 0 1600 420">
 <defs>
  <linearGradient id="bg" x1="0" x2="1"><stop stop-color="#060918"/><stop offset=".5" stop-color="#120726"/><stop offset="1" stop-color="#051a31"/></linearGradient>
  <radialGradient id="g"><stop stop-color="#ffffff" stop-opacity=".75"/><stop offset=".14" stop-color="#9c46ff" stop-opacity=".55"/><stop offset=".42" stop-color="#4134ff" stop-opacity=".22"/><stop offset="1" stop-color="#000" stop-opacity="0"/></radialGradient>
  <linearGradient id="ring" x1="0" x2="1"><stop stop-color="#d14cff"/><stop offset=".52" stop-color="#8e4dff"/><stop offset="1" stop-color="#1aa7ff"/></linearGradient>
  <filter id="blur"><feGaussianBlur stdDeviation="12"/></filter>
 </defs>
 <rect width="1600" height="420" rx="24" fill="url(#bg)"/>
 <ellipse cx="1120" cy="212" rx="420" ry="210" fill="url(#g)"/>
 <path d="M20 310 C350 235 620 345 915 235 S1290 155 1580 225" fill="none" stroke="#783eff" stroke-opacity=".42" stroke-width="4"/>
 <path d="M0 335 C340 255 650 370 935 252 S1300 170 1600 245" fill="none" stroke="#18a5ff" stroke-opacity=".32" stroke-width="3"/>
 <circle cx="1140" cy="210" r="132" fill="none" stroke="url(#ring)" stroke-width="16" filter="url(#blur)" opacity=".65"/>
 <circle cx="1140" cy="210" r="132" fill="#070a16" fill-opacity=".78" stroke="url(#ring)" stroke-width="7"/>
 <path d="M1085 250 L1085 164 L1140 218 L1195 164 L1195 250 L1172 250 L1172 211 L1140 243 L1108 211 L1108 250 Z" fill="none" stroke="#db8dff" stroke-width="10" stroke-linejoin="round"/>
</svg>
SVG

cat > "$ROOT/usr/share/mechos/reference-ui-v5.json" <<'JSON'
{
  "version": 5,
  "status": "final-authority",
  "screens": [
    "MechScope 2.0",
    "Unified Store",
    "Creator Mode",
    "Creator Store",
    "Performance Center",
    "Update Center",
    "Quick Actions",
    "Recovery Center",
    "MechOS Installer"
  ],
  "rules": {
    "controller_first": true,
    "keyboard_first": true,
    "instant_plasma_transitions": true,
    "postinstall_matches_live_reference_runtime": true,
    "no_bundled_commercial_game_art": true,
    "store_art_uses_local_or_official_sources": true
  }
}
JSON

patch_pyqt_surface() {
  local file="$1"
  [ -f "$file" ] || return 0
  grep -q 'PyQt6' "$file" || return 0

  python3 - "$file" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1]); text=p.read_text(encoding='utf-8')
marker='# MECHOS_REFERENCE_UI_V5'
if marker not in text:
    lines=text.splitlines(True)
    at=1 if lines and lines[0].startswith('#!') else 0
    lines.insert(at, marker+'\n')
    text=''.join(lines)

expr="(__import__('pathlib').Path('/usr/share/mechos/theme/reference-v5.qss').read_text(encoding='utf-8') if __import__('pathlib').Path('/usr/share/mechos/theme/reference-v5.qss').is_file() else '')"
# Preserve each screen's layout/backend and layer the final reference stylesheet
# at QApplication level so older local QSS cannot erase v5 focus/card styling.
pat=re.compile(r'(?m)^(\s*)(\w+)\s*=\s*QApplication\(sys\.argv\)\s*$')
m=pat.search(text)
if m and 'reference-v5.qss' not in text:
    ins=m.group(0)+f"\n{m.group(1)}{m.group(2)}.setStyleSheet({expr})"
    text=text[:m.start()]+ins+text[m.end():]

# The approved reference uses large command-center surfaces. Core MechOS-owned
# screens should fill the available session in both physical and VM fallback.
name=p.name
if name in {'mechscope','mechos-creator-mode','mechos-performance-center','mechos-update-center','mechos-recovery-center','mechos-live-setup'}:
    text=re.sub(r'(?m)^(\s*)(w|win)\.show\(\)\s*$', r'\1\2.showMaximized()', text)

p.write_text(text,encoding='utf-8')
PY
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$file" || fail "Python syntax failed after v5 styling: $file"
}

# Final surface list. Creator Store lives inside Creator Mode; Unified Store is
# inside MechScope, so their parent scripts receive v5 after Store v3 did its
# functional page replacement.
for name in \
  mechscope \
  mechos-creator-mode \
  mechos-performance-center \
  mechos-update-center \
  mechos-quick-actions \
  mechos-recovery-center \
  mechos-live-setup \
  mechos-oobe \
  mechos-stream-center
do
  if [ -f "$ROOT/usr/local/bin/$name.real" ]; then
    patch_pyqt_surface "$ROOT/usr/local/bin/$name.real"
  else
    patch_pyqt_surface "$ROOT/usr/local/bin/$name"
  fi
done

# Functional contracts behind the pictured screens. The UI must never expose a
# dead reference-only button; required backend launchers/helpers are validated.
for f in \
  "$ROOT/usr/local/bin/mechscope" \
  "$ROOT/usr/local/bin/mechos-performance-center" \
  "$ROOT/usr/local/bin/mechos-update-center" \
  "$ROOT/usr/local/bin/mechos-quick-actions" \
  "$ROOT/usr/local/bin/mechos-recovery-center" \
  "$ROOT/usr/local/bin/mechos-live-setup"
do
  [ -f "$f" ] || fail "required reference surface missing: $f"
done

# Required commands visible in the approved references.
grep -Fq 'Unified Store' "$ROOT/usr/local/bin/mechscope" || fail "MechScope lost Unified Store"
grep -Fq 'Performance Center' "$ROOT/usr/local/bin/mechscope" || fail "MechScope lost Performance Center"
grep -Fq 'Creator Mode' "$ROOT/usr/local/bin/mechscope" || fail "MechScope lost Creator Mode"
grep -Fq 'Steam' "$ROOT/usr/local/bin/mechscope" || fail "MechScope lost Steam launcher"
grep -Fq 'powerprofilesctl' "$ROOT/usr/local/bin/mechos-performance-center" || fail "Performance Center lost real power profiles"
grep -Eq 'checkupdates|mechos-update-helper' "$ROOT/usr/local/bin/mechos-update-center" || fail "Update Center lost real update backend"
grep -Eq 'wpctl|nmcli' "$ROOT/usr/local/bin/mechos-quick-actions" || fail "Quick Actions lost real device controls"
grep -Fq 'repair-boot' "$ROOT/usr/local/bin/mechos-recovery-center" || fail "Recovery Center lost boot repair"
grep -Fq 'QButtonGroup' "$ROOT/usr/local/bin/mechos-live-setup" || fail "Installer install-mode exclusivity is missing"

# Keep Plasma fast: the reference look remains, but input is not allowed to
# queue behind fades/pop-up animations.
mkdir -p "$ROOT/etc/xdg"
cat > "$ROOT/etc/xdg/kdeglobals" <<'EOF'
# MECHOS_REFERENCE_UI_V5 low-latency Plasma defaults
[KDE]
AnimationDurationFactor=0
EOF
cat > "$ROOT/etc/xdg/kwinrc" <<'EOF'
# MECHOS_REFERENCE_UI_V5 low-latency KWin defaults
[Plugins]
fadeEnabled=false
fadingpopupsEnabled=false
slidingpopupsEnabled=false
loginEnabled=false
logoutEnabled=false
kwin4_effect_maximizeEnabled=false
squashEnabled=false
EOF

log "Reference UI v5 applied as final Live UI authority"
