#!/usr/bin/env bash
set -euxo pipefail

pacman -Syu --noconfirm
pacman -S --noconfirm archiso git rsync sed grep coreutils findutils zstd python

rm -rf /workspace/archlive /workspace/work
cp -a /usr/share/archiso/configs/releng /workspace/archlive

# The rolling releng profile can temporarily reference packages that have
# already left the synchronized repositories. broadcom-wl was removed from the
# repositories but remained in the profile used by the build container, which
# makes pacstrap abort before the MechOS packages are installed. The kernel's
# in-tree Broadcom drivers remain available through linux and linux-firmware.
sed -i '/^broadcom-wl$/d' /workspace/archlive/packages.x86_64

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
archinstall
arch-install-scripts
grub
efibootmgr
os-prober
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
python-evdev
python-websocket-client
brightnessctl
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
pacman-contrib
fakeroot
polkit
snapper
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

mkdir -p /workspace/archlive/airootfs/usr/local/libexec
mkdir -p /workspace/archlive/airootfs/usr/share/mechos/creator-packages

cat > /workspace/archlive/airootfs/usr/share/mechos/creator-packages/streamer.json << "EOF"
{
  "id": "streamer",
  "name": "Streamer Package",
  "description": "Streaming, recording, editing and creator communication tools.",
  "disk_space": "Approximately 4 GB",
  "native": ["obs", "kdenlive", "audacity"],
  "flatpak": ["discord"]
}
EOF

cat > /workspace/archlive/airootfs/usr/share/mechos/creator-packages/graphics.json << "EOF"
{
  "id": "graphics",
  "name": "Graphics Creator",
  "description": "3D modeling, texturing and digital artwork tools.",
  "disk_space": "Approximately 5 GB",
  "native": ["blender", "krita"],
  "flatpak": []
}
EOF

cat > /workspace/archlive/airootfs/usr/share/mechos/creator-packages/game-dev.json << "EOF"
{
  "id": "game-dev",
  "name": "Game Developer",
  "description": "Open-source engine, 3D tools, editor and Git client.",
  "disk_space": "Approximately 7 GB plus downloaded engines",
  "native": ["godot", "blender"],
  "flatpak": ["vscode", "gitkraken", "unityhub"]
}
EOF

cat > /workspace/archlive/airootfs/usr/share/mechos/creator-packages/windows-apps.json << "EOF"
{
  "id": "windows-apps",
  "name": "Windows Apps & Bottles",
  "description": "Run supported Windows applications through Bottles, Wine and Proton compatibility tools.",
  "disk_space": "Approximately 3 GB",
  "native": ["wine", "winetricks", "protontricks"],
  "flatpak": ["bottles", "protonupqt"]
}
EOF

cat > /workspace/archlive/airootfs/usr/local/libexec/mechos-creator-app-installer << "EOF"
#!/usr/bin/env bash
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Administrator privileges required." >&2; exit 1; }

if [ "${1:-}" = "--package" ]; then
  case "${2:-}" in
    streamer) PKGS=(obs-studio kdenlive audacity) ;;
    graphics) PKGS=(blender krita) ;;
    game-dev) PKGS=(godot blender) ;;
    windows-apps) PKGS=(wine winetricks protontricks) ;;
    *) echo "Unknown Creator package id." >&2; exit 2 ;;
  esac
  if command -v snapper >/dev/null 2>&1 && snapper list-configs 2>/dev/null | awk '{print $1}' | grep -qx root; then
    snapper -c root create --type single --description "Before MechOS Creator package: ${2}" || true
  fi
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
chmod 755 /workspace/archlive/airootfs/usr/local/libexec/mechos-creator-app-installer

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-creator-app << "PYEOF"
#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT_HELPER="/usr/local/libexec/mechos-creator-app-installer"
MANIFEST_DIR=Path("/usr/share/mechos/creator-packages")

NATIVE={
 "blender":("blender",["blender"]),
 "obs":("obs-studio",["obs"]),
 "kdenlive":("kdenlive",["kdenlive"]),
 "krita":("krita",["krita"]),
 "godot":("godot",["godot"]),
 "audacity":("audacity",["audacity"]),
 "lmms":("lmms",["lmms"]),
 "lutris":("lutris",["lutris"]),
 "wine":("wine",["winecfg"]),
 "winetricks":("winetricks",["winetricks"]),
 "protontricks":("protontricks",["protontricks"]),
 "steam":("steam",["steam"]),
}
FLATPAK={
 "unityhub":"com.unity.UnityHub",
 "vscode":"com.visualstudio.code",
 "gitkraken":"com.axosoft.GitKraken",
 "bottles":"com.usebottles.bottles",
 "heroic":"com.heroicgameslauncher.hgl",
 "protonupqt":"net.davidotek.pupgui2",
 "discord":"com.discordapp.Discord",
}

def manifest(package):
    import json
    path=MANIFEST_DIR/(package+".json")
    if not path.is_file(): raise SystemExit("Unknown Creator package id")
    return json.loads(path.read_text())

