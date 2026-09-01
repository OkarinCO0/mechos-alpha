#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PACKAGES="/workspace/archlive/packages.x86_64"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"

log() { printf '[MechOS Creator Postinstall] %s\n' "$*"; }
fail() { printf '[MechOS Creator Postinstall] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing"
[ -f "$PACKAGES" ] || fail "ArchISO package list is missing"
[ -s "$ARCHIVE" ] || fail "installed-system payload archive is missing"

OPTIONAL_CREATOR_PACKAGES=(
  blender
  obs-studio
  kdenlive
  krita
  godot
  audacity
  lmms
)
for pkg in "${OPTIONAL_CREATOR_PACKAGES[@]}"; do
  sed -i "/^${pkg}$/d" "$PACKAGES"
done

install_creator_categories() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local libexec="$tree/usr/local/libexec"
  local manifests="$tree/usr/share/mechos/creator-packages"
  mkdir -p "$bin" "$libexec" "$manifests"

  cat > "$manifests/vrchat-creator.json" <<'EOF'
{
  "id": "vrchat-creator",
  "name": "VRChat Creator",
  "description": "Unity Hub, Blender and VS Code for avatar/world creation. VRChat SDK/VCC setup remains vendor-managed.",
  "disk_space": "Varies by Unity editor and projects",
  "native": ["blender"],
  "flatpak": ["unityhub", "vscode"]
}
EOF

  cat > "$manifests/game-design.json" <<'EOF'
{
  "id": "game-design",
  "name": "Game Design",
  "description": "Godot, Unity Hub, Blender, VS Code and GitKraken. Unreal Engine remains vendor-managed.",
  "disk_space": "Varies by installed engines",
  "native": ["godot", "blender"],
  "flatpak": ["unityhub", "vscode", "gitkraken"]
}
EOF

  cat > "$manifests/3d-texturing.json" <<'EOF'
{
  "id": "3d-texturing",
  "name": "3D Art & Texturing",
  "description": "Blender and Krita. Substance 3D Painter remains available separately through Steam.",
  "disk_space": "Approximately 3-5 GB plus projects",
  "native": ["blender", "krita"],
  "flatpak": []
}
EOF

  cat > "$manifests/streaming-video.json" <<'EOF'
{
  "id": "streaming-video",
  "name": "Streaming & Video",
  "description": "OBS Studio, Kdenlive, Audacity and Discord.",
  "disk_space": "Approximately 3-5 GB",
  "native": ["obs", "kdenlive", "audacity"],
  "flatpak": ["discord"]
}
EOF

  cat > "$manifests/audio-music.json" <<'EOF'
{
  "id": "audio-music",
  "name": "Audio & Music",
  "description": "Audacity and LMMS for audio editing and music production.",
  "disk_space": "Approximately 1-2 GB",
  "native": ["audacity", "lmms"],
  "flatpak": []
}
EOF

  cat > "$manifests/compatibility-tools.json" <<'EOF'
{
  "id": "compatibility-tools",
  "name": "Windows & Compatibility",
  "description": "Bottles, Heroic and ProtonUp-Qt. Core Wine/Proton support remains part of MechOS gaming.",
  "disk_space": "Approximately 2-4 GB plus prefixes",
  "native": [],
  "flatpak": ["bottles", "heroic", "protonupqt"]
}
EOF

  cat > "$libexec/mechos-creator-app-installer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Administrator privileges required." >&2; exit 1; }

if [ "${1:-}" = "--package" ]; then
  case "${2:-}" in
    vrchat-creator) PKGS=(blender) ;;
    game-design) PKGS=(godot blender) ;;
    3d-texturing) PKGS=(blender krita) ;;
    streaming-video) PKGS=(obs-studio kdenlive audacity) ;;
    audio-music) PKGS=(audacity lmms) ;;
    compatibility-tools) PKGS=() ;;
    streamer) PKGS=(obs-studio kdenlive audacity) ;;
    graphics) PKGS=(blender krita) ;;
    game-dev) PKGS=(godot blender) ;;
    windows-apps) PKGS=() ;;
    *) echo "Unknown Creator package id." >&2; exit 2 ;;
  esac

  if command -v snapper >/dev/null 2>&1 && snapper list-configs 2>/dev/null | awk '{print $1}' | grep -qx root; then
    snapper -c root create --type single --description "Before MechOS Creator package: ${2}" || true
  fi

  [ "${#PKGS[@]}" -gt 0 ] || exit 0
  exec pacman -S --needed --noconfirm "${PKGS[@]}"
