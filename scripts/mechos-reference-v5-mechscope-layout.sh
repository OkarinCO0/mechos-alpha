#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="/workspace/archlive/airootfs"
FILE="$ROOT/usr/local/bin/mechscope"
[ -f "$ROOT/usr/local/bin/mechscope.real" ] && FILE="$ROOT/usr/local/bin/mechscope.real"
[ -f "$FILE" ] || { echo '[MechOS MechScope v5] MechScope missing' >&2; exit 1; }

python3 - "$FILE" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); text=p.read_text(encoding='utf-8')
if '# MECHOS_REFERENCE_MECHSCOPE_V5' in text: raise SystemExit(0)

def replace_method(text,name,new):
    c=text.find('class MechScope(QMainWindow):')
    if c<0: raise SystemExit('[MechOS MechScope v5] class not found')
    s=text.find('    def '+name+'(',c)
    if s<0: raise SystemExit('[MechOS MechScope v5] method '+name+' not found')
    e=text.find('\n    def ',s+8)
    if e<0: raise SystemExit('[MechOS MechScope v5] method end not found: '+name)
    return text[:s]+new.rstrip()+'\n'+text[e:]

build=r'''    def build_ui(self):
        # MECHOS_REFERENCE_MECHSCOPE_V5
        root=QWidget(); self.setCentralWidget(root)
        outer=QVBoxLayout(root); outer.setContentsMargins(0,0,0,0); outer.setSpacing(0)

        top=self.panel('top'); tl=QHBoxLayout(top); tl.setContentsMargins(22,10,22,10)
        brand=QLabel('MECHOS'); brand.setObjectName('brand'); tl.addWidget(brand); tl.addStretch()
        scope=QLabel('MECHSCOPE 2.0'); scope.setObjectName('scope'); tl.addWidget(scope); tl.addStretch()
        self.net_label=QLabel(); self.net_label.setObjectName('metric'); tl.addWidget(self.net_label); self.time_label=QLabel(); self.time_label.setObjectName('metric'); tl.addWidget(self.time_label); outer.addWidget(top)

        body=QHBoxLayout(); body.setContentsMargins(18,12,18,12); body.setSpacing(12)
        main=QVBoxLayout(); main.setSpacing(10)

        hero=self.panel('hero'); hl=QHBoxLayout(hero); hl.setContentsMargins(24,16,24,16)
        copy=QVBoxLayout(); eye=QLabel('WELCOME TO'); eye.setObjectName('purple'); copy.addWidget(eye); title=QLabel('MechScope 2.0'); title.setObjectName('title'); title.setStyleSheet('font-size:38px;font-weight:900'); copy.addWidget(title)
        sub=QLabel('Your unified command center for gaming, performance, and creation.'); sub.setObjectName('muted'); sub.setWordWrap(True); copy.addWidget(sub)
        actions=QHBoxLayout(); play=self.focus_button(QPushButton('Steam Library\nBrowse your games')); play.setObjectName('primary'); play.clicked.connect(self.open_steam); actions.addWidget(play); store=self.focus_button(QPushButton('Unified Store\nAll games, one place')); store.clicked.connect(self.open_store); actions.addWidget(store); perf=self.focus_button(QPushButton('Performance Center\nOptimize. Monitor. Dominate.')); perf.clicked.connect(lambda:spawn(['/usr/local/bin/mechos-performance-center'])); actions.addWidget(perf); copy.addLayout(actions); hl.addLayout(copy,3)
        art=QLabel(); art.setAlignment(Qt.AlignmentFlag.AlignCenter); pix=QPixmap('/usr/share/mechos/branding/reference-hero-v5.svg');
        if not pix.isNull(): art.setPixmap(pix.scaled(600,250,Qt.AspectRatioMode.KeepAspectRatio,Qt.TransformationMode.SmoothTransformation))
        hl.addWidget(art,3); main.addWidget(hero)

        recent=self.panel(); rl=QVBoxLayout(recent); rh=QHBoxLayout(); rt=QLabel('RECENT GAMES'); rt.setObjectName('section'); rh.addWidget(rt); rh.addStretch(); view=QPushButton('View all'); view.clicked.connect(self.open_steam); rh.addWidget(view); rl.addLayout(rh)
        gamesrow=QHBoxLayout(); gamesrow.setSpacing(10)
        visible=self.games[:6]
        if visible:
            for g in visible:
                b=GameButton(g,self.launch_game); b.setMinimumHeight(190); self.focus_button(b); gamesrow.addWidget(b,1)
        else:
            empty=QLabel('No installed Steam games found yet. Open Steam Library to sign in or install games.'); empty.setObjectName('muted'); empty.setWordWrap(True); gamesrow.addWidget(empty)
        rl.addLayout(gamesrow); main.addWidget(recent,1)

        qm=self.panel(); ql=QVBoxLayout(qm); qh=QLabel('QUICK MODES'); qh.setObjectName('section'); ql.addWidget(qh); modes=QHBoxLayout()
        for label,detail,cb in [('Gaming Mode','Maximum performance',lambda:None),('Desktop Mode','Productivity & browsing',lambda:self.switch_mode('desktop')),('Creator Mode','Build. Edit. Publish.',lambda:self.switch_mode('creator')),('VR / SteamVR','Immersive experience',self.open_vr)]:
            b=self.focus_button(QPushButton(label+'\n'+detail)); b.setObjectName('mode'); b.clicked.connect(cb); modes.addWidget(b,1)
        ql.addLayout(modes); main.addWidget(qm); body.addLayout(main,4)

        mid=QVBoxLayout(); mid.setSpacing(10)
        status=self.panel(); sl=QVBoxLayout(status); sh=QLabel('SYSTEM STATUS'); sh.setObjectName('section'); sl.addWidget(sh); metrics=QHBoxLayout(); self.cpu_status=QLabel('CPU --%'); self.ram_status=QLabel('RAM --%'); self.disk_status=QLabel('DISK --%')
        for label in (self.cpu_status,self.ram_status,self.disk_status): label.setObjectName('metric'); label.setAlignment(Qt.AlignmentFlag.AlignCenter); metrics.addWidget(label)
        sl.addLayout(metrics); self.stats_label=QLabel(); self.stats_label.hide(); sl.addWidget(self.stats_label); self.gpu_status=QLabel(gpu_name()); self.gpu_status.setObjectName('muted'); self.gpu_status.setWordWrap(True); sl.addWidget(self.gpu_status); self.temp_label=QLabel('Temperature: sensor dependent'); self.temp_label.setObjectName('metric'); sl.addWidget(self.temp_label); ready=QLabel('✓ Ready'); ready.setStyleSheet('color:#31e981;font-weight:900'); sl.addWidget(ready); runopt=self.focus_button(QPushButton('Run Optimization')); runopt.clicked.connect(lambda:spawn(['/usr/local/bin/mechos-performance-center'])); sl.addWidget(runopt); mid.addWidget(status)

        quick=self.panel(); qal=QVBoxLayout(quick); qtitle=QLabel('QUICK ACTIONS'); qtitle.setObjectName('section'); qal.addWidget(qtitle)
        for label,cmd in [('Update Center',['/usr/local/bin/mechos-update-center']),('Drivers & Firmware',['/usr/local/bin/mechos-update-center']),('System Info',['systemsettings','kcm_about-distro']),('Network Manager',['systemsettings','kcm_networkmanagement']),('Power Plan',['/usr/local/bin/mechos-performance-center'])]:
            b=self.focus_button(QPushButton(label)); b.clicked.connect(lambda _=False,c=cmd:spawn(c)); qal.addWidget(b)
        mid.addWidget(quick,1); body.addLayout(mid,1)

        side=QVBoxLayout(); side.setSpacing(10)
        launchers=self.panel(); ll=QVBoxLayout(launchers); ltitle=QLabel('LAUNCHERS'); ltitle.setObjectName('section'); ll.addWidget(ltitle)
        launcher_actions=[('Steam',self.open_steam),('Unified Store',self.open_store),('Performance Center',lambda:spawn(['/usr/local/bin/mechos-performance-center'])),('Creator Mode',lambda:self.switch_mode('creator')),('Desktop Mode',lambda:self.switch_mode('desktop')),('VR / SteamVR',self.open_vr)]
        for label,fn in launcher_actions:
            b=self.focus_button(QPushButton(label)); b.clicked.connect(fn); ll.addWidget(b)
        side.addWidget(launchers)
        power=self.panel(); pl=QVBoxLayout(power); pt=QLabel('SYSTEM'); pt.setObjectName('section'); pl.addWidget(pt); restart=self.focus_button(QPushButton('Restart MechOS')); restart.clicked.connect(lambda:spawn(['systemctl','reboot'])); pl.addWidget(restart); shutdown=self.focus_button(QPushButton('Shut Down')); shutdown.setObjectName('danger'); shutdown.clicked.connect(lambda:spawn(['systemctl','poweroff'])); pl.addWidget(shutdown); side.addWidget(power); side.addStretch(); body.addLayout(side,1)

        outer.addLayout(body,1)
        bottom=self.panel('bottom'); bl=QHBoxLayout(bottom); hint=QLabel('A  Select     B  Back     Menu     D-Pad / Arrows Navigate'); hint.setObjectName('muted'); bl.addWidget(hint); bl.addStretch(); self.pad_label=QLabel('Controller: detecting'); self.pad_label.setObjectName('metric'); bl.addWidget(self.pad_label); outer.addWidget(bottom)
        if self.focusables: self.focusables[0].setFocus()
'''
text=replace_method(text,'build_ui',build)

