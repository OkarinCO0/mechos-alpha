#!/usr/bin/env python3
"""Creator Mode visual shell.

The approved Creator Mode reference artwork is the visual source of truth for the
Home screen. Functional, transparent hit-zones are layered over the reference so
we do not re-create the approved layout with approximate Qt widgets.
"""
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fixed_canvas import BASE_H, BASE_W, FixedCanvas
from PyQt6.QtCore import QRect
from PyQt6.QtGui import QColor, QPainter, QPixmap
from PyQt6.QtWidgets import QLabel, QPushButton, QStackedWidget, QWidget

REFERENCE_IMAGE = Path('/usr/share/mechos/branding/mechos-creator-mode-reference.png')
REFERENCE_W = 1672
REFERENCE_H = 941
REFERENCE_SECTIONS = (
    'CREATOR APPS & ENGINES',
    'PROJECT PROFILES',
    'ASSET PIPELINES',
    'RECENT PROJECTS',
    'PLUGINS & TOOLKITS',
    'CREATOR RESOURCES',
)


def rr(x, y, w, h):
    """Convert approved-reference pixel coordinates to the 1920x1080 canvas."""
    return QRect(
        round(x / REFERENCE_W * BASE_W),
        round(y / REFERENCE_H * BASE_H),
        round(w / REFERENCE_W * BASE_W),
        round(h / REFERENCE_H * BASE_H),
    )


class ReferenceHome(FixedCanvas):
    """Pixel-faithful Creator Mode home using the approved reference image."""

    def __init__(self, owner, parent=None):
        super().__init__(parent)
        self.owner = owner
        self.reference = QPixmap(str(REFERENCE_IMAGE))
        self.setStyleSheet('''
QWidget#mechosFixedCanvas{background:#030711}
QPushButton[role="hotspot"]{
 background:transparent;border:0;color:transparent;padding:0;margin:0
}
QPushButton[role="hotspot"]:hover,QPushButton[role="hotspot"]:focus{
 background:rgba(108,155,255,20);border:2px solid #8b78ff;border-radius:12px
}
''')
        self._build_hotspots()

    def hotspot(self, name, rect, fn):
        b = self.reg(QPushButton(''), rect)
        b.setProperty('role', 'hotspot')
        b.setToolTip(name)
        b.setAccessibleName(name)
        if fn:
            b.clicked.connect(fn)
        return b

    def _build_hotspots(self):
        # Hero actions.
        self.hotspot('Unified Workflow', rr(49, 238, 302, 96), lambda: self.owner.select(1))
        self.hotspot('High Performance', rr(365, 238, 326, 96), lambda: self.owner.apply_preset('3D Artist'))
        self.hotspot('Publish & Share', rr(707, 238, 316, 96), lambda: self.owner.quick('obs'))
        self.hotspot('Performance Center', rr(1090, 264, 516, 70), lambda: self._spawn('/usr/local/bin/mechos-performance-center'))

        # Creator apps & engines. The artwork supplies the exact cards/icons;
        # these transparent regions keep the cards functional.
        apps = [
            ('Unity Hub', 'unityhub', 41, 403, 94),
            ('Blender', 'blender', 145, 403, 105),
            ('Unreal Engine', 'unreal', 260, 403, 97),
            ('OBS Studio', 'obs', 367, 403, 92),
            ('Krita', 'krita', 469, 403, 92),
            ('Kdenlive', 'kdenlive', 572, 403, 92),
            ('Godot', 'godot', 675, 403, 92),
            ('VRChat Creator', 'vrchat', 777, 403, 101),
        ]
        for title, appid, x, y, w in apps:
            self.hotspot(title, rr(x, y, w, 164), lambda _=False, a=appid: self.owner.quick(a))

        # Project profiles.
        profiles = [
            ('Game Dev', 'Game Dev', 926, 404),
            ('3D Artist', '3D Artist', 1102, 404),
            ('VRChat Creator', 'VRChat Creator', 926, 492),
            ('Streaming', 'Streaming', 1102, 492),
        ]
        for title, preset, x, y in profiles:
            self.hotspot(title, rr(x, y, 160, 75), lambda _=False, p=preset: self.owner.apply_preset(p))

        # Asset pipelines.
        self.hotspot('Import Pipeline', rr(1298, 404, 310, 40), lambda: self.owner.select(5))
        self.hotspot('Optimization Pipeline', rr(1298, 449, 310, 40), lambda: self._spawn('/usr/local/bin/mechos-performance-center'))
        self.hotspot('Export Pipeline', rr(1298, 493, 310, 40), lambda: self.owner.select(1))
        self.hotspot('Version Control', rr(1298, 537, 310, 40), lambda: self.owner.quick('gitkraken'))

        # Recent project cards use the real scanned project list when available.
        for i, x in enumerate((42, 254, 465, 675)):
            self.hotspot(f'Recent Project {i + 1}', rr(x, 629, 200, 161), lambda _=False, n=i: self._launch_project(n))
        self.hotspot('View All Projects', rr(805, 596, 72, 30), lambda: self.owner.select(1))

        # Plug-ins and resources.
        for i, name in enumerate(('VRChat SDK', 'UdonSharp', 'VRCFury', 'Poiyomi Toon Shader')):
            self.hotspot(name, rr(925, 629 + i * 42, 337, 38), lambda: self.owner.select(4))
        self.hotspot('Creator Docs', rr(1298, 629, 310, 38), lambda: self.owner.select(7))
        self.hotspot('Tutorials', rr(1298, 671, 310, 38), lambda: self.owner.select(7))
        self.hotspot('Community Hub', rr(1298, 713, 310, 38), lambda: self.owner.select(8))
        self.hotspot('Support Center', rr(1298, 755, 310, 38), lambda: self.owner.select(9))

        # Exact bottom reference navigation.
        self.hotspot('Home', rr(22, 814, 274, 55), lambda: self.owner.select(0))
        self.hotspot('Creator Store', rr(308, 814, 311, 55), lambda: self.owner.select(4))
        self.hotspot('Projects', rr(630, 814, 294, 55), lambda: self.owner.select(1))
        self.hotspot('Tools', rr(936, 814, 297, 55), lambda: self.owner.select(3))
        self.hotspot('Back to MechScope', rr(1264, 814, 361, 55), self.owner.mechscope)

    def _module(self):
        return sys.modules.get(self.owner.__class__.__module__)

    def _projects(self):
        mod = self._module()
        fn = getattr(mod, 'scan_projects', None)
        try:
            return list(fn()) if callable(fn) else []
        except Exception:
            return []

    def _launch_project(self, index):
        projects = self._projects()
        if index >= len(projects):
            self.owner.select(1)
            return
        _, path, kind = projects[index]
        fn = getattr(self._module(), 'launch_project', None)
        if callable(fn):
            fn(path, kind)
        else:
            self.owner.select(1)

    def _spawn(self, path):
        try:
            subprocess.Popen([path])
        except Exception:
            pass

    def paint_background(self, painter: QPainter):
        target = self.scale_rect(QRect(0, 0, BASE_W, BASE_H))
        painter.fillRect(target, QColor('#030711'))
        if not self.reference.isNull():
            painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform, True)
            painter.drawPixmap(target, self.reference)
        else:
            painter.setPen(QColor('#eef5ff'))
            painter.drawText(target, 0x84, 'Creator Mode reference artwork is missing')


