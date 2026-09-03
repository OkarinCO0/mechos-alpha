#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
FILE="$ROOT/usr/local/bin/mechos-creator-mode"
[ -f "$ROOT/usr/local/bin/mechos-creator-mode.real" ] && FILE="$ROOT/usr/local/bin/mechos-creator-mode.real"
[ -f "$FILE" ] || { echo '[MechOS Creator v5] Creator Mode missing' >&2; exit 1; }

python3 - "$FILE" <<'PY'
from pathlib import Path
import sys

path=Path(sys.argv[1]); text=path.read_text(encoding='utf-8')
marker='# MECHOS_REFERENCE_CREATOR_V5'
if marker in text: raise SystemExit(0)

# Project-scoped toolkit status: never fabricate an Installed state. We inspect
# recent Unity/VRChat projects for package/assets markers and otherwise report
# that status is project-scoped.
helper=r'''
# MECHOS_REFERENCE_CREATOR_V5

def creator_project_tool_status(needle):
    needle=needle.lower()
    for _mtime, project, kind in scan_projects()[:12]:
        if kind not in ('Unity','Folder'): continue
        for rel in ('Packages/manifest.json','Packages/vpm-manifest.json','Packages/packages-lock.json'):
            f=project/rel
            if f.is_file():
                try:
                    if needle in f.read_text(errors='ignore').lower(): return 'Detected in '+project.name
                except Exception: pass
        # Asset-based tools/shaders can be detected by directory/file names.
        assets=project/'Assets'
        if assets.is_dir():
            try:
                for p in list(assets.iterdir())[:300]:
                    if needle in p.name.lower(): return 'Detected in '+project.name
            except Exception: pass
    return 'Project-scoped'
'''
classpos=text.find('class AppCard(')
if classpos < 0: raise SystemExit('[MechOS Creator v5] AppCard class not found')
text=text[:classpos]+helper+'\n'+text[classpos:]

# Replace dashboard only; keep all project/install/backend methods intact.
start=text.find('    def dashboard(self):')
end=text.find('\n    def app_store(self):',start)
if start < 0 or end < 0: raise SystemExit('[MechOS Creator v5] dashboard method not found')

