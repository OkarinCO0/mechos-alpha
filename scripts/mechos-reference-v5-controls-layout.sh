#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
PERF="$ROOT/usr/local/bin/mechos-performance-center"
UPDATE="$ROOT/usr/local/bin/mechos-update-center"
QUICK="$ROOT/usr/local/bin/mechos-quick-actions"
RECOVERY="$ROOT/usr/local/bin/mechos-recovery-center"

python3 - "$PERF" "$UPDATE" "$QUICK" "$RECOVERY" <<'PY'
from pathlib import Path
import sys

perf,update,quick,recovery=[Path(x) for x in sys.argv[1:]]

def replace_method(text,cls,name,new):
    c=text.find('class '+cls)
    if c<0: raise SystemExit(f'[MechOS Controls v5] class {cls} not found')
    s=text.find('    def '+name+'(',c)
    if s<0: raise SystemExit(f'[MechOS Controls v5] {cls}.{name} not found')
    e=text.find('\n    def ',s+8)
    if e<0: raise SystemExit(f'[MechOS Controls v5] end of {cls}.{name} not found')
    return text[:s]+new.rstrip()+'\n'+text[e:]

if perf.is_file():
    text=perf.read_text(encoding='utf-8')
    if '# MECHOS_REFERENCE_PERFORMANCE_V5' not in text:
        method=r'''    def build(self):
        # MECHOS_REFERENCE_PERFORMANCE_V5
        root=QWidget(); self.setCentralWidget(root)
        outer=QVBoxLayout(root); outer.setContentsMargins(20,14,20,14); outer.setSpacing(10)
        top=QHBoxLayout(); brand=QLabel('MECHOS'); brand.setObjectName('brand'); top.addWidget(brand); top.addStretch(); title=QLabel('PERFORMANCE CENTER'); title.setObjectName('purple'); top.addWidget(title); top.addStretch(); self.profile_badge=QLabel('PROFILE  --'); self.profile_badge.setObjectName('metric'); top.addWidget(self.profile_badge); outer.addLayout(top)

        first=QHBoxLayout(); first.setSpacing(10)
        hero=self.panel('surfaceHero'); hl=QHBoxLayout(hero); copy=QVBoxLayout(); eye=QLabel('SYSTEM OPTIMIZATION & TUNING'); eye.setObjectName('surfaceEyebrow'); copy.addWidget(eye); h=QLabel('Maximize Performance.\nDominate Every Game.'); h.setObjectName('surfaceTitle'); copy.addWidget(h); self.gpu_label=QLabel('Detecting graphics hardware…'); self.gpu_label.setObjectName('surfaceMuted'); self.gpu_label.setWordWrap(True); copy.addWidget(self.gpu_label)
        ar=QHBoxLayout(); ar.addWidget(self.action('Run Optimization','Open current optimization report / tools',lambda:run(['/usr/local/bin/mechos-optimization-report']),True) if Path('/usr/local/bin/mechos-optimization-report').exists() else self.action('Run Optimization','Open Performance tools',lambda:run(['/usr/local/bin/mechos-performance-center']))); ar.addWidget(self.action('Auto Optimization','Use MechOS performance profile',lambda:set_profile('performance',self))); copy.addLayout(ar); hl.addLayout(copy,3)
        first.addWidget(hero,3)

        metrics=self.panel(); ml=QHBoxLayout(metrics); self.cpu_card=MetricCard('CPU','--','Load'); self.ram_card=MetricCard('RAM','--','Used'); self.disk_card=MetricCard('DISK','--','Used'); self.zram_card=MetricCard('ZRAM','--','Compressed swap');
        for c in (self.cpu_card,self.ram_card,self.disk_card,self.zram_card): ml.addWidget(c)
        first.addWidget(metrics,3)
        gpu=self.panel(); gl=QVBoxLayout(gpu); gh=QLabel('GPU INFORMATION'); gh.setObjectName('surfaceSection'); gl.addWidget(gh); self.gpu_summary=QLabel('Detected GPU'); self.gpu_summary.setObjectName('surfaceMetric'); self.gpu_summary.setWordWrap(True); gl.addWidget(self.gpu_summary); gl.addWidget(self.action('GPU Diagnostics','Vulkan / VA-API / driver info',self.gpu_info)); first.addWidget(gpu,1)
        outer.addLayout(first)

        second=QHBoxLayout(); second.setSpacing(10)
        profiles=self.panel(); pl=QVBoxLayout(profiles); ph=QLabel('PERFORMANCE PROFILES'); ph.setObjectName('surfaceSection'); pl.addWidget(ph); pr=QHBoxLayout(); pr.addWidget(self.action('Gaming Performance','Maximum available FPS & responsiveness',lambda:set_profile('performance',self),True)); pr.addWidget(self.action('Balanced','Optimized for all-around use',lambda:set_profile('balanced',self))); pr.addWidget(self.action('Battery Saver','Extended battery & cooler operation',lambda:set_profile('power-saver',self))); pl.addLayout(pr); second.addWidget(profiles,2)
        health=self.panel(); hll=QVBoxLayout(health); hh=QLabel('SYSTEM HEALTH'); hh.setObjectName('surfaceSection'); hll.addWidget(hh); self.health_label=QLabel('CHECKING'); self.health_label.setObjectName('surfaceMetric'); hll.addWidget(self.health_label); hll.addWidget(QLabel('CPU / memory telemetry • storage tools • thermal checks')); hll.addWidget(self.action('Run Full Diagnostics','Hardware and health tools',lambda:run(['/usr/local/bin/mechos-hardware-scan']))); second.addWidget(health,1)
        status=self.panel(); st=QVBoxLayout(status); sh=QLabel('OPTIMIZATION STATUS'); sh.setObjectName('surfaceSection'); st.addWidget(sh); st.addWidget(QLabel('✓ Power profile managed by MechOS\n✓ GameMode available\n✓ Performance overlay available\n✓ Driver tools available')); st.addWidget(self.action('Optimize Now','Set gaming performance profile',lambda:set_profile('performance',self))); second.addWidget(status,1); outer.addLayout(second)

        tools=QHBoxLayout(); tools.setSpacing(10)
        groups=[
            ('GAMING & GRAPHICS',[('Open MangoHud Overlay','Real-time performance overlay',self.toggle_hud),('GPU Diagnostics','Deep GPU analysis',self.gpu_info)]),
            ('HARDWARE & HEALTH',[('System Monitor','Real-time system monitor',lambda:run(['konsole','-e','btop'])),('Hardware Info','Detailed hardware overview',self.cpu_info)]),
            ('MONITORING TOOLS',[('Resource Monitor','CPU, RAM, disk and network',lambda:run(['konsole','-e','btop'])),('Storage Health','NVMe / disk health',self.storage_info)]),
            ('MECHOS TOOLS',[('RadarAI','AI system diagnostics',self.launch_radarai),('Quick Actions','System controls',lambda:run(['/usr/local/bin/mechos-quick-actions']))]),
            ('OVERLAY & RECORDING',[('Performance Overlay','MangoHud / MangoApp',self.toggle_hud),('Recording & Capture','GPU Screen Recorder',self.recorder)]),
            ('UPDATE CENTER',[('Check for Updates','System & driver updates',lambda:run(['/usr/local/bin/mechos-update-center'])),('Update History','Open Update Center',lambda:run(['/usr/local/bin/mechos-update-center']))]),
        ]
        for title,items in groups:
            p=self.panel(); l=QVBoxLayout(p); q=QLabel(title); q.setObjectName('surfaceSection'); l.addWidget(q)
            for a,b,fn in items: l.addWidget(self.action(a,b,fn)); l.addStretch(); tools.addWidget(p,1)
        outer.addLayout(tools,1)

        bottom=QHBoxLayout(); qa=self.panel(); ql=QVBoxLayout(qa); qt=QLabel('QUICK ACTIONS'); qt.setObjectName('surfaceSection'); ql.addWidget(qt); qr=QHBoxLayout()
        for name,fn in [('Power Plan',lambda:set_profile('performance',self)),('Game Mode',lambda:run(['gamemoderun','true'])),('System Info',self.cpu_info),('Network',lambda:run(['systemsettings','kcm_networkmanagement']))]:
            qr.addWidget(self.action(name,'',fn))
        ql.addLayout(qr); bottom.addWidget(qa,3)
        radar=self.panel(); rl=QVBoxLayout(radar); rh=QLabel('RADARAI STATUS'); rh.setObjectName('surfaceSection'); rl.addWidget(rh); self.radar=self.action('RadarAI','Open diagnostics and insights',self.launch_radarai,True); rl.addWidget(self.radar); bottom.addWidget(radar,2); outer.addLayout(bottom)
'''
        text=replace_method(text,'Perf','build',method)
        # Keep GPU summary synchronized with the same real lspci value.
        needle="        self.gpu_label.setText(gpu)\n"
        if needle in text: text=text.replace(needle,needle+"        self.gpu_summary.setText(gpu)\n",1)
        perf.write_text(text,encoding='utf-8')

