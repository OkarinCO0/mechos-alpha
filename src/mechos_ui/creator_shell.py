#!/usr/bin/env python3
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from fixed_canvas import FixedCanvas
from PyQt6.QtCore import QRect,Qt
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import QLabel,QPushButton,QStackedWidget,QWidget

class CreatorDashboard(QWidget):
    BASE_W=1606; BASE_H=858
    def __init__(self,owner,parent=None):
        super().__init__(parent); self.owner=owner; self.rects={}; self.build()
        self.setStyleSheet('''QWidget{background:#060b13;color:#eef5ff} QLabel[role="muted"]{color:#8da1bd} QLabel[role="section"]{color:#69dcff;letter-spacing:2px} QLabel[role="accent"]{color:#a176ff} QPushButton{color:#f4f8ff;text-align:left;padding:9px 12px;border-radius:12px;background:#0d1727;border:1px solid #29415f;font-weight:750} QPushButton:hover,QPushButton:focus{border:2px solid #9c78ff;background:#151d32} QPushButton[role="primary"]{border:2px solid #936cff;background:#30205a}''')
    def reg(self,w,r): w.setParent(self); self.rects[w]=r; return w
    def label(self,t,r,size=12,bold=False,role='normal'):
        q=self.reg(QLabel(t),r); q.setWordWrap(True); q.setProperty('role',role); f=QFont('Sans Serif',size); f.setBold(bold); q.setFont(f); return q
    def button(self,t,s,r,fn=None,primary=False):
        q=self.reg(QPushButton(t+(('\n'+s) if s else '')),r); q.setProperty('role','primary' if primary else 'action'); fn and q.clicked.connect(fn); return q
    def build(self):
        self.label('WELCOME TO',QRect(34,22,280,28),11,True,'accent')
        self.label('Creator Mode',QRect(32,52,560,62),34,True)
        self.label('Build. Create. Share. Your all-in-one environment for game development, 3D creation, streaming, video editing and VR content production.',QRect(32,116,720,64),13,False,'muted')
        self.button('Unified Workflow','Projects, assets & tools',QRect(32,194,220,66),lambda:self.owner.select(1),True)
        self.button('High Performance','Creator performance profile',QRect(266,194,236,66),lambda:self.owner.apply_preset('3D Artist'))
        self.button('Publish & Share','Streaming and export tools',QRect(516,194,230,66),lambda:self.owner.quick('obs'))
        self.label('CREATOR APPS & ENGINES',QRect(32,294,350,28),11,True,'section')
        apps=[('Unity Hub','unityhub'),('Blender','blender'),('Unreal Engine','unreal'),('OBS Studio','obs'),('Krita','krita'),('Kdenlive','kdenlive'),('Godot','godot'),('VRChat Creator','vrchat')]
        for i,(title,appid) in enumerate(apps):
            x=32+(i%4)*374; y=332+(i//4)*88
            self.button(title,'Open / install creator tool',QRect(x,y,350,72),lambda _=False,a=appid:self.owner.quick(a),appid in ('unityhub','blender'))
        self.label('PROJECT PROFILES',QRect(32,524,300,28),11,True,'section')
        for i,name in enumerate(['Game Dev','3D Artist','VRChat Creator','Streaming']):
            self.button(name,{'Game Dev':'Unity • C# • High Performance','3D Artist':'Blender • Krita • Assets','VRChat Creator':'Unity • VRChat workflow','Streaming':'OBS • Kdenlive • Encoding'}[name],QRect(32,560+i*66,340,56),lambda _=False,n=name:self.owner.apply_preset(n))
        self.label('ASSET PIPELINES',QRect(404,524,300,28),11,True,'section')
        pipes=[('Import Pipeline','FBX • glTF • textures',5),('Optimization Pipeline','Performance and system tools',None),('Export Pipeline','Projects and publishing',1),('Version Control','Git workflow','gitkraken')]
        for i,(t,s,target) in enumerate(pipes):
            if target is None: fn=lambda:self._spawn('/usr/local/bin/mechos-performance-center')
            elif isinstance(target,int): fn=lambda _=False,j=target:self.owner.select(j)
            else: fn=lambda _=False,a=target:self.owner.quick(a)
            self.button(t,s,QRect(404,560+i*66,350,56),fn)
        self.label('RECENT PROJECTS',QRect(786,524,300,28),11,True,'section')
        projects=self._projects()
        if projects:
            for i,(m,p,k) in enumerate(projects[:4]): self.button(p.name,k+' project',QRect(786,560+i*66,370,56),lambda _=False,pp=p,kk=k:self._launch_project(pp,kk))
        else:self.label('No creator projects found yet.',QRect(786,560,370,56),12,False,'muted')
        self.button('View all','Project Manager',QRect(786,758,370,56),lambda:self.owner.select(1))
        self.label('PLUGINS & TOOLKITS',QRect(1188,524,340,28),11,True,'section')
        for i,(title,needle) in enumerate([('VRChat SDK','com.vrchat'),('UdonSharp','udonsharp'),('VRCFury','vrcfury'),('Poiyomi','poiyomi')]):
            self.button(title,self._tool_status(needle),QRect(1188,560+i*66,370,56),lambda:self.owner.select(4))
        self.button('Browse Creator Store','Apps, bundles & workflows',QRect(1188,758,370,56),lambda:self.owner.select(4),True)
    def _module(self): return sys.modules.get(self.owner.__class__.__module__)
    def _projects(self):
        mod=self._module(); fn=getattr(mod,'scan_projects',None)
        try:return list(fn()) if callable(fn) else []
        except Exception:return []
    def _launch_project(self,p,k):
        fn=getattr(self._module(),'launch_project',None)
        if callable(fn): fn(p,k)
    def _tool_status(self,needle):
        fn=getattr(self._module(),'creator_project_tool_status',None)
        try:return fn(needle) if callable(fn) else 'Project-scoped'
        except Exception:return 'Project-scoped'
    def _spawn(self,path):
        import subprocess
        try: subprocess.Popen([path])
        except Exception: pass
    def resizeEvent(self,event):
        sx=self.width()/self.BASE_W; sy=self.height()/self.BASE_H
        for w,r in self.rects.items(): w.setGeometry(int(r.x()*sx),int(r.y()*sy),max(1,int(r.width()*sx)),max(1,int(r.height()*sy)))
        super().resizeEvent(event)

class CreatorShell(FixedCanvas):
    def __init__(self,owner,parent=None):
        super().__init__(parent); self.owner=owner; self.build()
    def build(self):
        self.label('◉  MECHOS',QRect(34,16,250,54),20,True)
        self.label('CREATOR MODE 2.0',QRect(730,16,470,54),24,True,'accent')
        self.owner.cpu=self.label('CPU --',QRect(1460,16,100,54),11,True,'muted'); self.owner.ram=self.label('RAM --',QRect(1564,16,100,54),11,True,'muted'); self.owner.vram=self.label('VRAM --',QRect(1668,16,110,54),11,True,'muted'); self.owner.disk=self.label('DISK --',QRect(1780,16,110,54),11,True,'muted')
        navs=[('⌂  Dashboard',0),('▣  Projects',1),('⬡  Engines',2),('⚒  Tools',3),('▦  Creator Store',4),('▧  Assets',5),('✦  MechClip AI',6),('◈  Learn',7),('◎  Community',8),('⚙  Settings',9)]
        self.owner.nav=[]
        for i,(title,index) in enumerate(navs):
            b=self.button(title,'',QRect(24,104+i*66,200,54),lambda _=False,j=index:self.owner.select(j),i==0); b.setCheckable(True); self.owner.nav.append(b)
        self.owner.status=self.label('SYSTEM STATUS\nCreator workspace ready',QRect(24,800,200,86),11,False,'muted')
        self.button('System Monitor','Performance Center',QRect(24,898,200,62),lambda:self._spawn('/usr/local/bin/mechos-performance-center'))
        self.owner.stack=self.reg(QStackedWidget(),QRect(250,94,1606,858))
        self.owner.stack.addWidget(CreatorDashboard(self.owner))
        factories=[self.owner.projects,lambda:self.owner.catalog('GAME ENGINES',['unityhub','unreal','godot','vscode','gitkraken']),lambda:self.owner.catalog('CREATOR TOOLS',['blender','krita','obs','kdenlive','audacity','lmms','vscode','gitkraken']),self.owner.app_store,self.owner.assets,self.owner.mechclip,self.owner.learn,self.owner.community,self.owner.settings]
        for fn in factories:
            try:self.owner.stack.addWidget(fn())
            except Exception as exc:self.owner.stack.addWidget(self._error(str(exc)))
        self.owner.select(0)
        self.label('MECHOS',QRect(24,1004,130,36),10,True,'muted')
        self.button('Gaming Mode','Return to MechScope',QRect(250,976,260,54),self.owner.mechscope)
        self.button('Desktop Mode','Productivity desktop',QRect(524,976,260,54),self.owner.desktop)
        self.label('Build • Create • Stream • Publish',QRect(1280,982,576,42),11,False,'muted')
    def _error(self,text):
        w=QWidget(); q=QLabel('Creator page could not load:\n'+text,w); q.setGeometry(40,40,1000,120); q.setWordWrap(True); return w
    def _spawn(self,path):
        import subprocess
        try:subprocess.Popen([path])
        except Exception:pass
    def paint_background(self,p):
        self.panel(p,QRect(8,82,228,892),'#070d16','#233854',18,1)
        self.panel(p,QRect(238,82,1630,886),'#060b13','#223651',18,1)