dashboard=r'''    def dashboard(self):
        # MECHOS_REFERENCE_CREATOR_V5_DASHBOARD
        s,v=self.scroll()

        hero=self.panel(); hero.setObjectName('hero'); h=QHBoxLayout(hero); h.setContentsMargins(24,18,24,18)
        tx=QVBoxLayout(); eye=QLabel('WELCOME TO'); eye.setObjectName('purple'); tx.addWidget(eye)
        title=QLabel('Creator Mode'); title.setObjectName('title'); title.setStyleSheet('font-size:38px;font-weight:900'); tx.addWidget(title)
        desc=QLabel('Build. Create. Share. Your all-in-one environment for game development, 3D creation, streaming, video editing and VR content production.'); desc.setObjectName('muted'); desc.setWordWrap(True); tx.addWidget(desc)
        hb=QHBoxLayout()
        for name,sub,fn in [
            ('Unified Workflow','Projects, assets & tools',lambda:self.select(1)),
            ('High Performance','Creator performance profile',lambda:self.apply_preset('3D Artist')),
            ('Publish & Share','Streaming and export tools',lambda:self.quick('obs')),
        ]:
            b=QPushButton(name+'\n'+sub); b.setObjectName('action'); b.setMinimumHeight(62); b.clicked.connect(fn); hb.addWidget(b)
        tx.addLayout(hb); h.addLayout(tx,3)
        art=QLabel(); art.setAlignment(Qt.AlignmentFlag.AlignCenter); pix=QPixmap('/usr/share/mechos/branding/reference-hero-v5.svg')
        if not pix.isNull(): art.setPixmap(pix.scaled(520,230,Qt.AspectRatioMode.KeepAspectRatio,Qt.TransformationMode.SmoothTransformation))
        h.addWidget(art,2); v.addWidget(hero)

        self.section(v,'CREATOR APPS & ENGINES')
        apps=QHBoxLayout(); apps.setSpacing(10)
        for appid in ['unityhub','blender','unreal','obs','krita','kdenlive','godot','vrchat']:
            info=next((x for x in CATALOG if x[1]==appid),None)
            if info:
                card=AppCard(self,info); card.setMinimumHeight(175); self.cards.append(card); apps.addWidget(card,1)
        v.addLayout(apps)

        columns=QHBoxLayout(); columns.setSpacing(12)
        profiles=self.panel(); pl=QVBoxLayout(profiles); ph=QLabel('PROJECT PROFILES'); ph.setObjectName('purple'); pl.addWidget(ph)
        for name,detail in [('Game Dev','Unity • C# • High Performance'),('3D Artist','Blender • Krita • Assets'),('VRChat Creator','Unity • VRChat workflow'),('Streaming','OBS • Kdenlive • Encoding')]:
            b=QPushButton(name+'\n'+detail); b.setObjectName('action'); b.clicked.connect(lambda _=False,n=name:self.apply_preset(n)); pl.addWidget(b)
        pl.addStretch(); newp=QPushButton('+ New Profile / Preset'); newp.clicked.connect(lambda:self.select(9)); pl.addWidget(newp); columns.addWidget(profiles,1)

        pipes=self.panel(); pil=QVBoxLayout(pipes); pt=QLabel('ASSET PIPELINES'); pt.setObjectName('purple'); pil.addWidget(pt)
        for name,detail,fn in [
            ('Import Pipeline','FBX • glTF • textures',lambda:self.select(5)),
            ('Optimization Pipeline','Performance and system tools',lambda:spawn(['/usr/local/bin/mechos-performance-center'])),
            ('Export Pipeline','Projects and publishing',lambda:self.select(1)),
            ('Version Control','Git workflow',lambda:self.quick('gitkraken')),
        ]:
            b=QPushButton(name+'\n'+detail); b.setObjectName('action'); b.clicked.connect(fn); pil.addWidget(b)
        pil.addStretch(); columns.addWidget(pipes,1)

        recent=self.panel(); rl=QVBoxLayout(recent); rt=QLabel('RECENT PROJECTS'); rt.setObjectName('purple'); rl.addWidget(rt)
        projects=scan_projects()[:4]
        if projects:
            for m,p,k in projects:
                b=QPushButton(f'{p.name}\n{k} project'); b.setObjectName('action'); b.clicked.connect(lambda _=False,pp=p,kk=k:launch_project(pp,kk)); rl.addWidget(b)
        else:
            lab=QLabel('No creator projects found yet.'); lab.setObjectName('muted'); rl.addWidget(lab)
        rl.addStretch(); view=QPushButton('View all'); view.clicked.connect(lambda:self.select(1)); rl.addWidget(view); columns.addWidget(recent,1)

        plugins=self.panel(); kl=QVBoxLayout(plugins); kt=QLabel('PLUGINS & TOOLKITS'); kt.setObjectName('purple'); kl.addWidget(kt)
        for title,needle,url in [
            ('VRChat SDK','com.vrchat','https://creators.vrchat.com/'),
            ('UdonSharp','udonsharp','https://creators.vrchat.com/worlds/udon/'),
            ('VRCFury','vrcfury','https://vrcfury.com/'),
            ('Poiyomi','poiyomi','https://www.poiyomi.com/'),
        ]:
            state=creator_project_tool_status(needle)
            b=QPushButton(title+'\n'+state); b.clicked.connect(lambda _=False,u=url:open_url(u)); kl.addWidget(b)
        kl.addStretch(); browse=QPushButton('Browse Creator Store'); browse.setObjectName('action'); browse.clicked.connect(lambda:self.select(4)); kl.addWidget(browse); columns.addWidget(plugins,1)
        v.addLayout(columns)
        v.addStretch(); return s
'''
text=text[:start]+dashboard+text[end:]

# Replace app store with reference structure while retaining AppCard/PackageCard
# install/status functions and post-install restrictions.
start=text.find('    def app_store(self):')
end=text.find('\n    def new_project(self):',start)
if start < 0 or end < 0: raise SystemExit('[MechOS Creator v5] app_store method not found')