def fp_installed(appid):
    return subprocess.run(["flatpak","info","--user",appid],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0 or \
           subprocess.run(["flatpak","info","--system",appid],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0

def status(app):
    if app in NATIVE:
        print("installed" if shutil.which(NATIVE[app][1][0]) else "missing")
    elif app in FLATPAK:
        print("installed" if fp_installed(FLATPAK[app]) else "missing")
    else:
        print("special")

def install(app):
    if app in NATIVE:
        subprocess.run(["pkexec",ROOT_HELPER,app],check=True)
    elif app in FLATPAK:
        subprocess.run([
            "flatpak","remote-add","--user","--if-not-exists",
            "flathub","https://flathub.org/repo/flathub.flatpakrepo"
        ],check=True)
        subprocess.run(["flatpak","install","--user","-y","flathub",FLATPAK[app]],check=True)
    else:
        raise SystemExit(2)

def package_status(package):
    data=manifest(package)
    states=[]
    for app in data.get("native",[]):
        states.append(app in NATIVE and shutil.which(NATIVE[app][1][0]) is not None)
    for app in data.get("flatpak",[]):
        states.append(app in FLATPAK and fp_installed(FLATPAK[app]))
    print("installed" if states and all(states) else "partial" if any(states) else "missing")

def install_package(package):
    data=manifest(package)
    subprocess.run(["pkexec",ROOT_HELPER,"--package",package],check=True)
    flatpaks=data.get("flatpak",[])
    if flatpaks:
        subprocess.run([
            "flatpak","remote-add","--user","--if-not-exists",
            "flathub","https://flathub.org/repo/flathub.flatpakrepo"
        ],check=True)
        for app in flatpaks:
            subprocess.run(["flatpak","install","--user","-y","flathub",FLATPAK[app]],check=True)

def launch(app):
    if app in NATIVE:
        cmd=NATIVE[app][1]
        os.execvp(cmd[0],cmd)
    if app in FLATPAK:
        os.execvp("flatpak",["flatpak","run",FLATPAK[app]])
    raise SystemExit(2)

def windows_installer():
    prefix=Path.home()/".local/share/mechos/creator-wineprefix"
    prefix.mkdir(parents=True,exist_ok=True)
    env={**os.environ,"WINEPREFIX":str(prefix)}
    subprocess.run(["wineboot","-u"],env=env,check=False)
    p=subprocess.run(
        ["kdialog","--getopenfilename",str(Path.home()),"*.exe *.msi|Windows Installers"],
        text=True,stdout=subprocess.PIPE
    )
    file=p.stdout.strip()
    if not file: return
    if file.lower().endswith(".msi"):
        subprocess.Popen(["wine","msiexec","/i",file],env=env)
    else:
        subprocess.Popen(["wine",file],env=env)

if __name__=="__main__":
    if len(sys.argv)>=2 and sys.argv[1]=="windows-installer":
        windows_installer(); raise SystemExit
    if len(sys.argv)!=3:
        raise SystemExit("Usage: mechos-creator-app {status|install|launch|package-status|package-install} ID")
    {"status":status,"install":install,"launch":launch,
     "package-status":package_status,"package-install":install_package}[sys.argv[1]](sys.argv[2])
PYEOF
chmod 755 /workspace/archlive/airootfs/usr/local/bin/mechos-creator-app

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-creator-mode << "PYEOF"
#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import quote_plus

from PyQt6.QtCore import Qt, QTimer
from PyQt6.QtGui import QFont, QPixmap
from PyQt6.QtWidgets import (
    QApplication, QFileDialog, QFrame, QGridLayout, QHBoxLayout, QInputDialog,
    QLabel, QListWidget, QListWidgetItem, QMainWindow, QMessageBox, QPushButton,
    QScrollArea, QStackedWidget, QVBoxLayout, QWidget
)

LOGO="/usr/share/mechos/branding/mechos-logo.png"
REF="/usr/share/mechos/branding/mechos-creator-mode-reference.png"
APP="/usr/local/bin/mechos-creator-app"
PROJECT_ROOT=Path.home()/"MechOS/Projects"
ASSET_ROOT=Path.home()/"MechOS/Assets"
CONFIG_DIR=Path.home()/".config/mechos"
PRESET_FILE=CONFIG_DIR/"creator-preset.json"

CATALOG=[
 ("Blender","blender","3D Modeling & Animation","native"),
 ("Unity Hub","unityhub","Unity editor manager • community Flatpak","flatpak"),
 ("Unreal Engine","unreal","Epic Linux setup • vendor sign-in","vendor"),
 ("VRChat Creator","vrchat","Unity + VRChat SDK workflow","setup"),
 ("VS Code","vscode","Code editor • community Flatpak","flatpak"),
 ("GitKraken","gitkraken","Git client • community Flatpak","flatpak"),
 ("Krita","krita","Textures & digital art","native"),
 ("OBS Studio","obs","Streaming & recording","native"),
 ("Godot","godot","Open-source game engine","native"),
 ("Audacity","audacity","Audio editing","native"),
 ("LMMS","lmms","Music production","native"),
 ("Steam","steam","Steam + Proton runtime","native"),
 ("Lutris","lutris","Wine/Proton launcher","native"),
 ("Heroic","heroic","Epic/GOG/Amazon launcher","flatpak"),
 ("ProtonUp-Qt","protonupqt","GE-Proton / Wine tools","flatpak"),
 ("Bottles","bottles","Windows app environments","flatpak"),
 ("Wine","wine","Windows compatibility runtime","native"),
 ("Winetricks","winetricks","Wine components","native"),
 ("Protontricks","protontricks","Steam Proton prefix tools","native"),
 ("Discord","discord","Creator/community chat","flatpak"),
]

PACKAGES=[
 ("Streamer Package","streamer","OBS Studio, Kdenlive, Audacity and Discord","Approximately 4 GB"),
 ("Graphics Creator","graphics","Blender and Krita","Approximately 5 GB"),
 ("Game Developer","game-dev","Godot, Blender, VS Code, GitKraken and Unity Hub","Approximately 7 GB + engines"),
 ("Windows Apps & Bottles","windows-apps","Bottles, Wine, Winetricks, Protontricks and ProtonUp-Qt","Approximately 3 GB"),
]

STYLE="""
QWidget{background:#07080d;color:#f6f2fb;font-family:Sans Serif}
QFrame#sidebar{background:#09090e;border-right:1px solid #351b46}
QFrame#top,QFrame#bottom{background:#090a10;border:1px solid #2c1838}
QFrame#panel{background:#0e0f16;border:1px solid #2b2135;border-radius:12px}
QFrame#card{background:#11131b;border:1px solid #292b38;border-radius:11px}
QFrame#card:hover{border:1px solid #7b43bd}
QLabel#title{font-size:28px;font-weight:900;color:white}
QLabel#purple{font-size:15px;font-weight:800;color:#c273ff}
QLabel#muted{color:#9d94a9}
QLabel#metric{color:#d08cff;font-weight:700}
QPushButton#nav{background:transparent;border:0;border-radius:8px;padding:11px;text-align:left;color:#d8d0df;font-weight:650}
QPushButton#nav:checked,QPushButton#nav:hover{background:#6928b7;color:white}
QPushButton#action{background:#351750;border:1px solid #704198;border-radius:7px;padding:8px 11px;color:#f0dfff;font-weight:650}
QPushButton#action:hover{background:#5a2381}
QListWidget{background:#0b0d13;border:1px solid #2b2135;border-radius:8px}
QListWidget::item{padding:8px}
QListWidget::item:selected{background:#54227d}
QScrollArea{border:0}
"""

def out(cmd):
    try:return subprocess.check_output(cmd,text=True,stderr=subprocess.DEVNULL).strip()
    except:return ""

def spawn(cmd):
    try: subprocess.Popen(cmd)
    except Exception as e: QMessageBox.warning(None,"MechOS Creator Mode",str(e))

def open_url(url): spawn(["xdg-open",url])

def is_live():
    return Path("/run/archiso/bootmnt").exists() or "archiso" in out(["bash","-lc","cat /proc/cmdline"])

def vram_text():
    if shutil.which("nvidia-smi"):
        x=out(["nvidia-smi","--query-gpu=memory.used,memory.total","--format=csv,noheader,nounits"])
        if x:
            try:
                u,t=[int(v.strip()) for v in x.splitlines()[0].split(",")]
                return f"{u}/{t} MiB"
            except: pass
    return "N/A"

def scan_projects():
    PROJECT_ROOT.mkdir(parents=True,exist_ok=True)
    candidates=[]
    roots=[PROJECT_ROOT,Path.home()/"Projects"]
    for base in roots:
        if not base.exists(): continue
        for p in base.iterdir():
            if not p.is_dir(): continue
            kind="Folder"
            if list(p.glob("*.uproject")): kind="Unreal"
            elif (p/"ProjectSettings/ProjectVersion.txt").exists(): kind="Unity"
            elif list(p.glob("*.blend")): kind="Blender"
            elif (p/"project.godot").exists(): kind="Godot"
            try: mtime=p.stat().st_mtime
            except: mtime=0
            candidates.append((mtime,p,kind))
    candidates.sort(reverse=True,key=lambda x:x[0])
    return candidates[:30]

def launch_project(path,kind):
    p=Path(path)
    if kind=="Unreal":
        files=list(p.glob("*.uproject"))
        if files: spawn(["xdg-open",str(files[0])]); return
    if kind=="Unity":
        if shutil.which("unityhub"): spawn(["unityhub","--","--projectPath",str(p)]); return
        if shutil.which("flatpak"): spawn(["flatpak","run","com.unity.UnityHub"]); return
    if kind=="Blender":
        files=list(p.glob("*.blend"))
        if files and shutil.which("blender"): spawn(["blender",str(files[0])]); return
    if kind=="Godot" and shutil.which("godot"):
        spawn(["godot","--editor","--path",str(p)]); return
    spawn(["dolphin",str(p)])

class AppCard(QFrame):
    def __init__(self,owner,info):
        super().__init__(); self.owner=owner; self.info=info; self.setObjectName("card")
        name,appid,desc,kind=info
        l=QVBoxLayout(self); l.setContentsMargins(11,10,11,10)
        n=QLabel(name); n.setFont(QFont("Sans Serif",11,QFont.Weight.Bold)); l.addWidget(n)
        d=QLabel(desc); d.setObjectName("muted"); d.setWordWrap(True); l.addWidget(d)
        l.addStretch()
        self.state=QLabel(); self.state.setObjectName("metric"); l.addWidget(self.state)
        self.button=QPushButton(); self.button.setObjectName("action"); self.button.clicked.connect(self.activate); l.addWidget(self.button)
        self.refresh()

    @property
    def appid(self): return self.info[1]

    def status(self):
        if self.info[3] in ("vendor","setup"): return self.info[3]
        return out([APP,"status",self.appid]) or "missing"

    def refresh(self):
        st=self.status()
        if st=="installed": self.state.setText("READY"); self.button.setText("Launch")
        elif st=="vendor": self.state.setText("VENDOR SETUP"); self.button.setText("Setup")
        elif st=="setup": self.state.setText("CREATOR SETUP"); self.button.setText("Setup")
        else: self.state.setText("NOT INSTALLED"); self.button.setText("Install")

    def activate(self):
        st=self.status()
        if self.appid=="unreal": open_url("https://www.unrealengine.com/en-US/linux"); return
        if self.appid=="vrchat": self.owner.vrchat(); return
        if st=="installed": spawn([APP,"launch",self.appid])
        else: self.owner.install(self)

class PackageCard(QFrame):
    def __init__(self,owner,info):
        super().__init__(); self.owner=owner; self.info=info; self.setObjectName("card")
        name,package,desc,space=info
        l=QVBoxLayout(self); l.setContentsMargins(14,12,14,12)
        n=QLabel(name); n.setFont(QFont("Sans Serif",12,QFont.Weight.Bold)); l.addWidget(n)
        d=QLabel(desc); d.setObjectName("muted"); d.setWordWrap(True); l.addWidget(d)
        size=QLabel("DISK SPACE  "+space); size.setObjectName("metric"); l.addWidget(size)
        l.addStretch()
        self.state=QLabel(); self.state.setObjectName("metric"); l.addWidget(self.state)
        self.button=QPushButton(); self.button.setObjectName("action"); self.button.clicked.connect(self.activate); l.addWidget(self.button)
        self.refresh()

    @property
    def package(self): return self.info[1]

    def refresh(self):
        st=out([APP,"package-status",self.package]) or "missing"
        if st=="installed": self.state.setText("INSTALLED"); self.button.setText("Repair / Verify")
        elif st=="partial": self.state.setText("PARTIALLY INSTALLED"); self.button.setText("Complete Install")
        else: self.state.setText("NOT INSTALLED"); self.button.setText("Install Package")

    def activate(self): self.owner.install_package(self)

class Creator(QMainWindow):
    def __init__(self):
        super().__init__(); self.cards=[]; self.package_cards=[]
        PROJECT_ROOT.mkdir(parents=True,exist_ok=True)
        ASSET_ROOT.mkdir(parents=True,exist_ok=True)
        CONFIG_DIR.mkdir(parents=True,exist_ok=True)
        self.setWindowTitle("MechOS Creator Mode 2.0")
        self.resize(1580,960); self.setMinimumSize(1180,720); self.setStyleSheet(STYLE)
        self.build()
        self.timer=QTimer(self); self.timer.timeout.connect(self.metrics); self.timer.start(2500); self.metrics()

    def panel(self,name="panel"):
        p=QFrame(); p.setObjectName(name); return p

    def scroll(self):
        s=QScrollArea(); s.setWidgetResizable(True); w=QWidget(); v=QVBoxLayout(w); v.setContentsMargins(20,16,20,20); s.setWidget(w); return s,v

    def section(self,v,name):
        l=QLabel(name); l.setObjectName("purple"); v.addWidget(l)

    def build(self):
        root=QWidget(); self.setCentralWidget(root)
        outer=QVBoxLayout(root); outer.setContentsMargins(0,0,0,0); outer.setSpacing(0)

        top=self.panel("top"); tl=QHBoxLayout(top)
        if Path(LOGO).exists():
            lab=QLabel(); lab.setPixmap(QPixmap(LOGO).scaledToHeight(40,Qt.TransformationMode.SmoothTransformation)); tl.addWidget(lab)
        b=QLabel("MECHOS"); b.setObjectName("title"); tl.addWidget(b); tl.addStretch()
        m=QLabel("CREATOR MODE 2.0"); m.setObjectName("purple"); m.setFont(QFont("Sans Serif",22,QFont.Weight.Bold)); tl.addWidget(m); tl.addStretch()
        self.cpu=QLabel(); self.ram=QLabel(); self.vram=QLabel(); self.disk=QLabel()
        for x in (self.cpu,self.ram,self.vram,self.disk): x.setObjectName("metric"); tl.addWidget(x)
        outer.addWidget(top)

        body=QHBoxLayout(); body.setSpacing(0)
        side=self.panel("sidebar"); side.setFixedWidth(215); sl=QVBoxLayout(side)
        self.stack=QStackedWidget(); self.nav=[]
        pages=[
          ("⌂  Dashboard",self.dashboard),
          ("▣  Projects",self.projects),
          ("⬡  Engines",lambda:self.catalog("GAME ENGINES",["unityhub","unreal","godot","vscode","gitkraken"])),
          ("⚒  Tools",lambda:self.catalog("CREATOR TOOLS",["blender","krita","obs","kdenlive","audacity","lmms","vscode","gitkraken"])),
          ("▦  App Store",self.app_store),
          ("▧  Assets",self.assets),
          ("✦  MechClip AI",self.mechclip),
          ("◈  Learn",self.learn),
          ("◎  Community",self.community),
          ("⚙  Settings",self.settings)
        ]
        for i,(name,fn) in enumerate(pages):
            btn=QPushButton(name); btn.setObjectName("nav"); btn.setCheckable(True); btn.clicked.connect(lambda _,j=i:self.select(j)); sl.addWidget(btn); self.nav.append(btn); self.stack.addWidget(fn())
        sl.addStretch()
        stat=self.panel(); st=QVBoxLayout(stat); ss=QLabel("SYSTEM STATUS"); ss.setObjectName("purple"); st.addWidget(ss)
        self.status=QLabel(); self.status.setObjectName("muted"); self.status.setWordWrap(True); st.addWidget(self.status)
        mon=QPushButton("System Monitor"); mon.setObjectName("action"); mon.clicked.connect(lambda:spawn(["/usr/local/bin/mechos-performance-center"])); st.addWidget(mon)
        sl.addWidget(stat)
        body.addWidget(side); body.addWidget(self.stack,1); outer.addLayout(body,1)

        bottom=self.panel("bottom"); bl=QHBoxLayout(bottom); bl.addWidget(QLabel("MECHOS")); bl.addStretch()
        for name,fn in [("Gaming Mode",self.mechscope),("Creator Mode",lambda:None),("Desktop Mode",self.desktop),("MechScope",self.mechscope)]:
            btn=QPushButton(name); btn.setObjectName("action"); btn.clicked.connect(fn); bl.addWidget(btn)
        bl.addStretch(); outer.addWidget(bottom); self.select(0)

    def dashboard(self):
        s,v=self.scroll()
        hero=self.panel(); h=QHBoxLayout(hero); tx=QVBoxLayout()
        a=QLabel("WELCOME TO"); a.setObjectName("purple"); tx.addWidget(a)
        t=QLabel("CREATOR MODE"); t.setObjectName("title"); tx.addWidget(t)
        d=QLabel("Build worlds, avatars, games, video and streaming projects with one-click creator tools, projects, assets and compatibility runtimes."); d.setObjectName("muted"); d.setWordWrap(True); tx.addWidget(d)
        hero_buttons=QHBoxLayout()
        for name,fn in [("New Project",self.new_project),("Open Project",self.open_project_picker),("What's New",lambda:spawn(["/usr/local/bin/mechos-update-center"]))]:
            b=QPushButton(name); b.setObjectName("action"); b.clicked.connect(fn); hero_buttons.addWidget(b)
        tx.addLayout(hero_buttons); tx.addStretch()
        h.addLayout(tx,2)
        if Path(REF).exists():
            art=QLabel(); art.setPixmap(QPixmap(REF).scaled(560,260,Qt.AspectRatioMode.KeepAspectRatio,Qt.TransformationMode.SmoothTransformation)); art.setAlignment(Qt.AlignmentFlag.AlignCenter); h.addWidget(art,3)
        v.addWidget(hero)

        self.section(v,"QUICK LAUNCH")
        q=QGridLayout()
        for i,appid in enumerate(["blender","unityhub","unreal","vrchat","vscode","gitkraken","krita","obs","lutris","heroic","steam","protonupqt"]):
            info=next(x for x in CATALOG if x[1]==appid)
            btn=QPushButton(info[0]); btn.setObjectName("action"); btn.clicked.connect(lambda _,a=appid:self.quick(a)); q.addWidget(btn,i//6,i%6)
        v.addLayout(q)

        row=QHBoxLayout()
        recent=self.panel(); rl=QVBoxLayout(recent); rt=QLabel("RECENT PROJECTS"); rt.setObjectName("purple"); rl.addWidget(rt)
        projects=scan_projects()[:5]
        if projects:
            for m,p,k in projects:
                b=QPushButton(f"{p.name}   •   {k}"); b.setObjectName("action"); b.clicked.connect(lambda _,pp=p,kk=k:launch_project(pp,kk)); rl.addWidget(b)
        else:
            none=QLabel("No projects yet."); none.setObjectName("muted"); rl.addWidget(none)
        pm=QPushButton("Open Project Manager"); pm.setObjectName("action"); pm.clicked.connect(lambda:self.select(1)); rl.addWidget(pm)
        row.addWidget(recent,2)

        presets=self.panel(); pl=QVBoxLayout(presets); pt=QLabel("CREATOR MODE PRESETS"); pt.setObjectName("purple"); pl.addWidget(pt)
        for name in ["Game Dev","VRChat Creator","3D Artist","Streaming"]:
            b=QPushButton(name); b.setObjectName("action"); b.clicked.connect(lambda _,n=name:self.apply_preset(n)); pl.addWidget(b)
        row.addWidget(presets,1)

        news=self.panel(); nl=QVBoxLayout(news); nt=QLabel("NEWS & UPDATES"); nt.setObjectName("purple"); nl.addWidget(nt)
        release=Path("/etc/mechos-release")
        rtxt=release.read_text(errors="ignore") if release.exists() else "MechOS Alpha"
        lab=QLabel("Current system:\n"+rtxt[:240]); lab.setObjectName("muted"); lab.setWordWrap(True); nl.addWidget(lab)
        ub=QPushButton("Open Update Center"); ub.setObjectName("action"); ub.clicked.connect(lambda:spawn(["/usr/local/bin/mechos-update-center"])); nl.addWidget(ub)
        row.addWidget(news,1)
        v.addLayout(row)

        self.section(v,"1-CLICK INSTALL & COMPATIBILITY")
        g=QGridLayout()
        for i,appid in enumerate(["steam","lutris","heroic","protonupqt","wine","winetricks","bottles","discord"]):
            info=next(x for x in CATALOG if x[1]==appid); c=AppCard(self,info); self.cards.append(c); g.addWidget(c,i//4,i%4)
        v.addLayout(g)
        v.addStretch(); return s

    def app_store(self):
        s,v=self.scroll(); self.section(v,"CREATOR MODE APP STORE")
        intro=QLabel("Install trusted MechOS creator bundles or choose individual applications. Native packages request administrator approval; Flatpaks install only for your user account.")
        intro.setObjectName("muted"); intro.setWordWrap(True); v.addWidget(intro)
        self.section(v,"ONE-CLICK CREATOR PACKAGES")
        pg=QGridLayout()
        for i,info in enumerate(PACKAGES):
            c=PackageCard(self,info); self.package_cards.append(c); pg.addWidget(c,i//3,i%3)
        v.addLayout(pg)
        self.section(v,"INDIVIDUAL APPLICATIONS")
        g=QGridLayout()
        for i,info in enumerate(CATALOG):
            c=AppCard(self,info); self.cards.append(c); g.addWidget(c,i//4,i%4)
        v.addLayout(g); v.addStretch(); return s

    def new_project(self):
        name,ok=QInputDialog.getText(self,"New Project","Project name:")
        if not ok or not name.strip(): return
        safe="".join(c for c in name.strip() if c.isalnum() or c in " _-").strip()
        if not safe: return
        kind,ok=QInputDialog.getItem(self,"Project Template","Template:",["Generic","Unreal","Unity","Godot","Blender","VRChat"],0,False)
        if not ok:return
        p=PROJECT_ROOT/safe
        if p.exists():
            QMessageBox.warning(self,"MechOS Creator","That project already exists.");return
        p.mkdir(parents=True)
        meta={"name":safe,"template":kind,"created":int(time.time())}
        (p/".mechos-project.json").write_text(json.dumps(meta,indent=2))
        if kind=="Godot": (p/"project.godot").write_text('[application]\nconfig/name="'+safe+'"\n')
        elif kind=="Unity": (p/"ProjectSettings").mkdir(); (p/"Assets").mkdir(); (p/"ProjectSettings/ProjectVersion.txt").write_text("m_EditorVersion: configure-with-Unity-Hub\n")
        elif kind=="Unreal": (p/(safe+".uproject")).write_text('{"FileVersion":3,"EngineAssociation":"","Category":"","Description":"MechOS project"}\n')
        elif kind=="Blender": pass
        elif kind=="VRChat": (p/"README.txt").write_text("Open Unity Hub, create/open a supported Unity project here, then follow VRChat Creator documentation.\n")
        QMessageBox.information(self,"MechOS Creator",f"Created {kind} project:\n{p}")
        launch_project(p,kind)

    def open_project_picker(self):
        path=QFileDialog.getExistingDirectory(self,"Open Creator Project",str(PROJECT_ROOT))
        if path: launch_project(Path(path),"Folder")

    def projects(self):
        s,v=self.scroll(); self.section(v,"PROJECT MANAGER")
        top=QHBoxLayout()
        for name,fn in [("New Project",self.new_project),("Open Folder",self.open_project_picker),("Projects Directory",lambda:spawn(["dolphin",str(PROJECT_ROOT)]))]:
            b=QPushButton(name); b.setObjectName("action"); b.clicked.connect(fn); top.addWidget(b)
        v.addLayout(top)
        lst=QListWidget()
        projects=scan_projects()
        for m,p,k in projects:
            item=QListWidgetItem(f"{p.name}   [{k}]   {time.strftime('%Y-%m-%d %H:%M',time.localtime(m))}")
            item.setData(Qt.ItemDataRole.UserRole,(str(p),k)); lst.addItem(item)
        lst.itemDoubleClicked.connect(lambda it: launch_project(*it.data(Qt.ItemDataRole.UserRole)))
        v.addWidget(lst,1)
        openb=QPushButton("Open Selected Project"); openb.setObjectName("action")
        def open_selected():
            it=lst.currentItem()
            if it: launch_project(*it.data(Qt.ItemDataRole.UserRole))
        openb.clicked.connect(open_selected); v.addWidget(openb)
        return s

    def assets(self):
        s,v=self.scroll(); self.section(v,"ASSET BROWSER")
        bar=QHBoxLayout()
        imp=QPushButton("Import Files"); imp.setObjectName("action")
        def import_files():
            files,_=QFileDialog.getOpenFileNames(self,"Import Creator Assets",str(Path.home()))
            for f in files:
                try: shutil.copy2(f,ASSET_ROOT/Path(f).name)
                except Exception as e: QMessageBox.warning(self,"Asset Import",str(e))
            refresh()
        imp.clicked.connect(import_files); bar.addWidget(imp)
        folder=QPushButton("Open Assets Folder"); folder.setObjectName("action"); folder.clicked.connect(lambda:spawn(["dolphin",str(ASSET_ROOT)])); bar.addWidget(folder)
        v.addLayout(bar)
        lst=QListWidget()
        def refresh():
            lst.clear()
            for p in sorted(ASSET_ROOT.rglob("*")):
                if p.is_file():
                    lst.addItem(str(p.relative_to(ASSET_ROOT)))
        refresh()
        lst.itemDoubleClicked.connect(lambda it:spawn(["xdg-open",str(ASSET_ROOT/it.text())]))
        v.addWidget(lst,1)
        return s

    def catalog(self,title,ids):
        s,v=self.scroll(); self.section(v,title); g=QGridLayout()
        for i,appid in enumerate(ids):
            info=next(x for x in CATALOG if x[1]==appid); c=AppCard(self,info); self.cards.append(c); g.addWidget(c,i//3,i%3)
        v.addLayout(g); v.addStretch(); return s

    def mechclip(self):
        s,v=self.scroll(); self.section(v,"MECHCLIP AI")
        note=QLabel("MechClip launches when installed. OBS and Kdenlive are available below for capture/editing."); note.setObjectName("muted"); note.setWordWrap(True); v.addWidget(note)
        b=QPushButton("Launch MechClip"); b.setObjectName("action"); b.clicked.connect(self.open_mechclip); v.addWidget(b)
        for appid in ["obs","kdenlive"]:
            info=next(x for x in CATALOG if x[1]==appid); c=AppCard(self,info); self.cards.append(c); v.addWidget(c)
        v.addStretch(); return s

    def learn(self):
        s,v=self.scroll(); self.section(v,"LEARN")
        for name,url in [
            ("Blender Manual","https://docs.blender.org/manual/en/latest/"),
            ("Unity Manual","https://docs.unity3d.com/"),
            ("Unreal Documentation","https://dev.epicgames.com/documentation/"),
            ("VRChat Creator Docs","https://creators.vrchat.com/"),
            ("Godot Docs","https://docs.godotengine.org/"),
        ]:
            b=QPushButton(name); b.setObjectName("action"); b.clicked.connect(lambda _,u=url:open_url(u)); v.addWidget(b)
        v.addStretch(); return s

    def community(self):
        s,v=self.scroll(); self.section(v,"COMMUNITY")
        for name,url in [("Discord", "https://discord.com/"),("GitHub", "https://github.com/"),("VRChat Creators","https://creators.vrchat.com/")]:
            b=QPushButton(name); b.setObjectName("action"); b.clicked.connect(lambda _,u=url:open_url(u)); v.addWidget(b)
        v.addStretch(); return s

    def settings(self):
        s,v=self.scroll(); self.section(v,"CREATOR SETTINGS")
        for name,cmd in [
            ("System Settings",["systemsettings"]),
            ("Performance Center",["/usr/local/bin/mechos-performance-center"]),
            ("Update Center",["/usr/local/bin/mechos-update-center"]),
            ("Creator Folder Setup",["/usr/local/bin/mechos-creator-setup"]),
            ("Windows Creator Installer",[APP,"windows-installer"]),
        ]:
            b=QPushButton(name); b.setObjectName("action"); b.clicked.connect(lambda _,c=cmd:spawn(c)); v.addWidget(b)
        v.addStretch(); return s

    def select(self,i):
        self.stack.setCurrentIndex(i)
        for j,b in enumerate(self.nav): b.setChecked(i==j)

    def apply_preset(self,name):
        data={"preset":name,"updated":int(time.time())}
        PRESET_FILE.write_text(json.dumps(data,indent=2))
        profile="balanced"
        if name in ("Game Dev","3D Artist"): profile="performance"
        elif name=="Streaming": profile="balanced"
        elif name=="VRChat Creator": profile="performance"
        if shutil.which("powerprofilesctl"):
            subprocess.run(["powerprofilesctl","set",profile],check=False)
        QMessageBox.information(self,"Creator Preset",f"{name} preset activated.\nPower profile: {profile}")

    def install(self,card):
        if is_live():
            QMessageBox.information(self,"MechOS Live Desktop","One-click app installs are disabled in the disposable Live session. Install MechOS first so Creator apps persist.")
            return
        if QMessageBox.question(self,"Install Creator App",f"Install {card.info[0]}?")!=QMessageBox.StandardButton.Yes:return
        spawn(["konsole","-e","bash","-lc",f"{APP} install {card.appid}; rc=$?; echo; echo Installer exit code: $rc; read -rp 'Press Enter to close...'"])
        QTimer.singleShot(5000,self.refresh_cards)

    def install_package(self,card):
        if is_live():
            QMessageBox.information(self,"MechOS Live Desktop","Creator packages can only be installed after MechOS is installed to disk.")
            return
        name,package,desc,space=card.info
        message=f"Install {name}?\n\nIncludes: {desc}\nRequired space: {space}\n\nMechOS will request administrator approval for native packages."
        if QMessageBox.question(self,"Install Creator Package",message)!=QMessageBox.StandardButton.Yes:return
        spawn(["konsole","-e","bash","-lc",f"{APP} package-install {package}; rc=$?; echo; echo Package installer exit code: $rc; read -rp 'Press Enter to close...'"])
        QTimer.singleShot(8000,self.refresh_cards)

    def refresh_cards(self):
        for c in self.cards:c.refresh()
        for c in self.package_cards:c.refresh()

    def quick(self,appid):
        info=next(x for x in CATALOG if x[1]==appid)
        if appid=="unreal":open_url("https://www.unrealengine.com/en-US/linux");return
        if appid=="vrchat":self.vrchat();return
        st=out([APP,"status",appid])
        if st=="installed":spawn([APP,"launch",appid])
        else:
            temp=AppCard(self,info); self.install(temp)

    def vrchat(self):
        QMessageBox.information(self,"VRChat Creator","MechOS provides Unity Hub and creator tooling, but does not claim unsupported native VRChat Creator Companion behavior. The supported SDK workflow remains linked below.")
        open_url("https://creators.vrchat.com/")

    def open_mechclip(self):
        for p in [shutil.which("mechclip"),"/opt/mechclip/MechClip","/opt/MechClip/MechClip"]:
            if p and os.path.exists(p):spawn([p]);return
        QMessageBox.information(self,"MechClip AI","MechClip is not installed in a known path yet.")

    def metrics(self):
        self.cpu.setText("CPU "+(out(["bash","-lc","top -bn1 | awk '/Cpu\\(s\\)/ {printf \"%.0f%%\",100-$8;exit}'"]) or "?"))
        self.ram.setText("RAM "+(out(["bash","-lc","free | awk '/Mem:/ {printf \"%.0f%%\",($3/$2)*100}'"]) or "?"))
        self.vram.setText("VRAM "+vram_text())
        self.disk.setText("DISK "+(out(["bash","-lc","df -h / | awk 'NR==2 {print $5}'"]) or "?"))
        gpu=out(["bash","-lc","lspci | grep -Ei 'VGA|3D|Display' | sed 's/^[^ ]* //' | head -n1"]) or "Unknown GPU"
        preset="None"
        try: preset=json.loads(PRESET_FILE.read_text()).get("preset","None")
        except: pass
        self.status.setText("OS\\nMechOS Arch\\n\\nGPU\\n"+gpu[:48]+"\\n\\nPreset\\n"+preset)

    def mechscope(self):
        spawn(["/usr/local/bin/mechos-return-to-mechscope"]); QApplication.quit()

    def desktop(self): QApplication.quit()

app=QApplication(sys.argv); app.setApplicationName("MechOS Creator Mode 2.0")
w=Creator(); w.showMaximized(); sys.exit(app.exec())
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


# ---------- CORE MECHOS SYSTEM UTILITIES ----------
# These utilities existed in the earlier MechOS design and are restored here
# explicitly instead of depending on an old overlay.

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-session-select << "EOF"
#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-menu}"
MODE_FILE="/tmp/mechos-next-mode-$(id -u)"

choose_mode() {
  if command -v kdialog >/dev/null 2>&1; then
    kdialog --title "MechOS Mode Switcher" \
      --menu "Choose a MechOS mode" \
      gaming "Gaming Mode / MechScope" \
      creator "Creator Mode" \
      desktop "Desktop Mode" \
      performance "Performance Center" 2>/dev/null || true
  else
    printf '%s\n' gaming
  fi
}

if [ "$MODE" = "menu" ]; then
  MODE="$(choose_mode)"
fi

case "$MODE" in
  gaming)
    if [ "${MECHOS_MODE:-}" = "gaming" ]; then
      exit 0
    fi
    exec /usr/local/bin/mechos-return-to-mechscope
    ;;
  creator)
    if [ "${MECHOS_MODE:-}" = "gaming" ]; then
      printf '%s\n' creator > "$MODE_FILE"
      pkill -TERM -f "/usr/local/bin/mechscope" 2>/dev/null || true
      exit 0
    fi
    exec /usr/local/bin/mechos-creator-mode
    ;;
  desktop)
    if [ "${MECHOS_MODE:-}" = "gaming" ]; then
      printf '%s\n' desktop > "$MODE_FILE"
      pkill -TERM -f "/usr/local/bin/mechscope" 2>/dev/null || true
      exit 0
    fi
    exit 0
    ;;
  performance)
    exec /usr/local/bin/mechos-performance-center
    ;;
  *)
    echo "Usage: mechos-session-select {gaming|creator|desktop|performance|menu}" >&2
    exit 2
    ;;
esac
EOF

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-gpu-setup << "EOF"
#!/usr/bin/env bash
set -euo pipefail

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

GPU_LINE="$(lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | head -n 1 || true)"
VENDOR="unknown"
PKGS=()

if echo "$GPU_LINE" | grep -qi nvidia; then
  VENDOR="nvidia"
  PKGS=(nvidia-open nvidia-utils lib32-nvidia-utils nvidia-prime)
elif echo "$GPU_LINE" | grep -Eqi 'AMD|ATI'; then
  VENDOR="amd"
  PKGS=(mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon libva-mesa-driver)
elif echo "$GPU_LINE" | grep -qi intel; then
  VENDOR="intel"
  PKGS=(mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver)
fi

echo "MechOS GPU setup"
echo "Detected: ${GPU_LINE:-No GPU line detected}"
echo "Vendor: $VENDOR"

if [ "${#PKGS[@]}" -gt 0 ]; then
  echo "Recommended packages: ${PKGS[*]}"
fi

if [ "$APPLY" -eq 0 ]; then
  exit 0
fi

if [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null; then
  echo "Live ISO detected. Drivers are already bundled; not modifying the live system."
  exit 0
fi

if [ "$VENDOR" = "unknown" ]; then
  echo "Unknown GPU vendor; no package changes made." >&2
  exit 1
fi

sudo pacman -S --needed --noconfirm "${PKGS[@]}"
echo "GPU packages updated for $VENDOR."
EOF

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-update << "EOF"
#!/usr/bin/env bash
set -euo pipefail

if [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null; then
  echo "MechOS is running from the live ISO. Updates would not persist."
  if command -v kdialog >/dev/null 2>&1; then
    kdialog --title "MechOS Update Center" --sorry \
      "This is the MechOS live ISO. Install MechOS before using the updater."
  fi
  exit 2
fi

if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v python3 >/dev/null 2>&1; then
  exec /usr/local/bin/mechos-update-center
fi

exec sudo /usr/local/bin/mechos-update-helper apply
EOF

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-update-helper << "EOF"
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/var/lib/mechos"
CACHE_DIR="/var/cache/mechos"
LOG_DIR="/var/log/mechos"
HISTORY="$STATE_DIR/update-history.log"
LAST_RESULT="$STATE_DIR/last-update-result"
REBOOT_MARKER="$STATE_DIR/reboot-required"

mkdir -p "$STATE_DIR" "$CACHE_DIR" "$LOG_DIR" 2>/dev/null || true

is_live() {
  [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null
}

require_installed() {
  if is_live; then
    echo "ERROR: Updates are disabled in the MechOS live ISO."
    exit 2
  fi
}

check_updates() {
  require_installed

  echo "MECHOS_UPDATE_CHECK_BEGIN"

  local pacman_count=0
  local flatpak_count=0
  local updates=""

  if command -v checkupdates >/dev/null 2>&1; then
    updates="$(checkupdates 2>/dev/null || true)"
    if [ -n "$updates" ]; then
      echo "PACMAN_UPDATES_BEGIN"
      printf '%s\n' "$updates"
      echo "PACMAN_UPDATES_END"
      pacman_count="$(printf '%s\n' "$updates" | sed '/^[[:space:]]*$/d' | wc -l)"
    fi
  else
    echo "WARN: checkupdates is unavailable."
  fi

  if command -v flatpak >/dev/null 2>&1; then
    local flatpak_updates=""
    flatpak_updates="$(
      {
        flatpak remote-ls --system --updates --columns=application 2>/dev/null || true
        flatpak remote-ls --user --updates --columns=application 2>/dev/null || true
      } | sed '/^[[:space:]]*$/d' | sort -u
    )"
    if [ -n "$flatpak_updates" ]; then
      echo "FLATPAK_UPDATES_BEGIN"
      printf '%s\n' "$flatpak_updates"
      echo "FLATPAK_UPDATES_END"
      flatpak_count="$(printf '%s\n' "$flatpak_updates" | wc -l)"
    fi
  fi

  echo "PACMAN_COUNT=$pacman_count"
  echo "FLATPAK_COUNT=$flatpak_count"
  echo "TOTAL_COUNT=$((pacman_count + flatpak_count))"
  echo "MECHOS_UPDATE_CHECK_END"
}

create_snapshot_if_possible() {
  if ! command -v snapper >/dev/null 2>&1; then
    echo "[snapshot] snapper is not installed; skipping snapshot."
    return 0
  fi

  if ! snapper -c root list >/dev/null 2>&1; then
    echo "[snapshot] No configured root Snapper profile; skipping snapshot."
    return 0
  fi

  echo "[snapshot] Creating pre-update snapshot..."
  local snap_id=""
  snap_id="$(
    snapper -c root create \
      --type single \
      --description "MechOS pre-update $(date -Is)" \
      --cleanup-algorithm number \
      --print-number 2>/dev/null
  )" || {
      echo "[snapshot] Snapshot creation failed; continuing without it."
      return 0
    }

  if [[ "$snap_id" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$snap_id" > "$STATE_DIR/last-preupdate-snapshot"
    echo "[snapshot] Pre-update snapshot $snap_id created."
  else
    echo "[snapshot] Snapshot created but its ID could not be recorded."
  fi
}

apply_updates() {
  require_installed

  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: apply requires administrator privileges."
    exit 1
  fi

  local stamp log pending packages_needing_reboot=0
  stamp="$(date +'%Y%m%d-%H%M%S')"
  log="$LOG_DIR/update-$stamp.log"
  touch "$log"
  chmod 644 "$log"

  exec > >(tee -a "$log") 2>&1

  echo "MECHOS_UPDATE_APPLY_BEGIN"
  echo "Started: $(date -Is)"

  pending="$(checkupdates 2>/dev/null || true)"
  if printf '%s\n' "$pending" | awk '{print $1}' | grep -Eq '^(linux|linux-lts|linux-zen|linux-hardened|systemd|nvidia-open|nvidia-utils|mesa)$'; then
    packages_needing_reboot=1
  fi

  create_snapshot_if_possible

  echo "[pacman] Updating Arch/MechOS packages..."
  if pacman -Syu --needed --noconfirm; then
    echo "[pacman] System package update complete."
  else
    rc=$?
    echo "FAILED pacman rc=$rc" > "$LAST_RESULT"
    if [ -s "$STATE_DIR/last-preupdate-snapshot" ]; then
      cp -f "$STATE_DIR/last-preupdate-snapshot" "$STATE_DIR/rollback-pending"
      chmod 644 "$STATE_DIR/rollback-pending" 2>/dev/null || true
      echo "[recovery] Failed update marked for rollback protection."
    fi
    printf '%s | FAILED | pacman rc=%s | %s\n' "$(date -Is)" "$rc" "$log" >> "$HISTORY"
    echo "MECHOS_UPDATE_APPLY_FAILED"
    exit "$rc"
  fi

  if command -v flatpak >/dev/null 2>&1; then
    echo "[flatpak] Updating system Flatpaks..."
    flatpak update --system -y || true
  fi

  if [ "$packages_needing_reboot" -eq 1 ] || [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
    touch "$REBOOT_MARKER"
    echo "REBOOT_REQUIRED=1"
  else
    rm -f "$REBOOT_MARKER"
    echo "REBOOT_REQUIRED=0"
  fi

  rm -f "$STATE_DIR/rollback-pending"
echo "SUCCESS $(date -Is)" > "$LAST_RESULT"
  printf '%s | SUCCESS | %s\n' "$(date -Is)" "$log" >> "$HISTORY"

  # Keep the most recent 100 history rows.
  tail -n 100 "$HISTORY" > "$HISTORY.tmp" || true
  mv -f "$HISTORY.tmp" "$HISTORY" 2>/dev/null || true
  chmod 644 "$HISTORY" "$LAST_RESULT" 2>/dev/null || true

  echo "Finished: $(date -Is)"
  echo "MECHOS_UPDATE_APPLY_END"
}

show_status() {
  require_installed
  echo "CHANNEL=stable"
  echo "REBOOT_REQUIRED=$([ -e "$REBOOT_MARKER" ] && echo 1 || echo 0)"
  echo "LAST_RESULT=$(cat "$LAST_RESULT" 2>/dev/null || echo 'No completed update yet')"
  echo "HISTORY_FILE=$HISTORY"
}

case "${1:-}" in
  check)
    check_updates
    ;;
  apply)
    apply_updates
    ;;
  status)
    show_status
    ;;
  history)
    cat "$HISTORY" 2>/dev/null || true
    ;;
  *)
    echo "Usage: mechos-update-helper {check|apply|status|history}" >&2
    exit 2
    ;;
esac
EOF

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-update-center << "PYEOF"
#!/usr/bin/env python3

import os
import subprocess
import sys
from datetime import datetime

from PyQt6.QtCore import QProcess, Qt
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import (
    QApplication, QFrame, QHBoxLayout, QLabel, QMainWindow, QMessageBox,
    QPlainTextEdit, QProgressBar, QPushButton, QScrollArea, QSizePolicy,
    QVBoxLayout, QWidget
)

HELPER = "/usr/local/bin/mechos-update-helper"

STYLE = """
QWidget {
    background: #0b0712;
    color: #f3eaff;
    font-family: Sans Serif;
}
QFrame#panel {
    background: #15101f;
    border: 1px solid #332342;
    border-radius: 14px;
}
QPushButton {
    background: #251532;
    border: 1px solid #6f3b94;
    border-radius: 10px;
    padding: 11px 18px;
    font-weight: 600;
}
QPushButton:hover {
    background: #342044;
    border-color: #a85de0;
}
QPushButton:disabled {
    color: #756c7c;
    border-color: #332b39;
    background: #17131b;
}
QPlainTextEdit {
    background: #08060c;
    border: 1px solid #332342;
    border-radius: 9px;
    padding: 8px;
    font-family: Monospace;
}
QProgressBar {
    background: #09070e;
    border: 1px solid #332342;
    border-radius: 7px;
    text-align: center;
    min-height: 18px;
}
QProgressBar::chunk {
    background: #7c3fad;
    border-radius: 6px;
}
"""

