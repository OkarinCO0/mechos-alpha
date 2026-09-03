#!/usr/bin/env python3
"""Shared source-owned visual primitives for MechOS system screens."""
from __future__ import annotations
from PyQt6.QtCore import QRect, Qt
from PyQt6.QtGui import QColor, QFont, QPainter, QPen
from PyQt6.QtWidgets import QLabel, QPushButton, QWidget

BASE_W=1920
BASE_H=1080

class FixedCanvas(QWidget):
    def __init__(self,parent=None):
        super().__init__(parent)
        self._rects={}
        self.setObjectName('mechosFixedCanvas')
        self.setStyleSheet('''
QWidget#mechosFixedCanvas{background:#050912;color:#eef5ff}
QLabel[role="muted"]{color:#8da1bd}
QLabel[role="accent"]{color:#a176ff}
QLabel[role="section"]{color:#66dbff;letter-spacing:2px}
QPushButton[role="action"],QPushButton[role="primary"],QPushButton[role="danger"]{
 color:#f5f8ff;text-align:left;padding:11px 14px;border-radius:14px;
 background:#0c1422;border:1px solid #273a59;font-weight:750
}
QPushButton[role="action"]:hover,QPushButton[role="action"]:focus{border:2px solid #66dcff;background:#111d30}
QPushButton[role="primary"]{border:2px solid #936cff;background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #382164,stop:1 #10294a)}
QPushButton[role="primary"]:hover,QPushButton[role="primary"]:focus{border:3px solid #c3a7ff}
QPushButton[role="danger"]{border:1px solid #8e3852;background:#28111b}
''')
    def reg(self,w,rect):
        w.setParent(self); self._rects[w]=rect; return w
    def label(self,text,rect,size=14,bold=False,role='normal',align=None):
        q=self.reg(QLabel(text),rect); q.setWordWrap(True); q.setProperty('role',role)
        q.setAlignment(align or (Qt.AlignmentFlag.AlignVCenter|Qt.AlignmentFlag.AlignLeft))
        f=QFont('Sans Serif',size); f.setBold(bold); q.setFont(f); return q
    def button(self,title,subtitle,rect,fn=None,primary=False,danger=False):
        q=self.reg(QPushButton(title+(('\n'+subtitle) if subtitle else '')),rect)
        q.setProperty('role','danger' if danger else ('primary' if primary else 'action'))
        q.setCursor(Qt.CursorShape.PointingHandCursor)
        if fn: q.clicked.connect(fn)
        return q
    def scale_rect(self,r):
        s=min(self.width()/BASE_W,self.height()/BASE_H) if self.width() and self.height() else 1.0
        ox=int((self.width()-BASE_W*s)/2); oy=int((self.height()-BASE_H*s)/2)
        return QRect(ox+int(r.x()*s),oy+int(r.y()*s),max(1,int(r.width()*s)),max(1,int(r.height()*s)))
    def resizeEvent(self,event):
        for w,r in self._rects.items(): w.setGeometry(self.scale_rect(r))
        super().resizeEvent(event)
    def panel(self,p,r,fill='#08111e',border='#263a59',radius=20,width=1):
        rr=self.scale_rect(r); s=min(self.width()/BASE_W,self.height()/BASE_H) if self.width() and self.height() else 1.0
        p.setBrush(QColor(fill)); p.setPen(QPen(QColor(border),max(1,int(width*s)))); p.drawRoundedRect(rr,int(radius*s),int(radius*s))
    def paintEvent(self,event):
        p=QPainter(self); p.setRenderHint(QPainter.RenderHint.Antialiasing,True)
        self.paint_background(p)
    def paint_background(self,p):
        pass
