#!/usr/bin/env bash
set -euo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
PROFILE="/workspace/archlive/profiledef.sh"

log() { printf '[MechOS Tutorial] %s\n' "$*"; }
fail() { printf '[MechOS Tutorial] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"

install_tutorial() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local apps="$tree/usr/share/applications"
  mkdir -p "$bin" "$apps"

  cat > "$bin/mechos-tutorial" <<'PYEOF'
#!/usr/bin/env python3
import sys
from pathlib import Path

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import (
    QApplication, QFrame, QHBoxLayout, QLabel, QMainWindow, QMessageBox,
    QPushButton, QStackedWidget, QVBoxLayout, QWidget
)

CONFIG = Path.home() / ".config" / "mechos"
ALL_MARKER = CONFIG / "tutorial-v1-complete"
MECHSCOPE_MARKER = CONFIG / "tutorial-mechscope-v1.done"
CREATOR_MARKER = CONFIG / "tutorial-creator-v1.done"

STYLE = """
QWidget { background:#070910; color:#eef3ff; font-family:Sans Serif; }
QFrame#top { background:#0b0e19; border-bottom:1px solid #2f2350; }
QFrame#card { background:#0e1220; border:1px solid #433064; border-radius:18px; }
QLabel#brand { color:#b987ff; font-size:14px; font-weight:800; }
QLabel#title { color:white; font-size:32px; font-weight:900; }
QLabel#step { color:#8fa5c9; font-size:13px; }
QLabel#body { color:#cbd6e8; font-size:16px; line-height:1.35; }
QLabel#keys { color:#f0e7ff; font-size:15px; }
QPushButton { background:#161d2f; border:1px solid #5f3f8f; border-radius:10px;
              padding:12px 20px; font-size:15px; font-weight:700; }
QPushButton:hover { background:#242c44; border-color:#a86eff; }
QPushButton#primary { background:#6d36ad; border-color:#b475ff; }
QPushButton#primary:hover { background:#8446c8; }
QPushButton#skip { background:transparent; border-color:#384056; color:#aeb8ca; }
"""

MECHSCOPE_PAGES = [
    (
        "Welcome to MechScope",
        "Your gaming-first home screen",
        "MechScope is the default gaming interface on installed MechOS. Use it to launch games, open the Unified Store, reach performance and streaming tools, and switch into Desktop or Creator Mode."
    ),
    (
        "Move Around MechScope",
        "Keyboard and controller-friendly navigation",
        "Use Tab and Shift+Tab to move keyboard focus between controls. Arrow keys move through many lists and grids. Enter or Space activates the selected control. Controller navigation is handled by the gaming session/Steam Input where supported."
    ),
    (
        "Library and Unified Store",
        "Games stay centered in one place",
        "The Library is your launch area. Unified Store brings together the supported storefront links and launchers. Quick Access also opens Performance Center, Update Center, streaming tools, and MechOS utilities without leaving Gaming Mode."
    ),
    (
        "Quick Actions and Mode Switching",
        "Fast access without digging through menus",
        "Quick Actions is the fast settings panel. Use it for common system controls, then switch between Gaming, Desktop, and Creator workflows when you need a different workspace. Returning to MechScope brings you back to the gaming session."
    ),
]

CREATOR_PAGES = [
    (
        "Welcome to Creator Mode",
        "A workspace for building, editing, and publishing",
        "Creator Mode groups creator applications, one-click packages, projects, assets, presets, and compatibility tools into a single MechOS workspace."
    ),
    (
        "Apps and Creator Packages",
        "Install the tools you actually need",
        "Use Apps for individual programs such as Blender, Unity Hub, Unreal setup, VRChat tools, editors, streaming software, and compatibility utilities. Creator Packages install related tool groups together and show their current status."
    ),
    (
        "Projects and Assets",
        "Resume work without hunting through folders",
        "Projects scans the MechOS project locations and recognizes supported project types. Assets gives you a central place to browse creator files. Presets are for reusable Creator Mode setups and workflows."
    ),
    (
        "Move Around Creator Mode",
        "Standard desktop navigation works everywhere",
        "Use Tab and Shift+Tab to move focus, arrow keys to move through lists and grids, Enter or Space to activate the selected item, and Escape to close dialogs. Use the mode controls when you are ready to return to MechScope or the desktop."
    ),
]

HOTKEY_PAGE = (
    "Hotkeys and Navigation Keys",
    "Keep these nearby until they become automatic",
    """
<b>MechScope / MechOS</b><br><br>
<b>Ctrl + Shift + M</b> — Open Quick Actions<br>
<b>Ctrl + Shift + L</b> — Open the streaming/Stream Center shortcut<br>
<b>Controller Guide / Mode button</b> — Quick Actions on supported controller setups<br>
<b>Tab / Shift + Tab</b> — Move keyboard focus<br>
<b>Arrow keys</b> — Move through lists and grids<br>
<b>Enter / Space</b> — Activate the selected control<br>
<b>Esc</b> — Close the current dialog when supported<br><br>
<b>Creator Mode</b><br><br>
<b>Tab / Shift + Tab</b> — Move between controls<br>
<b>Arrow keys</b> — Navigate lists and grids<br>
<b>Enter / Space</b> — Open or activate the selected item<br>
<b>Esc</b> — Close dialogs / cancel the current dialog<br><br>
You can reopen this guide later from <b>MechOS Tutorial</b> in the application menu.
"""
)


def pages_for(mode):
    if mode == "mechscope":
        return MECHSCOPE_PAGES + [HOTKEY_PAGE]
    if mode == "creator":
        return CREATOR_PAGES + [HOTKEY_PAGE]
    return MECHSCOPE_PAGES + CREATOR_PAGES + [HOTKEY_PAGE]


def write_markers(mode):
    CONFIG.mkdir(parents=True, exist_ok=True)
    if mode in ("all", "mechscope"):
        MECHSCOPE_MARKER.write_text("MechScope tutorial v1 completed\n")
    if mode in ("all", "creator"):
        CREATOR_MARKER.write_text("Creator Mode tutorial v1 completed\n")
    if mode == "all":
        ALL_MARKER.write_text("MechOS first-run tutorial v1 completed\n")


class Tutorial(QMainWindow):
    def __init__(self, mode="all", first_run=False):
        super().__init__()
        self.mode = mode
        self.first_run = first_run
        self.pages = pages_for(mode)
        self.index = 0
        self.setWindowTitle("MechOS Navigation Tutorial")
        self.setMinimumSize(980, 650)
        self.setStyleSheet(STYLE)
        self.build_ui()
        self.render()

    def build_ui(self):
        root = QWidget()
        self.setCentralWidget(root)
        outer = QVBoxLayout(root)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)

        top = QFrame(); top.setObjectName("top")
        tl = QHBoxLayout(top); tl.setContentsMargins(32,18,32,18)
        brand = QLabel("MECHOS • FIRST-RUN GUIDE" if self.first_run else "MECHOS • NAVIGATION GUIDE")
        brand.setObjectName("brand")
        tl.addWidget(brand)
        tl.addStretch(1)
        self.progress = QLabel(); self.progress.setObjectName("step")
        tl.addWidget(self.progress)
        outer.addWidget(top)

        middle = QVBoxLayout(); middle.setContentsMargins(54,42,54,28)
        card = QFrame(); card.setObjectName("card")
        cl = QVBoxLayout(card); cl.setContentsMargins(42,38,42,38); cl.setSpacing(16)
        self.kicker = QLabel(); self.kicker.setObjectName("brand")
        self.title = QLabel(); self.title.setObjectName("title"); self.title.setWordWrap(True)
        self.body = QLabel(); self.body.setObjectName("body"); self.body.setWordWrap(True)
        self.body.setTextFormat(Qt.TextFormat.RichText)
        self.body.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        cl.addWidget(self.kicker)
        cl.addWidget(self.title)
        cl.addSpacing(8)
        cl.addWidget(self.body, 1)
        middle.addWidget(card, 1)
        outer.addLayout(middle, 1)

        bar = QHBoxLayout(); bar.setContentsMargins(54,0,54,34); bar.setSpacing(12)
        self.skip = QPushButton("Skip tutorial"); self.skip.setObjectName("skip"); self.skip.clicked.connect(self.skip_tutorial)
        self.back = QPushButton("Back"); self.back.clicked.connect(self.prev_page)
        self.next = QPushButton("Next"); self.next.setObjectName("primary"); self.next.clicked.connect(self.next_page)
        bar.addWidget(self.skip)
        bar.addStretch(1)
        bar.addWidget(self.back)
        bar.addWidget(self.next)
        outer.addLayout(bar)

    def render(self):
        title, kicker, body = self.pages[self.index]
        self.progress.setText(f"STEP {self.index + 1} OF {len(self.pages)}")
        self.kicker.setText(kicker.upper())
        self.title.setText(title)
        if "<b>" in body:
            self.body.setText(body)
        else:
            self.body.setText(body.replace("\n", "<br>"))
        self.back.setEnabled(self.index > 0)
        self.next.setText("Finish" if self.index == len(self.pages) - 1 else "Next")

    def prev_page(self):
        if self.index > 0:
            self.index -= 1
            self.render()

    def next_page(self):
        if self.index == len(self.pages) - 1:
            write_markers(self.mode)
            self.close()
            return
        self.index += 1
        self.render()

    def skip_tutorial(self):
        answer = QMessageBox.question(
            self,
            "Skip MechOS tutorial?",
            "Skip the tutorial and mark this guide as completed? You can reopen it later from the MechOS Tutorial launcher.",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        if answer == QMessageBox.StandardButton.Yes:
            write_markers(self.mode)
            self.close()

    def keyPressEvent(self, event):
        if event.key() in (Qt.Key.Key_Right, Qt.Key.Key_PageDown):
            self.next_page(); return
        if event.key() in (Qt.Key.Key_Left, Qt.Key.Key_PageUp):
            self.prev_page(); return
        super().keyPressEvent(event)


def main():
    mode = "all"
    if "--mode" in sys.argv:
        try:
            value = sys.argv[sys.argv.index("--mode") + 1]
            if value in ("all", "mechscope", "creator"):
                mode = value
        except (ValueError, IndexError):
            pass
    first_run = "--first-run" in sys.argv
    app = QApplication(sys.argv)
    app.setApplicationName("MechOS Tutorial")
    window = Tutorial(mode, first_run)
    window.showMaximized()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
PYEOF
  chmod 755 "$bin/mechos-tutorial"

  cat > "$apps/mechos-tutorial.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS Tutorial
Comment=Learn MechScope and Creator Mode navigation and hotkeys
Exec=/usr/local/bin/mechos-tutorial --mode all
Icon=help-contents
Terminal=false
Categories=System;Settings;
Keywords=MechOS;Tutorial;Help;MechScope;Creator;Hotkeys;
EOF

  cat > "$apps/mechscope-tutorial.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechScope Tutorial
Comment=Learn MechScope navigation and hotkeys
Exec=/usr/local/bin/mechos-tutorial --mode mechscope
Icon=applications-games
Terminal=false
Categories=Game;System;
Keywords=MechOS;MechScope;Tutorial;Help;Hotkeys;
EOF

  cat > "$apps/mechos-creator-tutorial.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Creator Mode Tutorial
Comment=Learn Creator Mode navigation and keyboard controls
Exec=/usr/local/bin/mechos-tutorial --mode creator
Icon=applications-graphics
Terminal=false
Categories=Graphics;Development;System;
Keywords=MechOS;Creator;Tutorial;Help;Hotkeys;
EOF
}