class UpdateCenter(QMainWindow):
    def __init__(self):
        super().__init__()
        self.proc = None
        self.check_buffer = ""
        self.update_count = 0
        self.setWindowTitle("MechOS Update Center")
        self.resize(1040, 720)
        self.setStyleSheet(STYLE)
        self.build_ui()
        self.load_status()
        self.check_updates()

    def panel(self):
        frame = QFrame()
        frame.setObjectName("panel")
        return frame

    def build_ui(self):
        root = QWidget()
        layout = QVBoxLayout(root)
        layout.setContentsMargins(28, 24, 28, 24)
        layout.setSpacing(18)

        top = QHBoxLayout()
        title_box = QVBoxLayout()
        title = QLabel("MECHOS UPDATE CENTER")
        title.setFont(QFont("Sans Serif", 24, QFont.Weight.Bold))
        subtitle = QLabel("System packages • Flatpaks • update history • recovery snapshot support")
        subtitle.setStyleSheet("color:#b4a5bf;")
        title_box.addWidget(title)
        title_box.addWidget(subtitle)
        top.addLayout(title_box)
        top.addStretch()

        self.channel = QLabel("CHANNEL  STABLE")
        self.channel.setStyleSheet(
            "background:#1e1328;border:1px solid #674080;border-radius:9px;"
            "padding:8px 14px;font-weight:700;"
        )
        top.addWidget(self.channel)
        layout.addLayout(top)

        cards = QHBoxLayout()

        status_panel = self.panel()
        sl = QVBoxLayout(status_panel)
        sl.addWidget(QLabel("SYSTEM STATUS"))
        self.status_label = QLabel("Checking…")
        self.status_label.setFont(QFont("Sans Serif", 18, QFont.Weight.Bold))
        sl.addWidget(self.status_label)
        self.details_label = QLabel("Looking for available updates")
        self.details_label.setStyleSheet("color:#b4a5bf;")
        self.details_label.setWordWrap(True)
        sl.addWidget(self.details_label)
        cards.addWidget(status_panel, 2)

        reboot_panel = self.panel()
        rl = QVBoxLayout(reboot_panel)
        rl.addWidget(QLabel("RESTART"))
        self.reboot_label = QLabel("Not required")
        self.reboot_label.setFont(QFont("Sans Serif", 18, QFont.Weight.Bold))
        rl.addWidget(self.reboot_label)
        self.reboot_button = QPushButton("Restart MechOS")
        self.reboot_button.clicked.connect(self.reboot)
        self.reboot_button.setEnabled(False)
        rl.addWidget(self.reboot_button)
        cards.addWidget(reboot_panel, 1)

        layout.addLayout(cards)

        action_panel = self.panel()
        al = QVBoxLayout(action_panel)

        buttons = QHBoxLayout()
        self.check_button = QPushButton("Check for Updates")
        self.check_button.clicked.connect(self.check_updates)
        buttons.addWidget(self.check_button)

        self.update_button = QPushButton("Install Updates")
        self.update_button.clicked.connect(self.apply_updates)
        self.update_button.setEnabled(False)
        buttons.addWidget(self.update_button)

        self.history_button = QPushButton("Refresh History")
        self.history_button.clicked.connect(self.load_history)
        buttons.addWidget(self.history_button)
        buttons.addStretch()
        al.addLayout(buttons)

        self.progress = QProgressBar()
        self.progress.setRange(0, 1)
        self.progress.setValue(0)
        self.progress.setFormat("Ready")
        al.addWidget(self.progress)

        layout.addWidget(action_panel)

        content = QHBoxLayout()

        log_panel = self.panel()
        ll = QVBoxLayout(log_panel)
        ll.addWidget(QLabel("UPDATE OUTPUT"))
        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        self.log.setPlaceholderText("Update information will appear here.")
        ll.addWidget(self.log)
        content.addWidget(log_panel, 2)

        history_panel = self.panel()
        hl = QVBoxLayout(history_panel)
        hl.addWidget(QLabel("RECENT UPDATE HISTORY"))
        self.history = QPlainTextEdit()
        self.history.setReadOnly(True)
        hl.addWidget(self.history)
        content.addWidget(history_panel, 1)

        layout.addLayout(content, 1)

        note = QLabel(
            "Safety: MechOS Update Center never updates the disposable Live ISO. "
            "When a root Snapper profile exists, it creates a pre-update snapshot automatically. "
            "Stable is the only active MechOS update channel in this Alpha build."
        )
        note.setWordWrap(True)
        note.setStyleSheet("color:#9d8ca9;")
        layout.addWidget(note)

        self.setCentralWidget(root)

    def append(self, text):
        if text:
            self.log.appendPlainText(text.rstrip())

    def set_busy(self, busy, label):
        self.check_button.setEnabled(not busy)
        self.update_button.setEnabled((not busy) and self.update_count > 0)
        self.history_button.setEnabled(not busy)
        if busy:
            self.progress.setRange(0, 0)
            self.progress.setFormat(label)
        else:
            self.progress.setRange(0, 1)
            self.progress.setValue(1)
            self.progress.setFormat(label)

    def run_process(self, args, mode, privileged=False):
        if self.proc is not None:
            return

        self.proc = QProcess(self)
        self.proc.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self.proc.readyReadStandardOutput.connect(self.read_output)

        if mode == "check":
            self.check_buffer = ""

        self.proc.finished.connect(lambda code, status: self.finished(mode, code))

        if privileged:
            program = "pkexec"
            pargs = [HELPER] + args
        else:
            program = HELPER
            pargs = args

        self.proc.start(program, pargs)

    def read_output(self):
        if not self.proc:
            return
        data = bytes(self.proc.readAllStandardOutput()).decode(errors="replace")
        self.append(data)
        self.check_buffer += data

    def check_updates(self):
        self.log.clear()
        self.status_label.setText("Checking…")
        self.details_label.setText("Scanning Arch packages and Flatpaks")
        self.set_busy(True, "Checking for updates…")
        self.run_process(["check"], "check", False)

    def apply_updates(self):
        if self.update_count <= 0:
            return

        response = QMessageBox.question(
            self,
            "Install MechOS Updates",
            f"Install {self.update_count} available update(s)?\n\n"
            "Administrator authorization will be requested. "
            "A pre-update snapshot will be created automatically when Snapper is configured.",
        )
        if response != QMessageBox.StandardButton.Yes:
            return

        self.log.clear()
        self.set_busy(True, "Installing updates…")
        self.status_label.setText("Updating")
        self.details_label.setText("Do not power off MechOS while packages are being installed.")
        self.run_process(["apply"], "apply", True)

    def finished(self, mode, code):
        output = self.check_buffer
        self.proc = None

        if mode == "check":
            if code == 2:
                self.status_label.setText("Live ISO")
                self.details_label.setText("Install MechOS before using Update Center.")
                self.update_count = 0
                self.set_busy(False, "Updates disabled in Live ISO")
                return

            total = 0
            for line in output.splitlines():
                if line.startswith("TOTAL_COUNT="):
                    try:
                        total = int(line.split("=", 1)[1])
                    except ValueError:
                        pass

            self.update_count = total
            if total:
                self.status_label.setText(f"{total} update(s) available")
                self.details_label.setText("Updates are ready to install.")
                self.update_button.setEnabled(True)
                self.set_busy(False, "Updates available")
            else:
                self.status_label.setText("Up to date")
                self.details_label.setText("No Arch or Flatpak updates were found.")
                self.update_button.setEnabled(False)
                self.set_busy(False, "System is current")

        elif mode == "apply":
            if code == 0:
                self.status_label.setText("Update complete")
                self.details_label.setText("MechOS finished installing available updates.")
                self.update_count = 0
                self.set_busy(False, "Update completed")
                self.load_status()
                self.load_history()
            else:
                self.status_label.setText("Update failed")
                self.details_label.setText("Review Update Output for the failure details.")
                self.set_busy(False, f"Update failed (code {code})")
                QMessageBox.warning(
                    self,
                    "MechOS Update",
                    "The update did not complete successfully. "
                    "No further update actions were started. Review the log shown in Update Center.",
                )

    def load_status(self):
        try:
            out = subprocess.check_output([HELPER, "status"], text=True, stderr=subprocess.STDOUT)
        except Exception:
            return

        reboot = "REBOOT_REQUIRED=1" in out
        self.reboot_label.setText("Required" if reboot else "Not required")
        self.reboot_button.setEnabled(reboot)
        self.load_history()

    def load_history(self):
        try:
            out = subprocess.check_output([HELPER, "history"], text=True, stderr=subprocess.STDOUT)
        except Exception:
            out = ""
        rows = [r for r in out.splitlines() if r.strip()]
        self.history.setPlainText("\n".join(reversed(rows[-30:])) if rows else "No completed updates yet.")

    def reboot(self):
        response = QMessageBox.question(
            self,
            "Restart MechOS",
            "Restart now to finish applying system updates?"
        )
        if response == QMessageBox.StandardButton.Yes:
            QProcess.startDetached("systemctl", ["reboot"])

def main():
    app = QApplication(sys.argv)
    win = UpdateCenter()
    win.show()
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
PYEOF

chmod 755 \
  /workspace/archlive/airootfs/usr/local/bin/mechos-update \
  /workspace/archlive/airootfs/usr/local/bin/mechos-update-helper \
  /workspace/archlive/airootfs/usr/local/bin/mechos-update-center

mkdir -p /workspace/archlive/airootfs/usr/share/applications
cat > /workspace/archlive/airootfs/usr/share/applications/mechos-update-center.desktop << "EOF"
[Desktop Entry]
Type=Application
Name=MechOS Update Center
Comment=Check for and install MechOS system updates
Exec=/usr/local/bin/mechos-update-center
Icon=system-software-update
Terminal=false
Categories=System;Settings;
Keywords=MechOS;Update;Upgrade;Packages;Pacman;Flatpak;
EOF


cat > /workspace/archlive/airootfs/usr/local/bin/mechos-creator-setup << "EOF"
#!/usr/bin/env bash
set -euo pipefail

mkdir -p \
  "$HOME/MechOS/Projects" \
  "$HOME/MechOS/Assets" \
  "$HOME/MechOS/Recordings" \
  "$HOME/MechOS/Exports"

echo "MechOS Creator workspace prepared."

for tool in blender obs kdenlive krita git ffmpeg; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '[OK] %s\n' "$tool"
  else
    printf '[MISSING] %s\n' "$tool"
  fi
done

if [ "${1:-}" = "--open" ]; then
  exec /usr/local/bin/mechos-creator-mode
fi
EOF


# ---------- MECHOS LIVE SETUP / RECOVERY UTILITIES ----------
cat > /workspace/archlive/airootfs/usr/local/bin/mechos-hardware-scan << "EOF"
#!/usr/bin/env bash
set +e

OUT="${1:-}"
emit() {
  printf '%s\n' "$*"
  if [ -n "$OUT" ]; then
    printf '%s\n' "$*" >> "$OUT"
  fi
}

if [ -n "$OUT" ]; then
  mkdir -p "$(dirname "$OUT")"
  : > "$OUT"
fi

emit "MECHOS HARDWARE SCAN"
emit "Generated: $(date -Is)"
emit
emit "== Boot Environment =="
if [ -d /sys/firmware/efi ]; then
  emit "Firmware: UEFI"
else
  emit "Firmware: Legacy/BIOS"
fi
emit "Virtualization: $(systemd-detect-virt 2>/dev/null || echo none)"
emit "Secure Boot: $(bootctl status 2>/dev/null | awk -F: '/Secure Boot:/ {gsub(/^[ \t]+/,"",$2); print $2; exit}' || true)"
emit
emit "== CPU =="
lscpu 2>/dev/null | grep -E 'Model name|Socket|Core|Thread|CPU\(s\)|Architecture' | while read -r l; do emit "$l"; done
emit
emit "== Memory =="
free -h 2>/dev/null | while read -r l; do emit "$l"; done
emit
emit "== GPU / Display =="
lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | while read -r l; do emit "$l"; done
emit
emit "== Network =="
lspci 2>/dev/null | grep -Ei 'Ethernet|Network|Wireless' | while read -r l; do emit "$l"; done
emit
emit "== Storage =="
lsblk -o NAME,SIZE,TYPE,FSTYPE,FSVER,LABEL,UUID,MOUNTPOINTS,MODEL 2>/dev/null | while read -r l; do emit "$l"; done
emit
emit "== USB =="
lsusb 2>/dev/null | head -n 40 | while read -r l; do emit "$l"; done
emit
emit "== Vulkan =="
timeout 8s vulkaninfo --summary 2>/dev/null | head -n 50 | while read -r l; do emit "$l"; done
emit
emit "== MechOS Notes =="
if lspci 2>/dev/null | grep -qi NVIDIA; then
  emit "GPU family: NVIDIA detected"
elif lspci 2>/dev/null | grep -Eqi 'AMD|ATI'; then
  emit "GPU family: AMD detected"
elif lspci 2>/dev/null | grep -qi Intel; then
  emit "GPU family: Intel graphics detected"
else
  emit "GPU family: unknown / virtual"
fi
emit "Scan complete."
EOF

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-recovery-helper << "EOF"
#!/usr/bin/env bash
set -euo pipefail

MNT="/mnt/mechos-recovery"

cleanup_mounts() {
  umount -R "$MNT" 2>/dev/null || true
  rm -rf "$MNT" 2>/dev/null || true
}

trap cleanup_mounts EXIT

mount_root() {
  local dev="$1"
  local mode="${2:-rw}"
  cleanup_mounts
  mkdir -p "$MNT"

  local opts=""
  [ "$mode" = "ro" ] && opts="-o ro"

  if mount $opts "$dev" "$MNT" 2>/dev/null; then
    if [ -f "$MNT/etc/os-release" ]; then
      return 0
    fi
    umount "$MNT" 2>/dev/null || true
  fi

  # Common Archinstall Btrfs root layout.
  if [ "$(lsblk -no FSTYPE "$dev" 2>/dev/null || true)" = "btrfs" ]; then
    local bopts="subvol=@"
    [ "$mode" = "ro" ] && bopts="ro,subvol=@"
    if mount -o "$bopts" "$dev" "$MNT" 2>/dev/null && [ -f "$MNT/etc/os-release" ]; then
      return 0
    fi
  fi

  echo "Unable to mount an installed root filesystem from $dev" >&2
  return 1
}