fi

case "${1:-}" in
  blender) PKG=blender ;;
  obs) PKG=obs-studio ;;
  kdenlive) PKG=kdenlive ;;
  krita) PKG=krita ;;
  godot) PKG=godot ;;
  audacity) PKG=audacity ;;
  lmms) PKG=lmms ;;
  lutris) PKG=lutris ;;
  wine) PKG=wine ;;
  winetricks) PKG=winetricks ;;
  protontricks) PKG=protontricks ;;
  steam) PKG=steam ;;
  *) echo "Unknown Creator app id." >&2; exit 2 ;;
esac

exec pacman -S --needed --noconfirm "$PKG"
EOF
  chmod 755 "$libexec/mechos-creator-app-installer"

  local creator="$bin/mechos-creator-mode"
  if [ -f "$creator.real" ]; then
    creator="$creator.real"
  fi
  [ -f "$creator" ] || fail "Creator Mode executable is missing in $tree"

  python3 - "$creator" <<'PYEOF'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

packages = '''PACKAGES=[
 ("VRChat Creator","vrchat-creator","Unity Hub, Blender and VS Code; VRChat SDK/VCC setup remains vendor-managed","Varies by Unity editor"),
 ("Game Design","game-design","Godot, Unity Hub, Blender, VS Code and GitKraken; Unreal remains vendor-managed","Varies by engines"),
 ("3D Art & Texturing","3d-texturing","Blender and Krita; Substance 3D Painter is available separately through Steam","Approximately 3-5 GB"),
 ("Streaming & Video","streaming-video","OBS Studio, Kdenlive, Audacity and Discord","Approximately 3-5 GB"),
 ("Audio & Music","audio-music","Audacity and LMMS","Approximately 1-2 GB"),
 ("Windows & Compatibility","compatibility-tools","Bottles, Heroic and ProtonUp-Qt","Approximately 2-4 GB"),
]'''

text, count = re.subn(r'PACKAGES=\[.*?\]\n\nSTYLE=', packages + '\n\nSTYLE=', text, count=1, flags=re.S)
if count != 1:
    raise SystemExit("Creator Mode PACKAGES block was not found")

text = text.replace(
    "Install trusted MechOS creator bundles or choose individual applications. Native packages request administrator approval; Flatpaks install only for your user account.",
    "Install by Creator category or choose individual applications. VRChat Creator, Game Design, 3D Art, Streaming, Audio and Compatibility categories can each be installed as a bundle."
)
path.write_text(text, encoding="utf-8")
PYEOF

  python3 -m py_compile "$creator" || fail "Creator Mode Python compile failed after category patch"
  grep -Fq 'VRChat Creator","vrchat-creator' "$creator" || fail "VRChat Creator category is missing from Creator Mode"
  grep -Fq 'Game Design","game-design' "$creator" || fail "Game Design category is missing from Creator Mode"
}

install_creator_postinstall() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local libexec="$tree/usr/local/libexec"
  local autostart="$tree/etc/xdg/autostart"
  mkdir -p "$bin" "$libexec" "$autostart"

  install_creator_categories "$tree"

  cat > "$libexec/mechos-creator-postinstall-native" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Administrator privileges are required." >&2; exit 1; }

declare -a pkgs=()
for app in "$@"; do
  case "$app" in
    blender) pkgs+=(blender) ;;
    krita) pkgs+=(krita) ;;
    obs) pkgs+=(obs-studio) ;;
    kdenlive) pkgs+=(kdenlive) ;;
    godot) pkgs+=(godot) ;;
    audacity) pkgs+=(audacity) ;;
    lmms) pkgs+=(lmms) ;;
    *) echo "Unknown native Creator app: $app" >&2; exit 2 ;;
  esac
done

[ "${#pkgs[@]}" -gt 0 ] || exit 0
mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | awk '!seen[$0]++')
exec pacman -S --needed --noconfirm "${pkgs[@]}"
EOF
  chmod 755 "$libexec/mechos-creator-postinstall-native"

  cat > "$bin/mechos-creator-postinstall-run" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/mechos/creator-postinstall-complete"
