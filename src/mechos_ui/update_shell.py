#!/usr/bin/env python3
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from fixed_canvas import FixedCanvas
from PyQt6.QtCore import QRect
from PyQt6.QtWidgets import QPlainTextEdit,QProgressBar

class UpdateShell(FixedCanvas):
    def __init__(self,owner,actions,parent=None):
        super().__init__(parent); self.owner=owner; self.actions=actions; self.build()
    def act(self,key): return self.actions.get(key)
    def build(self):
        self.label('◉  MECHOS',QRect(42,18,300,54),20,True)
        self.label('UPDATE CENTER',QRect(760,18,400,54),24,True,'accent')
        self.channel=self.label('CHANNEL  STABLE',QRect(1580,18,280,54),13,True,'muted')

        self.label('YOUR SYSTEM IS',QRect(74,116,310,32),13,True,'section')
        self.status_label=self.label('Checking…',QRect(72,152,600,68),34,True)
        self.details_label=self.label('Checking MechOS, Arch and Flatpak update state',QRect(72,220,720,60),14,False,'muted')
        self.check_button=self.button('Check for Updates','Scan system packages, Flatpaks and MechOS metadata',QRect(72,310,350,82),self.act('check'),True)
        self.update_button=self.button('Install Updates','Install all available updates',QRect(438,310,330,82),self.act('install'))
        self.update_button.setEnabled(False)

        self.label('SYSTEM HEALTH',QRect(938,116,300,32),13,True,'section')
        self.label('STABLE',QRect(938,154,260,52),25,True,'accent')
        self.reboot_label=self.label('Restart not required',QRect(938,220,390,48),15,True,'muted')
        self.reboot_button=self.button('Restart MechOS','Finish updates that require a reboot',QRect(938,310,360,82),self.act('reboot'))
        self.reboot_button.setEnabled(False)
        self.button('Performance Center','System optimization and health',QRect(1318,310,300,82),self.act('performance'))
        self.button('Creator Mode','Creator tools and packages',QRect(1634,310,220,82),self.act('creator'))

        self.label('UPDATE CATEGORIES',QRect(72,450,370,34),13,True,'section')
        cats=[('SYSTEM UPDATES','Core OS and runtime'),('DRIVERS & FIRMWARE','Hardware support'),('MECHOS HOTFIXES','Stability & fixes'),('CREATOR PACKAGES','Tools & dependencies'),('STORE METADATA','Catalog & profiles')]
        for i,(title,sub) in enumerate(cats):
            x=72+i*350
            self.label(title,QRect(x,502,320,34),11,True,'accent')
            self.label(sub,QRect(x,538,320,44),11,False,'muted')

        self.label('UPDATE PROGRESS',QRect(72,622,330,34),13,True,'section')
        self.progress=self.reg(QProgressBar(),QRect(72,666,720,48)); self.progress.setRange(0,1); self.progress.setValue(0); self.progress.setFormat('Ready')
        self.history_button=self.button('Refresh History','Reload completed update records',QRect(72,728,300,68),self.act('history'))

        self.label('CHANGELOG / UPDATE OUTPUT',QRect(838,622,450,34),13,True,'section')
        self.log=self.reg(QPlainTextEdit(),QRect(838,666,1016,230)); self.log.setReadOnly(True); self.log.setPlaceholderText('Update information will appear here.')
        self.log.setStyleSheet('QPlainTextEdit{background:#060b13;border:1px solid #253a58;border-radius:14px;padding:12px;color:#c9d7ed;font-family:Monospace}')

        self.label('UPDATE HISTORY',QRect(72,840,360,34),13,True,'section')
        self.history=self.reg(QPlainTextEdit(),QRect(72,884,720,112)); self.history.setReadOnly(True)
        self.history.setStyleSheet('QPlainTextEdit{background:#060b13;border:1px solid #253a58;border-radius:14px;padding:10px;color:#aebed6;font-family:Monospace}')
        self.label('Snapshots protect compatible Btrfs systems before major package changes.',QRect(838,918,1016,50),12,False,'muted')
    def paint_background(self,p):
        self.panel(p,QRect(46,94,786,322),'#08111e','#3b2d68',22,2)
        self.panel(p,QRect(860,94,996,322),'#07101c','#254465',22,1)
        self.panel(p,QRect(46,432,1810,170),'#070d16','#263a59',18,1)
        self.panel(p,QRect(46,606,770,408),'#070d16','#263a59',18,1)
        self.panel(p,QRect(816,606,1040,408),'#070d16','#263a59',18,1)