class CreatorShell(FixedCanvas):
    """Fullscreen Creator Mode shell with reference-faithful Home page."""

    def __init__(self, owner, parent=None):
        super().__init__(parent)
        self.owner = owner
        self.build()

    def build(self):
        # The old left navigation is intentionally removed. The approved
        # reference image supplies the actual Home navigation and composition.
        self.owner.nav = []
        self.owner.stack = self.reg(QStackedWidget(), QRect(0, 0, BASE_W, BASE_H))
        self.owner.stack.addWidget(ReferenceHome(self.owner))

        factories = [
            self.owner.projects,
            lambda: self.owner.catalog('GAME ENGINES', ['unityhub', 'unreal', 'godot', 'vscode', 'gitkraken']),
            lambda: self.owner.catalog('CREATOR TOOLS', ['blender', 'krita', 'obs', 'kdenlive', 'audacity', 'lmms', 'vscode', 'gitkraken']),
            self.owner.app_store,
            self.owner.assets,
            self.owner.mechclip,
            self.owner.learn,
            self.owner.community,
            self.owner.settings,
        ]
        for fn in factories:
            try:
                self.owner.stack.addWidget(fn())
            except Exception as exc:
                self.owner.stack.addWidget(self._error(str(exc)))

        # Keep the existing runtime metric updater API alive without drawing a
        # second set of labels over the approved reference artwork.
        self.owner.cpu = self._hidden_label()
        self.owner.ram = self._hidden_label()
        self.owner.vram = self._hidden_label()
        self.owner.disk = self._hidden_label()
        self.owner.status = self._hidden_label()
        self.owner.select(0)

    def _hidden_label(self):
        q = QLabel(self)
        q.hide()
        return q

    def _error(self, text):
        w = QWidget()
        q = QLabel('Creator page could not load:\n' + text, w)
        q.setGeometry(40, 40, 1000, 120)
        q.setWordWrap(True)
        return w

    def paint_background(self, painter):
        painter.fillRect(self.scale_rect(QRect(0, 0, BASE_W, BASE_H)), QColor('#030711'))