mkdir -p "$(dirname "$MARKER")"

native=()
flatpaks=()
for app in "$@"; do
  case "$app" in
    blender|krita|obs|kdenlive|godot|audacity|lmms)
      native+=("$app")
      ;;
    unityhub) flatpaks+=(com.unity.UnityHub) ;;
    vscode) flatpaks+=(com.visualstudio.code) ;;
    gitkraken) flatpaks+=(com.axosoft.GitKraken) ;;
    discord) flatpaks+=(com.discordapp.Discord) ;;
    bottles) flatpaks+=(com.usebottles.bottles) ;;
    heroic) flatpaks+=(com.heroicgameslauncher.hgl) ;;
    protonupqt) flatpaks+=(net.davidotek.pupgui2) ;;
    *) echo "Unknown Creator app: $app" >&2; exit 2 ;;
  esac
done

if [ "${#native[@]}" -gt 0 ]; then
  pkexec /usr/local/libexec/mechos-creator-postinstall-native "${native[@]}"
fi

if [ "${#flatpaks[@]}" -gt 0 ]; then
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  mapfile -t flatpaks < <(printf '%s\n' "${flatpaks[@]}" | awk '!seen[$0]++')
  flatpak install --user -y flathub "${flatpaks[@]}"
fi

touch "$MARKER"
printf 'Creator Apps setup complete.\n'

if [ -x /usr/local/bin/mechos-gaming-shell ]; then
  nohup /usr/local/bin/mechos-gaming-shell >/dev/null 2>&1 &
fi
EOF
  chmod 755 "$bin/mechos-creator-postinstall-run"

  cat > "$bin/mechos-creator-postinstall" <<'PYEOF'
#!/usr/bin/env python3
import os
import subprocess
import sys
from pathlib import Path

from PyQt6.QtWidgets import (
    QApplication, QCheckBox, QFrame, QGridLayout, QHBoxLayout, QLabel,
    QMainWindow, QMessageBox, QPushButton, QScrollArea, QVBoxLayout, QWidget
)

MARKER = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "mechos" / "creator-postinstall-complete"
RUNNER = "/usr/local/bin/mechos-creator-postinstall-run"

APPS = [
    ("Blender", "blender", "3D modeling and animation", "Native"),
    ("Krita", "krita", "Texture painting and digital art", "Native"),
    ("OBS Studio", "obs", "Streaming and recording", "Native"),
    ("Kdenlive", "kdenlive", "Video editing", "Native"),
    ("Godot", "godot", "Open-source game engine", "Native"),
    ("Audacity", "audacity", "Audio editing", "Native"),
    ("LMMS", "lmms", "Music production", "Native"),
    ("Unity Hub", "unityhub", "Unity editor manager", "Flatpak"),
    ("VS Code", "vscode", "Code editor", "Flatpak"),
    ("GitKraken", "gitkraken", "Git client", "Flatpak"),
    ("Discord", "discord", "Creator/community chat", "Flatpak"),
    ("Bottles", "bottles", "Windows application environments", "Flatpak"),
    ("Heroic", "heroic", "Epic/GOG/Amazon launcher", "Flatpak"),
    ("ProtonUp-Qt", "protonupqt", "GE-Proton and Wine tools", "Flatpak"),
]

CATEGORIES = [
    ("VRChat Creator", ["unityhub", "blender", "vscode"], "Avatar/world creation essentials. VRChat SDK/VCC setup remains vendor-managed."),
    ("Game Design", ["godot", "unityhub", "blender", "vscode", "gitkraken"], "Game engine, art and code tools. Unreal Engine remains vendor-managed."),
    ("3D Art & Texturing", ["blender", "krita"], "Modeling and texture tools. Substance 3D Painter stays available through Steam."),
    ("Streaming & Video", ["obs", "kdenlive", "audacity", "discord"], "Streaming, recording, editing and creator communication."),
    ("Audio & Music", ["audacity", "lmms"], "Audio editing and music production."),
    ("Windows & Compatibility", ["bottles", "heroic", "protonupqt"], "Optional Windows-app and launcher tools."),
]