resolve_fstab_source() {
  local src="$1"
  case "$src" in
    UUID=*) blkid -U "${src#UUID=}" 2>/dev/null || true ;;
    PARTUUID=*) blkid -t "PARTUUID=${src#PARTUUID=}" -o device 2>/dev/null | head -n1 ;;
    LABEL=*) blkid -L "${src#LABEL=}" 2>/dev/null || true ;;
    /dev/*) printf '%s\n' "$src" ;;
    *) printf '%s\n' "" ;;
  esac
}

mount_target_esp() {
  local provided="${1:-}"
  local esp_mp=""
  local esp_src=""

  # Prefer the target's own fstab mapping.
  while read -r src mp fs rest; do
    case "$mp:$fs" in
      /efi:vfat|/boot/efi:vfat|/boot:vfat|/efi:fat|/boot/efi:fat|/boot:fat)
        esp_mp="$mp"
        esp_src="$(resolve_fstab_source "$src")"
        break
        ;;
    esac
  done < <(grep -Ev '^[[:space:]]*(#|$)' "$MNT/etc/fstab" 2>/dev/null || true)

  if [ -n "$provided" ]; then
    esp_src="$provided"
  fi
  [ -n "$esp_mp" ] || esp_mp="/boot"

  if [ -n "$esp_src" ]; then
    mkdir -p "$MNT$esp_mp"
    if ! mountpoint -q "$MNT$esp_mp"; then
      mount "$esp_src" "$MNT$esp_mp"
    fi
  fi

  printf '%s\n' "$esp_mp"
}

scan_roots() {
  local tmp="/tmp/mechos-root-scan"
  mkdir -p "$tmp"

  while read -r dev type fs; do
    [ "$type" = "part" ] || [ "$type" = "lvm" ] || [ "$type" = "crypt" ] || continue
    case "$fs" in
      ext4|btrfs|xfs|f2fs) ;;
      *) continue ;;
    esac

    cleanup_mounts
    mkdir -p "$MNT"

    if mount -o ro "$dev" "$MNT" 2>/dev/null; then
      :
    elif [ "$fs" = "btrfs" ] && mount -o ro,subvol=@ "$dev" "$MNT" 2>/dev/null; then
      :
    else
      continue
    fi

    if [ -f "$MNT/etc/os-release" ]; then
      os="$(. "$MNT/etc/os-release"; printf '%s' "${PRETTY_NAME:-${NAME:-Linux}}")"
      home_line="$(awk '$2=="/home" {print $1" "$3" "$4; exit}' "$MNT/etc/fstab" 2>/dev/null || true)"
      mechos="no"
      [ -f "$MNT/etc/mechos-release" ] && mechos="yes"
      printf '%s|%s|%s|%s|%s\n' "$dev" "$fs" "$os" "$mechos" "${home_line:-none}"
    fi

    cleanup_mounts
  done < <(lsblk -prno NAME,TYPE,FSTYPE)
}

scan_esps() {
  while read -r dev type fs label size; do
    [ "$type" = "part" ] || continue
    case "$fs" in
      vfat|fat|fat32) printf '%s|%s|%s|%s\n' "$dev" "$fs" "${label:-EFI}" "$size" ;;
    esac
  done < <(lsblk -prno NAME,TYPE,FSTYPE,LABEL,SIZE)
}

repair_boot() {
  local rootdev="$1"
  local espdev="${2:-}"

  mount_root "$rootdev" rw
  local esp_mp
  esp_mp="$(mount_target_esp "$espdev")"

  echo "Mounted root at $MNT"
  echo "EFI mountpoint: $esp_mp"

  # Refresh initramfs first.
  arch-chroot "$MNT" mkinitcpio -P

  if [ -f "$MNT$esp_mp/loader/loader.conf" ] || \
     [ -d "$MNT$esp_mp/EFI/systemd" ] || \
     [ -d "$MNT/boot/loader" ]; then
    echo "Detected systemd-boot."
    arch-chroot "$MNT" bootctl install
  elif [ -f "$MNT/boot/grub/grub.cfg" ] || arch-chroot "$MNT" pacman -Q grub >/dev/null 2>&1; then
    echo "Detected GRUB."
    if [ -d /sys/firmware/efi ]; then
      arch-chroot "$MNT" grub-install \
        --target=x86_64-efi \
        --efi-directory="$esp_mp" \
        --bootloader-id=MechOS
    else
      parent="$(lsblk -no PKNAME "$rootdev" 2>/dev/null | head -n1)"
      [ -n "$parent" ] || {
        echo "Could not determine BIOS boot disk." >&2
        return 1
      }
      arch-chroot "$MNT" grub-install "/dev/$parent"
    fi
    arch-chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg
  else
    echo "No supported installed bootloader was detected." >&2
    return 1
  fi

  echo "Boot repair completed."
}

show_logs() {
  local rootdev="${1:-}"
  echo "=== Live installer logs ==="
  for f in \
    /var/log/mechos-installer.log \
    /var/log/mechos-installer-hardware.log \
    /var/log/archinstall/install.log \
    /tmp/mechos-installer-http.log; do
    if [ -f "$f" ]; then
      echo
      echo "----- $f -----"
      tail -n 250 "$f"
    fi
  done

  if [ -n "$rootdev" ]; then
    mount_root "$rootdev" ro || return 0
    for f in \
      "$MNT/var/log/mechos-postinstall.log" \
      "$MNT/var/log/mechos-update.log" \
      "$MNT/var/lib/mechos/update-history.log"; do
      if [ -f "$f" ]; then
        echo
        echo "----- ${f#"$MNT"} -----"
        tail -n 250 "$f"
      fi
    done
  fi
}

rollback_failed_update() {
  local rootdev="$1"
  mount_root "$rootdev" rw

  local marker="$MNT/var/lib/mechos/rollback-pending"
  if [ ! -s "$marker" ]; then
    echo "No failed-update rollback marker exists." >&2
    return 2
  fi

  local snap
  snap="$(head -n1 "$marker" | tr -cd '0-9')"
  [ -n "$snap" ] || {
    echo "Rollback marker is invalid." >&2
    return 1
  }

  if [ "$(findmnt -n -o FSTYPE -T "$MNT" 2>/dev/null || true)" != "btrfs" ]; then
    echo "Automatic rollback is available only for a Btrfs root filesystem." >&2
    return 3
  fi

  if ! arch-chroot "$MNT" snapper -c root list >/dev/null 2>&1; then
    echo "The target does not have a working Snapper root configuration." >&2
    return 4
  fi

  echo "Rolling the target back to pre-update snapshot $snap..."
  arch-chroot "$MNT" snapper -c root rollback "$snap"
  arch-chroot "$MNT" mkinitcpio -P || true

  mv "$marker" "$marker.applied-$(date +%s)"
  echo "Rollback prepared. Reboot the installed system."
}

case "${1:-}" in
  scan-roots) scan_roots ;;
  scan-esps) scan_esps ;;
  repair-boot)
    [ "$#" -ge 2 ] || { echo "Usage: $0 repair-boot ROOTDEV [ESPDEV]" >&2; exit 2; }
    repair_boot "$2" "${3:-}"
    ;;
  logs) show_logs "${2:-}" ;;
  rollback)
    [ "$#" -eq 2 ] || { echo "Usage: $0 rollback ROOTDEV" >&2; exit 2; }
    rollback_failed_update "$2"
    ;;
  *)
    echo "Usage: $0 {scan-roots|scan-esps|repair-boot|logs|rollback}" >&2
    exit 2
    ;;
esac
EOF

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-preserve-home << "EOF"
#!/usr/bin/env bash
set -euo pipefail

PLAN="/tmp/mechos-preserve-home-plan.txt"
: > "$PLAN"

cat | tee -a "$PLAN" <<'TEXT'
MECHOS REINSTALL — PRESERVE HOME ASSISTANT
==========================================

This mode does NOT automatically format or repartition disks.

It scans existing Linux installations and reports how /home is currently
mounted. The final partition choices remain visible in Archinstall.

For a safe preserve-home reinstall:
  • Use Manual partitioning.
  • Reuse the existing /home partition or @home subvolume.
  • Set its mountpoint to /home.
  • DO NOT select format/wipe for that home storage.
  • Only format the intended MechOS root partition.
  • Review Archinstall's final disk summary before accepting it.

Detected installations:
TEXT

/usr/local/bin/mechos-recovery-helper scan-roots | tee -a "$PLAN" || true

echo | tee -a "$PLAN"
echo "Plan saved to $PLAN" | tee -a "$PLAN"
echo
read -rp "Press Enter to open the MechOS/Archinstall partition screen, or Ctrl+C to cancel..."

exec /usr/local/bin/mechos-install --terminal --preserve-home
EOF

chmod 755 \
  /workspace/archlive/airootfs/usr/local/bin/mechos-hardware-scan \
  /workspace/archlive/airootfs/usr/local/bin/mechos-recovery-helper \
  /workspace/archlive/airootfs/usr/local/bin/mechos-preserve-home

cat > /workspace/archlive/airootfs/usr/local/libexec/mechos-gaming-setup-helper << "EOF"
#!/usr/bin/env bash
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Administrator privileges required." >&2; exit 1; }
[ "\${1:-}" = "install-steam" ] || { echo "Usage: mechos-gaming-setup-helper install-steam" >&2; exit 2; }

LOG="/var/log/mechos-gaming-setup.log"
mkdir -p /var/log
exec > >(tee -a "$LOG") 2>&1
echo "=== MechOS Steam setup $(date --iso-8601=seconds) ==="

if ! grep -q '^[[:space:]]*\[multilib\]' /etc/pacman.conf; then
  if grep -q '^[[:space:]]*#\[multilib\]' /etc/pacman.conf; then
    sed -i '/^[[:space:]]*#\[multilib\]/,/^[[:space:]]*#Include = \/etc\/pacman.d\/mirrorlist/ s/^[[:space:]]*#//' /etc/pacman.conf
  else
    printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf
  fi
fi

if command -v snapper >/dev/null 2>&1 && snapper list-configs 2>/dev/null | awk '{print $1}' | grep -qx root; then
  snapper -c root create --type single --description "Before MechOS Steam setup" || true
fi

packages=(steam gamemode lib32-gamemode mangohud lib32-mangohud vulkan-tools mesa lib32-mesa)
gpu="$(lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' || true)"
grep -Eqi 'AMD|ATI' <<<"$gpu" && packages+=(vulkan-radeon lib32-vulkan-radeon)
grep -Eqi 'Intel' <<<"$gpu" && packages+=(vulkan-intel lib32-vulkan-intel)
grep -Eqi 'NVIDIA' <<<"$gpu" && packages+=(nvidia-utils lib32-nvidia-utils)

# A full upgrade avoids creating an unsupported partial-upgrade state on Arch.
pacman -Syu --needed --noconfirm "\${packages[@]}"
ldconfig

echo
echo "Steam and gaming dependencies installed."
echo "Re-run dependency validation in MechOS Post-Install."
EOF
chmod 755 /workspace/archlive/airootfs/usr/local/libexec/mechos-gaming-setup-helper

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-postinstall << "PYEOF"
#!/usr/bin/env python3
import shutil
import subprocess
import sys
from pathlib import Path

from PyQt6.QtCore import QTimer
from PyQt6.QtWidgets import (
    QApplication, QFrame, QHBoxLayout, QLabel, QMainWindow, QMessageBox,
    QPushButton, QTabWidget, QVBoxLayout, QWidget
)

HELPER="/usr/local/libexec/mechos-gaming-setup-helper"
FIRST_RUN=Path.home()/".config/mechos/postinstall-seen"

STYLE="""
QWidget{background:#07080d;color:#f6f2fb;font-family:Sans Serif}
QFrame#panel{background:#0e0f16;border:1px solid #2b2135;border-radius:12px}
QLabel#title{font-size:30px;font-weight:900;color:white}
QLabel#purple{font-size:16px;font-weight:800;color:#c273ff}
QLabel#muted{color:#aaa1b4}
QPushButton{background:#351750;border:1px solid #704198;border-radius:8px;padding:10px;color:#f0dfff;font-weight:700}
QPushButton:hover{background:#5a2381}
QTabWidget::pane{border:1px solid #2b2135}
QTabBar::tab{background:#11131b;padding:11px 20px}
QTabBar::tab:selected{background:#6928b7}
"""

def run(cmd):
    return subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)

def installed(package):
    return run(["pacman","-Q",package]).returncode==0

def multilib_enabled():
    try:
        return any(line.strip()=="[multilib]" for line in Path("/etc/pacman.conf").read_text(errors="ignore").splitlines())
    except OSError:
        return False

def gpu_text():
    result=run(["bash","-lc","lspci | grep -Ei 'VGA|3D|Display' | sed 's/^[^ ]* //'"])
    return result.stdout.strip() or "No GPU detected"

def dependency_results():
    gpu=gpu_text().lower()
    checks=[
      ("Multilib repository",multilib_enabled(),"Steam and 32-bit packages"),
      ("Steam",installed("steam"),"Native Arch package"),
      ("GameMode",installed("gamemode") and installed("lib32-gamemode"),"64-bit and 32-bit runtime"),
      ("MangoHud",installed("mangohud") and installed("lib32-mangohud"),"Performance overlay"),
      ("Vulkan tools",installed("vulkan-tools"),"Vulkan diagnostics"),
      ("Mesa runtime",installed("mesa") and installed("lib32-mesa"),"64-bit and 32-bit graphics runtime"),
    ]
    if "amd" in gpu or "ati" in gpu:
        checks.append(("AMD Vulkan",installed("vulkan-radeon") and installed("lib32-vulkan-radeon"),"64-bit and 32-bit AMD driver"))
    if "intel" in gpu:
        checks.append(("Intel Vulkan",installed("vulkan-intel") and installed("lib32-vulkan-intel"),"64-bit and 32-bit Intel driver"))
    if "nvidia" in gpu:
        checks.append(("NVIDIA Vulkan",installed("nvidia-utils") and installed("lib32-nvidia-utils"),"64-bit and 32-bit NVIDIA driver"))
    checks.append(("32-bit Vulkan loader",Path("/usr/lib32/libvulkan.so.1").exists(),"Required by many Proton games"))
    return checks

class PostInstall(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MechOS Post-Install")
        self.resize(1050,700)
        self.setMinimumSize(850,580)
        self.setStyleSheet(STYLE)
        root=QWidget(); self.setCentralWidget(root)
        outer=QVBoxLayout(root)
        title=QLabel("MECHOS POST-INSTALL"); title.setObjectName("title"); outer.addWidget(title)
        subtitle=QLabel("Finish configuring your installed MechOS system."); subtitle.setObjectName("muted"); outer.addWidget(subtitle)
        self.tabs=QTabWidget(); outer.addWidget(self.tabs,1)
        self.tabs.addTab(self.overview_page(),"Overview")
        self.tabs.addTab(self.gaming_page(),"Gaming Setup")
        self.tabs.currentChanged.connect(lambda index:self.validate() if index==1 else None)
        QTimer.singleShot(350,self.validate)

    def overview_page(self):
        page=QWidget(); layout=QVBoxLayout(page)
        heading=QLabel("POST-INSTALL OVERVIEW"); heading.setObjectName("purple"); layout.addWidget(heading)
        note=QLabel("Steam is installed automatically with MechOS. Gaming Setup validates Steam, multilib, Vulkan and the required 32-bit GPU libraries. Creator packages remain available in the Creator Mode App Store.")
        note.setObjectName("muted"); note.setWordWrap(True); layout.addWidget(note)
        gaming=QPushButton("Open Gaming Setup"); gaming.clicked.connect(lambda:self.tabs.setCurrentIndex(1)); layout.addWidget(gaming)
        creator=QPushButton("Open Creator Mode App Store"); creator.clicked.connect(lambda:subprocess.Popen(["/usr/local/bin/mechos-creator-mode"])); layout.addWidget(creator)
        updates=QPushButton("Open Update Center"); updates.clicked.connect(lambda:subprocess.Popen(["/usr/local/bin/mechos-update-center"])); layout.addWidget(updates)
        layout.addStretch(); return page

    def gaming_page(self):
        page=QWidget(); layout=QVBoxLayout(page)
        heading=QLabel("GAMING SETUP"); heading.setObjectName("purple"); layout.addWidget(heading)
        self.gpu=QLabel(); self.gpu.setObjectName("muted"); self.gpu.setWordWrap(True); layout.addWidget(self.gpu)
        note=QLabel("Install native Steam and automatically configure the matching 64-bit and 32-bit Vulkan dependencies for the detected GPU.")
        note.setObjectName("muted"); note.setWordWrap(True); layout.addWidget(note)
        actions=QHBoxLayout()
        self.install_button=QPushButton("Repair Steam Setup"); self.install_button.clicked.connect(self.install_steam)
        validate=QPushButton("Validate Dependencies"); validate.clicked.connect(self.validate)
        launch=QPushButton("Launch Steam"); launch.clicked.connect(self.launch_steam)
        actions.addWidget(self.install_button); actions.addWidget(validate); actions.addWidget(launch); layout.addLayout(actions)
        panel=QFrame(); panel.setObjectName("panel"); self.results=QVBoxLayout(panel); layout.addWidget(panel)
        self.summary=QLabel(); self.summary.setWordWrap(True); layout.addWidget(self.summary)
        layout.addStretch(); return page

    def validate(self):
        self.gpu.setText("Detected GPU:\\n"+gpu_text())
        while self.results.count():
            item=self.results.takeAt(0)
            if item.widget(): item.widget().deleteLater()
        checks=dependency_results()
        passed=0
        for name,ok,detail in checks:
            row=QLabel(("✓  " if ok else "✗  ")+name+" — "+detail)
            row.setStyleSheet("color:#6ee7a8;font-weight:750" if ok else "color:#ff8a9b;font-weight:750")
            self.results.addWidget(row); passed+=int(ok)
        ready=passed==len(checks)
        self.summary.setStyleSheet("color:#6ee7a8;font-weight:750" if ready else "color:#ff8a9b;font-weight:750")
        self.summary.setText("Gaming dependencies are ready." if ready else f"{len(checks)-passed} gaming dependency check(s) need attention.")
        self.install_button.setText("Repair Steam Setup" if installed("steam") else "Install Missing Steam")

    def install_steam(self):
        if QMessageBox.question(self,"Repair Steam Setup","Validate and repair native Steam and the dependencies for this GPU?\\n\\nA system update and administrator approval are required.")!=QMessageBox.StandardButton.Yes:
            return
        subprocess.Popen(["konsole","-e","bash","-lc",f"pkexec {HELPER} install-steam; rc=$?; echo; echo Setup exit code: $rc; read -rp 'Press Enter to close...'"])
        QTimer.singleShot(12000,self.validate)

    def launch_steam(self):
        if shutil.which("steam"): subprocess.Popen(["steam"])
        else: QMessageBox.information(self,"MechOS Post-Install","Steam is missing from this installation. Select Install Missing Steam to repair it.")

    def closeEvent(self,event):
        FIRST_RUN.parent.mkdir(parents=True,exist_ok=True)
        FIRST_RUN.touch()
        super().closeEvent(event)

if "--first-run" in sys.argv and FIRST_RUN.exists():
    raise SystemExit(0)
if Path("/run/archiso/bootmnt").exists():
    raise SystemExit(0)
app=QApplication(sys.argv); app.setApplicationName("MechOS Post-Install")
window=PostInstall(); window.show(); sys.exit(app.exec())
PYEOF
chmod 755 /workspace/archlive/airootfs/usr/local/bin/mechos-postinstall

cat > /workspace/archlive/airootfs/usr/share/applications/mechos-postinstall.desktop << "EOF"
[Desktop Entry]
Type=Application
Name=MechOS Post-Install
Comment=Configure gaming and creator software
Exec=/usr/local/bin/mechos-postinstall
Icon=mechos
Categories=System;Settings;
Terminal=false
Keywords=MechOS;Post-Install;Gaming;Steam;Vulkan;
EOF

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-firstboot << "EOF"
#!/usr/bin/env bash
set -euo pipefail

MARKER="/var/lib/mechos/firstboot.done"

if [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null; then
  echo "Live ISO detected; first-boot setup is for installed MechOS."
  exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
  exec sudo "$0" "$@"
fi

mkdir -p /var/lib/mechos /var/log

systemctl enable NetworkManager.service 2>/dev/null || true
systemctl enable bluetooth.service 2>/dev/null || true
systemctl enable fstrim.timer 2>/dev/null || true
systemctl enable irqbalance.service 2>/dev/null || true
systemctl enable power-profiles-daemon.service 2>/dev/null || true
systemctl enable switcheroo-control.service 2>/dev/null || true

/usr/local/bin/mechos-gpu-setup > /var/log/mechos-gpu-detect.log 2>&1 || true
touch "$MARKER"

echo "MechOS first-boot setup complete."
EOF

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-live-welcome << "EOF"
#!/usr/bin/env bash
set -euo pipefail

if ! { [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null; }; then
  exit 0
fi

# KDE Plasma is the Live ISO desktop. The branded setup window is launched
# on top of Plasma after login; closing it leaves a completely usable desktop.
if grep -q 'mechos.recovery=1' /proc/cmdline 2>/dev/null; then
  exec /usr/local/bin/mechos-recovery-center
fi

# Give Plasma a moment to finish panel/compositor startup.
sleep 2
exec /usr/local/bin/mechos-live-setup
EOF


# Python is required by the cumulative integration's embedded GUI validators.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[MechOS v0.3.0] ERROR: python3 missing after bootstrap package install." >&2
  exit 66
fi

# MECHOS_CURRENT_INTEGRATION_EARLY
# Apply the cumulative MechOS runtime/installer integration.
bash /workspace/scripts/mechos-current-integration.sh early

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-install << "EOF"
#!/usr/bin/env bash
set -euo pipefail

PAYLOAD_DIR="/usr/share/mechos/install-payload"
CONFIG="$PAYLOAD_DIR/archinstall-mechos.json"
PORT=45811
LOG="/var/log/mechos-installer.log"
HWLOG="/var/log/mechos-installer-hardware.log"
PRESERVE_HOME=0
[[ " $* " == *" --preserve-home "* ]] && PRESERVE_HOME=1

if [ "${1:-}" != "--terminal" ] && [ ! -t 1 ]; then
  exec konsole -e bash -lc \
    'sudo /usr/local/bin/mechos-install --terminal; rc=$?; echo; echo "Installer exit code: $rc"; read -rp "Press Enter to close..."'
fi

if [ "$(id -u)" -ne 0 ]; then
  exec sudo "$0" "$@"
fi

mkdir -p /var/log
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1
/usr/local/bin/mechos-hardware-scan "$HWLOG" || true
echo "Hardware scan saved to $HWLOG"

if ! command -v archinstall >/dev/null 2>&1; then
  echo "archinstall is not available in this image." >&2
  exit 1
fi

for f in \
  "$PAYLOAD_DIR/mechos-rootfs.tar.zst" \
  "$PAYLOAD_DIR/mechos-postinstall-target" \
  "$CONFIG"; do
  if [ ! -f "$f" ]; then
    echo "Missing MechOS installer payload: $f" >&2
    exit 1
  fi
done

cat <<'WARN'

============================================================
                   MECHOS ALPHA INSTALLER
============================================================

Archinstall will handle disk selection, formatting, users,
bootloader and base Arch installation.

After Archinstall finishes its base install, MechOS will
automatically deploy:
  - MechScope Gaming Mode
  - Creator Mode
  - Desktop Mode integration
  - Performance Center
  - GPU setup
  - MechOS boot graphics / Plymouth
  - MechOS updater and first-boot services

IMPORTANT:
  Installing an operating system can erase a selected disk.
  Read Archinstall's disk summary carefully before confirming.
  For Alpha testing, use a VM or spare drive first.

============================================================
WARN

if command -v kdialog >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  kdialog --title "Install MechOS Alpha" --warningcontinuecancel \
    "MechOS uses Archinstall for disk setup.

The selected disk can be erased if you choose a wipe/format option.

Use a VM or spare drive for Alpha testing and verify the final disk summary before confirming." \
    || exit 0
fi

# Archinstall's custom post-install commands execute inside the new system.
# A tiny loopback-only HTTP server lets that chroot retrieve the MechOS
# payload from the live ISO without requiring an external download.
python3 -m http.server "$PORT" \
  --bind 127.0.0.1 \
  --directory "$PAYLOAD_DIR" \
  >/tmp/mechos-installer-http.log 2>&1 &
SERVER_PID=$!

cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

sleep 1
curl -fsS "http://127.0.0.1:${PORT}/mechos-postinstall-target" >/dev/null

echo
echo "Starting guided Archinstall..."
echo "MechOS post-install integration is loaded."
if [ "$PRESERVE_HOME" -eq 1 ]; then
  echo "PRESERVE-HOME MODE: choose Manual partitioning and do not format /home."
  echo "Review /tmp/mechos-preserve-home-plan.txt if it was created."
fi
echo

# Do NOT use --silent. The user still chooses the disk, filesystem,
# bootloader, username/password and confirms all destructive actions.
archinstall --config "$CONFIG"

echo
echo "Archinstall exited."
echo "If installation completed successfully, the MechOS post-install"
echo "stage should have created /var/lib/mechos/installed in the new system."
EOF

chmod 755 \
  /workspace/archlive/airootfs/usr/local/bin/mechos-firstboot \
  /workspace/archlive/airootfs/usr/local/bin/mechos-install \
  /workspace/archlive/airootfs/usr/local/bin/mechos-live-welcome \
  /workspace/archlive/airootfs/usr/local/bin/mechos-session-select \
  /workspace/archlive/airootfs/usr/local/bin/mechos-gpu-setup \
  /workspace/archlive/airootfs/usr/local/bin/mechos-update \
  /workspace/archlive/airootfs/usr/local/bin/mechos-creator-setup

# Live welcome autostart only does anything on an ArchISO boot.
mkdir -p /workspace/archlive/airootfs/etc/xdg/autostart
mkdir -p /workspace/archlive/airootfs/home/mechos/Desktop
cat > /workspace/archlive/airootfs/home/mechos/Desktop/Install-MechOS.desktop << "EOF"
[Desktop Entry]
Type=Application
Name=Install MechOS
Exec=/usr/local/bin/mechos-live-setup
Icon=mechos
Terminal=false
EOF
cat > /workspace/archlive/airootfs/home/mechos/Desktop/MechOS-Recovery.desktop << "EOF"
[Desktop Entry]
Type=Application
Name=MechOS Recovery
Exec=/usr/local/bin/mechos-recovery-center
Icon=system-rescue
Terminal=false
EOF
cat > /workspace/archlive/airootfs/home/mechos/Desktop/Creator-Mode.desktop << "EOF"
[Desktop Entry]
Type=Application
Name=MechOS Creator Mode
Exec=/usr/local/bin/mechos-creator-mode
Icon=applications-development
Terminal=false
EOF
chmod 755 \
  /workspace/archlive/airootfs/home/mechos/Desktop/Install-MechOS.desktop \
  /workspace/archlive/airootfs/home/mechos/Desktop/MechOS-Recovery.desktop \
  /workspace/archlive/airootfs/home/mechos/Desktop/Creator-Mode.desktop

cat > /workspace/archlive/airootfs/etc/xdg/autostart/mechos-live-welcome.desktop << "EOF"
[Desktop Entry]
Type=Application
Name=MechOS Live Welcome
Exec=/usr/local/bin/mechos-live-welcome
OnlyShowIn=KDE;
X-KDE-autostart-after=panel
Terminal=false
EOF

cat > /workspace/archlive/airootfs/etc/xdg/autostart/mechos-postinstall.desktop << "EOF"
[Desktop Entry]
Type=Application
Name=MechOS Post-Install
Exec=/usr/local/bin/mechos-postinstall --first-run
OnlyShowIn=KDE;
X-KDE-autostart-after=panel
Terminal=false
EOF

# Installed-system first-boot service. The script exits immediately on the live ISO.
mkdir -p /workspace/archlive/airootfs/etc/systemd/system
cat > /workspace/archlive/airootfs/etc/systemd/system/mechos-firstboot.service << "EOF"
[Unit]
Description=MechOS first-boot configuration
After=network.target
ConditionPathExists=!/var/lib/mechos/firstboot.done

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mechos-firstboot

[Install]
WantedBy=multi-user.target
EOF


# ---------- GRAPHICAL MECHOS SETUP + RECOVERY CENTER ----------
cat > /workspace/archlive/airootfs/usr/local/bin/mechos-recovery-center << "PYEOF"
#!/usr/bin/env python3
import os
import subprocess
import sys

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import (
    QApplication, QComboBox, QFrame, QHBoxLayout, QLabel, QMainWindow,
    QMessageBox, QPlainTextEdit, QPushButton, QVBoxLayout, QWidget
)

HELPER = "/usr/local/bin/mechos-recovery-helper"
STYLE = """
QWidget { background:#09060f; color:#f3eaff; font-family:Sans Serif; }
QFrame#panel { background:#15101f; border:1px solid #39254a; border-radius:14px; }
QPushButton { background:#251533; border:1px solid #714394; border-radius:10px;
              padding:11px 16px; font-weight:600; }
QPushButton:hover { background:#352047; border-color:#a45bd5; }
QComboBox,QPlainTextEdit { background:#0b0810; border:1px solid #39254a;
                          border-radius:8px; padding:8px; }
"""

class Recovery(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MechOS Recovery Center")
        self.resize(1050, 720)
        self.setStyleSheet(STYLE)
        self.roots = []
        self.esps = []
        self.build_ui()
        self.rescan()

    def build_ui(self):
        root = QWidget()
        outer = QVBoxLayout(root)
        outer.setContentsMargins(28,24,28,24)
        outer.setSpacing(15)

        title = QLabel("MECHOS RECOVERY CENTER")
        title.setFont(QFont("Sans Serif", 24, QFont.Weight.Bold))
        outer.addWidget(title)
        sub = QLabel("Repair boot • inspect installations • recover failed updates • view logs")
        sub.setStyleSheet("color:#b5a4c1;")
        outer.addWidget(sub)

        p = QFrame(); p.setObjectName("panel")
        pl = QVBoxLayout(p)
        row = QHBoxLayout()
        row.addWidget(QLabel("Installed system"))
        self.root_combo = QComboBox()
        row.addWidget(self.root_combo, 2)
        row.addWidget(QLabel("EFI partition"))
        self.esp_combo = QComboBox()
        row.addWidget(self.esp_combo, 2)
        rescan = QPushButton("Rescan")
        rescan.clicked.connect(self.rescan)
        row.addWidget(rescan)
        pl.addLayout(row)
        outer.addWidget(p)

        actions = QHBoxLayout()
        repair = QPushButton("Repair Boot")
        repair.clicked.connect(self.repair_boot)
        actions.addWidget(repair)
        rollback = QPushButton("Rollback Failed Update")
        rollback.clicked.connect(self.rollback)
        actions.addWidget(rollback)
        logs = QPushButton("Load Install / Update Logs")
        logs.clicked.connect(self.load_logs)
        actions.addWidget(logs)
        hw = QPushButton("Hardware Scan")
        hw.clicked.connect(self.hardware)
        actions.addWidget(hw)
        outer.addLayout(actions)

        self.output = QPlainTextEdit()
        self.output.setReadOnly(True)
        self.output.setPlaceholderText("Recovery output appears here.")
        outer.addWidget(self.output, 1)

        note = QLabel(
            "Boot Repair does not repartition or format disks. Rollback is offered only when "
            "MechOS recorded a valid pre-update Snapper snapshot on a Btrfs installation."
        )
        note.setWordWrap(True)
        note.setStyleSheet("color:#a995b6;")
        outer.addWidget(note)
        self.setCentralWidget(root)

    def run(self, args, privileged=False):
        cmd = [HELPER] + args
        if privileged:
            cmd = ["sudo", "-n"] + cmd
        try:
            out = subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT)
            self.output.setPlainText(out)
            return True
        except subprocess.CalledProcessError as e:
            self.output.setPlainText(e.output or str(e))
            return False

    def rescan(self):
        self.root_combo.clear(); self.esp_combo.clear()
        self.roots = []
        self.esps = []
        try:
            out = subprocess.check_output([HELPER, "scan-roots"], text=True)
            for line in out.splitlines():
                if not line.strip(): continue
                fields = line.split("|")
                dev = fields[0]
                self.roots.append(dev)
                desc = " • ".join(fields[:4])
                self.root_combo.addItem(desc, dev)
        except Exception as e:
            self.output.setPlainText(str(e))

        try:
            out = subprocess.check_output([HELPER, "scan-esps"], text=True)
            for line in out.splitlines():
                if not line.strip(): continue
                fields = line.split("|")
                dev = fields[0]
                self.esps.append(dev)
                self.esp_combo.addItem(" • ".join(fields), dev)
        except Exception:
            pass

        self.esp_combo.insertItem(0, "Auto-detect from installed fstab", "")
        self.output.setPlainText(
            f"Detected {len(self.roots)} Linux root candidate(s) and "
            f"{len(self.esps)} EFI partition candidate(s)."
        )

    def selected_root(self):
        return self.root_combo.currentData() or ""

    def selected_esp(self):
        return self.esp_combo.currentData() or ""

    def repair_boot(self):
        root = self.selected_root()
        if not root:
            QMessageBox.warning(self, "MechOS Recovery", "Select an installed system first.")
            return
        if QMessageBox.question(
            self, "Repair boot",
            f"Repair the boot files for:\n{root}\n\n"
            "This rebuilds initramfs and reinstalls the detected bootloader. "
            "It does not format partitions."
        ) != QMessageBox.StandardButton.Yes:
            return
        args = ["repair-boot", root]
        esp = self.selected_esp()
        if esp: args.append(esp)
        self.run(args, True)

    def rollback(self):
        root = self.selected_root()
        if not root:
            QMessageBox.warning(self, "MechOS Recovery", "Select an installed system first.")
            return
        if QMessageBox.question(
            self, "Rollback failed update",
            "Use the pre-update snapshot recorded by MechOS?\n\n"
            "This is available only on compatible Btrfs/Snapper installations."
        ) != QMessageBox.StandardButton.Yes:
            return
        self.run(["rollback", root], True)

    def load_logs(self):
        root = self.selected_root()
        args = ["logs"]
        if root: args.append(root)
        self.run(args, False)

    def hardware(self):
        try:
            out = subprocess.check_output(
                ["/usr/local/bin/mechos-hardware-scan"], text=True, stderr=subprocess.STDOUT
            )
            self.output.setPlainText(out)
        except Exception as e:
            self.output.setPlainText(str(e))

def main():
    app = QApplication(sys.argv)
    w = Recovery()
    w.show()
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
PYEOF

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-live-setup << "PYEOF"
#!/usr/bin/env python3
import os
import re
import subprocess
import sys

from PyQt6.QtCore import Qt, QSize
from PyQt6.QtGui import QFont, QIcon, QPixmap
from PyQt6.QtWidgets import (
    QApplication, QButtonGroup, QFrame, QHBoxLayout, QLabel, QListWidget,
    QListWidgetItem, QMainWindow, QMessageBox, QProgressBar, QPushButton,
    QRadioButton, QScrollArea, QSizePolicy, QStackedWidget, QVBoxLayout, QWidget
)

BRAND = "/usr/share/mechos/branding/mechos-installer-reference.png"
LOGO = "/usr/share/mechos/branding/mechos-logo.png"

STYLE = """
QWidget {
    background: #060913;
    color: #f3f7ff;
    font-family: Sans Serif;
}
QFrame#outerFrame {
    background: rgba(4,8,18,245);
    border: 1px solid #17345c;
    border-radius: 18px;
}
QFrame#panel {
    background: rgba(7,13,29,235);
    border: 1px solid #1a3150;
    border-radius: 12px;
}
QFrame#glowPanel {
    background: rgba(7,13,29,238);
    border: 2px solid #266dff;
    border-radius: 12px;
}
QLabel#accent {
    color: #47c9ff;
    font-weight: 700;
}
QLabel#muted {
    color: #94a6c3;
}
QLabel#purple {
    color: #a463ff;
}
QPushButton {
    background: #0a1326;
    border: 1px solid #244a75;
    border-radius: 10px;
    padding: 11px 16px;
    font-weight: 650;
    text-align: left;
}
QPushButton:hover {
    background: #10213d;
    border: 1px solid #2c8bff;
}
QPushButton#primary {
    background: #0e3fd4;
    border: 1px solid #47c9ff;
    color: white;
    text-align: center;
    font-size: 17px;
}
QPushButton#primary:hover {
    background: #1558ef;
}
QPushButton#secondary {
    text-align: center;
    border: 1px solid #7d42d5;
}
QRadioButton {
    spacing: 10px;
    color: #d8e5fa;
    padding: 8px;
}
QRadioButton::indicator {
    width: 18px;
    height: 18px;
}
QProgressBar {
    background: #09101e;
    border: 1px solid #263c59;
    border-radius: 7px;
    text-align: center;
    min-height: 16px;
}
QProgressBar::chunk {
    background: #2d75ff;
    border-radius: 6px;
}
QListWidget {
    background: transparent;
    border: none;
    outline: none;
}
QListWidget::item {
    border: 1px solid transparent;
    padding: 12px;
    margin: 2px 0;
    border-radius: 8px;
}
QListWidget::item:selected {
    background: #0d2b63;
    border: 1px solid #2f90ff;
}
QListWidget::item:hover {
    background: #0b1b34;
}
"""

def cmd_output(cmd):
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

def first_line(text):
    for line in text.splitlines():
        if line.strip():
            return line.strip()
    return "Unknown"

def hardware_summary():
    cpu = cmd_output(["bash","-lc","lscpu | awk -F: '/Model name/ {gsub(/^[ \t]+/,\"\",$2); print $2; exit}'"])
    ram = cmd_output(["bash","-lc","free -h | awk '/Mem:/ {print $2}'"])
    gpu = first_line(cmd_output(["bash","-lc","lspci | grep -Ei 'VGA|3D|Display' | sed 's/^[^ ]* //' | head -n1"]))
    storage = first_line(cmd_output(["bash","-lc","lsblk -dn -o MODEL,SIZE,TYPE | awk '$3==\"disk\" {print $1\" \"$2; exit}'"]))
    fw = "UEFI" if os.path.isdir("/sys/firmware/efi") else "Legacy BIOS"
    secure = cmd_output(["bash","-lc","bootctl status 2>/dev/null | awk -F: '/Secure Boot:/ {gsub(/^[ \t]+/,\"\",$2); print $2; exit}'"]) or "Unknown"
    return {
        "CPU": cpu or "Unknown CPU",
        "RAM": ram or "Unknown",
        "GPU": gpu or "Unknown / Virtual GPU",
        "STORAGE": storage or "No disk detected",
        "FIRMWARE": f"{fw} • Secure Boot: {secure}",
    }

def disk_list():
    out = cmd_output(["bash","-lc","lsblk -dpno NAME,SIZE,MODEL,TYPE | awk '$4==\"disk\" {print $1\"|\"$2\"|\"$3}'"])
    disks = []
    for line in out.splitlines():
        parts = line.split("|")
        if len(parts) >= 3:
            disks.append((parts[0], parts[1], parts[2]))
    return disks

class Installer(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MechOS Installer")
        self.resize(1500, 880)
        self.setMinimumSize(1180, 720)
        self.setStyleSheet(STYLE)
        self.hw = hardware_summary()
        self.disks = disk_list()
        self.selected_disk = self.disks[0][0] if self.disks else ""
        self.install_mode = "clean"
        self.build_ui()

    def panel(self, glow=False):
        f = QFrame()
        f.setObjectName("glowPanel" if glow else "panel")
        return f

    def build_ui(self):
        root = QWidget()
        root_layout = QVBoxLayout(root)
        root_layout.setContentsMargins(14,14,14,14)

        outer = QFrame()
        outer.setObjectName("outerFrame")
        root_layout.addWidget(outer)
        layout = QVBoxLayout(outer)
        layout.setContentsMargins(24,18,24,18)
        layout.setSpacing(16)

        # Header
        header = QHBoxLayout()
        if os.path.exists(LOGO):
            logo = QLabel()
            pix = QPixmap(LOGO).scaledToHeight(64, Qt.TransformationMode.SmoothTransformation)
            logo.setPixmap(pix)
            header.addWidget(logo)

        title_box = QVBoxLayout()
        t = QLabel("MECHOS INSTALLER")
        t.setFont(QFont("Sans Serif", 28, QFont.Weight.Bold))
        t.setStyleSheet("color:#f7f8ff;")
        st = QLabel("GAMING + CREATOR OS")
        st.setObjectName("accent")
        st.setFont(QFont("Sans Serif", 13, QFont.Weight.Bold))
        title_box.addWidget(t)
        title_box.addWidget(st)
        header.addLayout(title_box)
        header.addStretch()

        brand_text = QLabel("MECHOS")
        brand_text.setFont(QFont("Sans Serif", 22, QFont.Weight.Bold))
        brand_text.setStyleSheet("color:#d9e5ff; letter-spacing:2px;")
        header.addWidget(brand_text)
        layout.addLayout(header)

        body = QHBoxLayout()
        body.setSpacing(16)

        # Left nav
        nav_panel = self.panel()
        nav_l = QVBoxLayout(nav_panel)
        nav_l.setContentsMargins(12,12,12,12)
        self.nav = QListWidget()
        nav_items = [
            "1   WELCOME",
            "2   HARDWARE SCAN",
            "3   INSTALL",
            "4   REPAIR BOOT",
            "5   RECOVERY",
            "6   REINSTALL (KEEP HOME)",
            "7   INSTALL LOGS",
            "8   FINISH",
        ]
        for item in nav_items:
            self.nav.addItem(QListWidgetItem(item))
        self.nav.setCurrentRow(0)
        self.nav.currentRowChanged.connect(self.nav_selected)
        nav_l.addWidget(self.nav)
        body.addWidget(nav_panel, 1)

        # Center
        center = QVBoxLayout()
        welcome = QLabel("WELCOME TO MECHOS")
        welcome.setFont(QFont("Sans Serif", 22, QFont.Weight.Bold))
        center.addWidget(welcome)
        desc = QLabel("MechOS is optimized for gaming, content creation, and productivity. Select your target drive and installation type.")
        desc.setWordWrap(True)
        desc.setObjectName("muted")
        center.addWidget(desc)

        center.addSpacing(8)
        target_label = QLabel("SELECT INSTALL TARGET")
        target_label.setObjectName("purple")
        target_label.setFont(QFont("Sans Serif", 11, QFont.Weight.Bold))
        center.addWidget(target_label)

        self.disk_buttons = []
        self.disk_group = QButtonGroup(self)
        self.disk_group.setExclusive(True)
        for i, (dev, size, model) in enumerate(self.disks[:6]):
            p = self.panel(glow=(i == 0))
            pl = QHBoxLayout(p)
            rb = QRadioButton()
            rb.setChecked(i == 0)
            rb.toggled.connect(lambda checked, d=dev: self.select_disk(d, checked))
            self.disk_group.addButton(rb)
            pl.addWidget(rb)
            dl = QVBoxLayout()
            dl.addWidget(QLabel(f"{model or 'Disk'}   {size}"))
            sub = QLabel(dev)
            sub.setObjectName("muted")
            dl.addWidget(sub)
            pl.addLayout(dl)
            pl.addStretch()
            center.addWidget(p)
            self.disk_buttons.append(p)

        if not self.disks:
            nodisk = self.panel()
            nl = QVBoxLayout(nodisk)
            nl.addWidget(QLabel("No installable disks detected."))
            center.addWidget(nodisk)

        center.addSpacing(8)
        opt_label = QLabel("INSTALLATION OPTIONS")
        opt_label.setObjectName("purple")
        opt_label.setFont(QFont("Sans Serif", 11, QFont.Weight.Bold))
        center.addWidget(opt_label)

        opts = QHBoxLayout()
        self.clean = QRadioButton("Clean Install\nErase selected target and install MechOS")
        self.keep = QRadioButton("Keep Personal Data\nPreserve existing /home where supported")
        self.custom = QRadioButton("Custom Install\nAdvanced/manual partitioning")
        self.clean.setChecked(True)
        self.clean.toggled.connect(lambda v: self.set_mode("clean", v))
        self.keep.toggled.connect(lambda v: self.set_mode("keep", v))
        self.custom.toggled.connect(lambda v: self.set_mode("custom", v))
        for w in (self.clean, self.keep, self.custom):
            p = self.panel()
            pl = QVBoxLayout(p)
            pl.addWidget(w)
            opts.addWidget(p)
        center.addLayout(opts)

        warning = self.panel()
        wl = QHBoxLayout(warning)
        wicon = QLabel("ⓘ")
        wicon.setStyleSheet("color:#4ea4ff; font-size:20px;")
        wl.addWidget(wicon)
        self.warning_text = QLabel("All data on the selected target may be erased during installation. Review Archinstall's final disk summary before confirming.")
        self.warning_text.setWordWrap(True)
        self.warning_text.setObjectName("muted")
        wl.addWidget(self.warning_text, 1)
        center.addWidget(warning)
        body.addLayout(center, 3)

        # Right hardware summary
        right = QVBoxLayout()
        hw_panel = self.panel()
        hl = QVBoxLayout(hw_panel)
        htitle = QLabel("HARDWARE SUMMARY")
        htitle.setObjectName("accent")
        htitle.setFont(QFont("Sans Serif", 12, QFont.Weight.Bold))
        hl.addWidget(htitle)
        for k, v in self.hw.items():
            row = QHBoxLayout()
            key = QLabel(k)
            key.setObjectName("purple")
            row.addWidget(key)
            row.addStretch()
            val = QLabel(v)
            val.setWordWrap(True)
            row.addWidget(val)
            hl.addLayout(row)
        right.addWidget(hw_panel)

        overview = self.panel()
        ol = QVBoxLayout(overview)
        otitle = QLabel("INSTALL OVERVIEW")
        otitle.setObjectName("accent")
        otitle.setFont(QFont("Sans Serif", 12, QFont.Weight.Bold))
        ol.addWidget(otitle)
        self.target_value = QLabel(self.selected_disk or "No disk selected")
        self.mode_value = QLabel("Clean Install")
        for label, widget in [
            ("Edition", QLabel("MechOS Alpha")),
            ("Target Drive", self.target_value),
            ("Install Type", self.mode_value),
        ]:
            r = QHBoxLayout()
            l = QLabel(label); l.setObjectName("muted")
            r.addWidget(l)
            r.addStretch()
            r.addWidget(widget)
            ol.addLayout(r)
        self.progress = QProgressBar()
        self.progress.setValue(0)
        self.progress.setFormat("Ready to install")
        ol.addWidget(self.progress)
        right.addWidget(overview)
        right.addStretch()
        body.addLayout(right, 2)

        layout.addLayout(body, 1)

        # Footer actions
        footer = QHBoxLayout()
        live = QLabel("MECHOS LIVE ENVIRONMENT")
        live.setObjectName("muted")
        footer.addWidget(live)
        footer.addStretch()

        repair = QPushButton("Repair")
        repair.setObjectName("secondary")
        repair.clicked.connect(self.recovery)
        footer.addWidget(repair)

        install = QPushButton("Install Now")
        install.setObjectName("primary")
        install.clicked.connect(self.install)
        footer.addWidget(install)
        layout.addLayout(footer)

        self.setCentralWidget(root)

    def select_disk(self, dev, checked):
        if checked:
            self.selected_disk = dev
            self.target_value.setText(dev)

    def set_mode(self, mode, checked):
        if not checked:
            return
        self.install_mode = mode
        names = {"clean":"Clean Install","keep":"Keep Personal Data","custom":"Custom Install"}
        self.mode_value.setText(names[mode])
        if mode == "clean":
            self.warning_text.setText("The selected root/target can be erased. Review Archinstall's final disk summary before confirming.")
        else:
            self.warning_text.setText("MechOS will open manual partitioning so existing personal data is never silently formatted.")

    def nav_selected(self, row):
        if row == 1:
            subprocess.Popen(["konsole","-e","bash","-lc",
                "/usr/local/bin/mechos-hardware-scan; echo; read -rp 'Press Enter to close...'"])
        elif row == 2:
            self.install()
        elif row == 3:
            self.recovery()
        elif row == 4:
            self.recovery()
        elif row == 5:
            self.install_mode = "keep"
            self.keep.setChecked(True)
            self.install()
        elif row == 6:
            subprocess.Popen(["konsole","-e","bash","-lc",
                "/usr/local/bin/mechos-recovery-helper logs; echo; read -rp 'Press Enter to close...'"])
        elif row == 7:
            self.close()

    def install(self):
        if not self.selected_disk and self.install_mode == "clean":
            QMessageBox.warning(self, "MechOS Installer", "No install target was detected.")
            return

        if self.install_mode == "keep":
            subprocess.Popen(["konsole","-e","sudo","/usr/local/bin/mechos-preserve-home"])
            return

        if self.install_mode == "custom":
            subprocess.Popen(["konsole","-e","sudo","/usr/local/bin/mechos-install","--terminal","--preserve-home"])
            return

        answer = QMessageBox.question(
            self,
            "Install MechOS",
            f"Start guided installation for {self.selected_disk or 'the selected target'}?\n\n"
            "Archinstall will still display the final partition/disk summary and require confirmation before formatting."
        )
        if answer != QMessageBox.StandardButton.Yes:
            return

        subprocess.Popen(["konsole","-e","sudo","/usr/local/bin/mechos-install","--terminal"])

    def recovery(self):
        subprocess.Popen(["/usr/local/bin/mechos-recovery-center"])

def main():
    app = QApplication(sys.argv)
    w = Installer()
    w.showMaximized()
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
PYEOF

chmod 755 \
  /workspace/archlive/airootfs/usr/local/bin/mechos-recovery-center \
  /workspace/archlive/airootfs/usr/local/bin/mechos-live-setup

# Compatibility command required by mechos-current-integration.sh final
# validation. It forwards to the current graphical live installer.
cat > /workspace/archlive/airootfs/usr/local/bin/mechos-install-graphical << "EOF"
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/mechos-live-setup "$@"
EOF
chmod 755 /workspace/archlive/airootfs/usr/local/bin/mechos-install-graphical

cat > /workspace/archlive/airootfs/usr/share/applications/mechos-live-setup.desktop << "EOF"
[Desktop Entry]
Type=Application
Name=MechOS Setup
Comment=Install, recover or inspect MechOS
Exec=/usr/local/bin/mechos-live-setup
Icon=mechos
Terminal=false
Categories=System;
EOF

cat > /workspace/archlive/airootfs/usr/share/applications/mechos-recovery-center.desktop << "EOF"
[Desktop Entry]
Type=Application
Name=MechOS Recovery Center
Comment=Repair boot and recover MechOS installations
Exec=/usr/local/bin/mechos-recovery-center
Icon=system-rescue
Terminal=false
Categories=System;
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

# ---------- LIVE-BOOT SERVICE POLICY ----------
# Keep the live ISO lean. These maintenance/performance services are installed
# in the image but are enabled only after MechOS is installed.
mkdir -p /workspace/archlive/airootfs/etc/systemd/system/timers.target.wants
mkdir -p /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants

rm -f \
  /workspace/archlive/airootfs/etc/systemd/system/timers.target.wants/fstrim.timer \
  /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/irqbalance.service \
  /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/power-profiles-daemon.service \
  /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/switcheroo-control.service \
  || true

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

# Installer visual branding supplied with the MechOS repository.
if [ -f /workspace/branding/mechos-installer-reference.png ]; then
  install -Dm644     /workspace/branding/mechos-installer-reference.png     /workspace/archlive/airootfs/usr/share/mechos/branding/mechos-installer-reference.png
fi

if [ -f /workspace/branding/mechos-creator-mode-reference.png ]; then
  install -Dm644 /workspace/branding/mechos-creator-mode-reference.png /workspace/archlive/airootfs/usr/share/mechos/branding/mechos-creator-mode-reference.png
fi
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
# MechOS v0.3 dynamic boot theme.
# The visual direction matches the blue/purple Installer and Creator Mode.

Window.SetBackgroundTopColor(0.010, 0.018, 0.045);
Window.SetBackgroundBottomColor(0.030, 0.008, 0.065);

logo.image = Image("mechos-logo.png");
logo.sprite = Sprite(logo.image);
logo.sprite.SetX(Window.GetWidth() / 2 - logo.image.GetWidth() / 2);
logo.sprite.SetY(Window.GetHeight() / 2 - logo.image.GetHeight() / 2 - 85);

title.image = Image.Text("MECHOS", 0.92, 0.95, 1.00);
title.sprite = Sprite(title.image);
title.sprite.SetX(Window.GetWidth() / 2 - title.image.GetWidth() / 2);
title.sprite.SetY(Window.GetHeight() / 2 + 105);

tag.image = Image.Text("GAMING  +  CREATOR  OS", 0.12, 0.72, 1.00);
tag.sprite = Sprite(tag.image);
tag.sprite.SetX(Window.GetWidth() / 2 - tag.image.GetWidth() / 2);
tag.sprite.SetY(Window.GetHeight() / 2 + 145);

scope.image = Image.Text("MECHSCOPE 2.0", 0.72, 0.38, 1.00);
scope.sprite = Sprite(scope.image);
scope.sprite.SetX(Window.GetWidth() / 2 - scope.image.GetWidth() / 2);
scope.sprite.SetY(Window.GetHeight() / 2 + 180);

status.image = Image.Text("Initializing MechOS", 0.74, 0.63, 0.94);
status.sprite = Sprite(status.image);
status.sprite.SetX(Window.GetWidth() / 2 - status.image.GetWidth() / 2);
status.sprite.SetY(Window.GetHeight() / 2 + 230);

phase.image = Image.Text("Hardware check   •   System init   •   Drivers   •   Services", 0.34, 0.58, 0.86);
phase.sprite = Sprite(phase.image);
phase.sprite.SetX(Window.GetWidth() / 2 - phase.image.GetWidth() / 2);
phase.sprite.SetY(Window.GetHeight() / 2 + 265);

fun refresh_callback () {
    progress = Plymouth.GetBootProgress();
    pulse = 0.65 + (progress * 0.35);
    logo.sprite.SetOpacity(pulse);
    title.sprite.SetOpacity(0.75 + (progress * 0.25));
}
Plymouth.SetRefreshFunction(refresh_callback);
EOF

cat > /workspace/archlive/airootfs/etc/plymouth/plymouthd.conf << "EOF"
[Daemon]
Theme=mechos
ShowDelay=0
# Live media should not sit behind the splash waiting on a slow/virtual DRM device.
DeviceTimeout=3
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

# Add a UEFI MechOS Recovery Environment boot entry.
ENTRY_DIR="/workspace/archlive/efiboot/loader/entries"
if [ -d "$ENTRY_DIR" ]; then
  BASE_ENTRY="$(
    grep -l 'archisobasedir=' "$ENTRY_DIR"/*.conf 2>/dev/null | head -n1 || true
  )"
  if [ -n "$BASE_ENTRY" ]; then
    cp "$BASE_ENTRY" "$ENTRY_DIR/02-mechos-recovery.conf"
    sed -i -E \
      -e 's/^title .*/title MechOS Recovery Environment/' \
      -e '/^options / s/$/ mechos.recovery=1/' \
      "$ENTRY_DIR/02-mechos-recovery.conf"
  fi