if update.is_file():
    text=update.read_text(encoding='utf-8')
    if '# MECHOS_REFERENCE_UPDATE_V5' not in text:
        method=r'''    def build_ui(self):
        # MECHOS_REFERENCE_UPDATE_V5
        root=QWidget(); self.setCentralWidget(root); outer=QVBoxLayout(root); outer.setContentsMargins(20,14,20,14); outer.setSpacing(10)
        top=QHBoxLayout(); b=QLabel('MECHOS'); b.setObjectName('brand'); top.addWidget(b); top.addStretch(); t=QLabel('UPDATE CENTER'); t.setObjectName('purple'); top.addWidget(t); top.addStretch(); outer.addLayout(top)
        body=QHBoxLayout(); body.setSpacing(12); main=QVBoxLayout(); main.setSpacing(10)
        hero=self.panel(); hero.setObjectName('hero'); hl=QHBoxLayout(hero); copy=QVBoxLayout(); copy.addWidget(QLabel('Your system is')); self.status_label=QLabel('Checking…'); self.status_label.setObjectName('title'); copy.addWidget(self.status_label); self.details_label=QLabel('Checking MechOS, Arch and Flatpak update state'); self.details_label.setObjectName('muted'); self.details_label.setWordWrap(True); copy.addWidget(self.details_label); hl.addLayout(copy,2)
        stat=self.panel(); sl=QVBoxLayout(stat); self.channel=QLabel('SYSTEM HEALTH  •  STABLE'); self.channel.setObjectName('section'); sl.addWidget(self.channel); self.reboot_label=QLabel('Restart not required'); self.reboot_label.setObjectName('metric'); sl.addWidget(self.reboot_label); hl.addWidget(stat,1)
        self.check_button=QPushButton('Check for Updates'); self.check_button.setObjectName('primary'); self.check_button.clicked.connect(self.check_updates); hl.addWidget(self.check_button); main.addWidget(hero)
        cards=QHBoxLayout()
        for title,detail in [('System Updates','Core OS and runtime'),('Drivers & Firmware','Hardware support'),('MechOS Hotfixes','Stability & fixes'),('Creator Packages','Tools & dependencies'),('Store Metadata','Catalog & profiles')]:
            p=self.panel(); l=QVBoxLayout(p); h=QLabel(title); h.setStyleSheet('font-weight:900'); l.addWidget(h); d=QLabel(detail); d.setObjectName('muted'); l.addWidget(d); ok=QLabel('Status checked with Update Center'); ok.setStyleSheet('color:#31e981'); l.addWidget(ok); cards.addWidget(p,1)
        main.addLayout(cards)
        lower=QHBoxLayout(); prog=self.panel(); pl=QVBoxLayout(prog); ph=QLabel('UPDATE PROGRESS'); ph.setObjectName('section'); pl.addWidget(ph); self.progress=QProgressBar(); self.progress.setRange(0,1); self.progress.setValue(0); self.progress.setFormat('Ready'); pl.addWidget(self.progress); self.update_button=QPushButton('Install Updates'); self.update_button.setObjectName('primary'); self.update_button.clicked.connect(self.apply_updates); self.update_button.setEnabled(False); pl.addWidget(self.update_button); self.reboot_button=QPushButton('Schedule / Restart MechOS'); self.reboot_button.clicked.connect(self.reboot); self.reboot_button.setEnabled(False); pl.addWidget(self.reboot_button); lower.addWidget(prog,1)
        changelog=self.panel(); cl=QVBoxLayout(changelog); ch=QLabel('CHANGELOG / UPDATE OUTPUT'); ch.setObjectName('section'); cl.addWidget(ch); self.log=QPlainTextEdit(); self.log.setReadOnly(True); cl.addWidget(self.log); lower.addWidget(changelog,2); main.addLayout(lower,2)
        history=self.panel(); hll=QVBoxLayout(history); hh=QLabel('UPDATE HISTORY'); hh.setObjectName('section'); hll.addWidget(hh); self.history=QPlainTextEdit(); self.history.setReadOnly(True); hll.addWidget(self.history); self.history_button=QPushButton('Refresh History'); self.history_button.clicked.connect(self.load_history); hll.addWidget(self.history_button); main.addWidget(history,1); body.addLayout(main,5)
        side=QVBoxLayout(); status=self.panel(); ssl=QVBoxLayout(status); ss=QLabel('SYSTEM STATUS'); ss.setObjectName('section'); ssl.addWidget(ss); ssl.addWidget(QLabel('CPU / RAM / Disk telemetry is available in Performance Center.')); runp=QPushButton('Run Optimization'); runp.clicked.connect(lambda:spawn(['/usr/local/bin/mechos-performance-center'])); ssl.addWidget(runp); side.addWidget(status)
        quickp=self.panel(); ql=QVBoxLayout(quickp); qh=QLabel('QUICK ACTIONS'); qh.setObjectName('section'); ql.addWidget(qh)
        for name,cmd in [('Performance Center',['/usr/local/bin/mechos-performance-center']),('System Info',['systemsettings','kcm_about-distro']),('Network Manager',['systemsettings','kcm_networkmanagement']),('Creator Mode',['/usr/local/bin/mechos-creator-mode'])]:
            q=QPushButton(name); q.clicked.connect(lambda _=False,c=cmd:spawn(c)); ql.addWidget(q)
        side.addWidget(quickp); side.addStretch(); power=self.panel(); pw=QVBoxLayout(power); rr=QPushButton('Restart MechOS'); rr.clicked.connect(self.reboot); pw.addWidget(rr); sd=QPushButton('Shut Down'); sd.setObjectName('danger'); sd.clicked.connect(lambda:spawn(['systemctl','poweroff'])); pw.addWidget(sd); side.addWidget(power); body.addLayout(side,1); outer.addLayout(body,1)
'''
        text=replace_method(text,'UpdateCenter','build_ui',method); update.write_text(text,encoding='utf-8')

