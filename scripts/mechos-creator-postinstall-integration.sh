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

install_creator_postinstall() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local libexec="$tree/usr/local/libexec"
  local autostart="$tree/etc/xdg/autostart"
  mkdir -p "$bin" "$libexec" "$autostart"

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

STYLE = """
QWidget { background:#080a10; color:#f4effb; font-family:Sans Serif; }
QFrame#card { background:#111520; border:1px solid #34304a; border-radius:12px; }
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
        self.setWindowTitle("MechOS Creator Apps Setup")
        self.resize(1100, 760)
        self.setMinimumSize(900, 620)
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
            "MechOS keeps Creator applications out of the base install. "
            "Choose only what you want now. Anything you skip remains available later in Creator Mode."
        )
        subtitle.setObjectName("muted")
        subtitle.setWordWrap(True)
        outer.addWidget(subtitle)

        note = QLabel(
            "Core MechOS gaming components remain installed separately. "
            "Large vendor/store apps such as Unreal Engine, VRChat tooling and Substance 3D Painter stay in the Creator Store for vendor-managed setup."
        )
        note.setObjectName("purple")
        note.setWordWrap(True)
        outer.addWidget(note)

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
            grid.addWidget(card, i // 3, i % 3)

        scroll.setWidget(content)
        outer.addWidget(scroll, 1)

        buttons = QHBoxLayout()
        buttons.addStretch(1)
        skip = QPushButton("Skip — Install Later")
        skip.clicked.connect(self.skip)
        buttons.addWidget(skip)
        install = QPushButton("Install Selected Apps")
        install.clicked.connect(self.install)
        buttons.addWidget(install)
        outer.addLayout(buttons)

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
            "Skip app installation for now? You can install everything later from Creator Mode.",
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
Comment=Choose optional Creator applications after MechOS installation
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
grep -Fq 'MECHOS_CREATOR_POSTINSTALL_GATE' "$ROOT/usr/local/bin/mechos-gaming-shell" || fail "MechScope startup gate is missing"
for pkg in "${OPTIONAL_CREATOR_PACKAGES[@]}"; do
  ! grep -qx "$pkg" "$PACKAGES" || fail "Creator app still preloaded in core ISO: $pkg"
done

log "Creator Mode is catalog-first: workstation apps are opt-in during post-install setup and remain installable later"
