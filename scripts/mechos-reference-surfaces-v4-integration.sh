#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log() { printf '[MechOS Reference Surfaces v4] %s\n' "$*"; }
fail() { printf '[MechOS Reference Surfaces v4] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Reference Surfaces v4] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -s "$ARCHIVE" ] || fail "installed-system payload is missing: $ARCHIVE"

write_performance_center() {
  local tree="$1"
  local file="$tree/usr/local/bin/mechos-performance-center"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<'PY'
#!/usr/bin/env python3
# MECHOS_REFERENCE_SURFACES_V4
# MECHOS_RADARAI_PERFORMANCE_CENTER_V1
import shutil
import subprocess
import sys
from pathlib import Path

from PyQt6.QtCore import QTimer, Qt
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import (
    QApplication, QFrame, QGridLayout, QHBoxLayout, QLabel, QMainWindow,
    QMessageBox, QProgressBar, QPushButton, QVBoxLayout, QWidget
)

THEME = Path('/usr/share/mechos/theme/mechos-ui.qss')
RADARAI_APP_ID = 'io.mechgod.RadarAI'


def run(args):
    try:
        return subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as exc:
        QMessageBox.warning(None, 'MechOS Performance Center', str(exc))
        return None


def output(args):
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ''


def flatpak_app_installed(app_id):
    if not shutil.which('flatpak'):
        return False
    for scope in ('--user', '--system'):
        if subprocess.run(['flatpak', 'info', scope, app_id], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
            return True
    return False


def set_profile(profile, parent):
    if not shutil.which('powerprofilesctl'):
        QMessageBox.information(parent, 'Power Profile', 'Power profile controls are unavailable on this hardware.')
        return
    result = subprocess.run(['powerprofilesctl', 'set', profile], text=True, capture_output=True)
    if result.returncode:
        QMessageBox.information(parent, 'Power Profile', result.stderr.strip() or 'This profile is not available on this system.')


class MetricCard(QFrame):
    def __init__(self, title, value='--', detail=''):
        super().__init__(); self.setObjectName('metricCard')
        l = QVBoxLayout(self); l.setContentsMargins(16,14,16,14)
        t = QLabel(title); t.setObjectName('surfaceSection'); l.addWidget(t)
        self.value = QLabel(value); self.value.setObjectName('surfaceMetric'); l.addWidget(self.value)
        self.detail = QLabel(detail); self.detail.setObjectName('surfaceMuted'); self.detail.setWordWrap(True); l.addWidget(self.detail)


class Perf(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle('MechOS Performance Center')
        self.resize(1440, 860)
        self.setMinimumSize(1100, 700)
        self.setStyleSheet((THEME.read_text() if THEME.is_file() else '') + self.local_style())
        self.build()
        self.timer = QTimer(self); self.timer.timeout.connect(self.refresh); self.timer.start(2000)
        self.refresh()

    def local_style(self):
        return r'''
QFrame#surfaceHero { background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #091020,stop:.55 #15102d,stop:1 #07182b); border:1px solid #7b4dd3; border-radius:18px; }
QFrame#metricCard,QFrame#surfaceCard { background:#09111f; border:1px solid #304064; border-radius:15px; }
QFrame#metricCard:hover,QFrame#surfaceCard:hover { border:1px solid #8f69e8; }
QLabel#surfaceTitle { color:white; font-size:34px; font-weight:900; }
QLabel#surfaceEyebrow,QLabel#surfaceSection { color:#74d8ff; font-size:13px; font-weight:900; }
QLabel#surfaceMetric { color:white; font-size:26px; font-weight:900; }
QLabel#surfaceMuted { color:#9dacc3; }
QProgressBar { min-height:12px; max-height:12px; }
'''

    def panel(self, name='surfaceCard'):
        p = QFrame(); p.setObjectName(name); return p

    def action(self, title, subtitle, callback, primary=False):
        b = QPushButton(title + '\n' + subtitle)
        b.setMinimumHeight(72)
        if primary: b.setObjectName('primary')
        b.clicked.connect(callback)
        return b

    def build(self):
        root = QWidget(); self.setCentralWidget(root)
        outer = QVBoxLayout(root); outer.setContentsMargins(24,20,24,20); outer.setSpacing(14)

        top = QHBoxLayout()
        brand = QLabel('MECHOS'); brand.setObjectName('brand'); brand.setFont(QFont('Sans Serif',20,QFont.Weight.Bold)); top.addWidget(brand)
        top.addStretch(); center = QLabel('PERFORMANCE CENTER'); center.setObjectName('purple'); center.setFont(QFont('Sans Serif',22,QFont.Weight.Bold)); top.addWidget(center); top.addStretch()
        self.profile_badge = QLabel('PROFILE  --'); self.profile_badge.setObjectName('metric'); top.addWidget(self.profile_badge)
        outer.addLayout(top)

        hero = self.panel('surfaceHero'); hl = QHBoxLayout(hero); hl.setContentsMargins(22,20,22,20)
        copy = QVBoxLayout(); eye = QLabel('SYSTEM PERFORMANCE'); eye.setObjectName('surfaceEyebrow'); copy.addWidget(eye)
        h1 = QLabel('Tune. Monitor. Play.'); h1.setObjectName('surfaceTitle'); copy.addWidget(h1)
        self.gpu_label = QLabel('Detecting graphics hardware…'); self.gpu_label.setObjectName('surfaceMuted'); self.gpu_label.setWordWrap(True); copy.addWidget(self.gpu_label)
        pr = QHBoxLayout()
        pr.addWidget(self.action('Gaming Performance','Maximum available performance',lambda:set_profile('performance',self),True))
        pr.addWidget(self.action('Balanced','Everyday gaming + desktop',lambda:set_profile('balanced',self)))
        pr.addWidget(self.action('Battery Saver','Lower power usage',lambda:set_profile('power-saver',self)))
        copy.addLayout(pr); hl.addLayout(copy,3)
        health = self.panel(); health_l = QVBoxLayout(health); hs = QLabel('SYSTEM HEALTH'); hs.setObjectName('surfaceSection'); health_l.addWidget(hs)
        self.health_label = QLabel('Checking…'); self.health_label.setObjectName('surfaceMetric'); self.health_label.setWordWrap(True); health_l.addWidget(self.health_label)
        note = QLabel('Live telemetry updates every 2 seconds.'); note.setObjectName('surfaceMuted'); health_l.addWidget(note); hl.addWidget(health,1)
        outer.addWidget(hero)

        metrics = QHBoxLayout()
        self.cpu_card = MetricCard('CPU LOAD'); self.ram_card = MetricCard('MEMORY'); self.disk_card = MetricCard('SYSTEM DISK'); self.zram_card = MetricCard('ZRAM')
        for c in (self.cpu_card,self.ram_card,self.disk_card,self.zram_card): metrics.addWidget(c)
        outer.addLayout(metrics)

        body = QHBoxLayout(); body.setSpacing(14)
        gaming = self.panel(); gl = QVBoxLayout(gaming); gh = QLabel('GAMING & GRAPHICS'); gh.setObjectName('surfaceSection'); gl.addWidget(gh)
        gl.addWidget(self.action('Performance Overlay','Toggle MangoHud / MangoApp',self.toggle_hud,True))
        gl.addWidget(self.action('GPU & Vulkan Info','Vulkan renderer, VA-API and driver details',self.gpu_info))
        gl.addWidget(self.action('GPU Recorder','Open GPU Screen Recorder',self.recorder))
        gl.addWidget(self.action('Steam Gamepad UI','Open the console-style Steam library',lambda:run(['steam','-gamepadui'])))
        body.addWidget(gaming,1)

        hardware = self.panel(); hwl = QVBoxLayout(hardware); hh = QLabel('HARDWARE & HEALTH'); hh.setObjectName('surfaceSection'); hwl.addWidget(hh)
        hwl.addWidget(self.action('System Monitor','Open btop',lambda:run(['konsole','-e','btop']),True))
        hwl.addWidget(self.action('CPU Information','Frequency, topology and scheduler info',self.cpu_info))
        hwl.addWidget(self.action('Storage Health','NVMe / SMART-capable drive overview',self.storage_info))
        hwl.addWidget(self.action('Update Center','System packages, Flatpaks and recovery',lambda:run(['/usr/local/bin/mechos-update-center'])))
        body.addWidget(hardware,1)

        mechos = self.panel(); ml = QVBoxLayout(mechos); mh = QLabel('MECHOS TOOLS'); mh.setObjectName('surfaceSection'); ml.addWidget(mh)
        self.radar = self.action('RadarAI Diagnostics','Installed separately through Discover',self.launch_radarai,True); ml.addWidget(self.radar)
        ml.addWidget(self.action('Quick Actions','Power, audio, network and streaming controls',lambda:run(['/usr/local/bin/mechos-quick-actions'])))
        ml.addWidget(self.action('Stream Center','OBS streaming and recording controls',lambda:run(['/usr/local/bin/mechos-stream-center'])))
        ml.addWidget(self.action('System Settings','Open KDE hardware and device settings',lambda:run(['systemsettings'])))
        body.addWidget(mechos,1)
        outer.addLayout(body,1)

        footer = QHBoxLayout(); hint = QLabel('Controller / keyboard focus follows the same MechOS reference navigation language.'); hint.setObjectName('surfaceMuted'); footer.addWidget(hint); footer.addStretch()
        close = QPushButton('Close'); close.clicked.connect(self.close); footer.addWidget(close); outer.addLayout(footer)

    def shell(self, command):
        run(['konsole','-e','bash','-lc',command + "; echo; read -rp 'Press Enter to close…'"])

    def gpu_info(self): self.shell("vulkaninfo --summary 2>/dev/null || true; echo; vainfo 2>/dev/null || true")
    def cpu_info(self): self.shell("lscpu; echo; cpupower frequency-info 2>/dev/null || true")
    def storage_info(self): self.shell("echo '=== NVMe ==='; nvme list 2>/dev/null || true; echo; lsblk -d -o NAME,MODEL,SIZE,ROTA,TYPE")

    def recorder(self):
        for cmd in ('gpu-screen-recorder-gtk','gsr-ui','gpu-screen-recorder'):
            if shutil.which(cmd): run([cmd]); return
        QMessageBox.information(self,'Recorder','GPU Screen Recorder is not available.')

    def toggle_hud(self):
        if shutil.which('mangohudctl'):
            p = subprocess.run(['mangohudctl','toggle-hud'],capture_output=True)
            if p.returncode == 0: return
        QMessageBox.information(self,'Performance Overlay','Use Right Shift + F12 to toggle the performance overlay.')

    def launch_radarai(self):
        if flatpak_app_installed(RADARAI_APP_ID): run(['flatpak','run',RADARAI_APP_ID]); return
        QMessageBox.information(self,'RadarAI','RadarAI is not installed. Install io.mechgod.RadarAI from Discover and it will appear here automatically.')

    def refresh(self):
        cpu = output(['bash','-lc',"top -bn1 | awk '/Cpu\\(s\\)/ {printf \"%.0f%%\",100-$8;exit}'"]) or '--'
        ram = output(['bash','-lc',"free | awk '/Mem:/ {printf \"%.0f%%\",($3/$2)*100}'"]) or '--'
        disk = output(['bash','-lc',"df / | awk 'NR==2 {print $5}'"]) or '--'
        zram = output(['bash','-lc',"zramctl --noheadings -o SIZE 2>/dev/null | head -n1 | xargs"]) or 'Auto'
        profile = output(['powerprofilesctl','get']) if shutil.which('powerprofilesctl') else 'Unavailable'
        gpu = output(['bash','-lc',"lspci | grep -Ei 'VGA|3D|Display' | sed 's/^[^ ]* //' | head -n1"]) or 'Unknown GPU'
        self.cpu_card.value.setText(cpu); self.cpu_card.detail.setText('Current processor utilization')
        self.ram_card.value.setText(ram); self.ram_card.detail.setText('Active memory utilization')
        self.disk_card.value.setText(disk); self.disk_card.detail.setText('Root filesystem usage')
        self.zram_card.value.setText(zram); self.zram_card.detail.setText('Compressed memory swap')
        self.profile_badge.setText('PROFILE  ' + profile.upper())
        self.gpu_label.setText(gpu)
        self.health_label.setText('READY' if cpu != '--' and ram != '--' else 'CHECKING')
        self.radar.setVisible(flatpak_app_installed(RADARAI_APP_ID))

app = QApplication(sys.argv); app.setApplicationName('MechOS Performance Center')
w = Perf(); w.showMaximized(); sys.exit(app.exec())
PY
  chmod 755 "$file"
}

patch_python_layouts() {
  local tree="$1"
  local update="$tree/usr/local/bin/mechos-update-center"
  local quick="$tree/usr/local/bin/mechos-quick-actions"
  local stream="$tree/usr/local/bin/mechos-stream-center"
  local recovery="$tree/usr/local/bin/mechos-recovery-center"
  local creator
  if [ -f "$tree/usr/local/bin/mechos-creator-mode.real" ]; then creator="$tree/usr/local/bin/mechos-creator-mode.real"; else creator="$tree/usr/local/bin/mechos-creator-mode"; fi
  local control="$tree/usr/local/bin/mechos-gaming-layer-control"

  python3 - "$update" "$quick" "$stream" "$recovery" "$creator" "$control" <<'PY'
from pathlib import Path
import sys

update, quick, stream, recovery, creator, control = [Path(x) for x in sys.argv[1:]]


def replace_method(text, class_name, method_name, new_method):
    c = text.find(f'class {class_name}')
    if c < 0: raise SystemExit(f'could not locate class {class_name}')
    s = text.find(f'    def {method_name}(', c)
    if s < 0: raise SystemExit(f'could not locate {class_name}.{method_name}')
    e = text.find('\n    def ', s + 8)
    if e < 0: raise SystemExit(f'could not locate end of {class_name}.{method_name}')
    return text[:s] + new_method.rstrip() + '\n' + text[e:]

if update.is_file():
    text = update.read_text()
    if '# MECHOS_REFERENCE_UPDATE_V4' not in text:
        text = text.replace('QApplication, QFrame, QHBoxLayout, QLabel, QMainWindow, QMessageBox,', 'QApplication, QFrame, QGridLayout, QHBoxLayout, QLabel, QMainWindow, QMessageBox,')
        method = r'''    def build_ui(self):
        # MECHOS_REFERENCE_UPDATE_V4
        root = QWidget(); self.setCentralWidget(root)
        layout = QVBoxLayout(root); layout.setContentsMargins(24,20,24,20); layout.setSpacing(14)
        heading=QLabel("MECHOS     •     UPDATE CENTER"); heading.setObjectName("purple"); layout.addWidget(heading)
        hero = self.panel(); hero.setObjectName("hero"); hl = QHBoxLayout(hero)
        copy = QVBoxLayout(); eye=QLabel("SYSTEM UPDATE STATUS"); eye.setObjectName("section"); copy.addWidget(eye)
        self.status_label=QLabel("Checking…"); self.status_label.setObjectName("title"); copy.addWidget(self.status_label)
        self.details_label=QLabel("Looking for available MechOS, Arch and Flatpak updates"); self.details_label.setObjectName("muted"); self.details_label.setWordWrap(True); copy.addWidget(self.details_label)
        row=QHBoxLayout(); self.check_button=QPushButton("Check for Updates"); self.check_button.clicked.connect(self.check_updates); row.addWidget(self.check_button)
        self.update_button=QPushButton("Install Updates"); self.update_button.setObjectName("primary"); self.update_button.clicked.connect(self.apply_updates); self.update_button.setEnabled(False); row.addWidget(self.update_button); copy.addLayout(row); hl.addLayout(copy,3)
        side=self.panel(); sl=QVBoxLayout(side); self.channel=QLabel("CHANNEL  STABLE"); self.channel.setObjectName("section"); sl.addWidget(self.channel)
        self.reboot_label=QLabel("Restart not required"); self.reboot_label.setObjectName("metric"); self.reboot_label.setWordWrap(True); sl.addWidget(self.reboot_label)
        self.reboot_button=QPushButton("Restart MechOS"); self.reboot_button.clicked.connect(self.reboot); self.reboot_button.setEnabled(False); sl.addWidget(self.reboot_button); hl.addWidget(side,1)
        layout.addWidget(hero)
        action=self.panel(); al=QVBoxLayout(action); ah=QLabel("UPDATE PROGRESS"); ah.setObjectName("section"); al.addWidget(ah)
        self.progress=QProgressBar(); self.progress.setRange(0,1); self.progress.setValue(0); self.progress.setFormat("Ready"); al.addWidget(self.progress)
        ar=QHBoxLayout(); self.history_button=QPushButton("Refresh History"); self.history_button.clicked.connect(self.load_history); ar.addWidget(self.history_button); ar.addStretch(); al.addLayout(ar); layout.addWidget(action)
        content=QHBoxLayout(); logp=self.panel(); ll=QVBoxLayout(logp); lh=QLabel("UPDATE OUTPUT"); lh.setObjectName("section"); ll.addWidget(lh); self.log=QPlainTextEdit(); self.log.setReadOnly(True); ll.addWidget(self.log); content.addWidget(logp,2)
        histp=self.panel(); hpl=QVBoxLayout(histp); hh=QLabel("RECENT HISTORY"); hh.setObjectName("section"); hpl.addWidget(hh); self.history=QPlainTextEdit(); self.history.setReadOnly(True); hpl.addWidget(self.history); content.addWidget(histp,1); layout.addLayout(content,1)
        note=QLabel("MechOS does not update the disposable Live ISO. Compatible Btrfs installations receive a pre-update Snapper snapshot automatically."); note.setObjectName("muted"); note.setWordWrap(True); layout.addWidget(note)'''
        text = replace_method(text,'UpdateCenter','build_ui',method)
        update.write_text(text)

if quick.is_file():
    text=quick.read_text()
    if '# MECHOS_REFERENCE_QUICK_ACTIONS_V4' not in text:
        method=r'''    def build(self):
        # MECHOS_REFERENCE_QUICK_ACTIONS_V4
        root=QWidget(); self.setCentralWidget(root); outer=QVBoxLayout(root); outer.setContentsMargins(14,14,14,14); outer.setSpacing(10)
        hero=self.panel(); hl=QVBoxLayout(hero); t=QLabel("MECHOS QUICK ACTIONS"); t.setObjectName("title"); hl.addWidget(t); sub=QLabel("Guide/Home + Y  •  Ctrl+Shift+M"); sub.setObjectName("muted"); hl.addWidget(sub); outer.addWidget(hero)
        perf=self.panel(); pl=QVBoxLayout(perf); h=QLabel("PERFORMANCE"); h.setObjectName("section"); pl.addWidget(h); pg=QGridLayout(); pg.addWidget(self.button("Performance",lambda:self.profile("performance"),"profile"),0,0); pg.addWidget(self.button("Balanced",lambda:self.profile("balanced"),"profile"),0,1); pg.addWidget(self.button("Battery Saver",lambda:self.profile("power-saver"),"profile"),0,2); pl.addLayout(pg); pr=QHBoxLayout(); pr.addWidget(self.button("Toggle Overlay",self.toggle_hud)); pr.addWidget(self.button("Performance Center",lambda:spawn(["/usr/local/bin/mechos-performance-center"]))); pl.addLayout(pr); outer.addWidget(perf)
        controls=self.panel(); cl=QVBoxLayout(controls); ch=QLabel("DEVICE CONTROLS"); ch.setObjectName("section"); cl.addWidget(ch); cg=QGridLayout(); cg.addWidget(self.button("Volume −",lambda:self.wpctl("5%-")),0,0); cg.addWidget(self.button("Mute",self.mute),0,1); cg.addWidget(self.button("Volume +",lambda:self.wpctl("5%+")),0,2); cg.addWidget(self.button("Brightness −",lambda:self.brightness("5%-")),1,0); cg.addWidget(self.button("Brightness +",lambda:self.brightness("+5%")),1,1); cg.addWidget(self.button("Wi-Fi",self.toggle_wifi),2,0); cg.addWidget(self.button("Bluetooth",self.toggle_bt),2,1); cl.addLayout(cg); outer.addWidget(controls)
        stream=self.panel(); sl=QVBoxLayout(stream); sh=QLabel("STREAMING & RECORDING"); sh.setObjectName("section"); sl.addWidget(sh); sg=QGridLayout(); sg.addWidget(self.button("Go Live",lambda:spawn(["/usr/local/bin/mechos-stream-control","start-stream"])),0,0); sg.addWidget(self.button("End Stream",lambda:spawn(["/usr/local/bin/mechos-stream-control","stop-stream"])),0,1); sg.addWidget(self.button("Toggle Recording",lambda:spawn(["/usr/local/bin/mechos-stream-control","toggle-record"])),1,0); sg.addWidget(self.button("Stream Center",lambda:spawn(["/usr/local/bin/mechos-stream-center"])),1,1); sl.addLayout(sg); outer.addWidget(stream)
        tools=self.panel(); tl=QVBoxLayout(tools); th=QLabel("MECHOS TOOLS"); th.setObjectName("section"); tl.addWidget(th); tg=QGridLayout(); tg.addWidget(self.button("Update Center",lambda:spawn(["/usr/local/bin/mechos-update-center"])),0,0); tg.addWidget(self.button("Controller Settings",lambda:spawn(["systemsettings","kcm_gamecontroller"])),0,1); tg.addWidget(self.button("Audio Settings",lambda:spawn(["systemsettings","kcm_pulseaudio"])),1,0); tg.addWidget(self.button("Recorder",self.recorder),1,1); tl.addLayout(tg); outer.addWidget(tools)
        close=self.button("Close Quick Actions",self.close); close.setObjectName("primary"); outer.addWidget(close); outer.addStretch()'''
        text=replace_method(text,'QuickActions','build',method); quick.write_text(text)

if stream.is_file():
    text=stream.read_text()
    if '# MECHOS_REFERENCE_STREAM_V4' not in text:
        method=r'''    def build(self):
        # MECHOS_REFERENCE_STREAM_V4
        root=QWidget(); self.setCentralWidget(root); v=QVBoxLayout(root); v.setContentsMargins(22,20,22,20); v.setSpacing(14)
        top=QHBoxLayout(); brand=QLabel("MECHOS"); brand.setObjectName("title"); top.addWidget(brand); top.addStretch(); label=QLabel("STREAM CENTER"); label.setObjectName("section"); top.addWidget(label); v.addLayout(top)
        hero=self.panel(); hl=QHBoxLayout(hero); stat=QVBoxLayout(); h=QLabel("LIVE STATUS"); h.setObjectName("section"); stat.addWidget(h); self.live=QLabel("Checking OBS…"); self.live.setObjectName("offline"); stat.addWidget(self.live); self.detail=QLabel(); self.detail.setObjectName("muted"); self.detail.setWordWrap(True); stat.addWidget(self.detail); hl.addLayout(stat,2)
        actions=QGridLayout(); actions.addWidget(self.btn("Go Live",self.start_stream,"live"),0,0); actions.addWidget(self.btn("End Stream",self.stop_stream,"stop"),0,1); actions.addWidget(self.btn("Start Recording",self.start_record),1,0); actions.addWidget(self.btn("Stop Recording",self.stop_record),1,1); actions.addWidget(self.btn("Open OBS",self.open_obs),2,0); actions.addWidget(self.btn("Refresh",self.refresh),2,1); hl.addLayout(actions,2); v.addWidget(hero)
        middle=QHBoxLayout(); scenes=self.panel(); scl=QVBoxLayout(scenes); sch=QLabel("SCENES"); sch.setObjectName("section"); scl.addWidget(sch); self.scenes=QComboBox(); scl.addWidget(self.scenes); scl.addWidget(self.btn("Switch Scene",self.set_scene)); middle.addWidget(scenes,1)
        setup=self.panel(); spl=QVBoxLayout(setup); sph=QLabel("OBS CONTROL SETUP"); sph.setObjectName("section"); spl.addWidget(sph); note=QLabel("Streaming accounts and stream keys stay inside OBS. MechOS stores only the local WebSocket control settings."); note.setObjectName("muted"); note.setWordWrap(True); spl.addWidget(note); self.port=QSpinBox(); self.port.setRange(1,65535); self.port.setValue(4455); spl.addWidget(self.port); spl.addWidget(self.btn("Save Control Password",self.save_password)); spl.addWidget(self.btn("Open OBS Setup",self.open_obs)); middle.addWidget(setup,2); v.addLayout(middle,1)'''
        text=replace_method(text,'StreamCenter','build',method); stream.write_text(text)

if recovery.is_file():
    text=recovery.read_text()
    if '# MECHOS_REFERENCE_RECOVERY_V4' not in text:
        method=r'''    def build_ui(self):
        # MECHOS_REFERENCE_RECOVERY_V4
        root=QWidget(); outer=QVBoxLayout(root); outer.setContentsMargins(24,20,24,20); outer.setSpacing(14)
        hero=QFrame(); hero.setObjectName("hero"); hl=QVBoxLayout(hero); title=QLabel("MECHOS RECOVERY CENTER"); title.setObjectName("title"); hl.addWidget(title); sub=QLabel("Repair boot • inspect installations • recover failed updates • view logs"); sub.setObjectName("muted"); hl.addWidget(sub); outer.addWidget(hero)
        target=QFrame(); target.setObjectName("panel"); tl=QVBoxLayout(target); th=QLabel("RECOVERY TARGET"); th.setObjectName("section"); tl.addWidget(th); row=QHBoxLayout(); row.addWidget(QLabel("Installed system")); self.root_combo=QComboBox(); row.addWidget(self.root_combo,2); row.addWidget(QLabel("EFI partition")); self.esp_combo=QComboBox(); row.addWidget(self.esp_combo,2); rescan=QPushButton("Rescan"); rescan.clicked.connect(self.rescan); row.addWidget(rescan); tl.addLayout(row); outer.addWidget(target)
        actions=QFrame(); actions.setObjectName("panel"); al=QHBoxLayout(actions); repair=QPushButton("Repair Boot"); repair.setObjectName("primary"); repair.clicked.connect(self.repair_boot); al.addWidget(repair); rollback=QPushButton("Rollback Failed Update"); rollback.clicked.connect(self.rollback); al.addWidget(rollback); logs=QPushButton("Install / Update Logs"); logs.clicked.connect(self.load_logs); al.addWidget(logs); hw=QPushButton("Hardware Scan"); hw.clicked.connect(self.hardware); al.addWidget(hw); outer.addWidget(actions)
        output=QFrame(); output.setObjectName("panel"); ol=QVBoxLayout(output); oh=QLabel("RECOVERY OUTPUT"); oh.setObjectName("section"); ol.addWidget(oh); self.output=QPlainTextEdit(); self.output.setReadOnly(True); self.output.setPlaceholderText("Recovery output appears here."); ol.addWidget(self.output); outer.addWidget(output,1)
        note=QLabel("Boot Repair does not repartition or format disks. Rollback is offered only when MechOS recorded a valid pre-update Snapper snapshot."); note.setObjectName("muted"); note.setWordWrap(True); outer.addWidget(note); self.setCentralWidget(root)'''
        text=replace_method(text,'Recovery','build_ui',method); recovery.write_text(text)

if creator.is_file():
    text=creator.read_text()
    marker='# MECHOS_REFERENCE_CREATOR_MODE_V4'
    if marker not in text:
        anchor='        self.setWindowTitle("MechOS Creator Mode 2.0")\n'
        if anchor in text:
            text=text.replace(anchor,anchor+'        # MECHOS_REFERENCE_CREATOR_MODE_V4\n        self.setWindowFlag(Qt.WindowType.FramelessWindowHint, True)\n',1)
        old='''    def mechscope(self):\n        spawn(["/usr/local/bin/mechos-return-to-mechscope"]); QApplication.quit()\n'''
        new='''    def mechscope(self):\n        control="/usr/local/bin/mechos-gaming-layer-control"\n        if Path(control).exists():\n            result=subprocess.run([control,"gaming"],text=True,capture_output=True)\n            if result.returncode==0:\n                QTimer.singleShot(250,QApplication.quit)\n                return\n            QMessageBox.warning(self,"MechOS Mode Switch",result.stderr.strip() or "MechScope could not start.")\n            return\n        QMessageBox.warning(self,"MechOS Mode Switch","MechScope mode controller is unavailable.")\n'''
        if old in text: text=text.replace(old,new,1)
        creator.write_text(text)

if control.is_file():
    text=control.read_text()
    if '# MECHOS_CREATOR_READY_HANDOFF_V4' not in text:
        start=text.find('  creator)')
        end=text.find('\n    ;;',start)
        if start>=0 and end>=0:
            end += len('\n    ;;')
            block='''  creator)\n    # MECHOS_CREATOR_READY_HANDOFF_V4\n    systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE DBUS_SESSION_BUS_ADDRESS >/dev/null 2>&1 || true\n    systemctl --user reset-failed mechos-creator-mode.service >/dev/null 2>&1 || true\n    systemctl --user start --no-block mechos-creator-mode.service\n    ready=0\n    for _ in $(seq 1 20); do\n      if systemctl --user is-active --quiet mechos-creator-mode.service; then ready=1; break; fi\n      sleep 0.1\n    done\n    if [ "$ready" -eq 1 ]; then\n      stop_layer\n      exit 0\n    fi\n    echo "Creator Mode did not become active; keeping MechScope open." >&2\n    exit 1\n    ;;'''
            text=text[:start]+block+text[end:]
            control.write_text(text)
PY

  for f in "$update" "$quick" "$stream" "$recovery" "$creator"; do
    [ -f "$f" ] || continue
    PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$f" || fail "Python validation failed: $f"
  done
  [ ! -f "$control" ] || bash -n "$control" || fail "mode control validation failed: $control"
}

patch_tree() {
  local tree="$1"
  write_performance_center "$tree"
  patch_python_layouts "$tree"
  grep -Fq 'MECHOS_REFERENCE_SURFACES_V4' "$tree/usr/local/bin/mechos-performance-center" || fail "Performance Center v4 marker missing"
  grep -Fq 'MECHOS_RADARAI_PERFORMANCE_CENTER_V1' "$tree/usr/local/bin/mechos-performance-center" || fail "RadarAI integration marker missing after v4 rewrite"
  for name in mechos-update-center mechos-quick-actions mechos-stream-center mechos-recovery-center; do
    [ -f "$tree/usr/local/bin/$name" ] || continue
    grep -Fq 'MECHOS_REFERENCE_' "$tree/usr/local/bin/$name" || fail "$name did not receive a Reference v4 layout"
  done
}

patch_tree "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xf "$ARCHIVE" -C "$tmp"
patch_tree "$tmp"
replacement="$ARCHIVE.reference-surfaces-v4"
tar --zstd -cpf "$replacement" -C "$tmp" .
mv -f "$replacement" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

log "Reference Surfaces v4 applied to Performance, Updates, Quick Actions, Streaming, Recovery and Creator mode handoffs"