wrap_app() {
  local tree="$1"
  local name="$2"
  local tutorial_mode="$3"
  local marker_rel="$4"
  local app="$tree/usr/local/bin/$name"
  local real="$tree/usr/local/bin/${name}.real"

  [ -f "$app" ] || return 0
  if grep -Fq '# MECHOS_TUTORIAL_WRAPPER_V1' "$app" 2>/dev/null; then
    return 0
  fi

  mv "$app" "$real"
  chmod 755 "$real"
  cat > "$app" <<EOF
#!/usr/bin/env bash
set -euo pipefail
# MECHOS_TUTORIAL_WRAPPER_V1
REAL="/usr/local/bin/${name}.real"
MARKER="\${XDG_CONFIG_HOME:-\$HOME/.config}/mechos/${marker_rel}"

# The Live ISO should remain a fast test environment. The combined tutorial is
# intended for the first graphical boot of an installed MechOS system.
if [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null; then
  exec "\$REAL" "\$@"
fi

if [ ! -e "\$MARKER" ] && [ -x /usr/local/bin/mechos-tutorial ]; then
  /usr/local/bin/mechos-tutorial --mode ${tutorial_mode} --first-run || true
fi

exec "\$REAL" "\$@"
EOF
  chmod 755 "$app"
}

patch_mechscope_quick_access() {
  local tree="$1"
  local target="$tree/usr/local/bin/mechscope.real"
  [ -f "$target" ] || return 0
  python3 - "$target" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")
needle = '("Unified Store", ["/usr/local/bin/mechscope","--store"]),'
insert = '("Navigation Tutorial", ["/usr/local/bin/mechos-tutorial","--mode","mechscope"]),\n            ' + needle
if "Navigation Tutorial" not in text and needle in text:
    text = text.replace(needle, insert, 1)
p.write_text(text, encoding="utf-8")
PY
}

patch_tree() {
  local tree="$1"
  install_tutorial "$tree"
  wrap_app "$tree" mechscope all tutorial-v1-complete
  wrap_app "$tree" mechos-creator-mode creator tutorial-creator-v1.done
  patch_mechscope_quick_access "$tree"
}

# Live rootfs receives the help launchers and wrapped MechScope, but the wrapper
# explicitly skips first-run auto-launch in the Live environment.
patch_tree "$ROOT"

# Creator Mode is intentionally post-install-only in current MechOS builds, so
# patch the installed-system archive too. This is also what makes the tutorial
# run automatically before MechScope on the first installed graphical boot.
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"
if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xf "$ARCHIVE" -C "$tmp"
  patch_tree "$tmp"
  new_archive="$ARCHIVE.tutorial"
  tar --zstd -cf "$new_archive" -C "$tmp" .
  mv -f "$new_archive" "$ARCHIVE"
  rm -rf "$tmp"
  trap - EXIT
else
  fail "installed-system payload archive is missing"
fi

# Explicit ArchISO permissions for the new runtime and wrapped live MechScope.
if [ -f "$PROFILE" ]; then
  for path in \
    /usr/local/bin/mechos-tutorial \
    /usr/local/bin/mechscope \
    /usr/local/bin/mechscope.real; do
    if ! grep -Fq "file_permissions[\"$path\"]" "$PROFILE"; then
      printf '\nfile_permissions["%s"]="0:0:755"\n' "$path" >> "$PROFILE"
    fi
  done
fi

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$ROOT/usr/local/bin/mechos-tutorial" \
  || fail "tutorial Python validation failed"
bash -n "$ROOT/usr/local/bin/mechscope" || fail "MechScope tutorial wrapper validation failed"
grep -Fq '# MECHOS_TUTORIAL_WRAPPER_V1' "$ROOT/usr/local/bin/mechscope" \
  || fail "MechScope tutorial wrapper is missing"
grep -Fq 'Hotkeys and Navigation Keys' "$ROOT/usr/local/bin/mechos-tutorial" \
  || fail "hotkey tutorial page is missing"
grep -Fq 'Ctrl + Shift + M' "$ROOT/usr/local/bin/mechos-tutorial" \
  || fail "Quick Actions hotkey is missing from tutorial"
grep -Fq 'Creator Mode Tutorial' "$ROOT/usr/share/applications/mechos-creator-tutorial.desktop" \
  || fail "Creator Mode tutorial launcher is missing"

log "first-run MechScope + Creator Mode tutorials installed"
