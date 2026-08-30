#!/usr/bin/env bash
set -euxo pipefail

pacman -Syu --noconfirm
pacman -S --noconfirm archiso git rsync sed grep coreutils findutils

rm -rf /workspace/archlive /workspace/work
cp -a /usr/share/archiso/configs/releng /workspace/archlive

# Steam and Windows-game support need multilib.
sed -i "/^\#\[multilib\]/,/^\#Include = \/etc\/pacman.d\/mirrorlist/ s/^\#//" \
  /workspace/archlive/pacman.conf

# Gaming, desktop, GPU, VR and Creator Mode packages.
cat >> /workspace/archlive/packages.x86_64 << "PKGS"
plasma-meta
plymouth-kcm
plymouth
sddm
konsole
dolphin
ark
kate
kdialog
firefox
networkmanager
network-manager-applet
bluez
bluez-utils
pipewire
pipewire-alsa
pipewire-pulse
wireplumber
xdg-desktop-portal
xdg-desktop-portal-kde
steam
gamescope
lutris
gamemode
lib32-gamemode
mangohud
lib32-mangohud
wine
wine-mono
wine-gecko
winetricks
protontricks
vulkan-tools
mesa
lib32-mesa
vulkan-radeon
lib32-vulkan-radeon
vulkan-intel
lib32-vulkan-intel
nvidia-open
nvidia-utils
lib32-nvidia-utils
linux
linux-headers
linux-firmware
linux-firmware-whence
ntfs-3g
exfatprogs
btrfs-progs
dosfstools
e2fsprogs
f2fs-tools
xfsprogs
openssh
git
git-lfs
curl
wget
unzip
zip
p7zip
sudo
flatpak
base-devel
cmake
ninja
clang
python
python-pip
python-pygame
python-pyqt6
ffmpeg
blender
obs-studio
kdenlive
krita
zram-generator
power-profiles-daemon
irqbalance
cpupower
amd-ucode
intel-ucode
switcheroo-control
nvidia-prime
smartmontools
nvme-cli
btop
libva-utils
pciutils
usbutils
gpu-screen-recorder
gpu-screen-recorder-ui
intel-media-driver
libva-mesa-driver
PKGS

# Reuse all existing MechOS branding, wallpapers, MechScope files and tools.
if [ -d /workspace/overlay/rootfs ]; then
  rsync -aHAX --numeric-ids /workspace/overlay/rootfs/ /workspace/archlive/airootfs/
fi

# ---------- GUARANTEED CREATOR MODE ----------
mkdir -p /workspace/archlive/airootfs/usr/local/bin
mkdir -p /workspace/archlive/airootfs/usr/share/applications
mkdir -p /workspace/archlive/airootfs/usr/share/wayland-sessions
mkdir -p /workspace/archlive/airootfs/etc/skel/Desktop
mkdir -p /workspace/archlive/airootfs/home/mechos/Desktop

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-creator-mode << "PYEOF"
#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys
from pathlib import Path

from PyQt6.QtCore import Qt, QTimer
from PyQt6.QtGui import QPixmap
from PyQt6.QtWidgets import (
    QApplication, QFrame, QGridLayout, QHBoxLayout, QLabel,
    QMainWindow, QMessageBox, QPushButton, QScrollArea,
    QStackedWidget, QVBoxLayout, QWidget
)

BRAND = "/usr/share/mechos/branding/mechos-logo.png"

def spawn(args):
    try:
        subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        QMessageBox.warning(None, "MechOS Creator Mode", str(e))

def command(name):
    return shutil.which(name)

def open_url(url):
    spawn(["xdg-open", url])

def launch(name, args=None, missing=None):
    exe = command(name)
    if exe:
        spawn([exe] + (args or []))
    else:
        QMessageBox.information(
            None, "MechOS Creator Mode",
            missing or f"{name} is not installed in this image."
        )

def memory_text():
    try:
        info = {}
        with open("/proc/meminfo", "r", encoding="utf-8") as f:
            for line in f:
                k, v = line.split(":", 1)
                info[k] = int(v.strip().split()[0])
        total = info.get("MemTotal", 0) / 1024 / 1024
        avail = info.get("MemAvailable", 0) / 1024 / 1024
        used = max(total - avail, 0)
        return f"{used:.1f} / {total:.1f} GiB"
    except Exception:
        return "Unavailable"

def gpu_text():
    try:
        out = subprocess.check_output(
            ["lspci"], text=True, stderr=subprocess.DEVNULL
        )
        rows = [x.split(":", 2)[-1].strip() for x in out.splitlines()
                if "VGA compatible controller" in x or "3D controller" in x]
        return rows[0][:52] if rows else "Virtual / unknown GPU"
    except Exception:
        return "Virtual / unknown GPU"

class CreatorWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MechOS Creator Mode")
        self.resize(1500, 900)
        self.setMinimumSize(1050, 650)
        self.setStyleSheet("""
            QMainWindow, QWidget { background:#0a0710; color:#f7f2ff; }
            QFrame#sidebar { background:#110b19; border-right:1px solid #2d1b3c; }
            QLabel#brand { font-size:28px; font-weight:800; color:#d7a5ff; }
            QLabel#mode { font-size:12px; color:#8f79a5; letter-spacing:2px; }
            QLabel#heading { font-size:34px; font-weight:800; color:#ffffff; }
            QLabel#subheading { font-size:15px; color:#a99bb7; }
            QLabel#section { font-size:19px; font-weight:700; color:#dfc6f7; }
            QLabel#metric { font-size:13px; color:#bcaec8; }
            QPushButton#nav {
                background:transparent; border:0; text-align:left;
                padding:13px 18px; border-radius:10px; font-size:15px;
                color:#c8bdd3;
            }
            QPushButton#nav:hover, QPushButton#nav:checked {
                background:#241331; color:#ffffff;
            }
            QPushButton#card {
                background:#17101f; border:1px solid #38214c;
                border-radius:15px; padding:20px; text-align:left;
                min-height:78px; font-size:17px; font-weight:650;
            }
            QPushButton#card:hover {
                background:#2a1638; border:1px solid #b46cff;
            }
            QPushButton#modebtn {
                background:#241331; border:1px solid #5e347d;
                border-radius:10px; padding:10px 15px; font-weight:650;
            }
            QPushButton#modebtn:hover { background:#3a1d4f; }
            QFrame#panel {
                background:#120d18; border:1px solid #2b1b38;
                border-radius:15px;
            }
            QScrollArea { border:0; }
        """)

        root = QWidget()
        self.setCentralWidget(root)
        layout = QHBoxLayout(root)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        sidebar = QFrame()
        sidebar.setObjectName("sidebar")
        sidebar.setFixedWidth(230)
        side = QVBoxLayout(sidebar)
        side.setContentsMargins(22, 28, 22, 22)

        if Path(BRAND).exists():
            logo = QLabel()
            pm = QPixmap(BRAND).scaled(
                180, 72, Qt.AspectRatioMode.KeepAspectRatio,
                Qt.TransformationMode.SmoothTransformation
            )
            logo.setPixmap(pm)
            side.addWidget(logo)

        brand = QLabel("CREATOR MODE")
        brand.setObjectName("brand")
        side.addWidget(brand)
        mode = QLabel("MECHOS WORKSPACE")
        mode.setObjectName("mode")
        side.addWidget(mode)
        side.addSpacing(24)

        self.stack = QStackedWidget()
        nav_names = [
            ("Dashboard", self.make_dashboard),
            ("Projects", self.make_projects),
            ("Engines", self.make_engines),
            ("Tools", self.make_tools),
            ("Assets", self.make_assets),
            ("MechClip AI", self.make_mechclip),
            ("Learn", self.make_learn),
            ("Settings", self.make_settings),
        ]
        self.nav = []
        for i, (name, fn) in enumerate(nav_names):
            b = QPushButton(name)
            b.setObjectName("nav")
            b.setCheckable(True)
            b.clicked.connect(lambda checked=False, idx=i: self.select(idx))
            side.addWidget(b)
            self.nav.append(b)
            self.stack.addWidget(fn())

        side.addStretch(1)
        back = QPushButton("← Return to MechScope")
        back.setObjectName("modebtn")
        back.clicked.connect(self.return_to_mechscope)
        side.addWidget(back)

        desktop = QPushButton("Desktop Mode")
        desktop.setObjectName("modebtn")
        desktop.clicked.connect(self.desktop_mode)
        side.addWidget(desktop)

        layout.addWidget(sidebar)
        layout.addWidget(self.stack, 1)
        self.select(0)

    def select(self, idx):
        self.stack.setCurrentIndex(idx)
        for i, b in enumerate(self.nav):
            b.setChecked(i == idx)

    def page(self, title, subtitle):
        page = QWidget()
        v = QVBoxLayout(page)
        v.setContentsMargins(42, 34, 42, 38)
        h = QLabel(title); h.setObjectName("heading"); v.addWidget(h)
        s = QLabel(subtitle); s.setObjectName("subheading"); v.addWidget(s)
        v.addSpacing(20)
        return page, v

    def section(self, v, title):
        l = QLabel(title); l.setObjectName("section"); v.addWidget(l)

    def card_grid(self, items, columns=4):
        w = QWidget()
        g = QGridLayout(w)
        g.setContentsMargins(0, 0, 0, 0)
        g.setSpacing(14)
        for i, (label, fn) in enumerate(items):
            b = QPushButton(label)
            b.setObjectName("card")
            b.clicked.connect(fn)
            g.addWidget(b, i // columns, i % columns)
        return w

    def make_dashboard(self):
        page, v = self.page(
            "Creator Dashboard",
            "Build worlds, avatars, games, videos and stream content from one workspace."
        )
        self.section(v, "Quick Launch")
        v.addWidget(self.card_grid([
            ("Blender\n3D / Avatars", lambda: launch("blender")),
            ("OBS Studio\nRecord / Stream", lambda: launch("obs")),
            ("Kdenlive\nVideo Editing", lambda: launch("kdenlive")),
            ("Krita\nTextures / Art", lambda: launch("krita")),
            ("Unity Hub\nSetup", lambda: open_url("https://unity.com/download")),
            ("Unreal Engine\nLinux Setup", lambda: open_url("https://www.unrealengine.com/linux")),
            ("VRChat Creator\nSetup", lambda: open_url("https://vcc.docs.vrchat.com/")),
            ("MechClip AI\nClip Workflow", self.open_mechclip),
            ("Performance Center\nGPU / CPU / Power", lambda: spawn(["/usr/local/bin/mechos-performance-center"])),
        ]))
        v.addSpacing(18)
        self.section(v, "System")
        panel = QFrame(); panel.setObjectName("panel")
        ph = QHBoxLayout(panel)
        for name, value in [
            ("CPU", f"{os.cpu_count() or '?'} threads"),
            ("Memory", memory_text()),
            ("GPU", gpu_text()),
            ("Mode", "Creator"),
        ]:
            box = QVBoxLayout()
            a = QLabel(name); a.setObjectName("metric")
            b = QLabel(value); b.setWordWrap(True)
            box.addWidget(a); box.addWidget(b)
            ph.addLayout(box, 1)
        v.addWidget(panel)
        v.addStretch(1)
        return page

    def make_projects(self):
        page, v = self.page("Projects", "Open or organize your creator projects.")
        items = [
            ("Project Files", lambda: spawn(["dolphin", str(Path.home())])),
            ("Blender Projects", lambda: spawn(["dolphin", str(Path.home())])),
            ("Open Terminal", lambda: launch("konsole")),
            ("Git Tools", lambda: launch("konsole", ["-e", "bash", "-lc", "git --version; exec bash"])),
        ]
        v.addWidget(self.card_grid(items, 2)); v.addStretch(1); return page

    def make_engines(self):
        page, v = self.page("Engines", "Game and VR creator workflows.")
        v.addWidget(self.card_grid([
            ("Unity Hub\nDownload / Setup", lambda: open_url("https://unity.com/download")),
            ("Unreal Engine\nLinux Setup", lambda: open_url("https://www.unrealengine.com/linux")),
            ("VRChat Creator\nDocumentation", lambda: open_url("https://vcc.docs.vrchat.com/")),
            ("Wine / Lutris\nCompatibility", lambda: launch("lutris")),
        ], 2)); v.addStretch(1); return page

    def make_tools(self):
        page, v = self.page("Tools", "Installed production applications.")
        v.addWidget(self.card_grid([
            ("Blender", lambda: launch("blender")),
            ("OBS Studio", lambda: launch("obs")),
            ("Kdenlive", lambda: launch("kdenlive")),
            ("Krita", lambda: launch("krita")),
            ("Terminal", lambda: launch("konsole")),
            ("Files", lambda: launch("dolphin")),
            ("System Monitor", lambda: launch("konsole", ["-e", "btop"])),
            ("Settings", lambda: launch("systemsettings")),
        ])); v.addStretch(1); return page

    def make_assets(self):
        page, v = self.page("Assets", "Textures, models and project files.")
        v.addWidget(self.card_grid([
            ("Open Home Assets", lambda: spawn(["dolphin", str(Path.home())])),
            ("Krita Textures", lambda: launch("krita")),
            ("Blender Assets", lambda: launch("blender")),
            ("Archive Manager", lambda: launch("ark")),
        ], 2)); v.addStretch(1); return page

    def make_mechclip(self):
        page, v = self.page("MechClip AI", "Recording and editing entry point.")
        v.addWidget(self.card_grid([
            ("Launch MechClip", self.open_mechclip),
            ("OBS Studio", lambda: launch("obs")),
            ("Kdenlive", lambda: launch("kdenlive")),
            ("Recordings Folder", lambda: spawn(["dolphin", str(Path.home() / "Videos")])),
        ], 2)); v.addStretch(1); return page

    def make_learn(self):
        page, v = self.page("Learn", "Official setup and creator documentation.")
        v.addWidget(self.card_grid([
            ("Blender Manual", lambda: open_url("https://docs.blender.org/manual/en/latest/")),
            ("Unity Manual", lambda: open_url("https://docs.unity3d.com/")),
            ("Unreal Docs", lambda: open_url("https://dev.epicgames.com/documentation/")),
            ("VRChat Creator Docs", lambda: open_url("https://creators.vrchat.com/")),
        ], 2)); v.addStretch(1); return page

    def make_settings(self):
        page, v = self.page("Settings", "MechOS and creator workstation controls.")
        v.addWidget(self.card_grid([
            ("System Settings", lambda: launch("systemsettings")),
            ("Display Settings", lambda: launch("systemsettings", ["kcm_kscreen"])),
            ("Audio Settings", lambda: launch("systemsettings", ["kcm_pulseaudio"])),
            ("Network Settings", lambda: launch("systemsettings", ["kcm_networkmanagement"])),
        ], 2)); v.addStretch(1); return page

    def open_mechclip(self):
        for candidate in [
            command("mechclip"),
            "/opt/mechclip/MechClip",
            "/opt/MechClip/MechClip",
        ]:
            if candidate and os.path.exists(candidate):
                spawn([candidate]); return
        QMessageBox.information(
            self, "MechClip AI",
            "MechClip is not installed in a known path yet. "
            "Creator Mode is ready to launch it when the app is added."
        )

    def return_to_mechscope(self):
        spawn(["/usr/local/bin/mechos-return-to-mechscope"])
        QApplication.quit()

    def desktop_mode(self):
        # Creator Mode already runs on Plasma; closing the dashboard
        # leaves a normal Desktop Mode workspace.
        QApplication.quit()

app = QApplication(sys.argv)
app.setApplicationName("MechOS Creator Mode")
w = CreatorWindow()
w.showMaximized()
sys.exit(app.exec())
PYEOF
chmod 755 /workspace/archlive/airootfs/usr/local/bin/mechos-creator-mode

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-creator-session << "EOF"
#!/usr/bin/env bash
export MECHOS_MODE=creator
export XDG_CURRENT_DESKTOP=KDE
(
  sleep 6
  /usr/local/bin/mechos-creator-mode >/dev/null 2>&1 &
) &
exec /usr/bin/startplasma-wayland
EOF
chmod +x /workspace/archlive/airootfs/usr/local/bin/mechos-creator-session

cat > /workspace/archlive/airootfs/usr/share/wayland-sessions/mechos-creator.desktop << "EOF"
[Desktop Entry]
Name=MechOS Creator Mode
Comment=MechOS creator workstation
Exec=/usr/local/bin/mechos-creator-session
Type=Application
DesktopNames=KDE
EOF

cat > /workspace/archlive/airootfs/usr/share/applications/mechos-creator-mode.desktop << "EOF"
[Desktop Entry]
Type=Application
Name=MechOS Creator Mode
Comment=Open the MechOS creator workstation
Exec=/usr/local/bin/mechos-creator-mode
Icon=applications-graphics
Terminal=false
Categories=Graphics;AudioVideo;Development;
Keywords=MechOS;Creator;Blender;Unity;Unreal;VRChat;MechClip;
EOF

cp /workspace/archlive/airootfs/usr/share/applications/mechos-creator-mode.desktop \
  /workspace/archlive/airootfs/etc/skel/Desktop/Creator-Mode.desktop
cp /workspace/archlive/airootfs/usr/share/applications/mechos-creator-mode.desktop \
  /workspace/archlive/airootfs/home/mechos/Desktop/Creator-Mode.desktop
chmod +x /workspace/archlive/airootfs/etc/skel/Desktop/Creator-Mode.desktop
chmod +x /workspace/archlive/airootfs/home/mechos/Desktop/Creator-Mode.desktop

mkdir -p /workspace/archlive/airootfs/usr/share/doc/mechos
cat > /workspace/archlive/airootfs/usr/share/doc/mechos/CREATOR-MODE.txt << "EOF"
MECHOS CREATOR MODE
===================

Creator Mode is built into this ISO.

Included locally:
- Blender
- OBS Studio
- Kdenlive
- Krita
- FFmpeg
- Git / Git LFS
- CMake / Ninja / Clang
- Python
- Wine / Winetricks
- Lutris
- MechOS Creator dashboard

Large tools are intentionally installed after OS setup:
- Unity Hub / Unity editors
- Unreal Engine
- VRChat Creator Companion compatibility workflow

This keeps the bootable ISO small enough to build and update while preserving a
graphical Creator Mode experience.
EOF

# ---------- MECHOS PERFORMANCE + RELIABILITY LAYER ----------
# ZRAM: compressed swap in RAM to reduce stalls under heavy gaming /
# creator workloads. Cap at 8 GiB so large-memory systems do not
# reserve an excessive amount of addressable compressed swap.
mkdir -p /workspace/archlive/airootfs/etc/systemd
cat > /workspace/archlive/airootfs/etc/systemd/zram-generator.conf << "EOF"
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
swap-priority = 100
EOF

# Safe desktop/gaming VM tuning. These do not force CPU overclocks or
# experimental schedulers.
mkdir -p /workspace/archlive/airootfs/etc/sysctl.d
cat > /workspace/archlive/airootfs/etc/sysctl.d/90-mechos-performance.conf << "EOF"
vm.swappiness=100
vm.vfs_cache_pressure=75
fs.inotify.max_user_watches=1048576
fs.inotify.max_user_instances=1024
EOF

# GameMode defaults: keep the screen awake while gaming and allow a
# modest process-priority improvement without pinning CPU cores.
cat > /workspace/archlive/airootfs/etc/gamemode.ini << "EOF"
[general]
renice=5
softrealtime=auto
inhibit_screensaver=1

[cpu]
park_cores=no
pin_cores=no
EOF

# Enable stable system services using direct systemd wants links.
mkdir -p /workspace/archlive/airootfs/etc/systemd/system/timers.target.wants
mkdir -p /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants

# Weekly SSD/NVMe TRIM.
ln -sf /usr/lib/systemd/system/fstrim.timer \
  /workspace/archlive/airootfs/etc/systemd/system/timers.target.wants/fstrim.timer

# Spread hardware interrupts across available CPU cores.
ln -sf /usr/lib/systemd/system/irqbalance.service \
  /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/irqbalance.service

# KDE power-profile controls and hybrid-GPU discovery.
ln -sf /usr/lib/systemd/system/power-profiles-daemon.service \
  /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/power-profiles-daemon.service
ln -sf /usr/lib/systemd/system/switcheroo-control.service \
  /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/switcheroo-control.service

# Graphical MechOS Performance Center.
cat > /workspace/archlive/airootfs/usr/local/bin/mechos-performance-center << "PYEOF"
#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys

from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import (
    QApplication, QGridLayout, QLabel, QMainWindow,
    QMessageBox, QPushButton, QVBoxLayout, QWidget
)

def run(args):
    try:
        subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        QMessageBox.warning(None, "MechOS Performance Center", str(e))

def output(args):
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return "Unavailable"

def set_profile(profile):
    if not shutil.which("powerprofilesctl"):
        QMessageBox.information(None, "MechOS", "Power profile controls are unavailable on this hardware.")
        return
    result = subprocess.run(
        ["powerprofilesctl", "set", profile],
        text=True, capture_output=True
    )
    if result.returncode == 0:
        QMessageBox.information(None, "MechOS", f"Power profile set to {profile}.")
    else:
        QMessageBox.information(
            None, "MechOS",
            "That power profile is not exposed by this system.\n\n" +
            (result.stderr.strip() or "The hardware/VM may not support it.")
        )

class Perf(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MechOS Performance Center")
        self.resize(980, 650)
        self.setStyleSheet("""
            QMainWindow, QWidget { background:#09060e; color:#f8f2ff; }
            QLabel#title { font-size:32px; font-weight:800; color:#d49cff; }
            QLabel#sub { color:#a697b4; font-size:14px; }
            QLabel#status {
                background:#130d1a; border:1px solid #352044;
                border-radius:14px; padding:18px; color:#d8cde2;
            }
            QPushButton {
                background:#1b1025; border:1px solid #513067;
                border-radius:13px; padding:18px;
                text-align:left; font-size:16px; font-weight:650;
            }
            QPushButton:hover { background:#321844; border-color:#bd78ff; }
        """)

        root = QWidget()
        self.setCentralWidget(root)
        v = QVBoxLayout(root)
        v.setContentsMargins(34, 30, 34, 30)

        title = QLabel("MECHOS PERFORMANCE CENTER")
        title.setObjectName("title")
        v.addWidget(title)
        sub = QLabel("Gaming performance, power, GPU, recording and system health")
        sub.setObjectName("sub")
        v.addWidget(sub)

        profile = output(["powerprofilesctl", "get"]) if shutil.which("powerprofilesctl") else "Unavailable"
        gpu = output(["sh", "-lc", "lspci | grep -Ei 'VGA|3D|Display' | head -n 2"])
        zram = output(["sh", "-lc", "zramctl --noheadings 2>/dev/null | head -n 1 || true"])
        if not zram:
            zram = "Activates automatically when supported"

        status = QLabel(
            f"Power profile: {profile}\n"
            f"GPU: {gpu}\n"
            f"ZRAM: {zram}\n"
            "SSD TRIM: weekly  •  IRQ balancing: enabled"
        )
        status.setWordWrap(True)
        status.setObjectName("status")
        v.addWidget(status)

        grid = QGridLayout()
        grid.setSpacing(12)
        actions = [
            ("⚡ Gaming Performance", lambda: set_profile("performance")),
            ("◐ Balanced", lambda: set_profile("balanced")),
            ("🔋 Battery Saver", lambda: set_profile("power-saver")),
            ("📊 System Monitor", lambda: run(["konsole", "-e", "btop"])),
            ("🎥 GPU Recorder", lambda: run(["gsr-ui"]) if shutil.which("gsr-ui")
                else QMessageBox.information(self, "MechOS", "GPU Screen Recorder UI is unavailable.")),
            ("🎮 Vulkan / GPU Info", lambda: run([
                "konsole", "-e", "bash", "-lc",
                "vulkaninfo --summary 2>/dev/null; echo; vainfo 2>/dev/null || true; echo; read -rp 'Press Enter...'"
            ])),
            ("💾 Storage Health", lambda: run([
                "konsole", "-e", "bash", "-lc",
                "echo '=== NVMe ==='; nvme list 2>/dev/null || true; "
                "echo; echo '=== SMART-capable drives ==='; "
                "lsblk -d -o NAME,MODEL,SIZE,ROTA,TYPE; "
                "echo; read -rp 'Press Enter...'"
            ])),
            ("🧠 CPU Information", lambda: run([
                "konsole", "-e", "bash", "-lc",
                "lscpu; echo; cpupower frequency-info 2>/dev/null || true; "
                "echo; read -rp 'Press Enter...'"
            ])),
        ]
        for i, (label, cb) in enumerate(actions):
            b = QPushButton(label)
            b.clicked.connect(cb)
            grid.addWidget(b, i // 2, i % 2)

        v.addLayout(grid)
        v.addStretch(1)

app = QApplication(sys.argv)
w = Perf()
w.show()
sys.exit(app.exec())
PYEOF
chmod 755 /workspace/archlive/airootfs/usr/local/bin/mechos-performance-center

cat > /workspace/archlive/airootfs/usr/share/applications/mechos-performance-center.desktop << "EOF"
[Desktop Entry]
Type=Application
Name=MechOS Performance Center
Comment=Gaming, GPU, recording, power and health controls
Exec=/usr/local/bin/mechos-performance-center
Icon=utilities-system-monitor
Terminal=false
Categories=System;Settings;Game;
Keywords=MechOS;Performance;Gaming;GPU;ZRAM;Power;Recorder;
EOF

# ---------- MECHOS GRAPHICAL BOOT + BRANDING ----------
mkdir -p /workspace/archlive/airootfs/usr/share/mechos/branding
mkdir -p /workspace/archlive/airootfs/usr/share/plymouth/themes/mechos
mkdir -p /workspace/archlive/airootfs/etc/plymouth

base64 -d > /workspace/archlive/airootfs/usr/share/mechos/branding/mechos-logo.png << "B64EOF"
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
B64EOF

cp /workspace/archlive/airootfs/usr/share/mechos/branding/mechos-logo.png \
  /workspace/archlive/airootfs/usr/share/plymouth/themes/mechos/mechos-logo.png

cat > /workspace/archlive/airootfs/usr/share/plymouth/themes/mechos/mechos.plymouth << "EOF"
[Plymouth Theme]
Name=MechOS
Description=MechOS graphical boot intro
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/mechos
ScriptFile=/usr/share/plymouth/themes/mechos/mechos.script
EOF

cat > /workspace/archlive/airootfs/usr/share/plymouth/themes/mechos/mechos.script << "EOF"
Window.SetBackgroundTopColor(0.025, 0.012, 0.045);
Window.SetBackgroundBottomColor(0.080, 0.018, 0.120);

logo.image = Image("mechos-logo.png");
logo.sprite = Sprite(logo.image);
logo.sprite.SetX(Window.GetWidth() / 2 - logo.image.GetWidth() / 2);
logo.sprite.SetY(Window.GetHeight() / 2 - logo.image.GetHeight() / 2 - 30);

bar_bg.image = Image.Text("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", 0.22, 0.12, 0.30);
bar_bg.sprite = Sprite(bar_bg.image);
bar_bg.sprite.SetX(Window.GetWidth() / 2 - bar_bg.image.GetWidth() / 2);
bar_bg.sprite.SetY(Window.GetHeight() / 2 + 170);

status.image = Image.Text("Starting MechScope", 0.75, 0.55, 0.95);
status.sprite = Sprite(status.image);
status.sprite.SetX(Window.GetWidth() / 2 - status.image.GetWidth() / 2);
status.sprite.SetY(Window.GetHeight() / 2 + 210);

fun refresh_callback () {
    progress = Plymouth.GetBootProgress();
    opacity = 0.55 + (progress * 0.45);
    logo.sprite.SetOpacity(opacity);
}
Plymouth.SetRefreshFunction(refresh_callback);
EOF

cat > /workspace/archlive/airootfs/etc/plymouth/plymouthd.conf << "EOF"
[Daemon]
Theme=mechos
ShowDelay=0
DeviceTimeout=8
EOF

# Add Plymouth to whichever ArchISO mkinitcpio config owns HOOKS.
while IFS= read -r cfg; do
  if grep -q '^HOOKS=' "$cfg"; then
    if ! grep -q 'plymouth' "$cfg"; then
      if grep -q ' systemd ' "$cfg"; then
        sed -i -E 's/( systemd)( )/\1 plymouth\2/' "$cfg"
      elif grep -q ' udev ' "$cfg"; then
        sed -i -E 's/( udev)( )/\1 plymouth\2/' "$cfg"
      fi
    fi
  fi
done < <(find /workspace/archlive/airootfs/etc -type f -name '*.conf' 2>/dev/null)

# Quiet graphical boot. systemd will still surface real failures.
for cfg in $(find /workspace/archlive/efiboot /workspace/archlive/syslinux \
    -type f \( -name '*.conf' -o -name '*.cfg' \) 2>/dev/null); do
  if grep -q 'archisobasedir=' "$cfg"; then
    sed -i -E '/^[[:space:]]*(options|APPEND)[[:space:]]/ {
      /(^|[[:space:]])splash([[:space:]]|$)/! s/$/ quiet splash loglevel=3 rd.systemd.show_status=auto vt.global_cursor_default=0/
    }' "$cfg"
  fi
done

# Brand the boot menu text without changing the boot logic.
find /workspace/archlive/efiboot /workspace/archlive/syslinux \
  -type f \( -name '*.conf' -o -name '*.cfg' \) -print0 2>/dev/null | \
  xargs -0 -r sed -i \
    -e 's/Arch Linux install medium/MechOS Gaming System/g' \
    -e 's/Arch Linux/MechOS/g'

# Let Plasma use the same logo where a distro logo is requested.
mkdir -p /workspace/archlive/airootfs/usr/share/pixmaps
cp /workspace/archlive/airootfs/usr/share/mechos/branding/mechos-logo.png \
  /workspace/archlive/airootfs/usr/share/pixmaps/mechos.png

# ---------- MECHSCOPE BUILT-IN MODE SWITCHER ----------
# MechScope is the Gaming Mode shell. It owns the Steam launcher and
# mode switching so Desktop/Creator switching is part of MechScope,
# not a separate desktop-only utility.
cat > /workspace/archlive/airootfs/usr/local/bin/mechscope << "PYEOF"
#!/usr/bin/env python3
import os
import subprocess
import sys

from PyQt6.QtCore import Qt, QTimer
from PyQt6.QtGui import QFont, QKeyEvent
from PyQt6.QtWidgets import (
    QApplication, QLabel, QMainWindow, QPushButton,
    QVBoxLayout, QHBoxLayout, QWidget
)

try:
    import pygame
    HAVE_PYGAME = True
except Exception:
    HAVE_PYGAME = False

MODE_FILE = f"/tmp/mechos-next-mode-{os.getuid()}"
FALLBACK = os.environ.get("MECHOS_GAMING_FALLBACK") == "1"

def write_mode(mode):
    try:
        with open(MODE_FILE, "w", encoding="utf-8") as f:
            f.write(mode + "\n")
    except Exception:
        pass

class MechScope(QMainWindow):
    def __init__(self):
        super().__init__()
        self.steam = None
        self.buttons = []
        self.index = 0
        self.setWindowTitle("MechScope")
        self.setWindowFlag(Qt.WindowType.FramelessWindowHint, True)
        self.setStyleSheet("""
            QMainWindow, QWidget {
                background-color: #0c0715;
                color: white;
            }
            QLabel#title {
                color: #c78cff;
                font-size: 42px;
                font-weight: 800;
            }
            QLabel#subtitle {
                color: #b8b2c8;
                font-size: 16px;
            }
            QPushButton {
                background-color: #21152f;
                border: 2px solid #4a3268;
                border-radius: 16px;
                padding: 18px 24px;
                text-align: left;
                color: white;
                font-size: 22px;
                font-weight: 650;
            }
            QPushButton:focus {
                background-color: #44245f;
                border: 3px solid #cc8cff;
            }
            QPushButton:hover {
                background-color: #352047;
            }
            QLabel#hint {
                color: #8d849d;
                font-size: 14px;
            }
        """)

        root = QWidget()
        self.setCentralWidget(root)
        outer = QVBoxLayout(root)
        outer.setContentsMargins(70, 55, 70, 45)
        outer.setSpacing(16)

        title = QLabel("MECHSCOPE")
        title.setObjectName("title")
        outer.addWidget(title)

        subtitle = QLabel("MechOS Gaming Shell  •  Library  •  Modes  •  Power")
        subtitle.setObjectName("subtitle")
        outer.addWidget(subtitle)
        outer.addSpacing(22)

        self.add_button("🎮  Steam Library", self.open_steam)
        self.add_button("🖥  Desktop Mode", lambda: self.switch_mode("desktop"))
        self.add_button("🛠  Creator Mode", lambda: self.switch_mode("creator"))
        self.add_button("⚡  Performance Center", self.open_performance)
        self.add_button("↻  Restart MechOS", self.reboot)
        self.add_button("⏻  Shut Down", self.poweroff)

        outer.addStretch(1)
        hint = QLabel("Keyboard: ↑ ↓ / Enter     Controller: D-pad / A")
        hint.setObjectName("hint")
        outer.addWidget(hint)

        self.buttons[0].setFocus()

        self.gamepad = None
        if HAVE_PYGAME:
            try:
                pygame.init()
                pygame.joystick.init()
                if pygame.joystick.get_count() > 0:
                    self.gamepad = pygame.joystick.Joystick(0)
                    self.gamepad.init()
            except Exception:
                self.gamepad = None

        self.timer = QTimer(self)
        self.timer.timeout.connect(self.poll)
        self.timer.start(60)

    def add_button(self, label, callback):
        b = QPushButton(label)
        b.clicked.connect(callback)
        self.centralWidget().layout().addWidget(b)
        self.buttons.append(b)

    def move_focus(self, delta):
        self.index = (self.index + delta) % len(self.buttons)
        self.buttons[self.index].setFocus()

    def keyPressEvent(self, event: QKeyEvent):
        if event.key() in (Qt.Key.Key_Down, Qt.Key.Key_S):
            self.move_focus(1)
        elif event.key() in (Qt.Key.Key_Up, Qt.Key.Key_W):
            self.move_focus(-1)
        elif event.key() in (Qt.Key.Key_Return, Qt.Key.Key_Enter, Qt.Key.Key_Space):
            self.buttons[self.index].click()
        elif event.key() == Qt.Key.Key_Escape:
            self.open_steam()
        else:
            super().keyPressEvent(event)

    def poll(self):
        if self.steam is not None and self.steam.poll() is not None:
            self.steam = None
            self.showFullScreen()
            self.raise_()
            self.activateWindow()

        if not self.gamepad or not HAVE_PYGAME:
            return

        try:
            for ev in pygame.event.get():
                if ev.type == pygame.JOYHATMOTION:
                    if ev.value[1] > 0:
                        self.move_focus(-1)
                    elif ev.value[1] < 0:
                        self.move_focus(1)
                elif ev.type == pygame.JOYBUTTONDOWN:
                    # Common SDL mapping: A=0, B=1
                    if ev.button == 0:
                        self.buttons[self.index].click()
                    elif ev.button == 1:
                        self.open_steam()
        except Exception:
            pass

    def open_steam(self):
        if self.steam is not None:
            return
        try:
            self.hide()
            self.steam = subprocess.Popen(["steam", "-gamepadui"])
        except Exception:
            self.steam = None
            self.showFullScreen()

    def open_performance(self):
        subprocess.Popen(["/usr/local/bin/mechos-performance-center"])

    def switch_mode(self, mode):
        if FALLBACK:
            # In a VM fallback Plasma session, Desktop Mode means just
            # close MechScope; Creator Mode opens the creator dashboard.
            if mode == "creator":
                subprocess.Popen(["/usr/local/bin/mechos-creator-mode"])
            self.close()
            return

        write_mode(mode)
        QApplication.quit()

    def reboot(self):
        subprocess.Popen(["sudo", "-n", "systemctl", "reboot"])

    def poweroff(self):
        subprocess.Popen(["sudo", "-n", "systemctl", "poweroff"])

app = QApplication(sys.argv)
app.setApplicationName("MechScope")
window = MechScope()
window.showFullScreen()
sys.exit(app.exec())
PYEOF
chmod 755 /workspace/archlive/airootfs/usr/local/bin/mechscope

# Handy launcher when testing from KDE/VirtualBox.
cat > /workspace/archlive/airootfs/usr/share/applications/mechscope.desktop << "EOF"
[Desktop Entry]
Type=Application
Name=MechScope
Comment=MechOS gaming shell and mode switcher
Exec=/usr/local/bin/mechscope
Icon=applications-games
Terminal=false
Categories=Game;System;
Keywords=MechOS;MechScope;Gaming;Steam;Desktop;Creator;
EOF

# Desktop/Creator sessions can always return to the default MechScope
# Gaming session by restarting SDDM.
cat > /workspace/archlive/airootfs/usr/local/bin/mechos-return-to-mechscope << "EOF"
#!/usr/bin/env bash
exec sudo -n systemctl restart sddm
EOF
chmod 755 /workspace/archlive/airootfs/usr/local/bin/mechos-return-to-mechscope

cat > /workspace/archlive/airootfs/usr/share/applications/mechos-return-to-mechscope.desktop << "EOF"
[Desktop Entry]
Type=Application
Name=Return to MechScope
Comment=Return to MechOS Gaming Mode
Exec=/usr/local/bin/mechos-return-to-mechscope
Icon=applications-games
Terminal=false
Categories=Game;System;
EOF

cp /workspace/archlive/airootfs/usr/share/applications/mechos-return-to-mechscope.desktop \
  /workspace/archlive/airootfs/etc/skel/Desktop/Return-to-MechScope.desktop
cp /workspace/archlive/airootfs/usr/share/applications/mechos-return-to-mechscope.desktop \
  /workspace/archlive/airootfs/home/mechos/Desktop/Return-to-MechScope.desktop
chmod 755 /workspace/archlive/airootfs/etc/skel/Desktop/Return-to-MechScope.desktop
chmod 755 /workspace/archlive/airootfs/home/mechos/Desktop/Return-to-MechScope.desktop

# ---------- MECHOS GAMING MODE ----------
# Gaming Mode is the default session. If Gamescope/Vulkan cannot start
# (common in some virtual machines), fall back to KDE Plasma instead
# of leaving the user at a black screen.
cat > /workspace/archlive/airootfs/usr/local/bin/mechos-gaming-session << "EOF"
#!/usr/bin/env bash
set +e

export MECHOS_MODE=gaming
export STEAM_FORCE_DESKTOPUI_SCALING="${STEAM_FORCE_DESKTOPUI_SCALING:-1.0}"
MODE_FILE="/tmp/mechos-next-mode-$(id -u)"

# Real Gaming Mode: Gamescope hosts MechScope. MechScope launches
# Steam Gamepad UI and writes the requested mode when switching.
if command -v gamescope >/dev/null 2>&1 && \
   command -v vulkaninfo >/dev/null 2>&1 && \
   vulkaninfo --summary >/dev/null 2>&1; then
  while true; do
    rm -f "$MODE_FILE"
    gamescope -e -f -- /usr/local/bin/mechscope

    NEXT="$(cat "$MODE_FILE" 2>/dev/null || echo gaming)"
    rm -f "$MODE_FILE"

    case "$NEXT" in
      desktop)
        export MECHOS_MODE=desktop
        exec /usr/bin/startplasma-wayland
        ;;
      creator)
        exec /usr/local/bin/mechos-creator-session
        ;;
      gaming|"")
        # Re-open MechScope if it was closed without choosing a mode.
        continue
        ;;
    esac
  done
