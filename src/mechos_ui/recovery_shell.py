#!/usr/bin/env python3
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from fixed_canvas import FixedCanvas
from PyQt6.QtCore import QRect
from PyQt6.QtWidgets import QComboBox,QPlainTextEdit

class RecoveryShell(FixedCanvas):
    def __init__(self,owner,actions,parent=None):
        super().__init__(parent); self.owner=owner; self.actions=actions; self.build()
    def act(self,key): return self.actions.get(key)
    def build(self):
        self.label('◉  MECHOS',QRect(42,18,300,54),20,True)
        self.label('RECOVERY CENTER',QRect(700,18,520,54),24,True,'accent')
        self.label('SAFE SYSTEM REPAIR',QRect(1570,18,290,54),12,True,'muted')

        self.label('REPAIR. RESTORE. RECOVER.',QRect(74,116,620,34),13,True,'section')
        self.label('Get MechOS Back\nInto the Fight.',QRect(72,150,700,110),35,True)
        self.label('Repair boot files, inspect installed systems, recover failed updates and review diagnostics without blindly formatting disks.',QRect(72,270,720,88),14,False,'muted')
        self.button('Rescan Systems','Detect installed Linux roots and EFI partitions',QRect(72,382,340,78),self.act('rescan'),True)
        self.button('Hardware Scan','Inspect CPU, GPU, storage and boot environment',QRect(430,382,360,78),self.act('hardware'))

        self.label('RECOVERY TARGET',QRect(918,116,360,34),13,True,'section')
        self.label('Installed System',QRect(918,160,280,32),11,True,'muted')
        self.root_combo=self.reg(QComboBox(),QRect(918,198,900,54))
        self.root_combo.setStyleSheet('QComboBox{background:#0b1422;color:#eef5ff;border:1px solid #2c4669;border-radius:12px;padding:10px}')
        self.label('EFI Partition',QRect(918,272,280,32),11,True,'muted')
        self.esp_combo=self.reg(QComboBox(),QRect(918,310,900,54))
        self.esp_combo.setStyleSheet('QComboBox{background:#0b1422;color:#eef5ff;border:1px solid #2c4669;border-radius:12px;padding:10px}')
        self.label('Target selection is always shown before any repair action.',QRect(918,382,900,48),12,False,'muted')

        self.label('RECOVERY ACTIONS',QRect(72,526,380,34),13,True,'section')
        actions=[
          ('Repair Boot','Rebuild initramfs and restore the detected bootloader','repair',True,False),
          ('Rollback Failed Update','Use a recorded compatible Snapper snapshot','rollback',False,False),
          ('Load Install / Update Logs','Review MechOS install and update history','logs',False,False),
          ('Reinstall • Keep Home','Open protected reinstall workflow','keep-home',False,False),
          ('Disk Check','Inspect selected storage and filesystem state','disk',False,False),
          ('Return to MechScope','Leave recovery and return to Gaming Mode','mechscope',False,False),
        ]
        for i,(title,sub,key,primary,danger) in enumerate(actions):
            x=72+(i%3)*584; y=574+(i//3)*104
            self.button(title,sub,QRect(x,y,552,86),self.act(key),primary,danger)

        self.label('DIAGNOSTIC CONSOLE',QRect(72,808,420,34),13,True,'section')
        self.output=self.reg(QPlainTextEdit(),QRect(72,850,1746,152)); self.output.setReadOnly(True); self.output.setPlaceholderText('Recovery output appears here.')
        self.output.setStyleSheet('QPlainTextEdit{background:#050a11;color:#bcd0e8;border:1px solid #29435f;border-radius:14px;padding:12px;font-family:Monospace}')
        self.label('Boot Repair never repartitions or formats disks. Rollback is offered only when MechOS recorded a valid compatible snapshot.',QRect(72,1010,1746,38),11,False,'muted')
    def paint_background(self,p):
        self.panel(p,QRect(46,94,786,390),'#08111e','#3b2d68',22,2)
        self.panel(p,QRect(884,94,972,390),'#07101c','#254465',22,1)
        self.panel(p,QRect(46,508,1810,252),'#070d16','#263a59',18,1)
        self.panel(p,QRect(46,790,1810,232),'#070d16','#263a59',18,1)
