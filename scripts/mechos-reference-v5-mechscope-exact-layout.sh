#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
FILE="$ROOT/usr/local/bin/mechscope"
[ -f "$ROOT/usr/local/bin/mechscope.real" ] && FILE="$ROOT/usr/local/bin/mechscope.real"

log() { printf '[MechOS MechScope Exact Reference] %s\n' "$*"; }
fail() { printf '[MechOS MechScope Exact Reference] ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$FILE" ] || fail "MechScope implementation is missing: $FILE"
grep -Fq 'MECHOS_REFERENCE_MECHSCOPE_V5' "$FILE" \
  || fail "base Reference v5 MechScope layout must run before exact layout"

python3 - "$FILE" <<'PY'
from pathlib import Path
import sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
if '# MECHOS_REFERENCE_MECHSCOPE_EXACT_V1' in text:
    raise SystemExit(0)


def replace_method(source,name,new):
    cls=source.find('class MechScope(QMainWindow):')
    if cls < 0:
        raise SystemExit('[MechOS MechScope Exact Reference] MechScope class not found')
    start=source.find('    def '+name+'(',cls)
    if start < 0:
        raise SystemExit(f'[MechOS MechScope Exact Reference] MechScope.{name} not found')
    end=source.find('\n    def ',start+8)
    if end < 0:
        raise SystemExit(f'[MechOS MechScope Exact Reference] end of MechScope.{name} not found')
    return source[:start]+new.rstrip()+'\n'+source[end:]


helper=r"""
# MECHOS_REFERENCE_MECHSCOPE_EXACT_V1
class MechReferenceGauge(QWidget):
    def __init__(self,title,value=None,detail='Load',accent='#41ddff',parent=None):
        super().__init__(parent)
        self.title=str(title); self.value=value; self.detail=str(detail); self.accent=str(accent)
        self.setMinimumSize(92,92); self.setMaximumHeight(126)

    def setValue(self,value):
        try: self.value=max(0,min(100,int(float(value))))
        except Exception: self.value=None
        self.update()

    def paintEvent(self,event):
        from PyQt6.QtCore import QRectF, Qt as _Qt
        from PyQt6.QtGui import QColor, QFont, QPainter, QPen
        p=QPainter(self); p.setRenderHint(QPainter.RenderHint.Antialiasing,True)
        side=max(70,min(self.width(),self.height())-16); rect=QRectF((self.width()-side)/2,5,side,side)
        base=QPen(QColor('#172039'),9); base.setCapStyle(_Qt.PenCapStyle.RoundCap); p.setPen(base); p.drawArc(rect,90*16,-360*16)
        if self.value is not None:
            active=QPen(QColor(self.accent),9); active.setCapStyle(_Qt.PenCapStyle.RoundCap); p.setPen(active)
            p.drawArc(rect,90*16,-int(360*16*(self.value/100.0)))
        p.setPen(QColor('#dce7ff')); f=QFont(); f.setPointSize(8); f.setBold(True); p.setFont(f)
        p.drawText(rect.adjusted(0,12,0,0),_Qt.AlignmentFlag.AlignHCenter|_Qt.AlignmentFlag.AlignTop,self.title)
        f=QFont(); f.setPointSize(16); f.setBold(True); p.setFont(f)
        p.drawText(rect,_Qt.AlignmentFlag.AlignCenter,'--' if self.value is None else f'{self.value}%')
        p.setPen(QColor('#8fa1ba')); f=QFont(); f.setPointSize(7); p.setFont(f)
        p.drawText(rect.adjusted(0,0,0,-11),_Qt.AlignmentFlag.AlignHCenter|_Qt.AlignmentFlag.AlignBottom,self.detail)


def mechos_gpu_load_percent():
    command="if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1; exit 0; fi; for f in /sys/class/drm/card*/device/gpu_busy_percent; do [ -r \"$f\" ] || continue; cat \"$f\"; exit 0; done"
    try:
        value=output(['bash','-lc',command]).strip().splitlines()[0]
        return max(0,min(100,int(float(value))))
    except Exception:
        return None
"""
class_pos=text.find('class MechScope(QMainWindow):')
if class_pos < 0:
    raise SystemExit('[MechOS MechScope Exact Reference] MechScope insertion point missing')
text=text[:class_pos]+helper+'\n'+text[class_pos:]

build=r"""    def build_ui(self):
        # MECHOS_REFERENCE_MECHSCOPE_EXACT_V1_HOME
        self.setWindowTitle('MechOS • MechScope 2.0')
        self.setWindowFlag(Qt.WindowType.FramelessWindowHint,True)
        self.setWindowState(Qt.WindowState.WindowFullScreen)
        root=QWidget(); self.setCentralWidget(root)
        outer=QVBoxLayout(root); outer.setContentsMargins(0,0,0,0); outer.setSpacing(0)

        top=self.panel('top'); top.setMinimumHeight(62)
        tl=QHBoxLayout(top); tl.setContentsMargins(24,9,24,9); tl.setSpacing(14)
        brand=QLabel('◉  MECHOS'); brand.setObjectName('brand'); tl.addWidget(brand); tl.addStretch(1)
        scope=QLabel('MECHSCOPE 2.0'); scope.setObjectName('scope'); scope.setStyleSheet('font-size:28px;font-weight:900;letter-spacing:4px'); tl.addWidget(scope); tl.addStretch(1)
        self.net_label=QLabel('NET  detecting'); self.net_label.setObjectName('muted'); tl.addWidget(self.net_label)
        self.time_label=QLabel('--:--'); self.time_label.setObjectName('metric'); self.time_label.setStyleSheet('font-size:15px'); tl.addWidget(self.time_label)
        outer.addWidget(top)

        body=QHBoxLayout(); body.setContentsMargins(18,12,18,10); body.setSpacing(12)
        main=QVBoxLayout(); main.setSpacing(10)

        hero=self.panel('hero'); hero.setMinimumHeight(278)
        hl=QHBoxLayout(hero); hl.setContentsMargins(28,18,24,18); hl.setSpacing(16)
        copy=QVBoxLayout(); copy.setSpacing(8)
        eye=QLabel('WELCOME TO'); eye.setObjectName('purple'); eye.setStyleSheet('font-size:14px;font-weight:900;letter-spacing:2px'); copy.addWidget(eye)
        title=QLabel('MechScope 2.0'); title.setObjectName('title'); title.setStyleSheet('font-size:42px;font-weight:900'); copy.addWidget(title)
        sub=QLabel('Your unified command center for gaming,\nperformance, and creation.'); sub.setObjectName('muted'); sub.setStyleSheet('font-size:16px'); copy.addWidget(sub); copy.addStretch(1)
        actions=QHBoxLayout(); actions.setSpacing(12)
        for label,detail,fn,primary in [
            ('Steam Library','Browse your games',self.open_steam,True),
            ('Unified Store','All games, one place',self.open_store,False),
            ('Performance Center','Optimize. Monitor. Dominate.',lambda:spawn(['/usr/local/bin/mechos-performance-center']),False),
        ]:
            b=self.focus_button(QPushButton(label+'\n'+detail)); b.setMinimumHeight(72)
            if primary: b.setObjectName('primary')
            b.clicked.connect(fn); actions.addWidget(b,1)
        copy.addLayout(actions); hl.addLayout(copy,3)
        art=QLabel(); art.setAlignment(Qt.AlignmentFlag.AlignCenter); pix=QPixmap('/usr/share/mechos/branding/reference-hero-v5.svg')
        if not pix.isNull(): art.setPixmap(pix.scaled(620,255,Qt.AspectRatioMode.KeepAspectRatio,Qt.TransformationMode.SmoothTransformation))
        hl.addWidget(art,3); main.addWidget(hero)

        recent=self.panel(); rl=QVBoxLayout(recent); rl.setContentsMargins(14,10,14,12); rl.setSpacing(8)
        rh=QHBoxLayout(); rt=QLabel('RECENT GAMES'); rt.setObjectName('section'); rh.addWidget(rt); rh.addStretch(); view=QPushButton('View all'); view.clicked.connect(self.open_steam); rh.addWidget(view); rl.addLayout(rh)
        gamesrow=QHBoxLayout(); gamesrow.setSpacing(10); visible=self.games[:6]
        if visible:
            for game in visible:
                card=GameButton(game,self.launch_game); card.setMinimumHeight(188); self.focus_button(card); gamesrow.addWidget(card,1)
        else:
            empty=QLabel('No installed Steam games detected yet. Open Steam Library to sign in or install games.'); empty.setObjectName('muted'); empty.setWordWrap(True); gamesrow.addWidget(empty,1)
        rl.addLayout(gamesrow); main.addWidget(recent,1)

        modes=self.panel(); ml=QVBoxLayout(modes); ml.setContentsMargins(14,10,14,12); ml.setSpacing(8); mt=QLabel('QUICK MODES'); mt.setObjectName('section'); ml.addWidget(mt)
        mr=QHBoxLayout(); mr.setSpacing(10)
        for label,detail,fn,active in [
            ('Gaming Mode','Maximum performance',lambda:None,True),
            ('Desktop Mode','Productivity & browsing',lambda:self.switch_mode('desktop'),False),
            ('Creator Mode','Build. Edit. Publish.',lambda:self.switch_mode('creator'),False),
            ('VR / SteamVR','Immersive experience',self.open_vr,False),
        ]:
            b=self.focus_button(QPushButton(label+'\n'+detail)); b.setMinimumHeight(64); b.setCheckable(active); b.setChecked(active)
            if active: b.setObjectName('primary')
            b.clicked.connect(fn); mr.addWidget(b,1)
        ml.addLayout(mr); main.addWidget(modes)

        toolstrip=self.panel('bottom'); tsl=QHBoxLayout(toolstrip); tsl.setContentsMargins(10,8,10,8); tsl.setSpacing(8)
        for label,detail,fn in [
            ('Unified Store','All games, one place',self.open_store),
            ('Creator Mode','Build. Create. Share.',lambda:self.switch_mode('creator')),
            ('Creator Store','Tools. Assets. Bundles.',lambda:self.switch_mode('creator')),
            ('Performance','Optimize. Dominate.',lambda:spawn(['/usr/local/bin/mechos-performance-center'])),
            ('Update Center','Keep everything current',lambda:spawn(['/usr/local/bin/mechos-update-center'])),
            ('Recovery Center','Repair. Restore. Recover.',lambda:spawn(['/usr/local/bin/mechos-recovery-center'])),
            ('Installer / Repair','Install & recovery tools',lambda:spawn(['/usr/local/bin/mechos-live-setup']) if __import__('pathlib').Path('/usr/local/bin/mechos-live-setup').exists() else spawn(['/usr/local/bin/mechos-recovery-center'])),
        ]:
            b=self.focus_button(QPushButton(label+'\n'+detail)); b.setMinimumHeight(50); b.clicked.connect(fn); tsl.addWidget(b,1)
        main.addWidget(toolstrip); body.addLayout(main,5)

        middle=QVBoxLayout(); middle.setSpacing(10)
        status=self.panel(); sl=QVBoxLayout(status); sl.setContentsMargins(14,12,14,12); sl.setSpacing(8); sh=QLabel('SYSTEM STATUS'); sh.setObjectName('section'); sl.addWidget(sh)
        gauges=QHBoxLayout(); gauges.setSpacing(4)
        self.cpu_gauge=MechReferenceGauge('CPU',None,'Load','#49deff'); self.ram_gauge=MechReferenceGauge('RAM',None,'Used','#a85cff'); self.disk_gauge=MechReferenceGauge('DISK',None,'Used','#258cff')
        for gauge in (self.cpu_gauge,self.ram_gauge,self.disk_gauge): gauges.addWidget(gauge,1)
        sl.addLayout(gauges); self.stats_label=QLabel(); self.stats_label.hide(); sl.addWidget(self.stats_label)
        self.gpu_status=QLabel('GPU  '+gpu_name()); self.gpu_status.setObjectName('muted'); self.gpu_status.setWordWrap(True); sl.addWidget(self.gpu_status)
        row=QHBoxLayout(); self.temp_label=QLabel('Temperature: sensor dependent'); self.temp_label.setObjectName('purple'); row.addWidget(self.temp_label); row.addStretch(); ready=QLabel('✓ Ready'); ready.setStyleSheet('color:#31e981;font-weight:900'); row.addWidget(ready); sl.addLayout(row)
        runopt=self.focus_button(QPushButton('Run Optimization')); runopt.clicked.connect(lambda:spawn(['/usr/local/bin/mechos-performance-center'])); sl.addWidget(runopt); middle.addWidget(status)

        quick=self.panel(); ql=QVBoxLayout(quick); ql.setContentsMargins(14,12,14,12); ql.setSpacing(8); qt=QLabel('QUICK ACTIONS'); qt.setObjectName('section'); ql.addWidget(qt)
        for label,detail,cmd in [
            ('Update Center','Check for updates',['/usr/local/bin/mechos-update-center']),
            ('Drivers & Firmware','Keep everything current',['/usr/local/bin/mechos-update-center']),
            ('System Info','Hardware & system details',['systemsettings','kcm_about-distro']),
            ('Network Manager','Connection settings',['systemsettings','kcm_networkmanagement']),
            ('Power Plan','Performance profiles',['/usr/local/bin/mechos-performance-center']),
        ]:
            b=self.focus_button(QPushButton(label+'\n'+detail)); b.clicked.connect(lambda _=False,c=cmd:spawn(c)); ql.addWidget(b)
        ql.addStretch(1); middle.addWidget(quick,1); body.addLayout(middle,2)

        side=QVBoxLayout(); side.setSpacing(10)
        launchers=self.panel(); ll=QVBoxLayout(launchers); ll.setContentsMargins(14,12,14,12); ll.setSpacing(8); lt=QLabel('LAUNCHERS'); lt.setObjectName('section'); ll.addWidget(lt)
        for label,fn in [
            ('Steam',self.open_steam),('Unified Store',self.open_store),('Performance Center',lambda:spawn(['/usr/local/bin/mechos-performance-center'])),
            ('Creator Mode',lambda:self.switch_mode('creator')),('Desktop Mode',lambda:self.switch_mode('desktop')),('VR / SteamVR',self.open_vr),
        ]:
            b=self.focus_button(QPushButton(label)); b.setMinimumHeight(54); b.clicked.connect(fn); ll.addWidget(b)
        side.addWidget(launchers,1)
        power=self.panel(); pl=QVBoxLayout(power); pl.setContentsMargins(14,12,14,12); pl.setSpacing(10); pt=QLabel('SYSTEM'); pt.setObjectName('section'); pl.addWidget(pt)
        restart=self.focus_button(QPushButton('Restart MechOS')); restart.setMinimumHeight(62); restart.clicked.connect(lambda:spawn(['systemctl','reboot'])); pl.addWidget(restart)
        shutdown=self.focus_button(QPushButton('Shut Down')); shutdown.setObjectName('danger'); shutdown.setMinimumHeight(68); shutdown.clicked.connect(lambda:spawn(['systemctl','poweroff'])); pl.addWidget(shutdown); side.addWidget(power); body.addLayout(side,2)
        outer.addLayout(body,1)

        footer=self.panel('bottom'); fl=QHBoxLayout(footer); fl.setContentsMargins(24,8,24,8); fl.setSpacing(20)
        hint=QLabel('Ⓐ  Select     Ⓑ  Back     ☰  Menu     ✥  D-Pad / Arrows Navigate'); hint.setObjectName('muted'); fl.addWidget(hint); fl.addStretch(1)
        self.pad_label=QLabel('Controller: detecting'); self.pad_label.setObjectName('metric'); self.pad_label.setStyleSheet('font-size:13px'); fl.addWidget(self.pad_label); outer.addWidget(footer)
        if self.focusables: self.focusables[0].setFocus()
"""
text=replace_method(text,'build_ui',build)

stats=r"""    def refresh_stats(self):
        # MECHOS_REFERENCE_MECHSCOPE_EXACT_V1_STATS
        cpu=cpu_percent(); ram=ram_percent(); disk=disk_percent(); gpu=mechos_gpu_load_percent()
        self.cpu_gauge.setValue(cpu); self.ram_gauge.setValue(ram); self.disk_gauge.setValue(disk)
        self.stats_label.setText(f'CPU {cpu}% • RAM {ram}% • DISK {disk}%')
        gpu_text=gpu_name()
        if gpu is not None: gpu_text+=f'  •  {gpu}% load'
        self.gpu_status.setText('GPU  '+gpu_text)
        self.net_label.setText('NET  '+network_name()); self.time_label.setText(time.strftime('%I:%M %p'))
        temp=output(['bash','-lc',"for f in /sys/class/thermal/thermal_zone*/temp; do [ -r \"$f\" ] || continue; v=$(cat \"$f\"); [ \"$v\" -gt 1000 ] && v=$((v/1000)); [ \"$v\" -gt 0 ] && [ \"$v\" -lt 120 ] && { echo \"${v}°C\"; break; }; done"])
        self.temp_label.setText('♨  '+(temp or 'sensor unavailable'))
"""
text=replace_method(text,'refresh_stats',stats)
text=text.replace('w.showMaximized()','w.showFullScreen()').replace('win.showMaximized()','win.showFullScreen()')
compile(text,str(path),'exec')
path.write_text(text,encoding='utf-8')
PY

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$FILE" || fail "MechScope Python failed after exact-reference layout"
grep -Fq 'MECHOS_REFERENCE_MECHSCOPE_EXACT_V1_HOME' "$FILE" || fail "exact MechScope home marker missing"
grep -Fq 'class MechReferenceGauge' "$FILE" || fail "reference circular gauge widget missing"
grep -Fq 'Creator Store' "$FILE" || fail "bottom reference tool strip is incomplete"
grep -Fq 'LAUNCHERS' "$FILE" || fail "right launcher column is missing"
grep -Fq 'QUICK ACTIONS' "$FILE" || fail "middle quick-actions column is missing"
grep -Fq 'showFullScreen()' "$FILE" || fail "MechScope is not forced full-screen for the VM/physical reference canvas"

log "exact MechScope reference dashboard applied with real CPU/RAM/Disk/GPU telemetry and functional navigation"
