#!/usr/bin/env python3
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from fixed_canvas import FixedCanvas
from PyQt6.QtCore import QRect
from PyQt6.QtWidgets import QLabel

class MetricLabel(QLabel):
    def setValue(self,value):
        try:self.setText(f'{int(float(value))}%')
        except Exception:self.setText('--')

class PerformanceShell(FixedCanvas):
    def __init__(self,owner,actions,parent=None):
        super().__init__(parent); self.owner=owner; self.actions=actions; self.build()
    def act(self,key): return self.actions.get(key)
    def build(self):
        self.label('◉  MECHOS',QRect(42,18,300,54),20,True)
        self.label('PERFORMANCE CENTER',QRect(690,18,540,54),24,True,'accent')
        self.profile_badge=self.label('PROFILE  --',QRect(1590,18,280,54),13,True,'muted')
        self.label('SYSTEM OPTIMIZATION & TUNING',QRect(74,112,560,34),13,True,'section')
        self.label('Maximize Performance.\nDominate Every Game.',QRect(72,150,730,112),34,True)
        self.gpu_label=self.label('Detecting graphics hardware…',QRect(74,266,720,54),14,False,'muted')
        self.button('Run Optimization','Open current optimization report / tools',QRect(74,336,330,76),self.act('report'),True)
        self.button('Auto Optimization','Choose the best profile for this hardware',QRect(422,336,370,76),self.act('auto'))

        self.label('LIVE SYSTEM METRICS',QRect(910,112,450,34),13,True,'section')
        names=[('CPU',922),('RAM',1142),('DISK',1362),('ZRAM',1582)]
        cards=[]
        for name,x in names:
            self.label(name,QRect(x,164,190,34),12,True,'muted')
            m=self.reg(MetricLabel('--'),QRect(x,202,190,92),34)
            m.setStyleSheet('font-weight:900;color:#edf4ff;background:transparent;border:0')
            f=m.font(); f.setPointSize(34); f.setBold(True); m.setFont(f); cards.append(m)
        self.cpu_card,self.ram_card,self.disk_card,self.zram_card=cards
        self.gpu_summary=self.label('Detected GPU',QRect(922,314,600,48),14,True,'accent')
        self.button('GPU Diagnostics','Vulkan / VA-API / driver information',QRect(1538,310,300,64),self.act('gpu'))

        self.label('PERFORMANCE PROFILES',QRect(72,470,500,34),13,True,'section')
        self.button('Gaming Performance','Maximum available FPS & responsiveness',QRect(72,516,360,92),self.act('performance'),True)
        self.button('Balanced','Optimized for all-around use',QRect(448,516,320,92),self.act('balanced'))
        self.button('Battery Saver','Extended battery & cooler operation',QRect(784,516,320,92),self.act('battery'))

        self.label('SYSTEM HEALTH',QRect(1150,470,300,34),13,True,'section')
        self.health_label=self.label('CHECKING',QRect(1150,514,270,42),18,True,'accent')
        self.label('CPU / memory telemetry • storage tools • thermal checks',QRect(1150,558,420,48),12,False,'muted')
        self.button('Run Full Diagnostics','Hardware and health tools',QRect(1586,516,252,92),self.act('diagnostics'))

        self.label('TOOLS & MONITORING',QRect(72,660,420,34),13,True,'section')
        tools=[
          ('System Monitor','Real-time CPU, RAM, disk and network','monitor'),
          ('Storage Health','NVMe / SMART health','storage'),
          ('Performance Overlay','MangoHud / MangoApp','hud'),
          ('Recording & Capture','GPU Screen Recorder','recorder'),
          ('RadarAI','AI system diagnostics','radarai'),
          ('Update Center','System, drivers and hotfixes','updates'),
        ]
        for i,(title,sub,key) in enumerate(tools):
            x=72+(i%3)*584; y=706+(i//3)*104
            self.button(title,sub,QRect(x,y,552,86),self.act(key),key=='radarai')
        self.radar=self.label('RadarAI status available in diagnostics',QRect(1250,920,588,38),11,False,'muted')
        self.label('Hardware-aware profiles • VM-safe fallback • GameMode • MangoHud',QRect(72,988,1100,38),12,False,'muted')
    def paint_background(self,p):
        self.panel(p,QRect(46,92,806,346),'#08111e','#3b2d68',22,2)
        self.panel(p,QRect(884,92,972,346),'#07101c','#244466',22,1)
        self.panel(p,QRect(46,450,1080,180),'#070d16','#263a59',18,1)
        self.panel(p,QRect(1132,450,724,180),'#070d16','#263a59',18,1)
        self.panel(p,QRect(46,642,1810,312),'#070d16','#263a59',18,1)