if quick.is_file():
    text=quick.read_text(encoding='utf-8')
    if '# MECHOS_REFERENCE_QUICK_ACTIONS_V5' not in text:
        method=r'''    def build(self):
        # MECHOS_REFERENCE_QUICK_ACTIONS_V5
        root=QWidget(); self.setCentralWidget(root); outer=QVBoxLayout(root); outer.setContentsMargins(18,12,18,12); outer.setSpacing(10)
        top=QHBoxLayout(); b=QLabel('MECHOS'); b.setObjectName('brand'); top.addWidget(b); top.addStretch(); t=QLabel('QUICK ACTIONS'); t.setObjectName('purple'); top.addWidget(t); top.addStretch(); close=QPushButton('✕'); close.clicked.connect(self.close); top.addWidget(close); outer.addLayout(top)
        cols=QHBoxLayout(); cols.setSpacing(10)
        left=QVBoxLayout(); perf=self.panel(); pl=QVBoxLayout(perf); ph=QLabel('PERFORMANCE'); ph.setObjectName('section'); pl.addWidget(ph); pgrid=QHBoxLayout(); pgrid.addWidget(self.button('Quiet',lambda:self.profile('power-saver'),'profile')); pgrid.addWidget(self.button('Balanced',lambda:self.profile('balanced'),'profile')); pgrid.addWidget(self.button('Turbo',lambda:self.profile('performance'),'profile')); pgrid.addWidget(self.button('Custom',lambda:spawn(['/usr/local/bin/mechos-performance-center']))); pl.addLayout(pgrid); pl.addWidget(self.button('Performance Center',lambda:spawn(['/usr/local/bin/mechos-performance-center']))); left.addWidget(perf)
        devices=self.panel(); dl=QVBoxLayout(devices); dh=QLabel('DEVICE CONTROLS'); dh.setObjectName('section'); dl.addWidget(dh); dl.addWidget(self.button('Wi-Fi  •  Toggle',self.toggle_wifi)); dl.addWidget(self.button('Bluetooth  •  Toggle',self.toggle_bt)); dl.addWidget(self.button('Display / Touchpad Settings',lambda:spawn(['systemsettings']))); left.addWidget(devices); cols.addLayout(left,1)

        mid1=QVBoxLayout(); rgb=self.panel(); rl=QVBoxLayout(rgb); rh=QLabel('KEYBOARD RGB'); rh.setObjectName('section'); rl.addWidget(rh); rl.addWidget(self.button('Choose Color',lambda:spawn(['/usr/local/bin/mechos-rgb-keyboard','picker']))); rl.addWidget(self.button('Restore Saved Color',lambda:spawn(['/usr/local/bin/mechos-rgb-keyboard','restore']))); rl.addWidget(self.button('Advanced OpenRGB',lambda:spawn(['/usr/local/bin/mechos-rgb-keyboard','advanced']))); mid1.addWidget(rgb)
        stream=self.panel(); sl=QVBoxLayout(stream); sh=QLabel('STREAMING & RECORDING'); sh.setObjectName('section'); sl.addWidget(sh); sl.addWidget(self.button('Go Live',lambda:spawn(['/usr/local/bin/mechos-stream-control','start-stream']))); sl.addWidget(self.button('End Stream',lambda:spawn(['/usr/local/bin/mechos-stream-control','stop-stream']))); sl.addWidget(self.button('Toggle Recording',lambda:spawn(['/usr/local/bin/mechos-stream-control','toggle-record']))); sl.addWidget(self.button('Stream Center',lambda:spawn(['/usr/local/bin/mechos-stream-center']))); mid1.addWidget(stream); cols.addLayout(mid1,1)

        mid2=QVBoxLayout(); audio=self.panel(); al=QVBoxLayout(audio); ah=QLabel('AUDIO'); ah.setObjectName('section'); al.addWidget(ah); ar=QHBoxLayout(); ar.addWidget(self.button('Volume −',lambda:self.wpctl('5%-'))); ar.addWidget(self.button('Mute',self.mute)); ar.addWidget(self.button('Volume +',lambda:self.wpctl('5%+'))); al.addLayout(ar); al.addWidget(self.button('Audio Settings',lambda:spawn(['systemsettings','kcm_pulseaudio']))); mid2.addWidget(audio)
        display=self.panel(); dpl=QVBoxLayout(display); dph=QLabel('DISPLAY'); dph.setObjectName('section'); dpl.addWidget(dph); br=QHBoxLayout(); br.addWidget(self.button('Brightness −',lambda:self.brightness('5%-'))); br.addWidget(self.button('Brightness +',lambda:self.brightness('+5%'))); dpl.addLayout(br); dpl.addWidget(self.button('Display Settings',lambda:spawn(['systemsettings','kcm_kscreen']))); dpl.addWidget(self.button('Night Light / HDR',lambda:spawn(['systemsettings','kcm_kscreen']))); mid2.addWidget(display); cols.addLayout(mid2,1)

        right=QVBoxLayout(); network=self.panel(); nl=QVBoxLayout(network); nh=QLabel('NETWORK'); nh.setObjectName('section'); nl.addWidget(nh); nl.addWidget(self.button('Wi-Fi',self.toggle_wifi)); nl.addWidget(self.button('Bluetooth',self.toggle_bt)); nl.addWidget(self.button('Network Manager',lambda:spawn(['systemsettings','kcm_networkmanagement']))); right.addWidget(network)
        tools=self.panel(); tl=QVBoxLayout(tools); th=QLabel('MECHOS TOOLS'); th.setObjectName('section'); tl.addWidget(th); tl.addWidget(self.button('Performance Overlay',self.toggle_hud)); tl.addWidget(self.button('Power Plan',lambda:spawn(['/usr/local/bin/mechos-performance-center']))); tl.addWidget(self.button('System Info',lambda:spawn(['systemsettings','kcm_about-distro']))); tl.addWidget(self.button('Clean Memory / Monitor',lambda:spawn(['konsole','-e','btop']))); right.addWidget(tools); cols.addLayout(right,1); outer.addLayout(cols,1)
        launch=self.panel(); ll=QHBoxLayout(launch); label=QLabel('QUICK LAUNCH'); label.setObjectName('section'); ll.addWidget(label)
        for name,cmd in [('Performance Center',['/usr/local/bin/mechos-performance-center']),('Update Center',['/usr/local/bin/mechos-update-center']),('Stream Center',['/usr/local/bin/mechos-stream-center']),('Creator Mode',['/usr/local/bin/mechos-creator-mode']),('Desktop Mode',['/usr/local/bin/mechos-session-select','desktop'])]:
            ll.addWidget(self.button(name,lambda c=cmd:spawn(c)))
        back=self.button('Return to MechScope',self.close); back.setObjectName('primary'); ll.addWidget(back); outer.addWidget(launch)
'''
        text=replace_method(text,'QuickActions','build',method); quick.write_text(text,encoding='utf-8')