STYLE = """
QWidget { background:#080a10; color:#f4effb; font-family:Sans Serif; }
QFrame#card { background:#111520; border:1px solid #34304a; border-radius:12px; }
QFrame#category { background:#0d1018; border:1px solid #52316d; border-radius:12px; }
QLabel#title { font-size:28px; font-weight:900; }
QLabel#muted { color:#aaa2b7; }
QLabel#purple { color:#c879ff; font-weight:800; }
QPushButton { background:#351750; border:1px solid #704198; border-radius:8px; padding:10px 16px; font-weight:700; }
QPushButton:hover { background:#56257b; }
QScrollArea { border:0; }
"""

def is_live():
    try:
        return Path("/run/archiso/bootmnt").exists() or "archiso" in Path("/proc/cmdline").read_text(errors="ignore")
    except Exception:
        return False

class Setup(QMainWindow):
    def __init__(self):
        super().__init__()
        self.checks = []
        self.check_by_id = {}
        self.setWindowTitle("MechOS Creator Apps Setup")
        self.resize(1180, 840)
        self.setMinimumSize(940, 650)
        self.setStyleSheet(STYLE)
        self.build()

    def build(self):
        root = QWidget()
        self.setCentralWidget(root)
        outer = QVBoxLayout(root)
        outer.setContentsMargins(32, 26, 32, 26)
        outer.setSpacing(14)

        title = QLabel("CREATOR APPS SETUP")
        title.setObjectName("title")
        outer.addWidget(title)

        subtitle = QLabel(
            "Creator applications are optional. Install a complete category such as VRChat Creator or Game Design, mix categories, or choose individual apps. Anything skipped remains installable later inside Creator Mode."
        )
        subtitle.setObjectName("muted")
        subtitle.setWordWrap(True)
        outer.addWidget(subtitle)

        category_label = QLabel("INSTALL BY CATEGORY")
        category_label.setObjectName("purple")
        outer.addWidget(category_label)

        category_grid = QGridLayout()
        category_grid.setSpacing(10)
        for i, (name, ids, desc) in enumerate(CATEGORIES):
            card = QFrame()
            card.setObjectName("category")
            layout = QVBoxLayout(card)
            n = QLabel(name)
            n.setObjectName("purple")
            layout.addWidget(n)
            d = QLabel(desc)
            d.setObjectName("muted")
            d.setWordWrap(True)
            layout.addWidget(d)
            b = QPushButton("Select Category")
            b.clicked.connect(lambda _, items=ids: self.select_category(items))
            layout.addWidget(b)
            category_grid.addWidget(card, i // 3, i % 3)
        outer.addLayout(category_grid)

        individual = QHBoxLayout()
        label = QLabel("INDIVIDUAL APPS")
        label.setObjectName("purple")
        individual.addWidget(label)
        individual.addStretch()
        all_button = QPushButton("Select All")
        all_button.clicked.connect(self.select_all)
        individual.addWidget(all_button)
        clear_button = QPushButton("Clear")
        clear_button.clicked.connect(self.clear_selection)
        individual.addWidget(clear_button)
        outer.addLayout(individual)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        content = QWidget()
        grid = QGridLayout(content)
        grid.setSpacing(12)

        for i, (name, appid, desc, source) in enumerate(APPS):
            card = QFrame()
            card.setObjectName("card")
            layout = QVBoxLayout(card)
            check = QCheckBox(name)
            check.setProperty("appid", appid)
            layout.addWidget(check)
            d = QLabel(desc)
            d.setObjectName("muted")
            d.setWordWrap(True)
            layout.addWidget(d)
            s = QLabel(source.upper())
            s.setObjectName("purple")
            layout.addWidget(s)
            self.checks.append(check)
            self.check_by_id[appid] = check
            grid.addWidget(card, i // 3, i % 3)

        scroll.setWidget(content)
        outer.addWidget(scroll, 1)

        buttons = QHBoxLayout()
        buttons.addStretch(1)
        skip = QPushButton("Skip — Install Later")
        skip.clicked.connect(self.skip)
        buttons.addWidget(skip)
        install = QPushButton("Install Selected Categories / Apps")
        install.clicked.connect(self.install)
        buttons.addWidget(install)
        outer.addLayout(buttons)

    def select_category(self, ids):
        for appid in ids:
            check = self.check_by_id.get(appid)
            if check is not None:
                check.setChecked(True)

    def select_all(self):
        for check in self.checks:
            check.setChecked(True)

    def clear_selection(self):
        for check in self.checks:
            check.setChecked(False)

    def finish_marker(self):
        MARKER.parent.mkdir(parents=True, exist_ok=True)
        MARKER.touch()
        if Path("/usr/local/bin/mechos-gaming-shell").exists():
            subprocess.Popen(
                ["/usr/local/bin/mechos-gaming-shell"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )

    def skip(self):
        if QMessageBox.question(
            self,
            "Creator Apps",
            "Skip Creator app installation for now? You can install by category or individual app later from Creator Mode.",
        ) != QMessageBox.StandardButton.Yes:
            return
        self.finish_marker()
        self.close()

    def install(self):
        chosen = [str(c.property("appid")) for c in self.checks if c.isChecked()]
        if not chosen:
            self.skip()
            return
        quoted = " ".join(subprocess.list2cmdline([x]) for x in [RUNNER] + chosen)
        cmd = quoted + "; rc=$?; echo; echo Installer exit code: $rc; read -rp 'Press Enter to close...'"
        try:
            subprocess.Popen(["konsole", "-e", "bash", "-lc", cmd])
        except Exception as exc:
            QMessageBox.critical(self, "Creator Apps", str(exc))
            return
        self.close()

def main():
    if is_live() or MARKER.exists() or not Path("/var/lib/mechos/oobe-complete").exists():
        return 0
    app = QApplication(sys.argv)
    app.setApplicationName("MechOS Creator Apps Setup")
    w = Setup()
    w.showMaximized()
    return app.exec()

if __name__ == "__main__":
    raise SystemExit(main())
PYEOF
  chmod 755 "$bin/mechos-creator-postinstall"

  cat > "$autostart/mechos-creator-postinstall.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS Creator Apps Setup
Comment=Choose optional Creator categories or individual applications after MechOS installation
Exec=/usr/local/bin/mechos-creator-postinstall
Terminal=false
OnlyShowIn=KDE;
X-KDE-autostart-after=panel
EOF

  local gaming="$bin/mechos-gaming-shell"
  if [ -f "$gaming" ] && ! grep -Fq 'MECHOS_CREATOR_POSTINSTALL_GATE' "$gaming"; then
    python3 - "$gaming" <<'PYEOF'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
guard = r"""
# MECHOS_CREATOR_POSTINSTALL_GATE
if [ -e /var/lib/mechos/oobe-complete ] && \
   [ ! -e "${XDG_CONFIG_HOME:-$HOME/.config}/mechos/creator-postinstall-complete" ]; then
  exit 0
fi

"""
if text.startswith("#!"):
    pos = text.find("\n") + 1
    text = text[:pos] + guard + text[pos:]
else:
    text = guard + text
path.write_text(text)
PYEOF
    bash -n "$gaming" || fail "gaming shell syntax failed after Creator postinstall gate"
  fi
}

install_creator_postinstall "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xf "$ARCHIVE" -C "$tmp"
install_creator_postinstall "$tmp"

new_archive="$ARCHIVE.new"
tar --zstd -cpf "$new_archive" -C "$tmp" .
mv -f "$new_archive" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

grep -Fq 'CREATOR APPS SETUP' "$ROOT/usr/local/bin/mechos-creator-postinstall" || fail "Creator Apps wizard is missing"
grep -Fq 'VRChat Creator' "$ROOT/usr/local/bin/mechos-creator-postinstall" || fail "VRChat post-install category is missing"
grep -Fq 'Game Design' "$ROOT/usr/local/bin/mechos-creator-postinstall" || fail "Game Design post-install category is missing"
grep -Fq 'MECHOS_CREATOR_POSTINSTALL_GATE' "$ROOT/usr/local/bin/mechos-gaming-shell" || fail "MechScope startup gate is missing"
for pkg in "${OPTIONAL_CREATOR_PACKAGES[@]}"; do
  ! grep -qx "$pkg" "$PACKAGES" || fail "Creator app still preloaded in core ISO: $pkg"
done

log "Creator apps remain optional; users can install by VRChat, Game Design and other categories during post-install or later inside Creator Mode"