fi

# VM / no-Vulkan fallback: enter Plasma but automatically show the
# exact same MechScope switcher so its UI can still be tested.
export MECHOS_GAMING_FALLBACK=1
(
  sleep 5
  /usr/local/bin/mechscope >/dev/null 2>&1 &
) &
exec /usr/bin/startplasma-wayland
EOF
chmod 755 /workspace/archlive/airootfs/usr/local/bin/mechos-gaming-session

mkdir -p /workspace/archlive/airootfs/usr/share/wayland-sessions
cat > /workspace/archlive/airootfs/usr/share/wayland-sessions/mechos-gaming.desktop << "EOF"
[Desktop Entry]
Name=MechOS Gaming Mode
Comment=MechOS Gamescope + Steam Gamepad UI
Exec=/usr/local/bin/mechos-gaming-session
Type=Application
DesktopNames=MechOS;Gamescope;Steam;
EOF

# ---------- ARCH / LIVE DESKTOP DEFAULTS ----------
mkdir -p /workspace/archlive/airootfs/etc/sddm.conf.d
cat > /workspace/archlive/airootfs/etc/sddm.conf.d/mechos.conf << "EOF"
[Autologin]
User=mechos
Session=mechos-gaming.desktop
Relogin=true
EOF

mkdir -p /workspace/archlive/airootfs/etc/systemd/system/getty@tty1.service.d
cat > /workspace/archlive/airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf << "EOF"
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin mechos --noclear %I $TERM
EOF

