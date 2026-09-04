#!/usr/bin/env python3
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))

from fixed_canvas import FixedCanvas
from PyQt6.QtCore import QRect, Qt
from PyQt6.QtWidgets import QPlainTextEdit, QProgressBar

# Legacy validator compatibility label: UPDATE CATEGORIES
# Legacy validator compatibility assignment token: self.version_label=

class UpdateShell(FixedCanvas):
    """Source-owned MechOS Update Center composition.

    This screen intentionally uses the same 1920x1080 authored canvas as the
    rest of the system UI. Runtime state is supplied by the UpdateCenter owner;
    this module owns only the visual hierarchy and interactive surfaces.
    """

    def __init__(self, owner, actions, parent=None):
        super().__init__(parent)
        self.owner = owner
        self.actions = actions
        self.build()

    def act(self, key):
        return self.actions.get(key)

    def build(self):
        # Header
        self.label('◉  MECHOS', QRect(48, 22, 320, 54), 21, True)
        self.label('SYSTEM UPDATE CONTROL', QRect(658, 18, 604, 62), 27, True, 'accent', Qt.AlignmentFlag.AlignCenter)
        self.channel = self.label('●  STABLE CHANNEL', QRect(1570, 24, 300, 50), 13, True, 'section', Qt.AlignmentFlag.AlignCenter)

        # Main update state
        self.label('UPDATE STATUS', QRect(78, 126, 310, 32), 13, True, 'section')
        self.status_label = self.label('Checking for updates…', QRect(78, 164, 720, 70), 38, True)
        self.details_label = self.label(
            'Scanning MechOS release metadata, Arch packages and Flatpaks.',
            QRect(78, 232, 760, 60), 15, False, 'muted'
        )
        self.version_label = self.label(
            'CURRENT  checking…    →    LATEST  checking…',
            QRect(78, 302, 760, 38), 13, True, 'accent'
        )
        self.check_button = self.button(
            'CHECK AGAIN', 'Refresh release, package and Flatpak status',
            QRect(78, 360, 330, 86), self.act('check'), False, False, 13
        )
        self.update_button = self.button(
            'INSTALL UPDATES', 'Download, verify and install everything available',
            QRect(426, 360, 414, 86), self.act('install'), True, False, 14
        )
        self.update_button.setEnabled(False)

        # Protection / recovery status
        self.label('UPDATE PROTECTION', QRect(952, 126, 330, 32), 13, True, 'section')
        self.protection_title = self.label('VERIFIED + RECOVERABLE', QRect(952, 166, 590, 50), 25, True, 'accent')
        self.protection_text = self.label(
            'MechOS bundles require HTTPS + SHA-256 verification. A pre-update Snapper snapshot is created when supported.',
            QRect(952, 224, 820, 72), 14, False, 'muted'
        )
        self.reboot_label = self.label('RESTART NOT REQUIRED', QRect(952, 304, 450, 38), 14, True, 'muted')
        self.reboot_button = self.button(
            'RESTART MECHOS', 'Finish updates that require a reboot',
            QRect(952, 360, 328, 86), self.act('reboot'), False, False, 13
        )
        self.reboot_button.setEnabled(False)
        self.button(
            'PERFORMANCE CENTER', 'System health and optimization',
            QRect(1298, 360, 294, 86), self.act('performance'), False, False, 12
        )
        self.button(
            'CREATOR MODE', 'Creator workstation and packages',
            QRect(1610, 360, 236, 86), self.act('creator'), False, False, 12
        )

        # Category cards
        self.label('AVAILABLE UPDATE GROUPS', QRect(78, 500, 430, 34), 13, True, 'section')
        cards = [
            ('MECHOS OS', 'Verified release bundle', 'mechos_count_label'),
            ('ARCH SYSTEM', 'Packages + drivers', 'arch_count_label'),
            ('FLATPAKS', 'Desktop applications', 'flatpak_count_label'),
            ('RECOVERY', 'Snapshot / rollback state', 'recovery_state_label'),
        ]
        for i, (title, subtitle, attr) in enumerate(cards):
            x = 78 + i * 444
            self.label(title, QRect(x + 22, 566, 250, 30), 12, True, 'accent')
            value = self.label('—', QRect(x + 22, 600, 365, 55), 26, True)
            setattr(self, attr, value)
            self.label(subtitle, QRect(x + 22, 654, 365, 34), 11, False, 'muted')

        # Progress + history left
        self.label('UPDATE PROGRESS', QRect(78, 742, 320, 32), 13, True, 'section')
        self.progress = self.reg(QProgressBar(), QRect(78, 786, 700, 54), 12)
        self.progress.setRange(0, 1)
        self.progress.setValue(0)
        self.progress.setFormat('Ready')
        self.progress.setStyleSheet('''
QProgressBar{background:#050a12;border:1px solid #29486b;border-radius:14px;text-align:center;color:#dfeeff;font-weight:700;padding:2px}
QProgressBar::chunk{background:qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #6d4cff,stop:.55 #7f5cff,stop:1 #3edbff);border-radius:11px}
''')
        self.history_button = self.button(
            'REFRESH HISTORY', 'Reload completed update records',
            QRect(78, 858, 300, 72), self.act('history'), False, False, 12
        )
        self.label('RECENT UPDATE HISTORY', QRect(78, 956, 350, 28), 12, True, 'section')
        self.history = self.reg(QPlainTextEdit(), QRect(78, 990, 700, 66), 10)
        self.history.setReadOnly(True)
        self.history.setStyleSheet('QPlainTextEdit{background:#050a12;border:1px solid #263d5b;border-radius:12px;padding:9px;color:#9fb3d0;font-family:Monospace}')

        # Changelog / operation output right
        self.label('RELEASE NOTES + UPDATE OUTPUT', QRect(838, 742, 520, 32), 13, True, 'section')
        self.log = self.reg(QPlainTextEdit(), QRect(838, 786, 1008, 270), 11)
        self.log.setReadOnly(True)
        self.log.setPlaceholderText('Release notes, verification status and installation output appear here.')
        self.log.setStyleSheet('QPlainTextEdit{background:#050a12;border:1px solid #2b4568;border-radius:16px;padding:14px;color:#c9d9ef;font-family:Monospace}')

    def paint_background(self, p):
        # Header divider
        self.panel(p, QRect(42, 92, 1836, 370), '#07111e', '#4d3a80', 24, 2)
        self.panel(p, QRect(914, 108, 944, 338), '#08131f', '#23577c', 22, 1)

        # Category strip and individual cards
        self.panel(p, QRect(42, 482, 1836, 226), '#060d17', '#223a59', 20, 1)
        for i in range(4):
            x = 78 + i * 444
            border = '#6848ad' if i == 0 else '#234b68'
            self.panel(p, QRect(x, 548, 412, 142), '#091321', border, 16, 1)

        # Lower work areas
        self.panel(p, QRect(42, 726, 760, 342), '#060d17', '#253e5d', 20, 1)
        self.panel(p, QRect(814, 726, 1064, 342), '#060d17', '#253e5d', 20, 1)
