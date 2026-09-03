#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
FILE="$ROOT/usr/local/bin/mechscope"
[ -f "$ROOT/usr/local/bin/mechscope.real" ] && FILE="$ROOT/usr/local/bin/mechscope.real"

[ -f "$FILE" ] || { echo '[MechOS Reference Store v5] MechScope missing' >&2; exit 1; }

python3 - "$FILE" <<'PY'
from pathlib import Path
import sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
marker='# MECHOS_REFERENCE_UNIFIED_STORE_V5'
if marker in text:
    raise SystemExit(0)

start=text.find('class UnifiedStore(QDialog):')
end=text.find('\nclass MechScope(QMainWindow):',start)
if start < 0 or end < 0:
    raise SystemExit('[MechOS Reference Store v5] UnifiedStore class not found')

replacement=r'''class UnifiedStore(QDialog):
    # MECHOS_REFERENCE_UNIFIED_STORE_V5
    STORES = [
        ("Steam", "https://store.steampowered.com/search/?term={query}", ["steam", "-gamepadui"]),
        ("Epic Games", "https://store.epicgames.com/browse?q={query}", ["flatpak", "run", "com.heroicgameslauncher.hgl"]),
        ("GOG.com", "https://www.gog.com/en/games?query={query}", ["flatpak", "run", "com.heroicgameslauncher.hgl"]),
        ("Amazon Games", "https://gaming.amazon.com/home", ["flatpak", "run", "com.heroicgameslauncher.hgl"]),
        ("Heroic", "https://heroicgameslauncher.com/", ["flatpak", "run", "com.heroicgameslauncher.hgl"]),
        ("Lutris", "https://lutris.net/games?q={query}", ["lutris"]),
    ]

    def __init__(self,parent=None):
        super().__init__(parent)
        self.setWindowTitle('MechOS Unified Store')
        self.setWindowFlag(Qt.WindowType.FramelessWindowHint,True)
        self.setWindowState(Qt.WindowState.WindowFullScreen)
        self.selected_store=0
        self.games=steam_games()
        self.cards=[]
        self.build_reference_v5()

    def panel(self,name='panel'):
        f=QFrame(); f.setObjectName(name); return f

    def section(self,text):
        l=QLabel(text); l.setObjectName('section'); return l

    def muted(self,text):
        l=QLabel(text); l.setObjectName('muted'); l.setWordWrap(True); return l

    def launcher_ready(self,cmd):
        if not cmd: return False
        if cmd[0]=='flatpak':
            return shutil.which('flatpak') is not None
        return shutil.which(cmd[0]) is not None

    def disk_free(self):
        try:
            free=shutil.disk_usage(str(Path.home())).free
            if free >= 1024**3: return f'{free/(1024**3):.0f} GB free'
            return f'{free/(1024**2):.0f} MB free'
        except Exception:
            return 'Storage unavailable'

    def build_reference_v5(self):
        outer=QVBoxLayout(self); outer.setContentsMargins(20,14,20,14); outer.setSpacing(10)

        header=QHBoxLayout()
        brand=QLabel('MECHOS'); brand.setObjectName('brand'); header.addWidget(brand)
        header.addStretch()
        title=QLabel('UNIFIED STORE'); title.setObjectName('scope'); header.addWidget(title)
        header.addStretch()
        net=QLabel('OFFICIAL STORES  •  MECHOS LIBRARY'); net.setObjectName('muted'); header.addWidget(net)
        outer.addLayout(header)

        content=QHBoxLayout(); content.setSpacing(12)
        main=QVBoxLayout(); main.setSpacing(10)

        hero=self.panel('storeHero')
        hl=QHBoxLayout(hero); hl.setContentsMargins(28,20,28,20)
        copy=QVBoxLayout()
        eye=QLabel('ONE LIBRARY.'); eye.setObjectName('purple'); copy.addWidget(eye)
        h=QLabel('Every game.'); h.setObjectName('title'); copy.addWidget(h)
        copy.addWidget(self.muted('Discover installed games, search official PC stores, and launch supported libraries from one MechOS surface. Purchases, accounts, licenses and downloads remain with each official provider.'))
        feature=QHBoxLayout()
        for name,desc in [('All in one place','Installed libraries'),('Always Updated','Refresh local library'),('Play Anywhere','Launch supported games')]:
            p=self.panel('sourceCard'); pl=QVBoxLayout(p); t=QLabel(name); t.setStyleSheet('font-weight:900'); pl.addWidget(t); pl.addWidget(self.muted(desc)); feature.addWidget(p)
        copy.addLayout(feature)
        actions=QHBoxLayout()
        explore=QPushButton('Explore All Games'); explore.setObjectName('primary'); explore.clicked.connect(self.search_all); actions.addWidget(explore)
        manage=QPushButton('Manage Library'); manage.clicked.connect(self.refresh_library); actions.addWidget(manage)
        copy.addLayout(actions)
        hl.addLayout(copy,3)
        logo=QLabel(); logo.setMinimumWidth(380); logo.setAlignment(Qt.AlignmentFlag.AlignCenter)
        pix=QPixmap('/usr/share/mechos/branding/reference-hero-v5.svg')
        if not pix.isNull(): logo.setPixmap(pix.scaled(520,230,Qt.AspectRatioMode.KeepAspectRatio,Qt.TransformationMode.SmoothTransformation))
        hl.addWidget(logo,2)
        main.addWidget(hero)

        searchrow=QHBoxLayout()
        self.search=QLineEdit(); self.search.setPlaceholderText('Search for games, DLC, addons, and more…'); self.search.returnPressed.connect(self.search_selected); searchrow.addWidget(self.search,1)
        for label in ('Featured','Action','RPG','Shooter','Indie','Linux Ready'):
            b=QPushButton(label); b.clicked.connect(lambda _=False,q=label: self.set_query(q)); searchrow.addWidget(b)
        main.addLayout(searchrow)

        games_panel=self.panel(); gp=QVBoxLayout(games_panel); gp.setContentsMargins(14,12,14,12)
        sh=QHBoxLayout(); sh.addWidget(self.section('FEATURED / INSTALLED GAMES')); sh.addStretch(); view=QPushButton('View all'); view.clicked.connect(self.refresh_library); sh.addWidget(view); gp.addLayout(sh)
        row=QHBoxLayout(); row.setSpacing(10)
        shown=self.games[:5]
        if shown:
            for game in shown: row.addWidget(self.game_card(game),1)
        else:
            empty=self.panel('gameCard'); el=QVBoxLayout(empty); et=QLabel('Your game library will appear here'); et.setStyleSheet('font-size:18px;font-weight:900'); el.addWidget(et); el.addWidget(self.muted('Install or sign in to Steam, Heroic or Lutris, then refresh the library. No commercial game artwork is bundled in the MechOS ISO.')); opensteam=QPushButton('Open Steam'); opensteam.clicked.connect(lambda:spawn(['steam','-gamepadui'])); el.addWidget(opensteam); row.addWidget(empty)
        gp.addLayout(row)
        main.addWidget(games_panel)

        sources=self.panel(); sl=QVBoxLayout(sources); sl.setContentsMargins(14,10,14,10); sl.addWidget(self.section('STORE SOURCES'))
        sr=QHBoxLayout(); self.source_buttons=[]
        for i,(name,_url,cmd) in enumerate(self.STORES):
            p=self.panel('sourceCard'); pl=QVBoxLayout(p); t=QLabel(name.upper()); t.setStyleSheet('font-size:16px;font-weight:900'); pl.addWidget(t)
            ready=self.launcher_ready(cmd); state=QLabel('● Connected / available' if ready else '○ Launcher not installed'); state.setStyleSheet('color:#31e981' if ready else 'color:#9cacbf'); pl.addWidget(state)
            b=QPushButton('Select'); b.setCheckable(True); b.clicked.connect(lambda _=False,x=i:self.select_store(x)); pl.addWidget(b); self.source_buttons.append(b); sr.addWidget(p,1)
        sl.addLayout(sr); main.addWidget(sources)

        recent=self.panel(); rl=QHBoxLayout(recent); rl.addWidget(self.section('RECENTLY FOUND'))
        for game in self.games[5:11]:
            b=QPushButton(game.get('name','Game')); b.clicked.connect(lambda _=False,g=game:self.launch_game(g)); rl.addWidget(b)
        rl.addStretch(); main.addWidget(recent)
        content.addLayout(main,5)

        side=QVBoxLayout(); side.setSpacing(10)
        lib=self.panel(); ll=QVBoxLayout(lib); ll.addWidget(self.section('LIBRARY & DOWNLOADS'))
        ll.addWidget(self.info_button('My Library',f'{len(self.games)} Steam game(s) detected',self.refresh_library))
        ll.addWidget(self.info_button('Install Queue','Managed by Steam / Heroic / Lutris',self.open_selected_launcher))
        ll.addWidget(self.info_button('Downloads','Open selected launcher',self.open_selected_launcher))
        ll.addWidget(self.info_button('Storage',self.disk_free(),lambda:spawn(['dolphin',str(Path.home())])))
        side.addWidget(lib)

        compat=self.panel(); cl=QVBoxLayout(compat); cl.addWidget(self.section('COMPATIBILITY GUIDE'))
        for name,desc,color in [('Verified','Tested MechOS profile','#31e981'),('Playable','Works with minor setup','#f3c94e'),('Needs Setup','Compatibility profile required','#c77dff'),('Unsupported','Known blocker','#ff5f74'),('Unknown','Not tested yet','#9cacbf')]:
            line=QLabel(f'●  {name}\n    {desc}'); line.setStyleSheet(f'color:{color};padding:7px'); cl.addWidget(line)
        guide=QPushButton('View Compatibility Guide'); guide.clicked.connect(lambda:spawn(['xdg-open','https://www.protondb.com/'])); cl.addWidget(guide); side.addWidget(compat)
        side.addStretch()
        back=QPushButton('Return to MechScope'); back.setObjectName('primary'); back.clicked.connect(self.accept); side.addWidget(back)
        content.addLayout(side,1)
        outer.addLayout(content,1)

        footer=QHBoxLayout(); footer.addWidget(QLabel('A  Select     B  Back     Menu     D-Pad / Arrows Navigate')); footer.addStretch(); footer.addWidget(QLabel('Controller-ready')); outer.addLayout(footer)
        self.select_store(0)

    def info_button(self,title,detail,callback):
        b=QPushButton(title+'\n'+detail); b.clicked.connect(callback); return b

    def game_card(self,game):
        p=self.panel('gameCard'); p.setMinimumHeight(165); l=QVBoxLayout(p)
        title=QLabel(game.get('name','Game')); title.setStyleSheet('font-size:17px;font-weight:900'); title.setWordWrap(True); l.addWidget(title)
        appid=str(game.get('appid',''))
        l.addWidget(self.muted('Steam App '+appid if appid else 'Installed game'))
        l.addStretch(); play=QPushButton('Play'); play.setObjectName('primary'); play.clicked.connect(lambda _=False,g=game:self.launch_game(g)); l.addWidget(play)
        return p

    def set_query(self,q):
        self.search.setText('' if q=='Featured' else q); self.search.setFocus()

    def query(self):
        return quote_plus(self.search.text().strip()) if 'quote_plus' in globals() else self.search.text().strip().replace(' ','+')

    def select_store(self,index):
        self.selected_store=index
        for i,b in enumerate(self.source_buttons): b.setChecked(i==index)

    def search_selected(self):
        name,url,_cmd=self.STORES[self.selected_store]
        q=self.query()
        spawn(['xdg-open',url.format(query=q)])

    def search_all(self):
        q=self.query()
        if not q:
            self.search.setFocus(); return
        for _name,url,_cmd in self.STORES[:4]: spawn(['xdg-open',url.format(query=q)])

    def open_selected_launcher(self):
        _name,_url,cmd=self.STORES[self.selected_store]
        if self.launcher_ready(cmd): spawn(cmd)
        else: QMessageBox.information(self,'MechOS Store','That launcher is not installed yet. Use Creator/Unified Store setup or install it from the official source.')

    def refresh_library(self):
        count=len(steam_games())
        QMessageBox.information(self,'MechOS Library',f'Library scan complete. {count} installed Steam game(s) detected. Heroic and Lutris continue managing their own libraries and downloads.')

    def launch_game(self,game):
        appid=str(game.get('appid','')).strip()
        if appid: spawn(['xdg-open',f'steam://rungameid/{appid}'])
'''

text=text[:start]+replacement+text[end:]
path.write_text(text,encoding='utf-8')
PY

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$FILE"
grep -Fq 'MECHOS_REFERENCE_UNIFIED_STORE_V5' "$FILE"
grep -Fq 'ONE LIBRARY.' "$FILE"
grep -Fq 'COMPATIBILITY GUIDE' "$FILE"
echo '[MechOS Reference Store v5] Unified Store layout applied'
