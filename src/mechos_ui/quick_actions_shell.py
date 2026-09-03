#!/usr/bin/env python3
from PyQt6.QtCore import QRect,Qt
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import QLabel,QPushButton,QWidget

class QuickActionsShell(QWidget):
    BASE_W=560; BASE_H=1080
    def __init__(self,owner,actions,parent=None):
        super().__init__(parent); self.owner=owner; self.actions=actions; self.rects={}; self.build()
        self.setStyleSheet('''QWidget{background:#060b13;color:#eef5ff} QLabel[role="muted"]{color:#8fa1ba} QLabel[role="section"]{color:#69dcff;letter-spacing:2px} QPushButton{color:#f4f8ff;text-align:left;padding:10px 13px;border-radius:12px;background:#0d1727;border:1px solid #29415f;font-weight:750} QPushButton:hover,QPushButton:focus{border:2px solid #9c78ff;background:#151d32} QPushButton[role="primary"]{border:2px solid #936cff;background:#30205a}''')
    def reg(self,w,r): w.setParent(self); self.rects[w]=r; return w
    def label(self,t,r,size=12,bold=False,role='normal'):
        q=self.reg(QLabel(t),r); q.setProperty('role',role); q.setWordWrap(True); f=QFont('Sans Serif',size); f.setBold(bold); q.setFont(f); return q
    def button(self,title,sub,r,key,primary=False):
        q=self.reg(QPushButton(title+(('\n'+sub) if sub else '')),r); q.setProperty('role','primary' if primary else 'action'); fn=self.actions.get(key); fn and q.clicked.connect(fn); return q
    def build(self):
        self.label('MECHOS',QRect(24,20,180,34),17,True); self.label('QUICK ACTIONS',QRect(190,20,270,34),18,True,'section')
        self.button('✕','',QRect(486,18,50,40),'close')
        self.label('PERFORMANCE',QRect(24,82,220,28),11,True,'section')
        self.button('Turbo','Maximum performance',QRect(24,118,158,66),'performance',True); self.button('Balanced','All-around profile',QRect(194,118,158,66),'balanced'); self.button('Quiet','Cooler / lower power',QRect(364,118,172,66),'battery')
        self.button('Performance Center','Advanced monitoring & optimization',QRect(24,196,512,62),'performance-center')

        self.label('DEVICE CONTROLS',QRect(24,282,220,28),11,True,'section')
        self.button('Wi-Fi','Toggle wireless',QRect(24,316,158,62),'wifi'); self.button('Bluetooth','Toggle devices',QRect(194,316,158,62),'bluetooth'); self.button('Display','Screen settings',QRect(364,316,172,62),'display')

        self.label('AUDIO',QRect(24,402,160,28),11,True,'section')
        self.button('Volume −','',QRect(24,436,158,58),'vol-down'); self.button('Mute','',QRect(194,436,158,58),'mute'); self.button('Volume +','',QRect(364,436,172,58),'vol-up')

        self.label('STREAMING & RECORDING',QRect(24,520,330,28),11,True,'section')
        self.button('Go Live','Start OBS stream',QRect(24,554,246,66),'go-live',True); self.button('End Stream','Stop OBS stream',QRect(290,554,246,66),'end-stream')
        self.button('Toggle Recording','Start / stop capture',QRect(24,632,246,66),'record'); self.button('Stream Center','Scenes & OBS controls',QRect(290,632,246,66),'stream-center')

        self.label('MECHOS TOOLS',QRect(24,726,220,28),11,True,'section')
        self.button('Update Center','System & hotfix updates',QRect(24,760,246,66),'updates'); self.button('Creator Mode','Creation workspace',QRect(290,760,246,66),'creator')
        self.button('System Info','Hardware details',QRect(24,838,246,66),'system-info'); self.button('Recovery','Repair & restore',QRect(290,838,246,66),'recovery')

        self.label('Ctrl+Shift+M  Quick Actions   •   Esc  Close\nGuide/Home + Y  Open overlay',QRect(24,948,512,72),11,False,'muted')
        self.label('MECHSCOPE 2.0',QRect(24,1024,230,32),10,True,'muted')
    def resizeEvent(self,event):
        sx=self.width()/self.BASE_W; sy=self.height()/self.BASE_H
        for w,r in self.rects.items(): w.setGeometry(int(r.x()*sx),int(r.y()*sy),max(1,int(r.width()*sx)),max(1,int(r.height()*sy)))
        super().resizeEvent(event)