store=r'''    def app_store(self):
        # MECHOS_REFERENCE_CREATOR_STORE_V5
        s,v=self.scroll()
        hero=self.panel(); hero.setObjectName('hero'); hl=QHBoxLayout(hero); hl.setContentsMargins(24,18,24,18)
        copy=QVBoxLayout(); eye=QLabel('TOOLS. WORKFLOWS.'); eye.setObjectName('purple'); copy.addWidget(eye)
        title=QLabel('Creations.'); title.setObjectName('title'); title.setStyleSheet('font-size:36px;font-weight:900'); copy.addWidget(title)
        intro=QLabel('Everything you need to build, stream and share. Installed state is read from the real system; Creator installs remain post-install only.'); intro.setObjectName('muted'); intro.setWordWrap(True); copy.addWidget(intro)
        search=QLineEdit(); search.setPlaceholderText('Search is organized by the categories below'); copy.addWidget(search); hl.addLayout(copy,3)
        art=QLabel(); art.setAlignment(Qt.AlignmentFlag.AlignCenter); pix=QPixmap('/usr/share/mechos/branding/reference-hero-v5.svg')
        if not pix.isNull(): art.setPixmap(pix.scaled(470,210,Qt.AspectRatioMode.KeepAspectRatio,Qt.TransformationMode.SmoothTransformation)); hl.addWidget(art,2)
        v.addWidget(hero)

        tabs=QHBoxLayout()
        groups=[('All Apps',None),('Game Engines',['unityhub','unreal','godot']),('3D & Art',['blender','krita']),('Streaming',['obs','kdenlive','audacity','discord']),('Windows Tools',['wine','winetricks','protontricks','bottles','protonupqt'])]
        pages=QStackedWidget(); tab_buttons=[]
        def switch(i):
            pages.setCurrentIndex(i)
            for j,b in enumerate(tab_buttons): b.setChecked(i==j)
        for i,(name,ids) in enumerate(groups):
            b=QPushButton(name); b.setCheckable(True); b.clicked.connect(lambda _=False,x=i:switch(x)); tab_buttons.append(b); tabs.addWidget(b)
            page=QWidget(); pg=QGridLayout(page); pg.setSpacing(10)
            selected=CATALOG if ids is None else [x for x in CATALOG if x[1] in ids]
            for n,info in enumerate(selected):
                c=AppCard(self,info); c.setMinimumHeight(165); self.cards.append(c); pg.addWidget(c,n//5,n%5)
            pages.addWidget(page)
        featured=QPushButton('Featured Bundles'); featured.clicked.connect(lambda: QMessageBox.information(self,'Creator Bundles','Creator bundles are listed below and use the same real package installer backend.')); tabs.addWidget(featured)
        v.addLayout(tabs); switch(0); v.addWidget(pages)

        lower=QHBoxLayout(); lower.setSpacing(12)
        bundles=self.panel(); bl=QVBoxLayout(bundles); bh=QLabel('FEATURED BUNDLES'); bh.setObjectName('purple'); bl.addWidget(bh)
        for info in PACKAGES[:3]:
            c=PackageCard(self,info); self.package_cards.append(c); bl.addWidget(c)
        lower.addWidget(bundles,1)

        workflows=self.panel(); wl=QVBoxLayout(workflows); wh=QLabel('ONE-CLICK WORKFLOWS'); wh.setObjectName('purple'); wl.addWidget(wh)
        for title,preset,detail in [('Indie Game Starter','Game Dev','Unity/Godot • Blender • Git'),('Stream Like a Pro','Streaming','OBS • video/audio tools'),('3D Artist','3D Artist','Blender • Krita'),('VR World Creator','VRChat Creator','Unity • VRChat workflow')]:
            b=QPushButton(title+'\n'+detail); b.setObjectName('action'); b.clicked.connect(lambda _=False,p=preset:self.apply_preset(p)); wl.addWidget(b)
        wl.addStretch(); lower.addWidget(workflows,1)

        queue=self.panel(); ql=QVBoxLayout(queue); qh=QLabel('DOWNLOADS / INSTALL STATUS'); qh.setObjectName('purple'); ql.addWidget(qh)
        for appid in ['krita','godot','unreal','obs']:
            info=next((x for x in CATALOG if x[1]==appid),None)
            if not info: continue
            st='Vendor setup' if info[3]=='vendor' else (out([APP,'status',appid]) or 'missing')
            ql.addWidget(QLabel(f'{info[0]}   •   {st}'))
        note=QLabel('Actual package download progress remains in Pacman/Flatpak/vendor installers.'); note.setObjectName('muted'); note.setWordWrap(True); ql.addWidget(note); ql.addStretch(); lower.addWidget(queue,1)
        v.addLayout(lower); v.addStretch(); return s
'''
text=text[:start]+store+text[end:]
path.write_text(text,encoding='utf-8')
PY

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$FILE"
grep -Fq 'MECHOS_REFERENCE_CREATOR_V5_DASHBOARD' "$FILE"
grep -Fq 'PROJECT PROFILES' "$FILE"
grep -Fq 'ASSET PIPELINES' "$FILE"
grep -Fq 'PLUGINS & TOOLKITS' "$FILE"
grep -Fq 'MECHOS_REFERENCE_CREATOR_STORE_V5' "$FILE"
grep -Fq 'FEATURED BUNDLES' "$FILE"
grep -Fq 'ONE-CLICK WORKFLOWS' "$FILE"
echo '[MechOS Creator v5] Creator Mode and Creator Store layouts applied'
