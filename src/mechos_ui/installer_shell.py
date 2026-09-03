#!/usr/bin/env python3
"""Reference-backed MechOS Live installer surface.

The approved installer PNG is the visual authority. Broad transparent hotspots
keep the reference functional while live target/mode/progress data is rendered
in a restrained overlay instead of rebuilding the artwork with Qt layouts.
"""
from pathlib import Path

from PyQt6.QtCore import QRect, Qt
from PyQt6.QtGui import QColor, QFont, QPainter, QPixmap
from PyQt6.QtWidgets import QLabel, QProgressBar, QPushButton

from fixed_canvas import BASE_H, BASE_W, FixedCanvas

REFERENCE = Path('/usr/share/mechos/branding/mechos-installer-reference.png')


class InstallerShell(FixedCanvas):
    def __init__(self, owner, parent=None):
        super().__init__(parent)
        self.owner = owner
        self.reference = QPixmap(str(REFERENCE))
        self.mode_buttons = {}
        self.setStyleSheet('''
QWidget#mechosFixedCanvas{background:#030711;color:#eef5ff}
QPushButton[role="hotspot"]{background:transparent;border:0;color:transparent;padding:0;margin:0}
QPushButton[role="hotspot"]:hover,QPushButton[role="hotspot"]:focus{background:rgba(108,155,255,18);border:3px solid #a88cff;border-radius:14px}
QPushButton[role="mode-hotspot"]{background:transparent;border:0;color:transparent;padding:0;margin:0}
QPushButton[role="mode-hotspot"]:checked,QPushButton[role="mode-hotspot"]:focus{background:rgba(139,104,255,22);border:3px solid #a88cff;border-radius:16px}
QLabel[role="live"]{background:rgba(5,10,20,220);border:1px solid #315174;border-radius:10px;color:#eef5ff;padding:7px 12px}
QProgressBar{background:rgba(5,10,20,220);border:1px solid #315174;border-radius:8px;color:#eef5ff;text-align:center}
QProgressBar::chunk{background:qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #248dff,stop:1 #9b5cff);border-radius:7px}
''')
        self._build()

    def hotspot(self, name, rect, fn=None, mode=False):
        q = self.reg(QPushButton(''), rect)
        q.setProperty('role','mode-hotspot' if mode else 'hotspot')
        q.setToolTip(name); q.setAccessibleName(name)
        q.setCursor(Qt.CursorShape.PointingHandCursor)
        if mode: q.setCheckable(True)
        if fn: q.clicked.connect(fn)
        return q

    def _build(self):
        # Left step navigation. Wide targets intentionally tolerate small visual
        # differences between reference revisions while preserving the artwork.
        for row in range(9):
            self.hotspot(f'Installer step {row+1}',QRect(24,150+row*78,330,68),lambda _=False,r=row:self.owner.nav_selected(r))

        self.hotspot('Change Drive',QRect(1040,165,230,62),self.owner.open_partition_selector)

        modes=[('clean',QRect(400,330,720,120)),('keep',QRect(400,458,720,120)),('custom',QRect(400,586,720,120)),('alongside',QRect(400,714,720,120))]
        for name,rect in modes:
            b=self.hotspot(name.title(),rect,lambda _=False,m=name:self.owner.set_mode(m,True),True)
            self.mode_buttons[name]=b

        self.hotspot('Repair',QRect(1280,930,250,96),self.owner.recovery)
        self.hotspot('Install Now',QRect(1540,930,330,96),self.owner.install)

        # Live state overlays only values which must never come from static art.
        self.live_target=self.reg(QLabel('Selected drive: detecting'),QRect(1280,120,570,52),12)
        self.live_target.setProperty('role','live')
        f=QFont('Sans Serif',12); f.setBold(True); self.live_target.setFont(f)
        self.live_mode=self.reg(QLabel('Install mode: Clean Install'),QRect(1280,178,570,48),11)
        self.live_mode.setProperty('role','live')
        self.progress=self.reg(QProgressBar(),QRect(1280,850,570,48),11)
        self.progress.setRange(0,100); self.progress.setValue(0); self.progress.setFormat('Ready to install')
        self.set_mode('clean')

    def set_mode(self, mode):
        names={'clean':'Clean Install','keep':'Keep Personal Data','custom':'Custom Install','alongside':'Install Alongside Existing OS'}
        for key,b in self.mode_buttons.items(): b.setChecked(key==mode)
        self.live_mode.setText('Install mode: '+names.get(mode,mode))

    def set_drive(self, path='', model='', size=''):
        if path:
            display=(model or 'Selected drive').strip()
            if size: display += '  '+str(size).strip()
            self.live_target.setText(f'Selected drive: {display}  •  {path}')
        else:
            self.live_target.setText('Selected drive: none selected')

    def paint_background(self,painter:QPainter):
        target=self.scale_rect(QRect(0,0,BASE_W,BASE_H))
        painter.fillRect(target,QColor('#030711'))
        if not self.reference.isNull():
            painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform,True)
            painter.drawPixmap(target,self.reference)
        else:
            painter.setPen(QColor('#eef5ff'))
            painter.drawText(target,Qt.AlignmentFlag.AlignCenter,'Approved MechOS installer reference artwork is missing')