fi

# Let Plasma use the same logo where a distro logo is requested.
mkdir -p /workspace/archlive/airootfs/usr/share/pixmaps
cp /workspace/archlive/airootfs/usr/share/mechos/branding/mechos-logo.png \
  /workspace/archlive/airootfs/usr/share/pixmaps/mechos.png

# ---------- MECHSCOPE BUILT-IN MODE SWITCHER ----------
# MechScope is the Gaming Mode shell. It owns the Steam launcher and
# mode switching so Desktop/Creator switching is part of MechScope,
# not a separate desktop-only utility.


# ---------- MECHOS STREAM CENTER / OBS LOCAL CONTROL ----------
cat > /workspace/archlive/airootfs/usr/local/bin/mechos-stream-control << "PYEOF"
#!/usr/bin/env python3
import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path

try:
    import websocket
except Exception as exc:
    raise SystemExit(f"python-websocket-client is required: {exc}")

CONFIG_DIR = Path.home() / ".config/mechos"
CONFIG_FILE = CONFIG_DIR / "stream-control.json"

class ObsError(RuntimeError):
    pass

def load_config():
    cfg = {"host":"127.0.0.1","port":4455,"password":""}
    if CONFIG_FILE.exists():
        try:
            loaded = json.loads(CONFIG_FILE.read_text())
            if isinstance(loaded, dict):
                cfg.update(loaded)
        except Exception:
            pass
    return cfg

def save_config(host="127.0.0.1", port=4455, password=""):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(json.dumps({
        "host": host,
        "port": int(port),
        "password": password,
    }, indent=2) + "\n")
    os.chmod(CONFIG_FILE, 0o600)

