#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log() { printf '[MechOS Reference Stores v3] %s\n' "$*"; }
fail() { printf '[MechOS Reference Stores v3] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Reference Stores v3] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -s "$ARCHIVE" ] || fail "installed-system payload is missing: $ARCHIVE"

resolve_python_target() {
  local tree="$1" name="$2"
  if [ -f "$tree/usr/local/bin/$name.real" ]; then
    printf '%s\n' "$tree/usr/local/bin/$name.real"
  else
    printf '%s\n' "$tree/usr/local/bin/$name"
  fi
}

patch_mechscope_store() {
  local file="$1"
  [ -f "$file" ] || fail "MechScope GUI is missing: $file"

  python3 - "$file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_REFERENCE_UNIFIED_STORE_V3'
if marker in text:
    raise SystemExit(0)

if 'from urllib.parse import quote_plus' not in text:
    text = 'from urllib.parse import quote_plus\n' + text

start = text.find('class UnifiedStore(QDialog):')
end = text.find('\nclass MechScope(QMainWindow):', start)
if start < 0 or end < 0:
    raise SystemExit('[MechOS Reference Stores v3] could not locate UnifiedStore class')

# Triple-double quotes are deliberate here because the generated class contains
# a triple-single-quoted QSS block. Keeping the delimiters different prevents
# the QSS from terminating this generator string.
replacement = r"""class UnifiedStore(QDialog):
    # MECHOS_REFERENCE_UNIFIED_STORE_V3
    STORES = [
        ("Steam", "Your primary PC game library", "https://store.steampowered.com/search/?term={query}", ["steam", "-gamepadui"]),
        ("Epic Games", "Official Epic checkout • Heroic downloads", "https://store.epicgames.com/browse?q={query}", ["flatpak", "run", "com.heroicgameslauncher.hgl"]),
        ("GOG", "DRM-free catalog • Heroic downloads", "https://www.gog.com/en/games?query={query}", ["flatpak", "run", "com.heroicgameslauncher.hgl"]),
        ("Amazon Games", "Prime Gaming and Amazon titles", "https://gaming.amazon.com/home", ["flatpak", "run", "com.heroicgameslauncher.hgl"]),
    ]

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("MechScope Unified Store")
        self.setWindowFlag(Qt.WindowType.FramelessWindowHint, True)
        self.setWindowState(Qt.WindowState.WindowFullScreen)
        self.setModal(True)
        self.selected_store = 0
        self.build_reference_store()

    def panel(self, name="storePanel"):
        frame = QFrame()
        frame.setObjectName(name)
        return frame

    def store_button(self, label, index):
        b = QPushButton(label)
        b.setCheckable(True)
        b.setMinimumHeight(50)
        b.clicked.connect(lambda _=False, i=index: self.select_store(i))
        return b

    def build_reference_store(self):
        self.setStyleSheet(self.styleSheet() + r'''
QFrame#storeHero { background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #0a0b19,stop:.50 #15102d,stop:1 #07172b); border:1px solid #7d3ed1; border-radius:18px; }
QFrame#storePanel { background:#09101f; border:1px solid #342154; border-radius:16px; }
QFrame#sourceCard { background:#0d1426; border:1px solid #3b3766; border-radius:15px; }
QFrame#sourceCard:hover { border:1px solid #7dd3fc; }
QLabel#storeTitle { color:white; font-size:34px; font-weight:900; }
QLabel#storeEyebrow { color:#d28aff; font-size:13px; font-weight:900; }
QLabel#storeSection { color:#67e8f9; font-size:13px; font-weight:900; }
QLabel#storeMuted { color:#9fb0c8; }
QLineEdit { background:#080e1b; border:1px solid #3c4a70; border-radius:12px; padding:13px 15px; font-size:15px; }
QLineEdit:focus { border:2px solid #a855f7; }
''')
        outer = QVBoxLayout(self)
        outer.setContentsMargins(28, 22, 28, 22)
        outer.setSpacing(14)

        header = QHBoxLayout()
        brand = QLabel("MECHOS")
        brand.setStyleSheet("color:#d8b4fe;font-size:22px;font-weight:900;letter-spacing:1px")
        header.addWidget(brand)
        header.addStretch()
        title = QLabel("UNIFIED STORE")
        title.setStyleSheet("color:#c77dff;font-size:24px;font-weight:900")
        header.addWidget(title)
        header.addStretch()
        back = QPushButton("Back to MechScope")
        back.clicked.connect(self.accept)
        header.addWidget(back)
        outer.addLayout(header)

        hero = self.panel("storeHero")
        hl = QHBoxLayout(hero)
        hl.setContentsMargins(24, 22, 24, 22)
        copy = QVBoxLayout()
        eyebrow = QLabel("MECHSCOPE GAME MARKETPLACE")
        eyebrow.setObjectName("storeEyebrow")
        copy.addWidget(eyebrow)
        h1 = QLabel("Every game store. One MechOS view.")
        h1.setObjectName("storeTitle")
        copy.addWidget(h1)
        sub = QLabel("Search official PC stores, open the authorized launcher, then return to MechScope. Purchases, accounts, licenses, downloads and anti-cheat remain with each official provider.")
        sub.setObjectName("storeMuted")
        sub.setWordWrap(True)
        copy.addWidget(sub)
        sr = QHBoxLayout()
        self.search = QLineEdit()
        self.search.setPlaceholderText("Search for a game across stores")
        self.search.returnPressed.connect(self.search_selected)
        sr.addWidget(self.search, 1)
        search_selected = QPushButton("Search Selected Store")
        search_selected.setObjectName("primary")
        search_selected.clicked.connect(self.search_selected)
        sr.addWidget(search_selected)
        search_all = QPushButton("Search All Stores")
        search_all.clicked.connect(self.search_all)
        sr.addWidget(search_all)
        copy.addLayout(sr)
        hl.addLayout(copy, 3)

        featured = self.panel("sourceCard")
        fl = QVBoxLayout(featured)
        ft = QLabel("SELECTED SOURCE")
        ft.setObjectName("storeSection")
        fl.addWidget(ft)
        self.feature_name = QLabel("Steam")
        self.feature_name.setStyleSheet("font-size:24px;font-weight:900;color:white")
        fl.addWidget(self.feature_name)
        self.feature_desc = QLabel(self.STORES[0][1])
        self.feature_desc.setObjectName("storeMuted")
        self.feature_desc.setWordWrap(True)
        fl.addWidget(self.feature_desc)
        self.open_source = QPushButton("Browse / Buy on Steam")
        self.open_source.setObjectName("primary")
        self.open_source.clicked.connect(self.browse_selected)
        fl.addWidget(self.open_source)
        downloads = QPushButton("Open Downloads / Library")
        downloads.clicked.connect(self.open_selected_launcher)
        fl.addWidget(downloads)
        hl.addWidget(featured, 1)
        outer.addWidget(hero)

        section = QLabel("STORE SOURCES")
        section.setObjectName("storeSection")
        outer.addWidget(section)
        source_row = QHBoxLayout()
        self.source_buttons = []
        for i, (name, desc, _url, _launcher) in enumerate(self.STORES):
            card = self.panel("sourceCard")
            cl = QVBoxLayout(card)
            name_label = QLabel(name)
            name_label.setStyleSheet("font-size:18px;font-weight:900;color:white")
            cl.addWidget(name_label)
            d = QLabel(desc)
            d.setObjectName("storeMuted")
            d.setWordWrap(True)
            cl.addWidget(d)
            cl.addStretch()
            b = self.store_button("Select " + name, i)
            cl.addWidget(b)
            self.source_buttons.append(b)
            source_row.addWidget(card, 1)
        outer.addLayout(source_row)

        bottom = QHBoxLayout()
        management = self.panel()
        ml = QVBoxLayout(management)
        mt = QLabel("DOWNLOAD MANAGEMENT")
        mt.setObjectName("storeSection")
        ml.addWidget(mt)
        mn = QLabel("After checkout, install through Steam or Heroic. MechOS does not copy protected game files into the ISO and does not bypass account or anti-cheat systems.")
        mn.setObjectName("storeMuted")
        mn.setWordWrap(True)
        ml.addWidget(mn)
        br = QHBoxLayout()
        refresh = QPushButton("Refresh Game Library")
        refresh.clicked.connect(self.refresh_library)
        br.addWidget(refresh)
        lutris = QPushButton("Open Lutris Imports")
        lutris.clicked.connect(lambda: spawn(["lutris"]))
        br.addWidget(lutris)
        steam = QPushButton("Open Steam Gamepad UI")
        steam.clicked.connect(lambda: spawn(["steam", "-gamepadui"]))
        br.addWidget(steam)
        ml.addLayout(br)
        bottom.addWidget(management, 2)

        compatibility = self.panel()
        xl = QVBoxLayout(compatibility)
        xt = QLabel("MECHOS COMPATIBILITY")
        xt.setObjectName("storeSection")
        xl.addWidget(xt)
        x = QLabel("Verified • Playable • Needs Setup • Unsupported • Unknown\n\nCompatibility profiles are maintained by MechOS, while ownership and downloads stay with official stores.")
        x.setObjectName("storeMuted")
        x.setWordWrap(True)
        xl.addWidget(x)
        bottom.addWidget(compatibility, 1)
        outer.addLayout(bottom)
        self.select_store(0)

    def select_store(self, index):
        self.selected_store = index
        name, desc, _url, _launcher = self.STORES[index]
        self.feature_name.setText(name)
        self.feature_desc.setText(desc)
        self.open_source.setText("Browse / Buy on " + name)
        for i, button in enumerate(self.source_buttons):
            button.setChecked(i == index)

    def query(self):
        return quote_plus(self.search.text().strip())

    def browse_selected(self):
        _name, _desc, url, _launcher = self.STORES[self.selected_store]
        spawn(["xdg-open", url.format(query=self.query())])

    def search_selected(self):
        self.browse_selected()

    def search_all(self):
        q = self.query()
        if not q:
            self.browse_selected()
            return
        for _name, _desc, url, _launcher in self.STORES[:3]:
            spawn(["xdg-open", url.format(query=q)])

    def open_selected_launcher(self):
        _name, _desc, _url, launcher = self.STORES[self.selected_store]
        spawn(launcher)

    def open_launcher(self, cmd):
        spawn(cmd)

    def refresh_library(self):
        count = len(steam_games())
        QMessageBox.information(self, "Game Library", f"Library scan completed. {count} installed Steam game(s) detected. Heroic and Lutris continue managing their own downloads.")

"""

text = text[:start] + replacement + text[end:]
path.write_text(text, encoding='utf-8')
PY

  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$file" \
    || fail "MechScope syntax failed after Unified Store v3 patch: $file"
  grep -Fq 'MECHOS_REFERENCE_UNIFIED_STORE_V3' "$file" \
    || fail "Unified Store v3 marker is missing"
  grep -Fq 'Every game store. One MechOS view.' "$file" \
    || fail "Unified Store v3 hero is missing"
}

patch_creator_store() {
  local file="$1"
  [ -f "$file" ] || fail "Creator Mode GUI is missing: $file"

  python3 - "$file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_REFERENCE_CREATOR_STORE_V3'

if marker not in text:
    start = text.find('    def app_store(self):')
    end = text.find('\n    def new_project(self):', start)
    if start < 0 or end < 0:
        raise SystemExit('[MechOS Reference Stores v3] could not locate Creator app_store()')

    replacement = r'''    def app_store(self):
        # MECHOS_REFERENCE_CREATOR_STORE_V3
        s, v = self.scroll()

        hero = self.panel()
        hero.setStyleSheet("QFrame#panel{background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #0a0b19,stop:.55 #18102e,stop:1 #08172b);border:1px solid #7841c8;border-radius:18px}")
        hl = QHBoxLayout(hero)
        hl.setContentsMargins(24, 20, 24, 20)
        copy = QVBoxLayout()
        eyebrow = QLabel("MECHOS CREATOR MARKETPLACE")
        eyebrow.setObjectName("purple")
        copy.addWidget(eyebrow)
        title = QLabel("Creator Store")
        title.setObjectName("title")
        title.setStyleSheet("font-size:34px;font-weight:900;color:white")
        copy.addWidget(title)
        intro = QLabel("Install engines, 3D tools, art software, streaming apps and Windows compatibility tools from one controller-friendly MechOS surface.")
        intro.setObjectName("muted")
        intro.setWordWrap(True)
        copy.addWidget(intro)
        badge = QLabel("POST-INSTALL ONLY  •  ADMIN APPROVAL FOR SYSTEM PACKAGES  •  USER-SCOPED FLATPAKS")
        badge.setObjectName("metric")
        badge.setWordWrap(True)
        copy.addWidget(badge)
        hl.addLayout(copy, 3)

        featured = self.panel()
        fl = QVBoxLayout(featured)
        ft = QLabel("FEATURED WORKFLOWS")
        ft.setObjectName("purple")
        fl.addWidget(ft)
        for name, preset in [("Game Developer", "Game Dev"), ("VRChat Creator", "VRChat Creator"), ("3D Artist", "3D Artist"), ("Streamer", "Streaming")]:
            b = QPushButton(name)
            b.setObjectName("action")
            b.setMinimumHeight(42)
            b.clicked.connect(lambda _, p=preset: self.apply_preset(p))
            fl.addWidget(b)
        hl.addWidget(featured, 1)
        v.addWidget(hero)

        nav = self.panel()
        nl = QHBoxLayout(nav)
        label = QLabel("BROWSE")
        label.setObjectName("purple")
        nl.addWidget(label)
        pages = QStackedWidget()
        category_buttons = []

        def category_button(text, index):
            b = QPushButton(text)
            b.setObjectName("action")
            b.setCheckable(True)
            b.clicked.connect(lambda _=False, i=index: (pages.setCurrentIndex(i), [x.setChecked(j == i) for j, x in enumerate(category_buttons)]))
            category_buttons.append(b)
            nl.addWidget(b)

        def page_for(ids, columns=4, title_text='APPLICATIONS'):
            page = QWidget()
            pl = QVBoxLayout(page)
            heading = QLabel(title_text)
            heading.setObjectName("purple")
            pl.addWidget(heading)
            grid = QGridLayout()
            grid.setHorizontalSpacing(14)
            grid.setVerticalSpacing(14)
            selected = [info for info in CATALOG if info[1] in ids] if ids is not None else list(CATALOG)
            for i, info in enumerate(selected):
                c = AppCard(self, info)
                c.setMinimumHeight(175)
                self.cards.append(c)
                grid.addWidget(c, i // columns, i % columns)
            pl.addLayout(grid)
            pl.addStretch()
            return page

        featured_page = QWidget()
        fpl = QVBoxLayout(featured_page)
        h = QLabel("ONE-CLICK CREATOR BUNDLES")
        h.setObjectName("purple")
        fpl.addWidget(h)
        pg = QGridLayout()
        for i, info in enumerate(PACKAGES):
            c = PackageCard(self, info)
            c.setMinimumHeight(190)
            self.package_cards.append(c)
            pg.addWidget(c, i // 2, i % 2)
        fpl.addLayout(pg)
        note = QLabel("Bundles install only the tools in that workflow. Large engines remain vendor/user downloads instead of being baked into the MechOS ISO.")
        note.setObjectName("muted")
        note.setWordWrap(True)
        fpl.addWidget(note)
        pages.addWidget(featured_page)

        pages.addWidget(page_for(None, 4, 'ALL CREATOR APPS'))
        pages.addWidget(page_for(['unityhub','unreal','godot','vscode','gitkraken'], 3, 'GAME ENGINES & DEVELOPMENT'))
        pages.addWidget(page_for(['blender','krita','vrchat'], 3, '3D, ART & VRCHAT'))
        pages.addWidget(page_for(['obs','audacity','lmms','discord'], 3, 'STREAMING & MEDIA'))
        pages.addWidget(page_for(['bottles','wine','winetricks','protontricks','protonupqt','lutris','heroic'], 3, 'WINDOWS & COMPATIBILITY'))

        for text_value, index in [('Featured',0),('All Apps',1),('Game Engines',2),('3D & Art',3),('Streaming',4),('Windows Tools',5)]:
            category_button(text_value, index)
        category_buttons[0].setChecked(True)
        nl.addStretch()
        v.addWidget(nav)
        v.addWidget(pages, 1)

        footer = self.panel()
        f = QHBoxLayout(footer)
        status = QLabel("Installed apps show READY. Missing apps offer Install. Vendor-managed engines open their official setup path.")
        status.setObjectName("muted")
        status.setWordWrap(True)
        f.addWidget(status, 1)
        refresh = QPushButton("Refresh Store Status")
        refresh.setObjectName("action")
        refresh.clicked.connect(lambda: [card.refresh() for card in self.cards + self.package_cards])
        f.addWidget(refresh)
        v.addWidget(footer)
        return s
'''
    text = text[:start] + replacement + text[end:]

# Make Creator -> MechScope a same-session handoff. Replace the whole method
# structurally so formatting changes cannot drop the user back to Plasma.
method = '    def mechscope(self):\n'
ms = text.find(method)
if ms >= 0 and 'MECHOS_CREATOR_RETURN_TO_MECHSCOPE_V2' not in text[ms:ms+1400]:
    next_def = text.find('\n    def ', ms + len(method))
    if next_def < 0:
        raise SystemExit('[MechOS Reference Stores v3] could not bound Creator mechscope() method')
    replacement = '''    def mechscope(self):\n        # MECHOS_CREATOR_RETURN_TO_MECHSCOPE_V2\n        env_names = ["DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "XDG_SESSION_TYPE"]\n        subprocess.run(["systemctl", "--user", "import-environment", *env_names], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n        if shutil.which("dbus-update-activation-environment"):\n            subprocess.run(["dbus-update-activation-environment", "--systemd", *env_names], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n        result = subprocess.run(["systemctl", "--user", "start", "--no-block", "mechos-gaming-layer.service"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n        if result.returncode != 0:\n            QMessageBox.warning(self, "MechOS Creator Mode", "MechScope could not be started. Creator Mode will stay open instead of sending you to Desktop Mode.")\n            return\n        QTimer.singleShot(350, QApplication.quit)\n'''
    text = text[:ms] + replacement + text[next_def:]

if 'MECHOS_CREATOR_RETURN_TO_MECHSCOPE_V2' not in text:
    raise SystemExit('[MechOS Reference Stores v3] Creator return-to-MechScope marker is missing')

path.write_text(text, encoding='utf-8')
PY

  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$file" \
    || fail "Creator Mode syntax failed after Creator Store v3 patch: $file"
  grep -Fq 'MECHOS_REFERENCE_CREATOR_STORE_V3' "$file" \
    || fail "Creator Store v3 marker is missing"
  grep -Fq 'MECHOS_CREATOR_RETURN_TO_MECHSCOPE_V2' "$file" \
    || fail "Creator return-to-MechScope v2 marker is missing"
}

patch_creator_handoff() {
  local tree="$1"
  local control="$tree/usr/local/bin/mechos-gaming-layer-control"
  [ -f "$control" ] || return 0

  python3 - "$control" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_CREATOR_READINESS_HANDOFF_V2'
if marker in text:
    raise SystemExit(0)

needle = '  creator)\n'
start = text.find(needle)
if start < 0:
    raise SystemExit('[MechOS Reference Stores v3] creator mode case missing from gaming-layer-control')
end = text.find('\n    ;;', start)
if end < 0:
    raise SystemExit('[MechOS Reference Stores v3] creator mode case terminator missing')
end += len('\n    ;;')

replacement = r'''  creator)
    # MECHOS_CREATOR_READINESS_HANDOFF_V2
    systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XDG_SESSION_TYPE >/dev/null 2>&1 || true
    if command -v dbus-update-activation-environment >/dev/null 2>&1; then
      dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XDG_SESSION_TYPE >/dev/null 2>&1 || true
    fi
    if ! systemctl --user cat mechos-creator-mode.service >/dev/null 2>&1; then
      echo "Creator Mode service is missing; keeping MechScope active." >&2
      exit 1
    fi
    systemctl --user reset-failed mechos-creator-mode.service >/dev/null 2>&1 || true
    systemctl --user start --no-block mechos-creator-mode.service
    ready=0
    for _ in 1 2 3 4 5 6 7 8; do
      if systemctl --user is-active --quiet mechos-creator-mode.service; then ready=1; break; fi
      sleep 0.15
    done
    if [ "$ready" -ne 1 ]; then
      echo "Creator Mode failed to start; keeping MechScope active." >&2
      exit 1
    fi
    stop_layer
    ;;'''

text = text[:start] + replacement + text[end:]
path.write_text(text, encoding='utf-8')
PY

  chmod 755 "$control"
  bash -n "$control" || fail "gaming-layer-control syntax failed after Creator readiness patch"
  grep -Fq 'MECHOS_CREATOR_READINESS_HANDOFF_V2' "$control" \
    || fail "Creator readiness handoff marker is missing"
}

patch_tree() {
  local tree="$1"
  local mechscope creator
  mechscope="$(resolve_python_target "$tree" mechscope)"
  creator="$(resolve_python_target "$tree" mechos-creator-mode)"
  [ -f "$mechscope" ] || fail "MechScope target is missing in $tree"
  patch_mechscope_store "$mechscope"
  if [ -f "$creator" ]; then patch_creator_store "$creator"; fi
  patch_creator_handoff "$tree"
}

patch_tree "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xf "$ARCHIVE" -C "$tmp"
patch_tree "$tmp"
creator_payload="$(resolve_python_target "$tmp" mechos-creator-mode)"
[ -f "$creator_payload" ] || fail "installed payload lost Creator Mode"
grep -Fq 'MECHOS_REFERENCE_CREATOR_STORE_V3' "$creator_payload" \
  || fail "installed payload Creator Store v3 is missing"
replacement="$ARCHIVE.reference-stores-v3"
tar --zstd -cpf "$replacement" -C "$tmp" .
mv -f "$replacement" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

log "Unified Store and Creator Store rebuilt to Reference UI v3; Creator/MechScope handoff stays inside the authenticated session"
