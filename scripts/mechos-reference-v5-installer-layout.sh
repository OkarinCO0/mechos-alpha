#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
FILE="$ROOT/usr/local/bin/mechos-live-setup"
[ -f "$FILE" ] || { echo '[MechOS Installer v5] graphical installer missing' >&2; exit 1; }

python3 - "$FILE" <<'PY'
from pathlib import Path
import sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
marker='# MECHOS_REFERENCE_INSTALLER_V5'
if marker in text:
    raise SystemExit(0)

if 'import json\n' not in text:
    text=text.replace('import os\n','import json\nimport os\n',1)
if 'from pathlib import Path' not in text:
    anchor='import sys\n'
    if anchor in text: text=text.replace(anchor,anchor+'from pathlib import Path\n',1)

start=text.find('class Installer(QMainWindow):')
end=text.find('\ndef main():',start)
if start < 0 or end < 0:
    raise SystemExit('[MechOS Installer v5] Installer class not found')

replacement=r'''class Installer(QMainWindow):
    # MECHOS_REFERENCE_INSTALLER_V5
    SELECTION = Path('/tmp/mechos-install-target.json')

    def __init__(self):
        super().__init__()
        self.setWindowTitle('MechOS Installer')
        self.resize(1560,900)
        self.setMinimumSize(1180,720)
        self.setStyleSheet(STYLE)
        self.hw=hardware_summary()
        self.disks=disk_list()
        self.selected_disk=self.disks[0][0] if self.disks else ''
        self.selected_size=self.disks[0][1] if self.disks else ''
        self.selected_model=self.disks[0][2] if self.disks else ''
        self.install_mode='clean'
        self.build_ui()
        self.sync_selection_from_disk()
        self.selection_timer=QTimer(self)
        self.selection_timer.timeout.connect(self.read_external_selection)
        self.selection_timer.start(1000)

    def panel(self,glow=False,name=None):
        f=QFrame(); f.setObjectName(name or ('glowPanel' if glow else 'panel')); return f

    def section(self,text):
        l=QLabel(text); l.setObjectName('accent'); l.setStyleSheet('font-size:13px;font-weight:900;color:#48dfff'); return l

    def muted(self,text):
        l=QLabel(text); l.setObjectName('muted'); l.setWordWrap(True); return l

    def build_ui(self):
        root=QWidget(); self.setCentralWidget(root)
        outer=QVBoxLayout(root); outer.setContentsMargins(18,12,18,14); outer.setSpacing(10)

        header=QHBoxLayout()
        if os.path.exists(LOGO):
            logo=QLabel(); logo.setPixmap(QPixmap(LOGO).scaledToHeight(48,Qt.TransformationMode.SmoothTransformation)); header.addWidget(logo)
        brand=QLabel('MECHOS'); brand.setStyleSheet('font-size:23px;font-weight:900;color:white'); header.addWidget(brand)
        header.addStretch()
        titlebox=QVBoxLayout(); title=QLabel('MECHOS INSTALLER'); title.setStyleSheet('font-size:28px;font-weight:900;color:#c96cff;letter-spacing:2px'); title.setAlignment(Qt.AlignmentFlag.AlignCenter); titlebox.addWidget(title)
        sub=QLabel('Gaming + Creator OS'); sub.setAlignment(Qt.AlignmentFlag.AlignCenter); sub.setObjectName('muted'); titlebox.addWidget(sub); header.addLayout(titlebox)
        header.addStretch()
        net=QLabel('LIVE INSTALLATION'); net.setObjectName('muted'); header.addWidget(net)
        outer.addLayout(header)

        body=QHBoxLayout(); body.setSpacing(14)
        navp=self.panel(); navp.setFixedWidth(300); nl=QVBoxLayout(navp); nl.setContentsMargins(12,14,12,14)
        self.nav=QListWidget()
        nav_items=[
            '1    Welcome\n      Get started',
            '2    Hardware Scan\n      Detecting your system',
            '3    Partitions\n      Disk setup and layout',
            '4    Install\n      Install MechOS',
            '5    Repair Boot\n      Fix boot issues',
            '6    Recovery\n      System recovery tools',
            '7    Update / Reinstall\n      Keep Home',
            '8    Install Logs\n      Review logs',
            '9    Finish\n      Complete',
        ]
        for item in nav_items: self.nav.addItem(QListWidgetItem(item))
        self.nav.setCurrentRow(0); self.nav.currentRowChanged.connect(self.nav_selected); nl.addWidget(self.nav)
        body.addWidget(navp)

        center=QVBoxLayout(); center.setSpacing(10)
        target=self.panel(); tl=QVBoxLayout(target); tl.setContentsMargins(18,14,18,14)
        tl.addWidget(self.section('SELECT TARGET DRIVE'))
        targetrow=QHBoxLayout(); driveicon=QLabel('▣'); driveicon.setStyleSheet('font-size:34px;color:#c66dff'); targetrow.addWidget(driveicon)
        drivecopy=QVBoxLayout(); self.drive_name=QLabel('No install target'); self.drive_name.setStyleSheet('font-size:18px;font-weight:900'); drivecopy.addWidget(self.drive_name)
        self.drive_detail=self.muted('Choose a whole disk or existing partition'); drivecopy.addWidget(self.drive_detail); targetrow.addLayout(drivecopy,1)
        self.drive_space=QLabel(''); self.drive_space.setObjectName('metric'); targetrow.addWidget(self.drive_space)
        change=QPushButton('Change Drive'); change.clicked.connect(self.open_partition_selector); targetrow.addWidget(change); tl.addLayout(targetrow); center.addWidget(target)

        options=self.panel(); ol=QVBoxLayout(options); ol.setContentsMargins(18,14,18,14); ol.setSpacing(9); ol.addWidget(self.section('CHOOSE INSTALLATION OPTION'))
        self.mode_group=QButtonGroup(self); self.mode_group.setExclusive(True); self.mode_cards={}
        self.clean=self.install_card('clean','Clean Install','Erase the selected whole drive and install MechOS.','Best for new setups and maximum performance.')
        self.keep=self.install_card('keep','Keep Personal Data','Refresh / reinstall MechOS while preserving /home and system identity.','Existing personal files are not formatted or replaced.')
        self.custom=self.install_card('custom','Custom Install','Choose what to install and configure partitions.','For advanced users who want full control.')
        self.alongside=self.install_card('alongside','Install Alongside Existing OS','Guided dual-boot planning for an existing Windows/Linux system.','Disk changes remain visible and manually confirmed.')
        for card in (self.clean,self.keep,self.custom,self.alongside): ol.addWidget(card)
        info=self.panel(); il=QHBoxLayout(info); il.addWidget(QLabel('ⓘ')); self.warning_text=self.muted('Clean Install erases only the selected whole disk after a final MechOS confirmation.'); il.addWidget(self.warning_text,1); ol.addWidget(info)
        center.addWidget(options,1); body.addLayout(center,5)

        right=QVBoxLayout(); right.setSpacing(10)
        hw=self.panel(); hl=QVBoxLayout(hw); hl.addWidget(self.section('HARDWARE SUMMARY'))
        for key,val in self.hw.items():
            row=QHBoxLayout(); k=QLabel(key); k.setStyleSheet('color:#c96cff;font-weight:900'); row.addWidget(k); row.addStretch(); v=QLabel(str(val)); v.setWordWrap(True); v.setMaximumWidth(245); row.addWidget(v); hl.addLayout(row)
        right.addWidget(hw)
        overview=self.panel(); ov=QVBoxLayout(overview); ov.addWidget(self.section('INSTALL OVERVIEW'))
        self.ov_drive=QLabel(); self.ov_mode=QLabel('Clean Install'); self.ov_partition=QLabel('MechOS managed'); self.ov_fs=QLabel('Btrfs (Clean Install)')
        for label,widget in [('Selected Drive',self.ov_drive),('Installation Option',self.ov_mode),('Partition Scheme',self.ov_partition),('File System',self.ov_fs)]:
            row=QHBoxLayout(); l=QLabel(label); l.setObjectName('muted'); row.addWidget(l); row.addStretch(); widget.setWordWrap(True); widget.setMaximumWidth(220); row.addWidget(widget); ov.addLayout(row)
        self.progress=QProgressBar(); self.progress.setRange(0,100); self.progress.setValue(0); self.progress.setFormat('Ready to install'); ov.addWidget(self.progress)
        right.addWidget(overview); right.addStretch(); body.addLayout(right,2); outer.addLayout(body,1)

        footer=QHBoxLayout(); hint=QLabel('A / Enter  Select     B / Esc  Back     D-Pad / Arrows  Navigate'); hint.setObjectName('muted'); footer.addWidget(hint); footer.addStretch()
        repair=QPushButton('Repair\nFix boot or system issues'); repair.clicked.connect(self.recovery); footer.addWidget(repair)
        install=QPushButton('Install Now\nStart installation'); install.setObjectName('primary'); install.clicked.connect(self.install); footer.addWidget(install); outer.addLayout(footer)

        # Do not select the default radio button until every widget touched by
        # set_mode() exists. Selecting it earlier fires the Qt toggled signal
        # during build_ui() and can abort PyQt before the installer is shown.
        self.mode_buttons['clean'].setChecked(True)
        self.refresh_target_labels()

    def install_card(self,mode,title,desc,detail):
        if not hasattr(self,'mode_buttons'): self.mode_buttons={}
        p=self.panel(); p.setMinimumHeight(96); row=QHBoxLayout(p); row.setContentsMargins(18,12,18,12)
        rb=QRadioButton(); rb.setProperty('installMode',mode); self.mode_group.addButton(rb); self.mode_buttons[mode]=rb; row.addWidget(rb)
        icon=QLabel({'clean':'♨','keep':'▣','custom':'☷','alongside':'▤'}[mode]); icon.setStyleSheet('font-size:30px;color:#bf67ff'); row.addWidget(icon)
        copy=QVBoxLayout(); t=QLabel(title); t.setStyleSheet('font-size:18px;font-weight:900'); copy.addWidget(t); copy.addWidget(self.muted(desc)); copy.addWidget(self.muted(detail)); row.addLayout(copy,1)
        check=QLabel('○'); check.setStyleSheet('font-size:26px;color:#a9b3c8'); row.addWidget(check)
        rb.toggled.connect(lambda checked,m=mode,c=check:self.set_mode(m,checked,c)); p.mousePressEvent=lambda _event,b=rb: b.setChecked(True); self.mode_cards[mode]=p; return p

    def set_mode(self,mode,checked,check=None):
        if not checked:
            if check is not None: check.setText('○')
            return
        self.install_mode=mode
        for m in self.mode_buttons:
            c=self.mode_cards[m].findChildren(QLabel)[-1]
            if c.text() in ('○','✓'): c.setText('✓' if m==mode else '○')
        names={'clean':'Clean Install','keep':'Keep Personal Data','custom':'Custom Install','alongside':'Install Alongside Existing OS'}; self.ov_mode.setText(names[mode])
        if mode=='clean': self.warning_text.setText('Clean Install erases only the selected whole disk after a final MechOS confirmation.'); self.ov_partition.setText('GPT • BIOS + UEFI'); self.ov_fs.setText('Btrfs')
        elif mode=='keep': self.warning_text.setText('/home, accounts, passwords, network identity and completed first-boot state are preserved by the Live update/reinstall path.'); self.ov_partition.setText('Existing layout preserved'); self.ov_fs.setText('Existing filesystem')
        elif mode=='custom': self.warning_text.setText('Custom Install uses explicit manual partitioning. Nothing is formatted silently.'); self.ov_partition.setText('Manual'); self.ov_fs.setText('User selected')
        else: self.warning_text.setText('Alongside mode scans existing systems read-only and guides a dual-boot layout. Resizing/formatting is never automatic.'); self.ov_partition.setText('Guided dual boot'); self.ov_fs.setText('User confirmed')

    def refresh_target_labels(self):
        if self.selected_disk:
            name=(self.selected_model or 'Disk').strip(); self.drive_name.setText(f'{name}  {self.selected_size}'.strip()); self.drive_detail.setText(self.selected_disk); self.drive_space.setText('Selected'); self.ov_drive.setText(self.selected_disk)
        else: self.drive_name.setText('No install target selected'); self.drive_detail.setText('Choose a target drive before Clean Install.'); self.drive_space.setText(''); self.ov_drive.setText('None')

    def sync_selection_from_disk(self):
        if not self.selected_disk: return
        try:
            size=int(subprocess.check_output(['lsblk','-bdno','SIZE',self.selected_disk],text=True,stderr=subprocess.DEVNULL).strip() or 0)
            self.SELECTION.write_text(json.dumps({'kind':'disk','path':self.selected_disk,'disk':self.selected_disk,'size_bytes':size,'fstype':'','label':''},indent=2),encoding='utf-8')
        except Exception: pass

    def read_external_selection(self):
        if not self.SELECTION.is_file(): return
        try: data=json.loads(self.SELECTION.read_text(encoding='utf-8'))
        except Exception: return
        p=str(data.get('path') or '')
        if not p or p==self.selected_disk: return
        self.selected_disk=p; self.selected_size=''; self.selected_model='Selected location'
        try: self.selected_size=subprocess.check_output(['lsblk','-dno','SIZE',str(data.get('disk') or p)],text=True,stderr=subprocess.DEVNULL).strip()
        except Exception: pass
        self.refresh_target_labels()

    def open_partition_selector(self): subprocess.Popen(['/usr/local/bin/mechos-partition-selector'])

    def nav_selected(self,row):
        if row==1: subprocess.Popen(['konsole','-e','bash','-lc',"/usr/local/bin/mechos-hardware-scan; echo; read -rp 'Press Enter to close…'"])
        elif row==2: self.open_partition_selector()
        elif row==3: self.mode_buttons[self.install_mode].setFocus()
        elif row in (4,5): self.recovery()
        elif row==6: self.mode_buttons['keep'].setChecked(True); self.install()
        elif row==7: subprocess.Popen(['konsole','-e','bash','-lc',"/usr/local/bin/mechos-recovery-helper logs; echo; read -rp 'Press Enter to close…'"])
        elif row==8: self.close()

    def install(self):
        if self.install_mode=='keep': subprocess.Popen(['konsole','-e','sudo','/usr/local/bin/mechos-live-update-keep-home']); return
        if self.install_mode=='alongside': subprocess.Popen(['konsole','-e','sudo','/usr/local/bin/mechos-alongside-assistant']); return
        if self.install_mode=='custom':
            QMessageBox.information(self,'Custom Install','MechOS will open explicit manual partitioning. Review every mount point and formatting choice before confirming.')
            subprocess.Popen(['konsole','-e','sudo','/usr/local/bin/mechos-install','--terminal','--preserve-home']); return
        if not self.selected_disk: QMessageBox.warning(self,'MechOS Installer','Select a whole target disk before starting Clean Install.'); return
        self.sync_selection_from_disk(); subprocess.Popen(['/usr/local/bin/mechos-native-install'])

    def recovery(self): subprocess.Popen(['/usr/local/bin/mechos-recovery-center'])
'''

text=text[:start]+replacement+text[end:]
path.write_text(text,encoding='utf-8')
PY

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$FILE"
grep -Fq 'MECHOS_REFERENCE_INSTALLER_V5' "$FILE"
grep -Fq 'Install Alongside Existing OS' "$FILE"
grep -Fq 'mechos-native-install' "$FILE"
grep -Fq 'mechos-live-update-keep-home' "$FILE"
grep -Fq 'mechos-alongside-assistant' "$FILE"
grep -Fq -- "--preserve-home" "$FILE"
grep -Fq 'QButtonGroup' "$FILE"
echo '[MechOS Installer v5] reference installer layout applied'