def obs_running():
    return subprocess.run(
        ["pgrep","-x","obs"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0

def launch_obs():
    if obs_running():
        return
    subprocess.Popen(
        ["obs","--minimize-to-tray"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

def make_auth(password, salt, challenge):
    secret = base64.b64encode(
        hashlib.sha256((password + salt).encode("utf-8")).digest()
    ).decode("ascii")
    return base64.b64encode(
        hashlib.sha256((secret + challenge).encode("utf-8")).digest()
    ).decode("ascii")

class ObsClient:
    def __init__(self, auto_launch=False, timeout=4.0):
        self.cfg = load_config()
        if auto_launch:
            launch_obs()
        self.ws = None
        deadline = time.monotonic() + (12.0 if auto_launch else timeout)
        last = None
        while time.monotonic() < deadline:
            try:
                self.ws = websocket.create_connection(
                    f"ws://{self.cfg['host']}:{int(self.cfg['port'])}",
                    timeout=3,
                    subprotocols=["obswebsocket.json"],
                )
                break
            except Exception as exc:
                last = exc
                if not auto_launch:
                    break
                time.sleep(0.5)
        if self.ws is None:
            raise ObsError(f"Could not connect to OBS WebSocket: {last}")
        self.identify()

    def recv_json(self):
        raw = self.ws.recv()
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8", "replace")
        return json.loads(raw)

    def send_json(self, obj):
        self.ws.send(json.dumps(obj))

    def identify(self):
        hello = self.recv_json()
        if hello.get("op") != 0:
            raise ObsError("OBS WebSocket did not send Hello.")
        data = hello.get("d", {})
        identify = {"rpcVersion":1,"eventSubscriptions":0}
        auth = data.get("authentication")
        if auth:
            password = str(self.cfg.get("password",""))
            if not password:
                raise ObsError(
                    "OBS WebSocket authentication is enabled, but MechOS has no "
                    "local control password saved yet."
                )
            identify["authentication"] = make_auth(
                password,
                str(auth.get("salt","")),
                str(auth.get("challenge","")),
            )
        self.send_json({"op":1,"d":identify})
        identified = self.recv_json()
        if identified.get("op") != 2:
            raise ObsError("OBS WebSocket authentication/identification failed.")

    def request(self, request_type, data=None):
        rid = str(uuid.uuid4())
        payload = {
            "requestType": request_type,
            "requestId": rid,
        }
        if data:
            payload["requestData"] = data
        self.send_json({"op":6,"d":payload})

        while True:
            msg = self.recv_json()
            if msg.get("op") != 7:
                continue
            d = msg.get("d", {})
            if d.get("requestId") != rid:
                continue
            status = d.get("requestStatus", {})
            if not status.get("result", False):
                comment = status.get("comment") or "OBS request failed."
                code = status.get("code")
                raise ObsError(f"{comment} (code {code})")
            return d.get("responseData", {})

    def close(self):
        try:
            self.ws.close()
        except Exception:
            pass

def get_status(client):
    stream = client.request("GetStreamStatus")
    record = client.request("GetRecordStatus")
    scenes = client.request("GetSceneList")
    return {
        "streaming": bool(stream.get("outputActive")),
        "streamTimecode": stream.get("outputTimecode","00:00:00"),
        "streamCongestion": stream.get("outputCongestion",0),
        "recording": bool(record.get("outputActive")),
        "recordTimecode": record.get("outputTimecode","00:00:00"),
        "scene": scenes.get("currentProgramSceneName",""),
        "scenes": [x.get("sceneName","") for x in scenes.get("scenes",[])],
    }

def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)

    cfg = sub.add_parser("configure")
    cfg.add_argument("--host", default="127.0.0.1")
    cfg.add_argument("--port", type=int, default=4455)
    cfg.add_argument("--password", default="")

    for name in (
        "status","start-stream","stop-stream","toggle-stream",
        "start-record","stop-record","toggle-record","launch-obs",
        "list-scenes",
    ):
        sub.add_parser(name)

    scene = sub.add_parser("set-scene")
    scene.add_argument("name")

    args = p.parse_args()

    if args.cmd == "configure":
        save_config(args.host, args.port, args.password)
        print("saved")
        return

    if args.cmd == "launch-obs":
        launch_obs()
        print("launched")
        return

    client = ObsClient(auto_launch=args.cmd in ("start-stream","start-record"))
    try:
        if args.cmd == "status":
            print(json.dumps(get_status(client)))
        elif args.cmd == "start-stream":
            client.request("StartStream")
            print("streaming")
        elif args.cmd == "stop-stream":
            client.request("StopStream")
            print("stopped")
        elif args.cmd == "toggle-stream":
            client.request("ToggleStream")
            print(json.dumps(get_status(client)))
        elif args.cmd == "start-record":
            client.request("StartRecord")
            print("recording")
        elif args.cmd == "stop-record":
            client.request("StopRecord")
            print("stopped")
        elif args.cmd == "toggle-record":
            client.request("ToggleRecord")
            print(json.dumps(get_status(client)))
        elif args.cmd == "list-scenes":
            print(json.dumps(get_status(client)["scenes"]))
        elif args.cmd == "set-scene":
            client.request("SetCurrentProgramScene", {"sceneName":args.name})
            print(args.name)
    finally:
        client.close()

if __name__ == "__main__":
    try:
        main()
    except ObsError as exc:
        print(f"MECHOS_STREAM_ERROR: {exc}", file=sys.stderr)
        raise SystemExit(3)
PYEOF
chmod 755 /workspace/archlive/airootfs/usr/local/bin/mechos-stream-control

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-stream-center << "PYEOF"
#!/usr/bin/env python3
import json
import os
import subprocess
import sys
from pathlib import Path

from PyQt6.QtCore import QTimer
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import (
    QApplication, QComboBox, QFrame, QGridLayout, QHBoxLayout, QLabel,
    QInputDialog, QLineEdit, QMainWindow, QMessageBox, QPushButton,
    QSpinBox, QVBoxLayout, QWidget
)

CONTROL="/usr/local/bin/mechos-stream-control"
CONFIG=Path.home()/".config/mechos/stream-control.json"

STYLE="""
QWidget{background:#070b14;color:#f4f8ff;font-family:Sans Serif}
QFrame#panel{background:#0d1524;border:1px solid #294b70;border-radius:12px}
QLabel#title{font-size:24px;font-weight:900;color:#c16cff}
QLabel#section{font-size:13px;font-weight:800;color:#67caff}
QLabel#muted{color:#94a2ba}
QLabel#live{font-size:18px;font-weight:900;color:#ff5b75}
QLabel#offline{font-size:18px;font-weight:900;color:#8fa0b8}
QPushButton{
 background:#122039;border:1px solid #31577e;border-radius:8px;
 padding:10px 13px;color:#f4f8ff;font-weight:700
}
QPushButton:hover{background:#293166;border:1px solid #8b69ff}
QPushButton#live{background:#7b1835;border:1px solid #ff587c}
QPushButton#stop{background:#351321;border:1px solid #b84362}
QComboBox,QSpinBox{
 background:#0b1320;border:1px solid #31577e;border-radius:7px;padding:7px
}
"""

def call(args):
    return subprocess.run(
        [CONTROL]+args,
        text=True,
        capture_output=True,
        timeout=15,
        check=False,
    )

def spawn(args):
    try: subprocess.Popen(args)
    except Exception: pass

class StreamCenter(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MechOS Stream Center")
        self.resize(720,640)
        self.setStyleSheet(STYLE)
        self.build()
        self.timer=QTimer(self)
        self.timer.timeout.connect(self.refresh)
        self.timer.start(2500)
        self.refresh()

    def panel(self):
        p=QFrame(); p.setObjectName("panel"); return p

    def btn(self,text,fn,obj=""):
        b=QPushButton(text)
        if obj:b.setObjectName(obj)
        b.clicked.connect(fn)
        return b

    def build(self):
        root=QWidget(); self.setCentralWidget(root)
        v=QVBoxLayout(root); v.setContentsMargins(18,18,18,18); v.setSpacing(12)

        t=QLabel("MECHOS STREAM CENTER"); t.setObjectName("title"); v.addWidget(t)
        s=QLabel("Stream and record from MechScope through OBS Studio.")
        s.setObjectName("muted"); v.addWidget(s)

        status=self.panel(); sl=QVBoxLayout(status)
        sh=QLabel("STREAM STATUS"); sh.setObjectName("section"); sl.addWidget(sh)
        self.live=QLabel("Checking OBS…"); self.live.setObjectName("offline"); sl.addWidget(self.live)
        self.detail=QLabel(); self.detail.setObjectName("muted"); self.detail.setWordWrap(True); sl.addWidget(self.detail)
        v.addWidget(status)

        actions=self.panel(); al=QVBoxLayout(actions)
        ah=QLabel("LIVE CONTROL"); ah.setObjectName("section"); al.addWidget(ah)
        g=QGridLayout()
        g.addWidget(self.btn("Go Live",self.start_stream,"live"),0,0)
        g.addWidget(self.btn("End Stream",self.stop_stream,"stop"),0,1)
        g.addWidget(self.btn("Start Recording",self.start_record),1,0)
        g.addWidget(self.btn("Stop Recording",self.stop_record),1,1)
        g.addWidget(self.btn("Open OBS",self.open_obs),2,0)
        g.addWidget(self.btn("Refresh Status",self.refresh),2,1)
        al.addLayout(g)
        v.addWidget(actions)

        scenes=self.panel(); scl=QVBoxLayout(scenes)
        sch=QLabel("SCENES"); sch.setObjectName("section"); scl.addWidget(sch)
        row=QHBoxLayout()
        self.scenes=QComboBox(); row.addWidget(self.scenes,1)
        row.addWidget(self.btn("Switch Scene",self.set_scene))
        scl.addLayout(row)
        v.addWidget(scenes)

        setup=self.panel(); spl=QVBoxLayout(setup)
        sph=QLabel("ONE-TIME OBS SETUP"); sph.setObjectName("section"); spl.addWidget(sph)
        note=QLabel(
          "Configure your Twitch/YouTube/etc. account in OBS → Settings → Stream. "
          "Then enable OBS WebSocket under Tools → WebSocket Server Settings. "
          "MechOS stores only the local OBS control password; your stream key/account "
          "remain inside OBS."
        )
        note.setObjectName("muted"); note.setWordWrap(True); spl.addWidget(note)

        self.port=QSpinBox(); self.port.setRange(1,65535); self.port.setValue(4455)
        row=QHBoxLayout(); row.addWidget(QLabel("WebSocket port")); row.addWidget(self.port)
        row.addWidget(self.btn("Save Control Password",self.save_password))
        spl.addLayout(row)
        spl.addWidget(self.btn("Open OBS for Account / Scene Setup",self.open_obs))
        v.addWidget(setup)

        hot=self.panel(); hl=QVBoxLayout(hot)
        hh=QLabel("STREAMING HOTKEYS"); hh.setObjectName("section"); hl.addWidget(hh)
        info=QLabel(
          "Ctrl+Shift+B  Stream Center\n"
          "Ctrl+Shift+L  Go Live\n"
          "Ctrl+Shift+K  End Stream\n"
          "Ctrl+Shift+R  Toggle Recording\n"
          "Guide/Home + Y  Quick Actions"
        )
        info.setObjectName("muted"); hl.addWidget(info)
        v.addWidget(hot)
        v.addStretch()

    def show_error(self,prefix,p):
        msg=(p.stderr or p.stdout or "Unknown OBS control error").strip()
        QMessageBox.warning(self,prefix,msg)

    def start_stream(self):
        p=call(["start-stream"])
        if p.returncode:
            self.show_error("Could not start stream",p)
        self.refresh()

    def stop_stream(self):
        p=call(["stop-stream"])
        if p.returncode:
            self.show_error("Could not stop stream",p)
        self.refresh()

    def start_record(self):
        p=call(["start-record"])
        if p.returncode:self.show_error("Could not start recording",p)
        self.refresh()

    def stop_record(self):
        p=call(["stop-record"])
        if p.returncode:self.show_error("Could not stop recording",p)
        self.refresh()

    def open_obs(self):
        call(["launch-obs"])

    def save_password(self):
        password,ok=QInputDialog.getText(
            self,"OBS WebSocket Password",
            "Enter the password shown in OBS → Tools → WebSocket Server Settings:",
            QLineEdit.EchoMode.Password
        )
        if not ok:return
        p=call(["configure","--port",str(self.port.value()),"--password",password])
        if p.returncode:
            self.show_error("Could not save OBS control settings",p)
        else:
            QMessageBox.information(
              self,"MechOS Stream Center",
              "Local OBS control settings saved with user-only file permissions."
            )
            self.refresh()

    def set_scene(self):
        name=self.scenes.currentText()
        if not name:return
        p=call(["set-scene",name])
        if p.returncode:self.show_error("Could not switch scene",p)
        self.refresh()

    def refresh(self):
        p=call(["status"])
        if p.returncode:
            self.live.setText("OBS CONTROL OFFLINE")
            self.live.setObjectName("offline")
            self.live.style().unpolish(self.live); self.live.style().polish(self.live)
            self.detail.setText(
              "Open OBS and complete the one-time Stream Center setup. "
              "Streaming accounts and stream keys stay in OBS."
            )
            return
        try:
            st=json.loads(p.stdout)
        except Exception:
            return
        if st.get("streaming"):
            self.live.setText("● LIVE")
            self.live.setObjectName("live")
        else:
            self.live.setText("OFFLINE")
            self.live.setObjectName("offline")
        self.live.style().unpolish(self.live); self.live.style().polish(self.live)

        rec="Recording" if st.get("recording") else "Not recording"
        self.detail.setText(
          f"Scene: {st.get('scene') or 'Unknown'}\n"
          f"Stream time: {st.get('streamTimecode','00:00:00')} • {rec}"
        )

        current=self.scenes.currentText()
        self.scenes.blockSignals(True)
        self.scenes.clear()
        self.scenes.addItems(st.get("scenes",[]))
        if current:
            i=self.scenes.findText(current)
            if i>=0:self.scenes.setCurrentIndex(i)
        if st.get("scene"):
            i=self.scenes.findText(st["scene"])
            if i>=0:self.scenes.setCurrentIndex(i)
        self.scenes.blockSignals(False)

app=QApplication(sys.argv)
app.setApplicationName("MechOS Stream Center")
w=StreamCenter(); w.show(); sys.exit(app.exec())
PYEOF
chmod 755 /workspace/archlive/airootfs/usr/local/bin/mechos-stream-center

# ---------- MECHSCOPE QUICK ACTIONS + GLOBAL GAMING HOTKEYS ----------
cat > /workspace/archlive/airootfs/usr/local/bin/mechos-quick-actions << "PYEOF"
#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys
from pathlib import Path

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QFont, QKeyEvent
from PyQt6.QtWidgets import (
    QApplication, QFrame, QGridLayout, QHBoxLayout, QLabel, QMainWindow,
    QMessageBox, QPushButton, QVBoxLayout, QWidget
)

CONFIG = Path.home() / ".config/MangoHud/MangoHud.conf"

STYLE = """
QWidget { background:#070b15; color:#eef7ff; font-family:Sans Serif; }
QFrame#panel { background:#0c1424; border:1px solid #29456b; border-radius:13px; }
QLabel#title { color:#c477ff; font-size:22px; font-weight:900; }
QLabel#section { color:#72ccff; font-size:13px; font-weight:800; }
QLabel#muted { color:#91a0b8; }
QLabel#metric { color:#d0adff; font-weight:700; }
QPushButton {
  background:#111e31; border:1px solid #315377; border-radius:8px;
  padding:10px 12px; color:#eef7ff; font-weight:650;
}
QPushButton:hover, QPushButton:focus {
  background:#26305a; border:2px solid #8665ff;
}
QPushButton#profile {
  background:#24133a; border:1px solid #70429a;
}
"""

def run(cmd):
    try:
        return subprocess.run(cmd, check=False, text=True, capture_output=True)
    except Exception:
        return None

def spawn(cmd):
    try:
        subprocess.Popen(cmd)
    except Exception:
        pass

def out(cmd):
    p = run(cmd)
    if not p:
        return ""
    return (p.stdout or "").strip()

def ensure_mangohud_config():
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    if CONFIG.exists():
        return
    CONFIG.write_text("""legacy_layout=false
fps
frametime
gpu_stats
gpu_temp
vram
cpu_stats
cpu_temp
ram
wine
gamemode
battery
position=top-left
background_alpha=0.45
control=mangohud
no_display
fps_limit=0,30,60,120
toggle_fps_limit=Shift_L+F1
toggle_hud=Shift_R+F12
toggle_hud_position=Shift_R+F11
reload_cfg=Shift_L+F4
""")

class QuickActions(QMainWindow):
    def __init__(self):
        super().__init__()
        ensure_mangohud_config()

        self.setWindowTitle("MechOS Quick Actions")
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint |
            Qt.WindowType.WindowStaysOnTopHint |
            Qt.WindowType.Tool
        )
        self.setStyleSheet(STYLE)
        self.setFixedWidth(470)
        self.build()

        screen = QApplication.primaryScreen().availableGeometry()
        self.setGeometry(screen.right() - self.width() + 1, screen.top(), self.width(), screen.height())

    def panel(self):
        p = QFrame()
        p.setObjectName("panel")
        return p

    def button(self, text, fn, obj=""):
        b = QPushButton(text)
        if obj:
            b.setObjectName(obj)
        b.clicked.connect(fn)
        return b

    def build(self):
        root = QWidget()
        self.setCentralWidget(root)
        outer = QVBoxLayout(root)
        outer.setContentsMargins(14,14,14,14)
        outer.setSpacing(11)

        title = QLabel("MECHOS QUICK ACTIONS")
        title.setObjectName("title")
        outer.addWidget(title)
        subtitle = QLabel("In-game controls • Ctrl+Shift+M • Guide/Home + Y")
        subtitle.setObjectName("muted")
        outer.addWidget(subtitle)

        perf = self.panel()
        pl = QVBoxLayout(perf)
        h = QLabel("PERFORMANCE")
        h.setObjectName("section")
        pl.addWidget(h)

        profiles = QGridLayout()
        profiles.addWidget(self.button("Performance", lambda:self.profile("performance"), "profile"),0,0)
        profiles.addWidget(self.button("Balanced", lambda:self.profile("balanced"), "profile"),0,1)
        profiles.addWidget(self.button("Battery Saver", lambda:self.profile("power-saver"), "profile"),0,2)
        pl.addLayout(profiles)

        row = QHBoxLayout()
        row.addWidget(self.button("Toggle Performance Overlay", self.toggle_hud))
        row.addWidget(self.button("Performance Center", lambda:spawn(["/usr/local/bin/mechos-performance-center"])))
        pl.addLayout(row)

        mh = QLabel("MangoApp: Shift+F12 HUD • Shift+F1 FPS limit • Shift+F4 reload config")
        mh.setObjectName("muted")
        mh.setWordWrap(True)
        pl.addWidget(mh)
        outer.addWidget(perf)

        audio = self.panel()
        al = QVBoxLayout(audio)
        ah = QLabel("AUDIO")
        ah.setObjectName("section")
        al.addWidget(ah)
        ar = QHBoxLayout()
        ar.addWidget(self.button("Volume −", lambda:self.wpctl("5%-")))
        ar.addWidget(self.button("Mute", self.mute))
        ar.addWidget(self.button("Volume +", lambda:self.wpctl("5%+")))
        al.addLayout(ar)
        outer.addWidget(audio)

        stream = self.panel()
        sml = QVBoxLayout(stream)
        smh = QLabel("STREAMING")
        smh.setObjectName("section")
        sml.addWidget(smh)
        smr = QGridLayout()
        smr.addWidget(self.button("Go Live", lambda:spawn(["/usr/local/bin/mechos-stream-control","start-stream"])),0,0)
        smr.addWidget(self.button("End Stream", lambda:spawn(["/usr/local/bin/mechos-stream-control","stop-stream"])),0,1)
        smr.addWidget(self.button("Start Recording", lambda:spawn(["/usr/local/bin/mechos-stream-control","start-record"])),1,0)
        smr.addWidget(self.button("Stop Recording", lambda:spawn(["/usr/local/bin/mechos-stream-control","stop-record"])),1,1)
        smr.addWidget(self.button("Stream Center", lambda:spawn(["/usr/local/bin/mechos-stream-center"])),2,0)
        smr.addWidget(self.button("Open OBS", lambda:spawn(["/usr/local/bin/mechos-stream-control","launch-obs"])),2,1)
        sml.addLayout(smr)
        stream_note = QLabel("Streaming account/profile stays configured inside OBS Studio.")
        stream_note.setObjectName("muted")
        stream_note.setWordWrap(True)
        sml.addWidget(stream_note)
        outer.addWidget(stream)

        display = self.panel()
        dl = QVBoxLayout(display)
        dh = QLabel("DISPLAY")
        dh.setObjectName("section")
        dl.addWidget(dh)
        dr = QHBoxLayout()
        dr.addWidget(self.button("Brightness −", lambda:self.brightness("5%-")))
        dr.addWidget(self.button("Brightness +", lambda:self.brightness("+5%")))
        dl.addLayout(dr)
        outer.addWidget(display)

        connectivity = self.panel()
        cl = QVBoxLayout(connectivity)
        ch = QLabel("CONNECTIVITY")
        ch.setObjectName("section")
        cl.addWidget(ch)
        cr = QHBoxLayout()
        cr.addWidget(self.button("Toggle Wi-Fi", self.toggle_wifi))
        cr.addWidget(self.button("Toggle Bluetooth", self.toggle_bt))
        cl.addLayout(cr)
        outer.addWidget(connectivity)

        tools = self.panel()
        tl = QVBoxLayout(tools)
        th = QLabel("QUICK TOOLS")
        th.setObjectName("section")
        tl.addWidget(th)
        tr = QGridLayout()
        tr.addWidget(self.button("Update Center", lambda:spawn(["/usr/local/bin/mechos-update-center"])),0,0)
        tr.addWidget(self.button("Controller Settings", lambda:spawn(["systemsettings","kcm_gamecontroller"])),0,1)
        tr.addWidget(self.button("Audio Settings", lambda:spawn(["systemsettings","kcm_pulseaudio"])),1,0)
        tr.addWidget(self.button("Recorder", self.recorder),1,1)
        tl.addLayout(tr)
        outer.addWidget(tools)

        hotkeys = self.panel()
        hl = QVBoxLayout(hotkeys)
        hh = QLabel("MECHSCOPE HOTKEYS")
        hh.setObjectName("section")
        hl.addWidget(hh)
        info = QLabel(
            "Ctrl+Shift+M  Quick Actions\n"
            "Ctrl+Shift+P  Performance Center\n"
            "Ctrl+Shift+U  Update Center\n"
            "Ctrl+Shift+S  Steam Gamepad UI\n"
            "Ctrl+Shift+B  Stream Center\n"
            "Ctrl+Shift+L  Go Live\n"
            "Ctrl+Shift+K  End Stream\n"
            "Ctrl+Shift+R  Toggle Recording\n"
            "Ctrl+Shift+C  Creator Mode (from MechScope)\n"
            "Ctrl+Shift+D  Desktop Mode (from MechScope)\n"
            "Esc           Close Quick Actions"
        )
        info.setObjectName("muted")
        hl.addWidget(info)
        outer.addWidget(hotkeys)

        close = self.button("Close", self.close)
        outer.addWidget(close)
        outer.addStretch()

    def profile(self, name):
        if shutil.which("powerprofilesctl"):
            run(["powerprofilesctl","set",name])

    def toggle_hud(self):
        if shutil.which("mangohudctl"):
            p = run(["mangohudctl","toggle-hud"])
            if p and p.returncode == 0:
                return
        QMessageBox.information(
            self, "Performance Overlay",
            "The Gamescope MangoApp control socket is not ready.\n"
            "Use Right Shift + F12 to toggle the performance overlay."
        )

    def wpctl(self, value):
        if shutil.which("wpctl"):
            run(["wpctl","set-volume","@DEFAULT_AUDIO_SINK@",value])

    def mute(self):
        if shutil.which("wpctl"):
            run(["wpctl","set-mute","@DEFAULT_AUDIO_SINK@","toggle"])

    def brightness(self, value):
        if shutil.which("brightnessctl"):
            run(["brightnessctl","set",value])

    def toggle_wifi(self):
        if not shutil.which("nmcli"):
            return
        current = out(["nmcli","radio","wifi"])
        run(["nmcli","radio","wifi","off" if current == "enabled" else "on"])

    def toggle_bt(self):
        if not shutil.which("bluetoothctl"):
            return
        info = out(["bluetoothctl","show"]).lower()
        run(["bluetoothctl","power","off" if "powered: yes" in info else "on"])

    def recorder(self):
        if shutil.which("gpu-screen-recorder-gtk"):
            spawn(["gpu-screen-recorder-gtk"])
        elif shutil.which("gpu-screen-recorder"):
            spawn(["gpu-screen-recorder"])
        else:
            QMessageBox.information(self,"Recorder","GPU Screen Recorder is not available.")

    def keyPressEvent(self, event: QKeyEvent):
        if event.key() == Qt.Key.Key_Escape:
            self.close()
            return
        super().keyPressEvent(event)

app = QApplication(sys.argv)
app.setApplicationName("MechOS Quick Actions")
w = QuickActions()
w.show()
w.raise_()
w.activateWindow()
sys.exit(app.exec())
PYEOF
chmod 755 /workspace/archlive/airootfs/usr/local/bin/mechos-quick-actions

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-quick-actions-daemon << "PYEOF"
#!/usr/bin/env python3
import os
import select
import signal
import subprocess
import sys
import time
from pathlib import Path

try:
    from evdev import InputDevice, list_devices, ecodes
except Exception as exc:
    print(f"[MechOS Quick Actions] evdev unavailable: {exc}", file=sys.stderr)
    raise SystemExit(1)

UID = os.getuid()
PIDFILE = Path(f"/tmp/mechos-quick-actions-daemon-{UID}.pid")
LOG = Path.home()/".local/state/mechos/quick-actions-hotkeys.log"
LOG.parent.mkdir(parents=True, exist_ok=True)

overlay = None
devices = {}
pressed = {}
mode_down = {}

CTRL = {ecodes.KEY_LEFTCTRL, ecodes.KEY_RIGHTCTRL}
SHIFT = {ecodes.KEY_LEFTSHIFT, ecodes.KEY_RIGHTSHIFT}

def log(msg):
    try:
        with LOG.open("a") as f:
            f.write(f"{time.strftime('%F %T')} {msg}\n")
    except Exception:
        pass

def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except Exception:
        return False

if PIDFILE.exists():
    try:
        old = int(PIDFILE.read_text().strip())
        if old != os.getpid() and alive(old):
            raise SystemExit(0)
    except ValueError:
        pass

PIDFILE.write_text(str(os.getpid()))

def cleanup(*_):
    try:
        PIDFILE.unlink(missing_ok=True)
    except Exception:
        pass
    raise SystemExit(0)

signal.signal(signal.SIGTERM, cleanup)
signal.signal(signal.SIGINT, cleanup)

def launch(cmd):
    try:
        subprocess.Popen(cmd)
    except Exception as exc:
        log(f"launch failed {cmd}: {exc}")

def open_overlay():
    global overlay
    if overlay is not None and overlay.poll() is None:
        return
    try:
        overlay = subprocess.Popen(["/usr/local/bin/mechos-quick-actions"])
    except Exception as exc:
        log(f"overlay launch failed: {exc}")

def action(name):
    log(f"hotkey action: {name}")
    if name == "overlay":
        open_overlay()
    elif name == "performance":
        launch(["/usr/local/bin/mechos-performance-center"])
    elif name == "update":
        launch(["/usr/local/bin/mechos-update-center"])
    elif name == "steam":
        launch(["steam","-gamepadui"])
    elif name == "hud":
        launch(["mangohudctl","toggle-hud"])
    elif name == "volume-up":
        launch(["wpctl","set-volume","@DEFAULT_AUDIO_SINK@","5%+"])
    elif name == "volume-down":
        launch(["wpctl","set-volume","@DEFAULT_AUDIO_SINK@","5%-"])
    elif name == "stream-center":
        launch(["/usr/local/bin/mechos-stream-center"])
    elif name == "go-live":
        launch(["/usr/local/bin/mechos-stream-control","start-stream"])
    elif name == "end-stream":
        launch(["/usr/local/bin/mechos-stream-control","stop-stream"])
    elif name == "toggle-record":
        launch(["/usr/local/bin/mechos-stream-control","toggle-record"])

def rescan():
    global devices
    current = set(list_devices())

    for path in list(devices):
        if path not in current:
            try:
                devices[path].close()
            except Exception:
                pass
            devices.pop(path, None)
            pressed.pop(path, None)
            mode_down.pop(path, None)

    for path in current:
        if path in devices:
            continue
        try:
            d = InputDevice(path)
            caps = d.capabilities()
            keys = set(caps.get(ecodes.EV_KEY, []))
            # Keyboard or standard gamepad button device.
            interesting = (
                ecodes.KEY_M in keys or
                ecodes.BTN_MODE in keys or
                ecodes.BTN_NORTH in keys
            )
            if interesting:
                devices[path] = d
                pressed[path] = set()
                log(f"monitoring {path}: {d.name}")
            else:
                d.close()
        except Exception:
            pass

last_scan = 0.0
last_trigger = 0.0

while True:
    now = time.monotonic()
    if now - last_scan > 3.0:
        rescan()
        last_scan = now

    if not devices:
        time.sleep(0.25)
        continue

    try:
        ready, _, _ = select.select(list(devices.values()), [], [], 0.20)
    except Exception:
        devices = {}
        continue

    for d in ready:
        path = d.path
        try:
            events = d.read()
        except Exception:
            continue

        keys = pressed.setdefault(path, set())

        for ev in events:
            if ev.type != ecodes.EV_KEY:
                continue

            code = ev.code
            if ev.value in (1,2):
                keys.add(code)
            elif ev.value == 0:
                keys.discard(code)

            # Keyboard combinations.
            ctrl = bool(keys & CTRL)
            shift = bool(keys & SHIFT)

            if ev.value == 1 and ctrl and shift:
                mapping = {
                    ecodes.KEY_M: "overlay",
                    ecodes.KEY_P: "performance",
                    ecodes.KEY_U: "update",
                    ecodes.KEY_S: "steam",
                    ecodes.KEY_O: "hud",
                    ecodes.KEY_B: "stream-center",
                    ecodes.KEY_L: "go-live",
                    ecodes.KEY_K: "end-stream",
                    ecodes.KEY_R: "toggle-record",
                    ecodes.KEY_EQUAL: "volume-up",
                    ecodes.KEY_MINUS: "volume-down",
                }
                name = mapping.get(code)
                if name and time.monotonic() - last_trigger > 0.35:
                    action(name)
                    last_trigger = time.monotonic()

            # Standard Linux gamepad codes:
            # BTN_MODE = Guide/Home, BTN_NORTH = Y/Triangle.
            if code == ecodes.BTN_MODE:
                if ev.value == 1:
                    mode_down[path] = time.monotonic()
                elif ev.value == 0:
                    mode_down.pop(path, None)

            if code == ecodes.BTN_NORTH and ev.value == 1 and path in mode_down:
                if time.monotonic() - mode_down[path] >= 0.12 and time.monotonic() - last_trigger > 0.50:
                    action("overlay")
                    last_trigger = time.monotonic()
PYEOF
chmod 755 /workspace/archlive/airootfs/usr/local/bin/mechos-quick-actions-daemon

cat > /workspace/archlive/airootfs/usr/local/bin/mechscope << "PYEOF"
#!/usr/bin/env python3
import glob
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

from PyQt6.QtCore import Qt, QTimer
from PyQt6.QtGui import QFont, QKeyEvent, QPixmap
from PyQt6.QtWidgets import (
    QApplication, QDialog, QFrame, QGridLayout, QHBoxLayout, QLabel, QLineEdit,
    QMainWindow, QMessageBox, QPushButton, QScrollArea, QSizePolicy, QVBoxLayout,
    QWidget
)

try:
    import pygame
    HAVE_PYGAME = True
except Exception:
    HAVE_PYGAME = False

MODE_FILE = f"/tmp/mechos-next-mode-{os.getuid()}"
FALLBACK = os.environ.get("MECHOS_GAMING_FALLBACK") == "1"

STYLE = """
QWidget { background:#060914; color:#f3f7ff; font-family:Sans Serif; }
QFrame#top, QFrame#bottom {
    background:#080d1a; border:1px solid #162945;
}
QFrame#panel {
    background:#091122; border:1px solid #1c3352; border-radius:12px;
}
QFrame#hero {
    background:#0a1428; border:1px solid #275184; border-radius:14px;
}
QFrame#gameCard {
    background:#0b1321; border:1px solid #243552; border-radius:10px;
}
QFrame#gameCard:focus, QFrame#gameCard:hover {
    border:2px solid #7a54ff;
}
QLabel#brand { font-size:28px; font-weight:900; color:#f7f9ff; }
QLabel#scope { font-size:26px; font-weight:900; color:#b86cff; }
QLabel#section { color:#8fd8ff; font-size:14px; font-weight:800; }
QLabel#muted { color:#8fa0bb; }
QLabel#metric { color:#caa6ff; font-weight:700; }
QPushButton {
    background:#101a2b; border:1px solid #274566; border-radius:9px;
    padding:10px 13px; color:#eef6ff; font-weight:650;
}
QPushButton:hover, QPushButton:focus {
    background:#172a46; border:2px solid #6b7cff;
}
QPushButton#primary {
    background:#6425b8; border:1px solid #9d6cff; color:white;
}
QPushButton#mode {
    background:#0d1728; border:1px solid #293e60; text-align:center;
}
QPushButton#mode:focus, QPushButton#mode:hover {
    background:#432061; border:2px solid #a867ff;
}
QScrollArea { border:0; }
"""

def output(cmd):
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

def spawn(cmd):
    try:
        return subprocess.Popen(cmd)
    except Exception:
        return None

def write_mode(mode):
    try:
        Path(MODE_FILE).write_text(mode + "\n")
    except Exception:
        pass

def steam_roots():
    roots = []
    for p in [
        Path.home()/".local/share/Steam",
        Path.home()/".steam/steam",
        Path.home()/".var/app/com.valvesoftware.Steam/.local/share/Steam",
    ]:
        if p.exists():
            roots.append(p)
    expanded = list(roots)
    for root in roots:
        vdf = root/"steamapps/libraryfolders.vdf"
        if not vdf.exists():
            continue
        try:
            data = vdf.read_text(errors="ignore")
            for raw in re.findall(r'"path"\s+"([^"]+)"', data):
                path = Path(raw.replace("\\\\","/"))
                if path.exists() and path not in expanded:
                    expanded.append(path)
        except Exception:
            pass
    return expanded

def steam_games():
    games = []
    seen = set()
    last_played = {}
    for root in steam_roots():
        # Best-effort last-played extraction from localconfig.
        for cfg in root.glob("userdata/*/config/localconfig.vdf"):
            try:
                data = cfg.read_text(errors="ignore")
                for appid, ts in re.findall(r'"(\d+)"\s*\{[^{}]*?"LastPlayed"\s+"(\d+)"', data, re.S):
                    last_played[appid] = max(int(ts), last_played.get(appid, 0))
            except Exception:
                pass

    for root in steam_roots():
        appdir = root/"steamapps"
        for manifest in appdir.glob("appmanifest_*.acf"):
            try:
                data = manifest.read_text(errors="ignore")
                appid_m = re.search(r'"appid"\s+"(\d+)"', data)
                name_m = re.search(r'"name"\s+"([^"]+)"', data)
                if not appid_m or not name_m:
                    continue
                appid = appid_m.group(1)
                if appid in seen:
                    continue
                seen.add(appid)
                name = name_m.group(1)
                art = ""
                candidates = [
                    root/f"appcache/librarycache/{appid}_library_600x900.jpg",
                    root/f"appcache/librarycache/{appid}_library_600x900.png",
                    root/f"appcache/librarycache/{appid}_header.jpg",
                ]
                for c in candidates:
                    if c.exists():
                        art = str(c)
                        break
                games.append({
                    "appid": appid,
                    "name": name,
                    "art": art,
                    "last": last_played.get(appid, int(manifest.stat().st_mtime)),
                })
            except Exception:
                pass
    games.sort(key=lambda x: x["last"], reverse=True)
    return games

def cpu_percent():
    line = output(["bash","-lc","top -bn1 | awk '/Cpu\\(s\\)/ {printf \"%.0f\",100-$8;exit}'"])
    return line or "?"

def ram_percent():
    return output(["bash","-lc","free | awk '/Mem:/ {printf \"%.0f\",($3/$2)*100}'"]) or "?"

def disk_percent():
    return output(["bash","-lc","df / | awk 'NR==2 {gsub(/%/,\"\",$5); print $5}'"]) or "?"

def gpu_name():
    return output(["bash","-lc","lspci | grep -Ei 'VGA|3D|Display' | sed 's/^[^ ]* //' | head -n1"]) or "Unknown GPU"

def network_name():
    return output(["bash","-lc","nmcli -t -f NAME connection show --active 2>/dev/null | head -n1"]) or "Offline"

class GameButton(QPushButton):
    def __init__(self, game, launch_cb):
        super().__init__()
        self.game = game
        self.setMinimumSize(150, 190)
        self.setMaximumWidth(190)
        self.setText(game["name"])
        self.setStyleSheet("""
            QPushButton {
              text-align:center; padding:10px; background:#0b1321;
              border:1px solid #263a5a; border-radius:11px;
              font-size:13px; font-weight:700;
            }
            QPushButton:hover, QPushButton:focus {
              background:#152743; border:2px solid #7b5bff;
            }
        """)
        if game.get("art"):
            pm = QPixmap(game["art"])
            if not pm.isNull():
                self.setIcon(pm)
                self.setIconSize(pm.scaled(125,145,Qt.AspectRatioMode.KeepAspectRatio,
                                           Qt.TransformationMode.SmoothTransformation).size())
        self.clicked.connect(lambda: launch_cb(game))

class UnifiedStore(QDialog):
    STORES=[
      ("Steam","Games are purchased and downloaded through Steam.","https://store.steampowered.com/search/?term={query}",["steam","-gamepadui"]),
      ("Epic Games","Official Epic checkout; downloads are managed by Heroic.","https://store.epicgames.com/browse?q={query}",["flatpak","run","com.heroicgameslauncher.hgl"]),
      ("GOG","Official GOG checkout; downloads are managed by Heroic.","https://www.gog.com/en/games?query={query}",["flatpak","run","com.heroicgameslauncher.hgl"]),
      ("Amazon Games","Official Amazon Gaming page; supported downloads are managed by Heroic.","https://gaming.amazon.com/home",["flatpak","run","com.heroicgameslauncher.hgl"]),
    ]

    def __init__(self,parent=None):
        super().__init__(parent)
        self.setWindowTitle("MechScope Unified Store")
        self.resize(1050,720)
        self.setStyleSheet(STYLE)
        outer=QVBoxLayout(self)
        title=QLabel("UNIFIED STORE"); title.setObjectName("scope"); outer.addWidget(title)
        note=QLabel("Find games across official stores. Checkout, account authentication and payment stay on each store's official page. Downloads and updates stay inside the authorized launcher.")
        note.setObjectName("muted"); note.setWordWrap(True); outer.addWidget(note)
        searchrow=QHBoxLayout()
        self.search=QLineEdit(); self.search.setPlaceholderText("Search for a game")
        self.search.returnPressed.connect(self.search_all); searchrow.addWidget(self.search,1)
        search=QPushButton("Search All Stores"); search.setObjectName("primary"); search.clicked.connect(self.search_all); searchrow.addWidget(search)
        outer.addLayout(searchrow)
        grid=QGridLayout(); grid.setSpacing(12)
        for i,store in enumerate(self.STORES):
            name,description,url,launcher=store
            card=QFrame(); card.setObjectName("panel"); layout=QVBoxLayout(card)
            heading=QLabel(name); heading.setObjectName("section"); layout.addWidget(heading)
            detail=QLabel(description); detail.setObjectName("muted"); detail.setWordWrap(True); layout.addWidget(detail)
            browse=QPushButton("Browse / Buy on "+name)
            browse.clicked.connect(lambda _,u=url:self.open_store(u)); layout.addWidget(browse)
            downloads=QPushButton("Open Downloads / Library")
            downloads.clicked.connect(lambda _,c=launcher:self.open_launcher(c)); layout.addWidget(downloads)
            grid.addWidget(card,i//2,i%2)
        outer.addLayout(grid)
        status=QFrame(); status.setObjectName("panel"); sl=QVBoxLayout(status)
        st=QLabel("DOWNLOAD MANAGEMENT"); st.setObjectName("section"); sl.addWidget(st)
        info=QLabel("After checkout, open the matching Downloads / Library button and install the game. Return to MechScope and select Refresh Game Library when the launcher finishes.")
        info.setObjectName("muted"); info.setWordWrap(True); sl.addWidget(info)
        buttons=QHBoxLayout()
        refresh=QPushButton("Refresh Game Library"); refresh.clicked.connect(self.refresh_library); buttons.addWidget(refresh)
        lutris=QPushButton("Open Lutris Imports"); lutris.clicked.connect(lambda:spawn(["lutris"])); buttons.addWidget(lutris)
        close=QPushButton("Return to MechScope"); close.clicked.connect(self.accept); buttons.addWidget(close)
        sl.addLayout(buttons); outer.addWidget(status)

    def query(self):
        return quote_plus(self.search.text().strip())

    def open_store(self,url):
        target=url.format(query=self.query())
        spawn(["xdg-open",target])

    def search_all(self):
        if not self.search.text().strip():
            QMessageBox.information(self,"Unified Store","Enter a game name first.")
            return
        for _,_,url,_ in self.STORES[:3]: self.open_store(url)

    def open_launcher(self,command):
        if command[0]=="flatpak" and output(["flatpak","info","--user","com.heroicgameslauncher.hgl"])=="":
            # System-scope Flatpaks are also valid; let Flatpak report any real launch error.
            pass
        if spawn(command) is None:
            QMessageBox.warning(self,"Unified Store","The selected launcher is not installed yet. Install it from Creator Mode App Store.")

    def refresh_library(self):
        count=len(steam_games())
        QMessageBox.information(self,"Game Library",f"Library scan completed. {count} installed Steam game(s) detected. Heroic and Lutris continue managing their own downloads.")

class MechScope(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MechScope 2.0")
        self.setWindowFlag(Qt.WindowType.FramelessWindowHint, True)
        self.setStyleSheet(STYLE)
        self.games = steam_games()
        self.focusables = []
        self.focus_index = 0
        self.gamepad = None
        self.last_pad_count = -1
        self.build_ui()
        self.setup_gamepad()
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.tick)
        self.timer.start(500)
        self.clock_timer = QTimer(self)
        self.clock_timer.timeout.connect(self.refresh_stats)
        self.clock_timer.start(2000)
        self.hotkey_daemon = None
        self.start_hotkey_daemon()
        self.refresh_stats()

    def panel(self, name="panel"):
        p = QFrame()
        p.setObjectName(name)
        return p

    def focus_button(self, b):
        self.focusables.append(b)
        return b

    def build_ui(self):
        root = QWidget()
        self.setCentralWidget(root)
        outer = QVBoxLayout(root)
        outer.setContentsMargins(0,0,0,0)
        outer.setSpacing(0)

        top = self.panel("top")
        tl = QHBoxLayout(top)
        tl.setContentsMargins(18,9,18,9)
        brand = QLabel("MECHOS")
        brand.setObjectName("brand")
        tl.addWidget(brand)
        tl.addStretch()
        scope = QLabel("MECHSCOPE 2.0")
        scope.setObjectName("scope")
        tl.addWidget(scope)
        tl.addStretch()
        self.net_label = QLabel()
        self.net_label.setObjectName("metric")
        tl.addWidget(self.net_label)
        self.time_label = QLabel()
        self.time_label.setObjectName("metric")
        tl.addWidget(self.time_label)
        outer.addWidget(top)

        body = QHBoxLayout()
        body.setContentsMargins(18,14,18,14)
        body.setSpacing(14)

        main = QVBoxLayout()
        hero = self.panel("hero")
        hl = QHBoxLayout(hero)
        hero_text = QVBoxLayout()
        hlabel = QLabel("YOUR GAME LIBRARY")
        hlabel.setObjectName("section")
        hero_text.addWidget(hlabel)
        self.hero_name = QLabel(self.games[0]["name"] if self.games else "Steam Gamepad Library")
        self.hero_name.setFont(QFont("Sans Serif", 24, QFont.Weight.Bold))
        self.hero_name.setWordWrap(True)
        hero_text.addWidget(self.hero_name)
        hsub = QLabel("Launch installed Steam games directly, or open Steam Gamepad UI.")
        hsub.setObjectName("muted")
        hsub.setWordWrap(True)
        hero_text.addWidget(hsub)
        row = QHBoxLayout()
        play = self.focus_button(QPushButton("Play / Open Steam"))
        play.setObjectName("primary")
        play.clicked.connect(self.launch_featured)
        row.addWidget(play)
        library = self.focus_button(QPushButton("Steam Library"))
        library.clicked.connect(self.open_steam)
        row.addWidget(library)
        store = self.focus_button(QPushButton("Unified Store"))
        store.clicked.connect(self.open_store)
        row.addWidget(store)
        hero_text.addLayout(row)
        hl.addLayout(hero_text, 2)

        hero_stats = QVBoxLayout()
        st = QLabel("SYSTEM STATUS")
        st.setObjectName("section")
        hero_stats.addWidget(st)
        self.stats_label = QLabel()
        self.stats_label.setObjectName("metric")
        self.stats_label.setWordWrap(True)
        hero_stats.addWidget(self.stats_label)
        gpu = QLabel(gpu_name())
        gpu.setObjectName("muted")
        gpu.setWordWrap(True)
        hero_stats.addWidget(gpu)
        hl.addLayout(hero_stats, 1)
        main.addWidget(hero)

        section = QLabel("RECENT LIBRARY")
        section.setObjectName("section")
        main.addWidget(section)

        game_scroll = QScrollArea()
        game_scroll.setWidgetResizable(True)
        game_scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        game_wrap = QWidget()
        gg = QGridLayout(game_wrap)
        gg.setSpacing(10)

        visible = self.games[:8]
        if visible:
            for i,g in enumerate(visible):
                b = GameButton(g, self.launch_game)
                self.focus_button(b)
                gg.addWidget(b, i//4, i%4)
        else:
            msg = QLabel("No installed Steam manifests found yet. Steam Gamepad UI is ready.")
            msg.setObjectName("muted")
            gg.addWidget(msg,0,0)
        game_scroll.setWidget(game_wrap)
        main.addWidget(game_scroll, 1)

        quick_modes = QLabel("QUICK MODES")
        quick_modes.setObjectName("section")
        main.addWidget(quick_modes)
        modes = QHBoxLayout()
        for label, cb in [
            ("Gaming Mode", lambda: None),
            ("Desktop Mode", lambda: self.switch_mode("desktop")),
            ("Creator Mode", lambda: self.switch_mode("creator")),
            ("VR / SteamVR", self.open_vr),
        ]:
            b = self.focus_button(QPushButton(label))
            b.setObjectName("mode")
            b.clicked.connect(cb)
            modes.addWidget(b)
        main.addLayout(modes)
        body.addLayout(main, 4)

        side = QVBoxLayout()
        quick = self.panel()
        ql = QVBoxLayout(quick)
        qtitle = QLabel("QUICK ACCESS")
        qtitle.setObjectName("section")
        ql.addWidget(qtitle)
        actions = [
            ("Unified Store", ["/usr/local/bin/mechscope","--store"]),
            ("Quick Actions", ["/usr/local/bin/mechos-quick-actions"]),
            ("Stream Center", ["/usr/local/bin/mechos-stream-center"]),
            ("Go Live", ["/usr/local/bin/mechos-stream-control","start-stream"]),
            ("Performance Center", ["/usr/local/bin/mechos-performance-center"]),
            ("Update Center", ["/usr/local/bin/mechos-update-center"]),
            ("Controller Settings", ["systemsettings","kcm_gamecontroller"]),
            ("Display Settings", ["systemsettings","kcm_kscreen"]),
            ("Audio Settings", ["systemsettings","kcm_pulseaudio"]),
        ]
        for label,cmd in actions:
            b = self.focus_button(QPushButton(label))
            b.clicked.connect(lambda checked=False,c=cmd: spawn(c))
            ql.addWidget(b)
        side.addWidget(quick)

        launchers = self.panel()
        ll = QVBoxLayout(launchers)
        ltitle = QLabel("LAUNCHERS")
        ltitle.setObjectName("section")
        ll.addWidget(ltitle)
        for label, cmd in [
            ("Steam", ["steam","-gamepadui"]),
            ("Lutris", ["lutris"]),
            ("Heroic", ["flatpak","run","com.heroicgameslauncher.hgl"]),
        ]:
            b = self.focus_button(QPushButton(label))
            b.clicked.connect(lambda checked=False,c=cmd: spawn(c))
            ll.addWidget(b)
        side.addWidget(launchers)

        power = self.panel()
        pl = QVBoxLayout(power)
        ptitle = QLabel("SYSTEM")
        ptitle.setObjectName("section")
        pl.addWidget(ptitle)
        restart = self.focus_button(QPushButton("Restart MechOS"))
        restart.clicked.connect(lambda: spawn(["systemctl","reboot"]))
        pl.addWidget(restart)
        shutdown = self.focus_button(QPushButton("Shut Down"))
        shutdown.clicked.connect(lambda: spawn(["systemctl","poweroff"]))
        pl.addWidget(shutdown)
        side.addWidget(power)
        side.addStretch()
        body.addLayout(side, 1)

        outer.addLayout(body,1)

        bottom = self.panel("bottom")
        bl = QHBoxLayout(bottom)
        hint = QLabel("A/Enter Select   •   B/Esc Back/Steam   •   D-pad/Arrows Navigate")
        hint.setObjectName("muted")
        bl.addWidget(hint)
        bl.addStretch()
        self.pad_label = QLabel("Controller: detecting")
        self.pad_label.setObjectName("metric")
        bl.addWidget(self.pad_label)
        outer.addWidget(bottom)

        if self.focusables:
            self.focusables[0].setFocus()

    def setup_gamepad(self):
        if not HAVE_PYGAME:
            self.pad_label.setText("Controller: pygame unavailable")
            return
        try:
            pygame.init()
            pygame.joystick.init()
            self.refresh_gamepad()
        except Exception:
            self.gamepad = None

    def refresh_gamepad(self):
        if not HAVE_PYGAME:
            return
        try:
            count = pygame.joystick.get_count()
            if count == self.last_pad_count:
                return
            self.last_pad_count = count
            self.gamepad = None
            if count:
                self.gamepad = pygame.joystick.Joystick(0)
                self.gamepad.init()
                self.pad_label.setText("Controller: " + self.gamepad.get_name()[:30])
            else:
                self.pad_label.setText("Controller: none")
        except Exception:
            pass

    def move_focus(self, delta):
        if not self.focusables:
            return
        self.focus_index = (self.focus_index + delta) % len(self.focusables)
        self.focusables[self.focus_index].setFocus()

    def keyPressEvent(self, event: QKeyEvent):
        mods = event.modifiers()
        ctrl = bool(mods & Qt.KeyboardModifier.ControlModifier)
        shift = bool(mods & Qt.KeyboardModifier.ShiftModifier)

        if ctrl and shift:
            if event.key() == Qt.Key.Key_M:
                spawn(["/usr/local/bin/mechos-quick-actions"])
                return
            if event.key() == Qt.Key.Key_P:
                spawn(["/usr/local/bin/mechos-performance-center"])
                return
            if event.key() == Qt.Key.Key_U:
                spawn(["/usr/local/bin/mechos-update-center"])
                return
            if event.key() == Qt.Key.Key_S:
                self.open_steam()
                return
            if event.key() == Qt.Key.Key_C:
                self.switch_mode("creator")
                return
            if event.key() == Qt.Key.Key_D:
                self.switch_mode("desktop")
                return
            if event.key() == Qt.Key.Key_O:
                spawn(["mangohudctl","toggle-hud"])
                return
            if event.key() == Qt.Key.Key_B:
                spawn(["/usr/local/bin/mechos-stream-center"])
                return
            if event.key() == Qt.Key.Key_L:
                spawn(["/usr/local/bin/mechos-stream-control","start-stream"])
                return
            if event.key() == Qt.Key.Key_K:
                spawn(["/usr/local/bin/mechos-stream-control","stop-stream"])
                return
            if event.key() == Qt.Key.Key_R:
                spawn(["/usr/local/bin/mechos-stream-control","toggle-record"])
                return

        if event.key() in (Qt.Key.Key_Down, Qt.Key.Key_Right, Qt.Key.Key_S, Qt.Key.Key_D):
            self.move_focus(1)
        elif event.key() in (Qt.Key.Key_Up, Qt.Key.Key_Left, Qt.Key.Key_W, Qt.Key.Key_A):
            self.move_focus(-1)
        elif event.key() in (Qt.Key.Key_Return, Qt.Key.Key_Enter, Qt.Key.Key_Space):
            w = self.focusWidget()
            if isinstance(w,QPushButton):
                w.click()
        elif event.key() == Qt.Key.Key_Escape:
            self.open_steam()
        else:
            super().keyPressEvent(event)

    def start_hotkey_daemon(self):
        if not Path("/usr/local/bin/mechos-quick-actions-daemon").exists():
            return
        try:
            self.hotkey_daemon = subprocess.Popen(
                ["/usr/local/bin/mechos-quick-actions-daemon"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            self.hotkey_daemon = None

    def closeEvent(self, event):
        if self.hotkey_daemon is not None and self.hotkey_daemon.poll() is None:
            try:
                self.hotkey_daemon.terminate()
            except Exception:
                pass
        super().closeEvent(event)

    def tick(self):
        self.refresh_gamepad()
        if not self.gamepad or not HAVE_PYGAME:
            return
        try:
            for ev in pygame.event.get():
                if ev.type == pygame.JOYHATMOTION:
                    if ev.value[0] > 0 or ev.value[1] < 0:
                        self.move_focus(1)
                    elif ev.value[0] < 0 or ev.value[1] > 0:
                        self.move_focus(-1)
                elif ev.type == pygame.JOYBUTTONDOWN:
                    if ev.button == 0:
                        w = self.focusWidget()
                        if isinstance(w,QPushButton):
                            w.click()
                    elif ev.button == 1:
                        self.open_steam()
        except Exception:
            pass

    def refresh_stats(self):
        self.stats_label.setText(
            f"CPU {cpu_percent()}%   •   RAM {ram_percent()}%   •   DISK {disk_percent()}%"
        )
        self.net_label.setText("NET  " + network_name())
        self.time_label.setText(time.strftime("%I:%M %p"))

    def launch_featured(self):
        if self.games:
            self.launch_game(self.games[0])
        else:
            self.open_steam()

    def launch_game(self, game):
        spawn(["xdg-open", f"steam://rungameid/{game['appid']}"])

    def open_steam(self):
        spawn(["steam","-gamepadui"])

    def open_store(self):
        dialog=UnifiedStore(self)
        dialog.exec()

    def open_vr(self):
        # SteamVR app id is 250820. This opens through Steam; actual headset/runtime
        # support remains dependent on SteamVR/Linux and the connected hardware.
        if shutil.which("steam"):
            spawn(["xdg-open","steam://rungameid/250820"])
        else:
            QMessageBox.information(self,"MechOS VR","Steam is not installed.")

    def switch_mode(self, mode):
        if FALLBACK:
            if mode == "creator":
                spawn(["/usr/local/bin/mechos-creator-mode"])
            self.close()
            return
        write_mode(mode)
        QApplication.quit()

app = QApplication(sys.argv)
app.setApplicationName("MechScope 2.0")
if "--store" in sys.argv:
    dialog=UnifiedStore(); dialog.showMaximized(); sys.exit(app.exec())
w = MechScope()
w.showFullScreen()
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
set -euo pipefail

# Logging out is enough because SDDM is configured to auto-login to the
# MechOS Gaming session. This avoids requiring passwordless sudo on an
# installed system.
if command -v qdbus6 >/dev/null 2>&1; then
  qdbus6 org.kde.Shutdown /Shutdown logout || true
elif command -v qdbus >/dev/null 2>&1; then
  qdbus org.kde.Shutdown /Shutdown logout || true
else
  loginctl terminate-session "${XDG_SESSION_ID:-}" 2>/dev/null || true
fi
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

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
mkdir -p "$STATE_DIR"
SESSION_LOG="$STATE_DIR/gaming-session.log"
MECHSCOPE_LOG="$STATE_DIR/mechscope.log"

exec >>"$SESSION_LOG" 2>&1
echo
echo "===== MechOS Gaming Session $(date -Is) ====="
echo "User: $(id)"
echo "Session: ${XDG_SESSION_TYPE:-unknown}"
echo "Desktop: ${XDG_CURRENT_DESKTOP:-unknown}"

start_plasma_fallback() {
  echo "[MechOS] Starting safe Plasma fallback."
  export MECHOS_GAMING_FALLBACK=1

  (
    sleep 4
    echo "===== MechScope fallback $(date -Is) =====" >>"$MECHSCOPE_LOG"
    /usr/local/bin/mechscope >>"$MECHSCOPE_LOG" 2>&1
  ) &

  if command -v startplasma-wayland >/dev/null 2>&1; then
    exec /usr/bin/startplasma-wayland
  fi

  echo "[MechOS] startplasma-wayland is unavailable; launching MechScope directly."
  exec /usr/local/bin/mechscope
}

# Virtual machines are deliberately sent to Plasma fallback. Gamescope inside
# nested/virtual graphics stacks is not required to test the MechOS UI and can
# hang even when a Vulkan loader is technically present.
if command -v systemd-detect-virt >/dev/null 2>&1; then
  VIRT="$(systemd-detect-virt 2>/dev/null || true)"
  if [ -n "$VIRT" ] && [ "$VIRT" != "none" ]; then
    echo "[MechOS] Virtualization detected: $VIRT"
    start_plasma_fallback
  fi
fi

# Never allow a broken Vulkan probe to block the login session forever.
VULKAN_OK=0
if command -v vulkaninfo >/dev/null 2>&1; then
  if timeout 8s vulkaninfo --summary >/tmp/mechos-vulkan-summary.log 2>&1; then
    VULKAN_OK=1
    echo "[MechOS] Vulkan preflight passed."
  else
    RC=$?
    echo "[MechOS] Vulkan preflight failed/timed out (rc=$RC)."
  fi
else
  echo "[MechOS] vulkaninfo not found."
fi

if [ "$VULKAN_OK" -ne 1 ] || ! command -v gamescope >/dev/null 2>&1; then
  start_plasma_fallback
fi

# Quick Gamescope smoke test. If Gamescope itself cannot create a compositor,
# do not trap the user behind the boot splash.
if ! timeout 12s gamescope -f -- /usr/bin/true >/tmp/mechos-gamescope-test.log 2>&1; then
  RC=$?
  echo "[MechOS] Gamescope smoke test failed/timed out (rc=$RC)."
  start_plasma_fallback
fi

echo "[MechOS] Starting real Gamescope + MechScope mode."

while true; do
  rm -f "$MODE_FILE"

  echo "===== MechScope Gamescope launch $(date -Is) =====" >>"$MECHSCOPE_LOG"
  gamescope -e -f --mangoapp -- /usr/local/bin/mechscope >>"$MECHSCOPE_LOG" 2>&1
  GS_RC=$?
  echo "[MechOS] Gamescope/MechScope exited rc=$GS_RC"

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
      # If Gamescope failed immediately, stop looping forever and give the user
      # a usable Plasma session instead.
      if [ "$GS_RC" -ne 0 ]; then
        echo "[MechOS] Gamescope failed; entering safe fallback."
        start_plasma_fallback
      fi
      continue
      ;;
    *)
      echo "[MechOS] Unknown requested mode '$NEXT'; returning to MechScope."
      continue
      ;;
  esac
done
EOF
chmod 755 /workspace/archlive/airootfs/usr/local/bin/mechos-gaming-session

cat > /workspace/archlive/airootfs/usr/local/bin/mechos-boot-diagnostics << "EOF"
#!/usr/bin/env bash
set +e

echo "=== MechOS Boot Diagnostics ==="
echo
echo "--- Virtualization ---"
systemd-detect-virt 2>&1 || true
echo
echo "--- Session ---"
printf 'XDG_SESSION_TYPE=%s\n' "${XDG_SESSION_TYPE:-}"
printf 'XDG_CURRENT_DESKTOP=%s\n' "${XDG_CURRENT_DESKTOP:-}"
echo
echo "--- GPU ---"
lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' || true
echo
echo "--- Vulkan (8 second limit) ---"
timeout 8s vulkaninfo --summary 2>&1 || true
echo
echo "--- SDDM ---"
systemctl --no-pager --full status sddm.service 2>&1 || true
echo
echo "--- Boot timing ---"
systemd-analyze time 2>&1 || true
echo
echo "--- Slowest boot units ---"
systemd-analyze blame 2>&1 | head -n 30 || true
echo
echo "--- Critical boot chain ---"
systemd-analyze critical-chain graphical.target 2>&1 || true
echo
echo "--- Gaming session log ---"
cat "${XDG_STATE_HOME:-$HOME/.local/state}/mechos/gaming-session.log" 2>/dev/null || true
echo
echo "--- MechScope log ---"
cat "${XDG_STATE_HOME:-$HOME/.local/state}/mechos/mechscope.log" 2>/dev/null || true
echo
echo "--- Gamescope smoke-test log ---"
cat /tmp/mechos-gamescope-test.log 2>/dev/null || true
echo
echo "--- Vulkan preflight log ---"
cat /tmp/mechos-vulkan-summary.log 2>/dev/null || true
EOF
chmod 755 /workspace/archlive/airootfs/usr/local/bin/mechos-boot-diagnostics

mkdir -p /workspace/archlive/airootfs/usr/share/wayland-sessions
cat > /workspace/archlive/airootfs/usr/share/wayland-sessions/mechos-gaming.desktop << "EOF"
[Desktop Entry]
Name=MechOS Gaming Mode
Comment=MechOS Gamescope + MechScope 2.0
Exec=/usr/local/bin/mechos-gaming-session
Type=Application
DesktopNames=MechOS;Gamescope;Steam;
EOF

# ---------- ARCH / LIVE DESKTOP DEFAULTS ----------
mkdir -p /workspace/archlive/airootfs/etc/sddm.conf.d
cat > /workspace/archlive/airootfs/etc/sddm.conf.d/mechos.conf << "EOF"
[Autologin]
User=mechos
Session=plasma.desktop
Relogin=false
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

# Never block the graphical live boot waiting for DHCP or internet access.
rm -f \
  /workspace/archlive/airootfs/etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service \
  /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager-wait-online.service \
  || true
ln -sf /dev/null \
  /workspace/archlive/airootfs/etc/systemd/system/NetworkManager-wait-online.service

# Keep systemd-resolved for DNS, but do not let time synchronization
# block the graphical boot if the VM/PC has no network yet.
mkdir -p /workspace/archlive/airootfs/etc/systemd/system/sysinit.target.wants
ln -sf /usr/lib/systemd/system/systemd-resolved.service \
  /workspace/archlive/airootfs/etc/systemd/system/sysinit.target.wants/systemd-resolved.service
ln -sf /run/systemd/resolve/stub-resolv.conf \
  /workspace/archlive/airootfs/etc/resolv.conf
ln -sf /dev/null \
  /workspace/archlive/airootfs/etc/systemd/system/systemd-time-wait-sync.service

# Bluetooth is available in the live image but is not part of the critical
# boot path. The installed-system firstboot enables it permanently.
rm -f /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/bluetooth.service || true
ln -sf /usr/lib/systemd/system/sddm.service \
  /workspace/archlive/airootfs/etc/systemd/system/display-manager.service

mkdir -p /workspace/archlive/airootfs/etc/systemd/system/sddm.service.d
cat > /workspace/archlive/airootfs/etc/systemd/system/sddm.service.d/mechos-live.conf << "EOF"
[Unit]
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
TimeoutStartSec=25s
EOF

sed -i "s/^iso_name=.*/iso_name=\"mechos\"/" /workspace/archlive/profiledef.sh
sed -i "s/^iso_label=.*/iso_label=\"MECHOS_$(date +%Y%m)\"/" /workspace/archlive/profiledef.sh
sed -i "s/^iso_publisher=.*/iso_publisher=\"MechOS\"/" /workspace/archlive/profiledef.sh
sed -i "s/^iso_application=.*/iso_application=\"MechOS Arch + MechScope + Creator GUI + Performance\"/" /workspace/archlive/profiledef.sh


# ---------- FULL INSTALLED-SYSTEM DEPLOYMENT ----------
mkdir -p /workspace/archlive/airootfs/usr/share/mechos/install-payload

cat > /workspace/archlive/airootfs/usr/share/mechos/install-payload/mechos-postinstall-target << "TARGETEOF"
#!/usr/bin/env bash
set -euxo pipefail

PORT=45811
BASE_URL="http://127.0.0.1:${PORT}"
PAYLOAD="/tmp/mechos-rootfs.tar.zst"
LOG="/var/log/mechos-postinstall.log"

exec > >(tee -a "$LOG") 2>&1

if [ "$(id -u)" -ne 0 ]; then
  echo "MechOS post-install must run as root." >&2
  exit 1
fi

echo "=== MechOS post-install starting ==="

# Steam and 32-bit gaming libraries need multilib.
if grep -q '^\#\[multilib\]' /etc/pacman.conf 2>/dev/null; then
  sed -i "/^\#\[multilib\]/,/^\#Include = \/etc\/pacman.d\/mirrorlist/ s/^\#//" /etc/pacman.conf
fi

pacman -Sy --noconfirm

# The installed machine gets the same core experience as the live ISO.
# GPU-specific NVIDIA modules are selected later by mechos-gpu-setup.
pacman -S --needed --noconfirm \
  plasma-meta sddm konsole dolphin ark kate kdialog firefox \
  networkmanager network-manager-applet bluez bluez-utils \
  pipewire pipewire-alsa pipewire-pulse wireplumber \
  xdg-desktop-portal xdg-desktop-portal-kde \
  steam gamescope lutris gamemode lib32-gamemode \
  mangohud lib32-mangohud wine wine-mono wine-gecko \
  winetricks protontricks vulkan-tools \
  mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon \
  vulkan-intel lib32-vulkan-intel \
  linux-headers linux-firmware \
  ntfs-3g exfatprogs btrfs-progs dosfstools e2fsprogs f2fs-tools xfsprogs \
  git git-lfs curl wget unzip zip p7zip sudo flatpak arch-install-scripts grub efibootmgr os-prober \
  base-devel cmake ninja clang python python-pip python-pygame python-evdev python-websocket-client python-pyqt6 brightnessctl \
  ffmpeg blender obs-studio kdenlive krita \
  plymouth zram-generator power-profiles-daemon irqbalance cpupower \
  amd-ucode intel-ucode switcheroo-control nvidia-prime \
  smartmontools nvme-cli btop pacman-contrib snapper libva-utils pciutils usbutils \
  gpu-screen-recorder gpu-screen-recorder-ui intel-media-driver libva-mesa-driver

curl -fsSL "$BASE_URL/mechos-rootfs.tar.zst" -o "$PAYLOAD"
tar --zstd -xpf "$PAYLOAD" -C /
rm -f "$PAYLOAD"

# Pick the first real wheel/sudo user created by Archinstall.
MECHOS_USER="$(
  awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd |
  while read -r u; do
    if id -nG "$u" 2>/dev/null | grep -qw wheel; then
      echo "$u"
      break
    fi
  done
)"

if [ -z "${MECHOS_USER:-}" ]; then
  MECHOS_USER="$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd)"
fi

if [ -z "${MECHOS_USER:-}" ]; then
  echo "Could not identify the installed desktop user." >&2
  exit 1
fi

echo "Configuring MechOS for user: $MECHOS_USER"

# Installed machines use their real account, never the live 'mechos' account.
rm -f /etc/sudoers.d/10-mechos-live
rm -f /usr/lib/sysusers.d/mechos.conf
rm -f /usr/lib/tmpfiles.d/mechos.conf
rm -f /etc/xdg/autostart/mechos-live-welcome.desktop

mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/mechos.conf <<SDDMEOF
[Autologin]
User=$MECHOS_USER
Session=mechos-gaming.desktop
Relogin=true
SDDMEOF

# Creator folders belong to the real installed user.
HOME_DIR="$(getent passwd "$MECHOS_USER" | cut -d: -f6)"
mkdir -p \
  "$HOME_DIR/MechOS/Projects" \
  "$HOME_DIR/MechOS/Assets" \
  "$HOME_DIR/MechOS/Recordings" \
  "$HOME_DIR/MechOS/Exports" \
  "$HOME_DIR/Desktop"

cp -f /usr/share/applications/mechos-return-to-mechscope.desktop \
  "$HOME_DIR/Desktop/Return-to-MechScope.desktop" 2>/dev/null || true
cp -f /usr/share/applications/mechos-performance-center.desktop \
  "$HOME_DIR/Desktop/Performance-Center.desktop" 2>/dev/null || true
chown -R "$MECHOS_USER:$MECHOS_USER" "$HOME_DIR/MechOS" "$HOME_DIR/Desktop"
chmod +x "$HOME_DIR/Desktop/"*.desktop 2>/dev/null || true

# Stable services.
systemctl enable NetworkManager.service
systemctl enable bluetooth.service 2>/dev/null || true
systemctl enable sddm.service
systemctl enable fstrim.timer 2>/dev/null || true
systemctl enable irqbalance.service 2>/dev/null || true
systemctl enable power-profiles-daemon.service 2>/dev/null || true
systemctl enable switcheroo-control.service 2>/dev/null || true
systemctl enable mechos-firstboot.service 2>/dev/null || true

# Keep NetworkManager as the one network manager.
systemctl disable systemd-networkd.service 2>/dev/null || true
systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true

# Plymouth boot theme + quiet graphical handoff.
mkdir -p /etc/plymouth
cat > /etc/plymouth/plymouthd.conf <<'PLYEOF'
[Daemon]
Theme=mechos
ShowDelay=0
DeviceTimeout=8
PLYEOF

if [ -f /etc/mkinitcpio.conf ]; then
  if grep -q '^HOOKS=' /etc/mkinitcpio.conf && ! grep -q 'plymouth' /etc/mkinitcpio.conf; then
    if grep -q ' systemd ' /etc/mkinitcpio.conf; then
      sed -i -E 's/( systemd)( )/\1 plymouth\2/' /etc/mkinitcpio.conf
    elif grep -q ' udev ' /etc/mkinitcpio.conf; then
      sed -i -E 's/( udev)( )/\1 plymouth\2/' /etc/mkinitcpio.conf
    fi
  fi
fi

mkinitcpio -P || true

# systemd-boot entries
if [ -d /boot/loader/entries ]; then
  for entry in /boot/loader/entries/*.conf; do
    [ -f "$entry" ] || continue
    if grep -q '^options ' "$entry" && ! grep -q ' splash' "$entry"; then
      sed -i '/^options / s/$/ quiet splash loglevel=3 rd.systemd.show_status=auto vt.global_cursor_default=0/' "$entry"
    fi
    sed -i 's/^title .*/title MechOS/' "$entry" 2>/dev/null || true
  done
fi

# GRUB installations
if [ -f /etc/default/grub ]; then
  if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
    sed -i -E 's|^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"|GRUB_CMDLINE_LINUX_DEFAULT="\1 quiet splash loglevel=3 rd.systemd.show_status=auto"|' /etc/default/grub
  else
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 rd.systemd.show_status=auto"' >> /etc/default/grub
  fi
  command -v grub-mkconfig >/dev/null 2>&1 && grub-mkconfig -o /boot/grub/grub.cfg || true
fi

# Apply GPU-specific packages after the common graphics stack is installed.
# If an older NVIDIA card needs a legacy branch, this can fail without
# breaking the rest of the MechOS install.
if /usr/local/bin/mechos-gpu-setup --apply; then
  echo "GPU-specific setup completed."
else
  echo "GPU-specific setup needs review; base graphics stack remains installed."
fi

mkdir -p /var/lib/mechos
cat > /etc/mechos-release <<'RELEASEEOF'
NAME="MechOS"
VERSION="0.3.0 Alpha"
ID=mechos
ID_LIKE=arch
VARIANT="Gaming + Creator"
RELEASEEOF

# Configure rollback protection on compatible Btrfs installations.
if [ "$(findmnt -n -o FSTYPE / 2>/dev/null || true)" = "btrfs" ]; then
  if command -v snapper >/dev/null 2>&1 && [ ! -f /etc/snapper/configs/root ]; then
    snapper -c root create-config / || true
  fi
  systemctl enable snapper-timeline.timer 2>/dev/null || true
  systemctl enable snapper-cleanup.timer 2>/dev/null || true
fi

touch /var/lib/mechos/installed

echo "=== MechOS post-install complete ==="
echo "Installed user: $MECHOS_USER"
echo "Default session: MechOS Gaming Mode / MechScope"
TARGETEOF
chmod 755 /workspace/archlive/airootfs/usr/share/mechos/install-payload/mechos-postinstall-target

# Partial Archinstall config: it does NOT choose or wipe a disk. The TUI still
# requires the user to make and confirm those choices. This only injects the
# package needed to retrieve the local payload plus the post-install commands.
cat > /workspace/archlive/airootfs/usr/share/mechos/install-payload/archinstall-mechos.json <<'JSONEOF'
{
  "packages": [
    "curl"
  ],
  "custom_commands": [
    "curl -fsSL http://127.0.0.1:45811/mechos-postinstall-target -o /root/mechos-postinstall-target",
    "chmod 755 /root/mechos-postinstall-target",
    "/root/mechos-postinstall-target"
  ]
}
JSONEOF

# Stage only installed-system MechOS files. Live-only account/sudo/welcome
# configuration is intentionally excluded.
PAYLOAD_STAGE="/tmp/mechos-installed-rootfs"
rm -rf "$PAYLOAD_STAGE"
mkdir -p "$PAYLOAD_STAGE"

copy_payload() {
  local src="$1"
  if [ -e "/workspace/archlive/airootfs$src" ]; then
    mkdir -p "$PAYLOAD_STAGE$(dirname "$src")"
    cp -a "/workspace/archlive/airootfs$src" "$PAYLOAD_STAGE$src"
  fi
}

for f in \
  /usr/local/bin/mechscope \
  /usr/local/bin/mechos-quick-actions \
  /usr/local/bin/mechos-stream-control \
  /usr/local/bin/mechos-stream-center \
  /usr/local/bin/mechos-quick-actions-daemon \
  /usr/local/bin/mechos-creator-mode \
  /usr/local/bin/mechos-creator-app \
  /usr/local/libexec/mechos-creator-app-installer \
  /usr/local/bin/mechos-postinstall \
  /usr/local/libexec/mechos-gaming-setup-helper \
  /usr/local/bin/mechos-creator-session \
  /usr/local/bin/mechos-gaming-session \
  /usr/local/bin/mechos-boot-diagnostics \
  /usr/local/bin/mechos-return-to-mechscope \
  /usr/local/bin/mechos-performance-center \
  /usr/local/bin/mechos-session-select \
  /usr/local/bin/mechos-gpu-setup \
  /usr/local/bin/mechos-update \
  /usr/local/bin/mechos-update-helper \
  /usr/local/bin/mechos-update-center \
  /usr/share/applications/mechos-update-center.desktop \
  /usr/share/applications/mechos-creator-mode.desktop \
  /usr/share/applications/mechos-postinstall.desktop \
  /usr/local/bin/mechos-creator-setup \
  /usr/local/bin/mechos-firstboot \
  /usr/local/bin/mechos-install-graphical \
  /usr/local/bin/mechos-recovery-center \
  /usr/local/bin/mechos-recovery-helper \
  /usr/local/bin/mechos-hardware-scan \
  /usr/share/applications/mechscope.desktop \
  /usr/share/applications/mechos-return-to-mechscope.desktop \
  /usr/share/applications/mechos-performance-center.desktop \
  /usr/share/wayland-sessions/mechos-gaming.desktop \
  /usr/share/wayland-sessions/mechos-creator.desktop \
  /usr/share/mechos/creator-packages \
  /usr/share/mechos/branding \
  /usr/share/plymouth/themes/mechos \
  /usr/share/pixmaps/mechos.png \
  /etc/plymouth/plymouthd.conf \
  /etc/systemd/zram-generator.conf \
  /etc/sysctl.d/90-mechos-performance.conf \
  /etc/gamemode.ini \
  /etc/systemd/system/mechos-firstboot.service \
  /etc/xdg/autostart/mechos-postinstall.desktop \
  /usr/share/doc/mechos
do
  copy_payload "$f"
done

tar --zstd -cpf \
  /workspace/archlive/airootfs/usr/share/mechos/install-payload/mechos-rootfs.tar.zst \
  -C "$PAYLOAD_STAGE" .

rm -rf "$PAYLOAD_STAGE"

test -s /workspace/archlive/airootfs/usr/share/mechos/install-payload/mechos-rootfs.tar.zst
test -x /workspace/archlive/airootfs/usr/share/mechos/install-payload/mechos-postinstall-target
test -s /workspace/archlive/airootfs/usr/share/mechos/install-payload/archinstall-mechos.json


# ArchISO-authoritative permissions. These prevent launchers from
# losing executable bits inside the final SquashFS image.
cat >> /workspace/archlive/profiledef.sh << "EOF"

file_permissions["/usr/local/bin/mechos-postinstall"]="0:0:755"
file_permissions["/usr/local/libexec/mechos-gaming-setup-helper"]="0:0:755"
file_permissions["/usr/local/bin/mechos-gaming-session"]="0:0:755"
file_permissions["/usr/local/bin/mechos-boot-diagnostics"]="0:0:755"
file_permissions["/usr/local/bin/mechscope"]="0:0:755"
file_permissions["/usr/local/bin/mechos-return-to-mechscope"]="0:0:755"
file_permissions["/usr/local/bin/mechos-performance-center"]="0:0:755"
file_permissions["/usr/local/bin/mechos-firstboot"]="0:0:755"
file_permissions["/usr/local/bin/mechos-install"]="0:0:755"
file_permissions["/usr/local/bin/mechos-live-welcome"]="0:0:755"
file_permissions["/usr/local/bin/mechos-live-setup"]="0:0:755"
file_permissions["/usr/local/bin/mechos-install-graphical"]="0:0:755"
file_permissions["/usr/local/bin/mechos-recovery-center"]="0:0:755"
file_permissions["/usr/local/bin/mechos-recovery-helper"]="0:0:755"
file_permissions["/usr/local/bin/mechos-hardware-scan"]="0:0:755"
file_permissions["/usr/local/bin/mechos-preserve-home"]="0:0:755"
file_permissions["/usr/local/bin/mechos-session-select"]="0:0:755"
file_permissions["/usr/local/bin/mechos-gpu-setup"]="0:0:755"
file_permissions["/usr/local/bin/mechos-update"]="0:0:755"
file_permissions["/usr/local/bin/mechos-update-helper"]="0:0:755"
file_permissions["/usr/local/bin/mechos-update-center"]="0:0:755"
file_permissions["/usr/share/mechos/install-payload/mechos-postinstall-target"]="0:0:755"
file_permissions["/usr/share/mechos/install-payload/archinstall-mechos.json"]="0:0:644"
file_permissions["/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"]="0:0:644"
file_permissions["/usr/share/mechos/creator-packages/streamer.json"]="0:0:644"
file_permissions["/usr/share/mechos/creator-packages/graphics.json"]="0:0:644"
file_permissions["/usr/share/mechos/creator-packages/game-dev.json"]="0:0:644"
file_permissions["/usr/share/mechos/creator-packages/windows-apps.json"]="0:0:644"
file_permissions["/usr/share/applications/mechos-postinstall.desktop"]="0:0:644"
file_permissions["/etc/xdg/autostart/mechos-postinstall.desktop"]="0:0:644"
file_permissions["/usr/share/mechos/branding/mechos-logo.png"]="0:0:644"
file_permissions["/etc/sudoers.d/10-mechos-live"]="0:0:440"
EOF

# Final sanity check before mkarchiso.
chmod 755 \
  /workspace/archlive/airootfs/usr/local/bin/mechos-creator-mode \
  /workspace/archlive/airootfs/usr/local/bin/mechos-creator-session \
  /workspace/archlive/airootfs/usr/local/bin/mechos-gaming-session \
  /workspace/archlive/airootfs/usr/local/bin/mechscope \
  /workspace/archlive/airootfs/usr/local/bin/mechos-quick-actions \
  /workspace/archlive/airootfs/usr/local/bin/mechos-stream-control \
  /workspace/archlive/airootfs/usr/local/bin/mechos-stream-center \
  /workspace/archlive/airootfs/usr/local/bin/mechos-quick-actions-daemon \
  /workspace/archlive/airootfs/usr/local/bin/mechos-return-to-mechscope \
  /workspace/archlive/airootfs/usr/local/bin/mechos-performance-center
chmod 440 /workspace/archlive/airootfs/etc/sudoers.d/10-mechos-live

echo "=== MechOS pre-build validation ==="
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-creator-mode
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-creator-app
test -x /workspace/archlive/airootfs/usr/local/libexec/mechos-creator-app-installer
test -s /workspace/archlive/airootfs/usr/share/mechos/branding/mechos-creator-mode-reference.png
grep -q "1-CLICK INSTALL & COMPATIBILITY" /workspace/archlive/airootfs/usr/local/bin/mechos-creator-mode
grep -q "com.unity.UnityHub" /workspace/archlive/airootfs/usr/local/bin/mechos-creator-app
grep -q "net.davidotek.pupgui2" /workspace/archlive/airootfs/usr/local/bin/mechos-creator-app
grep -q "Session=plasma.desktop" /workspace/archlive/airootfs/etc/sddm.conf.d/mechos.conf
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-creator-session
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-gaming-session
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-boot-diagnostics
test -L /workspace/archlive/airootfs/etc/systemd/system/NetworkManager-wait-online.service
test "$(readlink /workspace/archlive/airootfs/etc/systemd/system/NetworkManager-wait-online.service)" = "/dev/null"
test ! -e /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/bluetooth.service
test ! -e /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/irqbalance.service
test ! -e /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/power-profiles-daemon.service
test ! -e /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/switcheroo-control.service
grep -q 'DeviceTimeout=3' /workspace/archlive/airootfs/etc/plymouth/plymouthd.conf
test -x /workspace/archlive/airootfs/usr/local/bin/mechscope
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-quick-actions
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-stream-control
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-stream-center
grep -q "StartStream" /workspace/archlive/airootfs/usr/local/bin/mechos-stream-control
grep -q "StopStream" /workspace/archlive/airootfs/usr/local/bin/mechos-stream-control
grep -q "MECHOS STREAM CENTER" /workspace/archlive/airootfs/usr/local/bin/mechos-stream-center
grep -q "Ctrl+Shift+L" /workspace/archlive/airootfs/usr/local/bin/mechos-stream-center
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-quick-actions-daemon
grep -q "MECHOS QUICK ACTIONS" /workspace/archlive/airootfs/usr/local/bin/mechos-quick-actions
grep -q "BTN_MODE" /workspace/archlive/airootfs/usr/local/bin/mechos-quick-actions-daemon
grep -q "Ctrl+Shift+M" /workspace/archlive/airootfs/usr/local/bin/mechos-quick-actions
grep -q -- "--mangoapp" /workspace/archlive/airootfs/usr/local/bin/mechos-gaming-session
grep -q "MECHSCOPE 2.0" /workspace/archlive/airootfs/usr/local/bin/mechscope
grep -q "RECENT LIBRARY" /workspace/archlive/airootfs/usr/local/bin/mechscope
grep -q "PROJECT MANAGER" /workspace/archlive/airootfs/usr/local/bin/mechos-creator-mode
grep -q "ASSET BROWSER" /workspace/archlive/airootfs/usr/local/bin/mechos-creator-mode
grep -q "CREATOR MODE PRESETS" /workspace/archlive/airootfs/usr/local/bin/mechos-creator-mode
grep -q "CREATOR MODE 2.0" /workspace/archlive/airootfs/usr/local/bin/mechos-creator-mode
grep -q "exec /usr/local/bin/mechos-live-setup" /workspace/archlive/airootfs/usr/local/bin/mechos-live-welcome
grep -q "MECHSCOPE 2.0" /workspace/archlive/airootfs/usr/share/plymouth/themes/mechos/mechos.script
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-return-to-mechscope
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-performance-center
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-firstboot
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-install
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-live-welcome
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-live-setup
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-install-graphical
grep -q 'exec /usr/local/bin/mechos-live-setup' /workspace/archlive/airootfs/usr/local/bin/mechos-install-graphical
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-recovery-center
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-recovery-helper
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-hardware-scan
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-preserve-home
test -s /workspace/archlive/airootfs/usr/share/applications/mechos-live-setup.desktop
test -s /workspace/archlive/airootfs/usr/share/applications/mechos-recovery-center.desktop
test -s /workspace/archlive/airootfs/usr/share/mechos/branding/mechos-installer-reference.png
grep -q "MECHOS INSTALLER" /workspace/archlive/airootfs/usr/local/bin/mechos-live-setup
grep -q "Select your target drive and installation type" /workspace/archlive/airootfs/usr/local/bin/mechos-live-setup
grep -q "HARDWARE SUMMARY" /workspace/archlive/airootfs/usr/local/bin/mechos-live-setup
grep -q "INSTALL OVERVIEW" /workspace/archlive/airootfs/usr/local/bin/mechos-live-setup
grep -q "MECHOS RECOVERY CENTER" /workspace/archlive/airootfs/usr/local/bin/mechos-recovery-center
grep -q "repair-boot" /workspace/archlive/airootfs/usr/local/bin/mechos-recovery-helper
grep -q "rollback" /workspace/archlive/airootfs/usr/local/bin/mechos-recovery-helper
grep -q "rollback-pending" /workspace/archlive/airootfs/usr/local/bin/mechos-update-helper
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-session-select
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-gpu-setup
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-update
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-update-helper
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-update-center
test -s /workspace/archlive/airootfs/usr/share/applications/mechos-update-center.desktop
grep -q 'MECHOS UPDATE CENTER' /workspace/archlive/airootfs/usr/local/bin/mechos-update-center
grep -q 'checkupdates' /workspace/archlive/airootfs/usr/local/bin/mechos-update-helper
test -x /workspace/archlive/airootfs/usr/local/bin/mechos-creator-setup
test -x /workspace/archlive/airootfs/usr/share/mechos/install-payload/mechos-postinstall-target
test -s /workspace/archlive/airootfs/usr/share/mechos/install-payload/mechos-rootfs.tar.zst
test -s /workspace/archlive/airootfs/usr/share/mechos/install-payload/archinstall-mechos.json
grep -q '"custom_commands"' /workspace/archlive/airootfs/usr/share/mechos/install-payload/archinstall-mechos.json
grep -q 'MechOS post-install complete' /workspace/archlive/airootfs/usr/share/mechos/install-payload/mechos-postinstall-target
grep -q 'mechos-firstboot' /workspace/archlive/profiledef.sh
grep -q 'mechos-session-select' /workspace/archlive/profiledef.sh
grep -q 'mechos-gpu-setup' /workspace/archlive/profiledef.sh
test -f /workspace/archlive/airootfs/etc/systemd/zram-generator.conf
grep -q "Performance Center" /workspace/archlive/airootfs/usr/local/bin/mechscope
grep -q "Update Center" /workspace/archlive/airootfs/usr/local/bin/mechscope
grep -q "mechos-update-center" /workspace/archlive/airootfs/usr/local/bin/mechscope
grep -q "Update Center" /workspace/archlive/airootfs/usr/local/bin/mechos-creator-mode
grep -q "Steam Library" /workspace/archlive/airootfs/usr/local/bin/mechscope
test -s /workspace/archlive/airootfs/usr/share/mechos/branding/mechos-logo.png
test -f /workspace/archlive/airootfs/usr/share/plymouth/themes/mechos/mechos.plymouth
grep -Rqs 'plymouth' /workspace/archlive/airootfs/etc/mkinitcpio.conf* /workspace/archlive/airootfs/etc/mkinitcpio.conf.d 2>/dev/null
grep -q "Session=plasma.desktop" /workspace/archlive/airootfs/etc/sddm.conf.d/mechos.conf
grep -q "mechos ALL=(ALL:ALL) NOPASSWD: ALL" /workspace/archlive/airootfs/etc/sudoers.d/10-mechos-live
grep -q "u mechos 1000" /workspace/archlive/airootfs/usr/lib/sysusers.d/mechos.conf
echo "MechOS boot/admin validation passed."

mkdir -p /workspace/out /workspace/work

# MECHOS_CURRENT_INTEGRATION_LATE
# Re-apply after all legacy builder blocks so current fixes win.
bash /workspace/scripts/mechos-current-integration.sh final

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