# Create the live user through systemd-sysusers instead of
# manually editing passwd/group/shadow. This avoids the boot-time
# systemd-sysusers failure seen in the Alpha VM.
mkdir -p /workspace/archlive/airootfs/usr/lib/sysusers.d
cat > /workspace/archlive/airootfs/usr/lib/sysusers.d/mechos.conf << "EOF"
u mechos 1000 "MechOS Live User" /home/mechos /bin/bash
m mechos wheel
EOF

mkdir -p /workspace/archlive/airootfs/usr/lib/tmpfiles.d
cat > /workspace/archlive/airootfs/usr/lib/tmpfiles.d/mechos.conf << "EOF"
d /home/mechos 0755 mechos mechos -
EOF

# Passwordless sudo is for the temporary LIVE tester account only.
# A future installed-system installer should create a normal user
# password and use normal sudo authentication.
mkdir -p /workspace/archlive/airootfs/etc/sudoers.d
cat > /workspace/archlive/airootfs/etc/sudoers.d/10-mechos-live << "EOF"
mechos ALL=(ALL:ALL) NOPASSWD: ALL
EOF

mkdir -p /workspace/archlive/airootfs/home/mechos
chown -R 1000:1000 /workspace/archlive/airootfs/home/mechos

ln -sf /usr/lib/systemd/system/graphical.target \
  /workspace/archlive/airootfs/etc/systemd/system/default.target