if recovery.is_file():
    text=recovery.read_text(encoding='utf-8')
    if '# MECHOS_REFERENCE_RECOVERY_V5' not in text:
        method=r'''    def build_ui(self):
        # MECHOS_REFERENCE_RECOVERY_V5
        root=QWidget(); self.setCentralWidget(root); outer=QVBoxLayout(root); outer.setContentsMargins(16,12,16,12); outer.setSpacing(10)
        top=QHBoxLayout(); b=QLabel('MECHOS'); b.setObjectName('brand'); top.addWidget(b); top.addStretch(); t=QLabel('RECOVERY CENTER'); t.setObjectName('purple'); top.addWidget(t); top.addStretch(); outer.addLayout(top)
        body=QHBoxLayout(); body.setSpacing(12)
        left=QVBoxLayout(); system=QFrame(); system.setObjectName('panel'); sl=QVBoxLayout(system); h=QLabel('SYSTEM'); h.setObjectName('section'); sl.addWidget(h)
        for name,fn in [('System Status',lambda:spawn(['/usr/local/bin/mechos-hardware-scan'])),('Performance Center',lambda:spawn(['/usr/local/bin/mechos-performance-center'])),('Recovery Center',lambda:None),('Update Center',lambda:spawn(['/usr/local/bin/mechos-update-center'])),('Network Manager',lambda:spawn(['systemsettings','kcm_networkmanagement']))]:
            b=QPushButton(name); b.clicked.connect(fn); sl.addWidget(b)
        left.addWidget(system); quick=QFrame(); quick.setObjectName('panel'); ql=QVBoxLayout(quick); ql.addWidget(QLabel('QUICK ACCESS')); dm=QPushButton('Desktop Mode'); dm.clicked.connect(lambda:spawn(['/usr/local/bin/mechos-session-select','desktop'])); ql.addWidget(dm); cm=QPushButton('Creator Mode'); cm.clicked.connect(lambda:spawn(['/usr/local/bin/mechos-creator-mode'])); ql.addWidget(cm); left.addWidget(quick); left.addStretch(); body.addLayout(left,1)

        main=QVBoxLayout(); hero=QFrame(); hero.setObjectName('hero'); hl=QVBoxLayout(hero); ht=QLabel('RECOVERY CENTER'); ht.setObjectName('title'); hl.addWidget(ht); sub=QLabel('Diagnose issues, repair your system, and restore performance. Choose a recovery option below to get MechOS back on track.'); sub.setObjectName('muted'); sub.setWordWrap(True); hl.addWidget(sub); main.addWidget(hero)
        options=QFrame(); options.setObjectName('panel'); ol=QVBoxLayout(options); oh=QLabel('RECOVERY OPTIONS'); oh.setObjectName('section'); ol.addWidget(oh); r1=QHBoxLayout(); repair=QPushButton('Repair Boot\nFix boot issues and restore startup files'); repair.setObjectName('primary'); repair.clicked.connect(self.repair_boot); r1.addWidget(repair); live=QPushButton('Live Update (Keep Home)\nRefresh system from Live media'); live.clicked.connect(lambda:spawn(['/usr/local/bin/mechos-live-update-keep-home']) if Path('/run/archiso/bootmnt').exists() else QMessageBox.information(self,'Live Update','Boot the current MechOS Live USB to refresh the installed system while preserving /home.')); r1.addWidget(live); rollback=QPushButton('Rollback Snapshot\nRevert a failed update'); rollback.clicked.connect(self.rollback); r1.addWidget(rollback); ol.addLayout(r1)
        r2=QHBoxLayout(); disk=QPushButton('Disk Check\nInspect storage health'); disk.clicked.connect(self.hardware); r2.addWidget(disk); logs=QPushButton('Logs & Diagnostics\nView install/update logs'); logs.clicked.connect(self.load_logs); r2.addWidget(logs); reinstall=QPushButton('Reinstall (Keep Home)\nUse Live recovery flow'); reinstall.clicked.connect(lambda:QMessageBox.information(self,'Reinstall MechOS','Boot the current MechOS Live USB and choose Keep Personal Data / Update-Reinstall.')); r2.addWidget(reinstall); ol.addLayout(r2); main.addWidget(options)
        target=QFrame(); target.setObjectName('panel'); tl=QVBoxLayout(target); th=QLabel('RECOVERY TARGET'); th.setObjectName('section'); tl.addWidget(th); row=QHBoxLayout(); row.addWidget(QLabel('Installed system')); self.root_combo=QComboBox(); row.addWidget(self.root_combo,2); row.addWidget(QLabel('EFI partition')); self.esp_combo=QComboBox(); row.addWidget(self.esp_combo,2); rescan=QPushButton('Rescan'); rescan.clicked.connect(self.rescan); row.addWidget(rescan); tl.addLayout(row); main.addWidget(target)
        output=QFrame(); output.setObjectName('panel'); opl=QVBoxLayout(output); op=QLabel('DIAGNOSTIC CONSOLE'); op.setObjectName('section'); opl.addWidget(op); self.output=QPlainTextEdit(); self.output.setReadOnly(True); self.output.setPlaceholderText('Recovery diagnostics and command output appear here.'); opl.addWidget(self.output); main.addWidget(output,1); body.addLayout(main,4)
        right=QVBoxLayout(); status=QFrame(); status.setObjectName('panel'); st=QVBoxLayout(status); sh=QLabel('RECOVERY STATUS'); sh.setObjectName('section'); st.addWidget(sh); st.addWidget(QLabel('System checks are performed on demand.')); hc=QPushButton('Run Quick Health Check'); hc.clicked.connect(self.hardware); st.addWidget(hc); right.addWidget(status); safe=QFrame(); safe.setObjectName('panel'); sf=QVBoxLayout(safe); sf.addWidget(QLabel('SAFEGUARDS')); sf.addWidget(QLabel('✓ Personal files preserved by Keep Home flows\n✓ Boot Repair does not repartition disks\n✓ Rollback requires a valid snapshot\n✓ Live media is protected during Clean Install')); right.addWidget(safe); warn=QFrame(); warn.setObjectName('panel'); wl=QVBoxLayout(warn); w=QLabel('FACTORY RESET'); w.setStyleSheet('color:#ff5f74;font-weight:900'); wl.addWidget(w); reset=QPushButton('Open Live Installer for Clean Install'); reset.setObjectName('danger'); reset.clicked.connect(lambda:QMessageBox.information(self,'Factory Reset','For safety, factory reset is performed from the MechOS Live Installer using Clean Install and its final whole-disk confirmation.')); wl.addWidget(reset); right.addWidget(warn); right.addStretch(); body.addLayout(right,1); outer.addLayout(body,1)
'''
        text=replace_method(text,'Recovery','build_ui',method); recovery.write_text(text,encoding='utf-8')

for p in (perf,update,quick,recovery):
    if p.is_file():
        compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY

for f in "$PERF" "$UPDATE" "$QUICK" "$RECOVERY"; do
  [ -f "$f" ] || { echo "[MechOS Controls v5] missing $f" >&2; exit 1; }
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$f"
done
grep -Fq 'MECHOS_REFERENCE_PERFORMANCE_V5' "$PERF"
grep -Fq 'MECHOS_REFERENCE_UPDATE_V5' "$UPDATE"
grep -Fq 'MECHOS_REFERENCE_QUICK_ACTIONS_V5' "$QUICK"
grep -Fq 'MECHOS_REFERENCE_RECOVERY_V5' "$RECOVERY"
echo '[MechOS Controls v5] Performance, Update, Quick Actions and Recovery layouts applied'
