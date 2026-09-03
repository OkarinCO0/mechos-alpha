#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
TARGET="$ROOT/usr/local/bin/mechos-live-setup"

log() { printf '[MechOS Installer Layout] %s\n' "$*"; }
fail() { printf '[MechOS Installer Layout] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Installer Layout] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -f "$TARGET" ] || fail "Live graphical installer is missing: $TARGET"

python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "# MECHOS_INSTALLER_RESPONSIVE_LAYOUT_V1"


def require(condition, message):
    if not condition:
        raise SystemExit("[MechOS Installer Layout] " + message)


if marker in text:
    raise SystemExit(0)

require("class Installer(QMainWindow):" in text, "Installer class was not found")
require("QScrollArea" in text, "QScrollArea import is missing")
require("QSizePolicy" in text, "QSizePolicy import is missing")
require("QButtonGroup" in text, "QButtonGroup import is missing")

start = text.index("class Installer(QMainWindow):")
end = text.find("\nclass ", start + 1)
if end < 0:
    main_index = text.find("\nif __name__", start)
    end = main_index if main_index >= 0 else len(text)
block = text[start:end]

# Give the maximized Live installer more breathing room while still allowing
# it to run on smaller 720p-class displays.
block = block.replace("        self.resize(1500, 880)\n", "        self.resize(1600, 900)\n", 1)
block = block.replace("        self.setMinimumSize(1180, 720)\n", "        self.setMinimumSize(1024, 640)\n", 1)

# Increase the spacing around the main themed shell. The old 14px margins and
# 16px three-column gap caused the sidebar, install controls and hardware cards
# to visually run into one another when the Live desktop used display scaling.
old_root = "        root_layout = QVBoxLayout(root)\n        root_layout.setContentsMargins(14,14,14,14)\n"
new_root = (
    "        root_layout = QVBoxLayout(root)\n"
    "        root_layout.setContentsMargins(24,20,24,20)\n"
    "        root_layout.setSpacing(16)\n"
)
require(old_root in block, "root installer layout anchor was not found")
block = block.replace(old_root, new_root, 1)

require("        body = QHBoxLayout()\n        body.setSpacing(16)\n" in block,
        "main three-column body anchor was not found")
block = block.replace(
    "        body = QHBoxLayout()\n        body.setSpacing(16)\n",
    "        body = QHBoxLayout()\n        body.setContentsMargins(4,4,4,4)\n        body.setSpacing(24)\n",
    1,
)

# Stop the left navigation from collapsing until its long step labels overlap.
nav_anchor = (
    "        nav_panel = self.panel()\n"
    "        nav_l = QVBoxLayout(nav_panel)\n"
    "        nav_l.setContentsMargins(12,12,12,12)\n"
    "        self.nav = QListWidget()\n"
)
require(nav_anchor in block, "installer navigation panel anchor was not found")
block = block.replace(
    nav_anchor,
    "        nav_panel = self.panel()\n"
    "        nav_panel.setMinimumWidth(245)\n"
    "        nav_panel.setMaximumWidth(300)\n"
    "        nav_l = QVBoxLayout(nav_panel)\n"
    "        nav_l.setContentsMargins(16,16,16,16)\n"
    "        nav_l.setSpacing(10)\n"
    "        self.nav = QListWidget()\n"
    "        self.nav.setMinimumWidth(215)\n",
    1,
)

# Keep the hardware summary readable instead of allowing its labels and values
# to be compressed into the center installation controls.
hw_anchor = (
    "        right = QVBoxLayout()\n"
    "        hw_panel = self.panel()\n"
    "        hl = QVBoxLayout(hw_panel)\n"
)
require(hw_anchor in block, "hardware summary panel anchor was not found")
block = block.replace(
    hw_anchor,
    "        right = QVBoxLayout()\n"
    "        right.setSpacing(14)\n"
    "        hw_panel = self.panel()\n"
    "        hw_panel.setMinimumWidth(320)\n"
    "        hl = QVBoxLayout(hw_panel)\n"
    "        hl.setContentsMargins(18,16,18,16)\n"
    "        hl.setSpacing(10)\n",
    1,
)

# The install-mode radio buttons are each placed inside their own visual panel.
# QRadioButton's default auto-exclusive behavior only applies to sibling radio
# buttons with the same parent, so the panels accidentally allowed Clean/Keep/
# Custom/Alongside to all remain checked. Bind them to one explicit exclusive
# QButtonGroup instead. Clean Install stays the single default selection.
install_group_marker = "# MECHOS_INSTALL_MODE_EXCLUSIVE_GROUP_V1"
if install_group_marker not in block:
    alongside_hook = '        self.alongside.toggled.connect(lambda v: self.set_mode("alongside", v))\n'
    custom_hook = '        self.custom.toggled.connect(lambda v: self.set_mode("custom", v))\n'

    if alongside_hook in block:
        group_code = (
            alongside_hook
            + "        # MECHOS_INSTALL_MODE_EXCLUSIVE_GROUP_V1\n"
            + "        self.install_mode_group = QButtonGroup(self)\n"
            + "        self.install_mode_group.setExclusive(True)\n"
            + "        for button in (self.clean, self.keep, self.custom, self.alongside):\n"
            + "            self.install_mode_group.addButton(button)\n"
            + "        self.clean.setChecked(True)\n"
        )
        block = block.replace(alongside_hook, group_code, 1)
    else:
        require(custom_hook in block, "installer mode toggle hooks were not found")
        group_code = (
            custom_hook
            + "        # MECHOS_INSTALL_MODE_EXCLUSIVE_GROUP_V1\n"
            + "        self.install_mode_group = QButtonGroup(self)\n"
            + "        self.install_mode_group.setExclusive(True)\n"
            + "        for button in (self.clean, self.keep, self.custom):\n"
            + "            self.install_mode_group.addButton(button)\n"
            + "        self.clean.setChecked(True)\n"
        )
        block = block.replace(custom_hook, group_code, 1)

# The important part of the responsive fix: do not let Qt squeeze all three
# columns below their useful widths. Put the main body in a borderless scroll
# area. At normal 1080p resolutions it expands naturally; at lower resolution
# or high scaling, scrollbars appear instead of cards/text/buttons being
# crushed together.
body_anchor = "        layout.addLayout(body, 1)\n\n        # Footer actions\n"
require(body_anchor in block, "installer body/footer anchor was not found")
body_replacement = '''        body_widget = QWidget()\n        body_widget.setObjectName("installerBody")\n        body_widget.setLayout(body)\n        body_widget.setMinimumWidth(1250)\n        body_widget.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)\n\n        body_scroll = QScrollArea()\n        body_scroll.setObjectName("installerBodyScroll")\n        body_scroll.setFrameShape(QFrame.Shape.NoFrame)\n        body_scroll.setWidgetResizable(True)\n        body_scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)\n        body_scroll.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)\n        body_scroll.setStyleSheet("QScrollArea#installerBodyScroll { border:0; background:transparent; } QWidget#installerBody { background:transparent; }")\n        body_scroll.setWidget(body_widget)\n        layout.addWidget(body_scroll, 1)\n\n        # Footer actions\n'''
block = block.replace(body_anchor, body_replacement, 1)

# Add a little separation to the footer without making it oversized.
block = block.replace(
    "        footer = QHBoxLayout()\n",
    "        footer = QHBoxLayout()\n        footer.setContentsMargins(4,8,4,2)\n        footer.setSpacing(12)\n",
    1,
)

text = text[:start] + block + text[end:]
lines = text.splitlines(True)
insert_at = 1 if lines and lines[0].startswith("#!") else 0
lines.insert(insert_at, marker + "\n")
path.write_text("".join(lines), encoding="utf-8")
PY

python3 -m py_compile "$TARGET" || fail "Live installer Python syntax validation failed"
grep -Fq '# MECHOS_INSTALLER_RESPONSIVE_LAYOUT_V1' "$TARGET" \
  || fail "responsive installer layout marker is missing"
grep -Fq '# MECHOS_INSTALL_MODE_EXCLUSIVE_GROUP_V1' "$TARGET" \
  || fail "exclusive install-mode radio group is missing"
grep -Fq 'self.install_mode_group.setExclusive(True)' "$TARGET" \
  || fail "install-mode radio group is not exclusive"
grep -Fq 'body_widget.setMinimumWidth(1250)' "$TARGET" \
  || fail "installer anti-squish body width guard is missing"
grep -Fq 'body_scroll.setHorizontalScrollBarPolicy' "$TARGET" \
  || fail "installer responsive scroll fallback is missing"
grep -Fq 'nav_panel.setMinimumWidth(245)' "$TARGET" \
  || fail "installer navigation width guard is missing"
grep -Fq 'hw_panel.setMinimumWidth(320)' "$TARGET" \
  || fail "installer hardware summary width guard is missing"

log "Live installer layout spacing, responsive anti-squish behavior and exclusive install-mode selection applied"