mkdir -p /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants

# Use NetworkManager as the single network manager. The stock releng
# profile enables systemd-networkd; running both caused the boot
# failures seen in VirtualBox.
rm -f \
  /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/systemd-networkd.service \
  /workspace/archlive/airootfs/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service \
  /workspace/archlive/airootfs/etc/systemd/system/dbus-org.freedesktop.network1.service \
  || true

ln -sf /dev/null \
  /workspace/archlive/airootfs/etc/systemd/system/systemd-networkd.service
ln -sf /dev/null \
  /workspace/archlive/airootfs/etc/systemd/system/systemd-networkd-wait-online.service

ln -sf /usr/lib/systemd/system/NetworkManager.service \
  /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service

# Keep systemd-resolved for DNS, but do not let time synchronization
# block the graphical boot if the VM/PC has no network yet.
mkdir -p /workspace/archlive/airootfs/etc/systemd/system/sysinit.target.wants
ln -sf /usr/lib/systemd/system/systemd-resolved.service \
  /workspace/archlive/airootfs/etc/systemd/system/sysinit.target.wants/systemd-resolved.service
ln -sf /run/systemd/resolve/stub-resolv.conf \
  /workspace/archlive/airootfs/etc/resolv.conf
ln -sf /dev/null \
  /workspace/archlive/airootfs/etc/systemd/system/systemd-time-wait-sync.service

