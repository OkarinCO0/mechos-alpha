#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log() { printf '[MechOS Reference UI] %s\n' "$*"; }
fail() { printf '[MechOS Reference UI] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Reference UI] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -s "$ARCHIVE" ] || fail "installed-system payload is missing: $ARCHIVE"

write_theme() {
  local tree="$1"
  local dir="$tree/usr/share/mechos/theme"
  mkdir -p "$dir"

  cat > "$dir/mechos-ui.qss" <<'QSS'
/* MECHOS_REFERENCE_UI_V2
 * Master visual system based on the approved MechOS graphical reference.
 * One visual language for MechScope, Store, Installer, Performance, Updates,
 * Creator Mode, Recovery, OOBE and supporting tools.
 */

QMainWindow, QDialog {
  background:qlineargradient(x1:0,y1:0,x2:1,y2:1,
    stop:0 #03050b, stop:0.45 #060915, stop:1 #0b0716);
  color:#f7f9ff;
}
QWidget {
  color:#edf3ff;
  font-family:"Noto Sans", "Sans Serif";
  font-size:14px;
}
QLabel { background:transparent; }
QLabel#title, QLabel#heroTitle {
  color:#ffffff;
  font-size:32px;
  font-weight:900;
}
QLabel#brand, QLabel#purple, QLabel#scope {
  color:#bd7cff;
  font-weight:900;
}
QLabel#section {
  color:#75cfff;
  font-size:13px;
  font-weight:900;
}
QLabel#muted, QLabel#body, QLabel#sub {
  color:#9baac4;
}
QLabel#metric {
  color:#ffffff;
  font-size:22px;
  font-weight:900;
}

QFrame#sidebar {
  background:qlineargradient(x1:0,y1:0,x2:1,y2:0,
    stop:0 #04060d, stop:1 #090d18);
  border:0;
  border-right:1px solid #332857;
}
QFrame#top, QFrame#bottom, QFrame#header {
  background:qlineargradient(x1:0,y1:0,x2:1,y2:0,
    stop:0 #070b15, stop:1 #0c0a1a);
  border:1px solid #2b3156;
  border-radius:12px;
}
QFrame#hero, QFrame#glowPanel {
  background:qlineargradient(x1:0,y1:0,x2:1,y2:1,
    stop:0 #0a1020, stop:0.55 #0c0b20, stop:1 #170b27);
  border:2px solid #6e45bd;
  border-radius:18px;
}
QFrame#panel, QFrame#card {
  background:qlineargradient(x1:0,y1:0,x2:0,y2:1,
    stop:0 #0b1322, stop:1 #070c16);
  border:1px solid #273659;
  border-radius:14px;
}
QFrame#panel:hover, QFrame#card:hover {
  border:1px solid #6f58b6;
}