stats=r'''    def refresh_stats(self):
        # MECHOS_REFERENCE_MECHSCOPE_V5_STATS
        cpu=cpu_percent(); ram=ram_percent(); disk=disk_percent()
        self.cpu_status.setText(f'CPU {cpu}%')
        self.ram_status.setText(f'RAM {ram}%')
        self.disk_status.setText(f'DISK {disk}%')
        self.stats_label.setText(f'CPU {cpu}% • RAM {ram}% • DISK {disk}%')
        self.net_label.setText('NET  '+network_name())
        self.time_label.setText(time.strftime('%I:%M %p'))
        temp=output(['bash','-lc',"for f in /sys/class/thermal/thermal_zone*/temp; do [ -r \"$f\" ] || continue; v=$(cat \"$f\"); [ \"$v\" -gt 1000 ] && v=$((v/1000)); [ \"$v\" -gt 0 ] && [ \"$v\" -lt 120 ] && { echo \"${v}°C\"; break; }; done"])
        self.temp_label.setText('Temperature  '+(temp or 'sensor unavailable'))
'''
text=replace_method(text,'refresh_stats',stats)
p.write_text(text,encoding='utf-8'); compile(text,str(p),'exec')
PY

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$FILE"
grep -Fq 'MECHOS_REFERENCE_MECHSCOPE_V5' "$FILE"
grep -Fq 'RECENT GAMES' "$FILE"
grep -Fq 'QUICK MODES' "$FILE"
grep -Fq 'SYSTEM STATUS' "$FILE"
grep -Fq 'QUICK ACTIONS' "$FILE"
grep -Fq 'LAUNCHERS' "$FILE"
echo '[MechOS MechScope v5] reference home layout applied'