ln -sf /usr/lib/systemd/system/bluetooth.service \
  /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/bluetooth.service
ln -sf /usr/lib/systemd/system/sddm.service \
  /workspace/archlive/airootfs/etc/systemd/system/display-manager.service

sed -i "s/^iso_name=.*/iso_name=\"mechos\"/" /workspace/archlive/profiledef.sh
sed -i "s/^iso_label=.*/iso_label=\"MECHOS_$(date +%Y%m)\"/" /workspace/archlive/profiledef.sh
sed -i "s/^iso_publisher=.*/iso_publisher=\"MechOS\"/" /workspace/archlive/profiledef.sh
sed -i "s/^iso_application=.*/iso_application=\"MechOS Arch + MechScope + Creator GUI + Performance\"/" /workspace/archlive/profiledef.sh

# ArchISO-authoritative permissions. These prevent launchers from
# losing executable bits inside the final SquashFS image.
cat >> /workspace/archlive/profiledef.sh << "EOF"

file_permissions["/usr/local/bin/mechos-creator-mode"]="0:0:755"
file_permissions["/usr/local/bin/mechos-creator-session"]="0:0:755"
file_permissions["/usr/local/bin/mechos-gaming-session"]="0:0:755"
file_permissions["/usr/local/bin/mechscope"]="0:0:755"
file_permissions["/usr/local/bin/mechos-return-to-mechscope"]="0:0:755"
file_permissions["/usr/local/bin/mechos-performance-center"]="0:0:755"
file_permissions["/usr/share/mechos/branding/mechos-logo.png"]="0:0:644"
file_permissions["/etc/sudoers.d/10-mechos-live"]="0:0:440"
EOF