QPushButton, QToolButton {
  color:#f7f9ff;
  background:qlineargradient(x1:0,y1:0,x2:1,y2:0,
    stop:0 #101a30, stop:1 #18132d);
  border:1px solid #344b78;
  border-radius:10px;
  min-height:38px;
  padding:8px 15px;
  font-weight:700;
}
QPushButton:hover, QToolButton:hover {
  background:qlineargradient(x1:0,y1:0,x2:1,y2:0,
    stop:0 #15284a, stop:1 #291a4c);
  border:1px solid #8d69e6;
}
QPushButton:focus, QToolButton:focus {
  background:qlineargradient(x1:0,y1:0,x2:1,y2:0,
    stop:0 #183057, stop:1 #321e59);
  border:2px solid #a87cff;
  color:#ffffff;
}
QPushButton:pressed, QToolButton:pressed {
  background:#20193b;
  border:2px solid #58c9ff;
}
QPushButton:disabled, QToolButton:disabled {
  color:#56657b;
  background:#090e18;
  border:1px solid #202b3e;
}
QPushButton#primary, QPushButton#action, QPushButton#profile,
QPushButton#nav:checked, QPushButton:checked {
  color:#ffffff;
  font-weight:900;
  background:qlineargradient(x1:0,y1:0,x2:1,y2:0,
    stop:0 #6238c9, stop:0.55 #7646da, stop:1 #8f45d2);
  border:1px solid #bb8dff;
}
QPushButton#danger {
  background:#34111b;
  border:1px solid #bd4459;
  color:#ffb8c1;
}

QLineEdit, QComboBox, QSpinBox, QDoubleSpinBox,
QTextEdit, QPlainTextEdit {
  color:#f7f9ff;
  background:#070e1a;
  border:1px solid #304369;
  border-radius:9px;
  padding:9px;
  selection-background-color:#6847bd;
}
QLineEdit:focus, QComboBox:focus, QSpinBox:focus,
QDoubleSpinBox:focus, QTextEdit:focus, QPlainTextEdit:focus {
  background:#091426;
  border:2px solid #8b63e8;
}
QComboBox::drop-down { border:0; width:28px; }
QComboBox QAbstractItemView {
  background:#080f1d;
  color:#f5f8ff;
  border:1px solid #493c78;
  selection-background-color:#382c6a;
}

QListWidget, QTreeWidget, QTableWidget {
  background:#060c16;
  alternate-background-color:#09111e;
  border:1px solid #263758;
  border-radius:10px;
  outline:0;
  gridline-color:#1f2b45;
}
QListWidget::item, QTreeWidget::item, QTableWidget::item {
  padding:8px;
  border-radius:7px;
}
QListWidget::item:selected, QTreeWidget::item:selected,
QTableWidget::item:selected {
  color:#ffffff;
  background:#25214d;
  border:1px solid #8b68dc;
}
QHeaderView::section {
  color:#aebbd0;
  background:#0b1220;
  border:0;
  border-bottom:1px solid #293958;
  padding:8px;
  font-weight:800;
}

QTabWidget::pane {
  background:#070d18;
  border:1px solid #283959;
  border-radius:11px;
}
QTabBar::tab {
  color:#9faec5;
  background:#090f1b;
  border:1px solid #293854;
  padding:10px 17px;
  margin-right:4px;
  border-radius:9px;
}
QTabBar::tab:hover {
  color:#ffffff;
  border:1px solid #6c55a7;
}
QTabBar::tab:selected {
  color:#ffffff;
  font-weight:800;
  background:#352365;
  border:1px solid #9a72ee;
}

QProgressBar {
  color:#eef7ff;
  background:#070d17;
  border:1px solid #2e3d5d;
  border-radius:8px;
  text-align:center;
  min-height:16px;
}
QProgressBar::chunk {
  border-radius:7px;
  background:qlineargradient(x1:0,y1:0,x2:1,y2:0,
    stop:0 #2aaeff, stop:0.5 #6859ee, stop:1 #b35cff);
}

QSlider::groove:horizontal {
  height:6px;
  background:#11192a;
  border-radius:3px;
}
QSlider::sub-page:horizontal {
  background:qlineargradient(x1:0,y1:0,x2:1,y2:0,
    stop:0 #2caeff, stop:1 #9b5bff);
  border-radius:3px;
}
QSlider::handle:horizontal {
  width:18px;
  margin:-6px 0;
  border-radius:9px;
  background:#d7bdff;
  border:2px solid #7047c2;
}

QCheckBox, QRadioButton {
  color:#dbe5f7;
  background:transparent;
  spacing:8px;
}
QCheckBox::indicator, QRadioButton::indicator {
  width:17px;
  height:17px;
  border:1px solid #53688c;
  background:#08101d;
}
QCheckBox::indicator { border-radius:4px; }
QRadioButton::indicator { border-radius:9px; }
QCheckBox::indicator:checked, QRadioButton::indicator:checked {
  background:#7449d6;
  border:2px solid #b48cff;
}

QGroupBox {
  color:#dfe8f7;
  background:#080f1b;
  border:1px solid #2b3a59;
  border-radius:11px;
  margin-top:14px;
  padding-top:12px;
  font-weight:800;
}
QGroupBox::title {
  subcontrol-origin:margin;
  left:12px;
  padding:0 6px;
  color:#8ed7ff;
}

QScrollBar:vertical {
  width:10px;
  background:#050a12;
  margin:2px;
}
QScrollBar::handle:vertical {
  min-height:30px;
  background:#35456b;
  border-radius:5px;
}
QScrollBar::handle:vertical:hover { background:#7958c3; }
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height:0; }
QScrollBar:horizontal {
  height:10px;
  background:#050a12;
  margin:2px;
}
QScrollBar::handle:horizontal {
  min-width:30px;
  background:#35456b;
  border-radius:5px;
}
QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal { width:0; }

QMenu {
  color:#f1f6ff;
  background:#080f1b;
  border:1px solid #45366f;
  padding:6px;
}
QMenu::item { padding:9px 25px; border-radius:7px; }
QMenu::item:selected { background:#33265e; }
QToolTip {
  color:#ffffff;
  background:#10182a;
  border:1px solid #8d67df;
  padding:7px;
}
QMessageBox { background:#070c16; }
QSS

  cat > "$dir/reference-ui-v2.conf" <<'TOKENS'
MECHOS_REFERENCE_UI=2
BACKGROUND=#03050b
SURFACE=#070c16
CARD=#0b1322
BORDER=#273659
PURPLE=#8f5be8
BLUE=#58c9ff
MAGENTA=#b35cff
TEXT=#f7f9ff
MUTED=#9baac4
RADIUS_CARD=14
RADIUS_HERO=18
CONTROLLER_FOCUS=#a87cff
TOKENS
}

patch_late_pyqt() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  [ -d "$bin" ] || return 0

  while IFS= read -r -d '' file; do
    grep -q 'PyQt6' "$file" || continue
    grep -q '/usr/share/mechos/theme/mechos-ui.qss' "$file" && continue

    python3 - "$file" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_REFERENCE_UI_V2'
if marker in text:
    raise SystemExit(0)

expr = "(__import__('pathlib').Path('/usr/share/mechos/theme/mechos-ui.qss').read_text(encoding='utf-8') if __import__('pathlib').Path('/usr/share/mechos/theme/mechos-ui.qss').is_file() else '')"
changed = False

# Most MechOS windows use a shared STYLE variable.
if 'self.setStyleSheet(STYLE)' in text:
    text = text.replace('self.setStyleSheet(STYLE)', f'self.setStyleSheet(STYLE + {expr})')
    changed = True

# Handle a one-line custom setStyleSheet expression inside a primary window.
if not changed:
    pattern = re.compile(r'(?m)^(\s*)self\.setStyleSheet\(([^\n]+)\)\s*$')
    match = pattern.search(text)
    if match:
        current = match.group(2).strip()
        replacement = f"{match.group(1)}self.setStyleSheet(({current}) + {expr})"
        text = text[:match.start()] + replacement + text[match.end():]
        changed = True

# Last-resort application-level injection for late-created tools with no window
# stylesheet. This still gives standard controls/cards the reference palette.
if not changed:
    pattern = re.compile(r'(?m)^(\s*)(\w+)\s*=\s*QApplication\(sys\.argv\)\s*$')
    match = pattern.search(text)
    if match:
        var = match.group(2)
        replacement = match.group(0) + f"\n{match.group(1)}{var}.setStyleSheet({expr})"
        text = text[:match.start()] + replacement + text[match.end():]
        changed = True

if not changed:
    raise SystemExit(0)

lines = text.splitlines(True)
insert_at = 1 if lines and lines[0].startswith('#!') else 0
lines.insert(insert_at, marker + '\n')
path.write_text(''.join(lines), encoding='utf-8')
PY

    PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$file"
  done < <(find "$bin" -maxdepth 1 -type f -print0)
}

patch_tree() {
  local tree="$1"
  write_theme "$tree"
  patch_late_pyqt "$tree"

  local theme="$tree/usr/share/mechos/theme/mechos-ui.qss"
  grep -Fq 'MECHOS_REFERENCE_UI_V2' "$theme" || fail "reference UI marker missing: $theme"
  grep -Fq 'CONTROLLER_FOCUS=#a87cff' "$tree/usr/share/mechos/theme/reference-ui-v2.conf" \
    || fail "reference UI token file is incomplete"

  # Major surfaces should either already use the v1 shared loader or receive
  # the late v2 loader here. Missing optional post-install apps are allowed in Live.
  for name in mechscope mechos-live-setup mechos-performance-center mechos-update-center \
              mechos-creator-mode mechos-recovery-center mechos-oobe \
              mechos-system-tools mechos-native-install; do
    file="$tree/usr/local/bin/$name"
    [ -f "$file" ] || continue
    if grep -q 'PyQt6' "$file"; then
      grep -Fq '/usr/share/mechos/theme/mechos-ui.qss' "$file" \
        || fail "$name is not connected to the master reference theme"
      PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$file"
    fi
  done
}

# Apply last to the Live image so no later UI generator can overwrite it.
patch_tree "$ROOT"

# Apply the identical design system to the installed-system payload.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xf "$ARCHIVE" -C "$tmp"
patch_tree "$tmp"
new_archive="$ARCHIVE.reference-ui"
tar --zstd -cpf "$new_archive" -C "$tmp" .
mv -f "$new_archive" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

# Assert the installed archive actually carries the final master theme.
tar --zstd -tf "$ARCHIVE" './usr/share/mechos/theme/mechos-ui.qss' >/dev/null \
  || fail "installed payload lost the master theme"
tar --zstd -tf "$ARCHIVE" './usr/share/mechos/theme/reference-ui-v2.conf' >/dev/null \
  || fail "installed payload lost the reference UI tokens"

log "Reference UI v2 applied as the final visual authority for Live and installed MechOS"