# Final sanity check before mkarchiso.
chmod 755 \
  /workspace/archlive/airootfs/usr/local/bin/mechos-creator-mode \
  /workspace/archlive/airootfs/usr/local/bin/mechos-creator-session \
  /workspace/archlive/airootfs/usr/local/bin/mechos-gaming-session \
  /workspace/archlive/airootfs/usr/local/bin/mechscope \
  /workspace/archlive/airootfs/usr/local/bin/mechos-return-to-mechscope \
  /workspace/archlive/airootfs/usr/local/bin/mechos-performance-center
chmod 440 /workspace/archlive/airootfs/etc/sudoers.d/10-mechos-live

echo "=== MechOS pre-build validation ==="
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-creator-mode
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-creator-session
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-gaming-session
test -x /workspace/archlive/airootfs/usr/local/bin/mechscope
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-return-to-mechscope
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-performance-center
test -f /workspace/archlive/airootfs/etc/systemd/zram-generator.conf
test -L /workspace/archlive/airootfs/etc/systemd/system/timers.target.wants/fstrim.timer
test -L /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/irqbalance.service
grep -q "Performance Center" /workspace/archlive/airootfs/usr/local/bin/mechscope
grep -q "Steam Library" /workspace/archlive/airootfs/usr/local/bin/mechscope
grep -q "Creator Dashboard" /workspace/archlive/airootfs/usr/local/bin/mechos-creator-mode
test -s /workspace/archlive/airootfs/usr/share/mechos/branding/mechos-logo.png
test -f /workspace/archlive/airootfs/usr/share/plymouth/themes/mechos/mechos.plymouth
grep -Rqs 'plymouth' /workspace/archlive/airootfs/etc/mkinitcpio.conf* /workspace/archlive/airootfs/etc/mkinitcpio.conf.d 2>/dev/null
grep -q "Session=mechos-gaming.desktop" /workspace/archlive/airootfs/etc/sddm.conf.d/mechos.conf
grep -q "mechos ALL=(ALL:ALL) NOPASSWD: ALL" /workspace/archlive/airootfs/etc/sudoers.d/10-mechos-live
grep -q "u mechos 1000" /workspace/archlive/airootfs/usr/lib/sysusers.d/mechos.conf
echo "MechOS boot/admin validation passed."

mkdir -p /workspace/out /workspace/work
mkarchiso -v \
  -w /workspace/work \
  -o /workspace/out \
  /workspace/archlive

ISO="$(find /workspace/out -maxdepth 1 -type f -name "*.iso" | head -n1)"
test -n "$ISO"

FINAL=/workspace/out/MechOS-Arch-Creator-x86_64.iso
mv "$ISO" "$FINAL"

# Write a portable checksum that uses only the ISO filename,
# not the Docker-only /workspace/out path.
(
  cd /workspace/out
  sha256sum MechOS-Arch-Creator-x86_64.iso               > MechOS-Arch-Creator-x86_64.iso.sha256
)

ls -lh /workspace/out
