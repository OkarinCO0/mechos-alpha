#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
FILE="$ROOT/usr/local/bin/mechos-live-setup"

log() { printf '[MechOS Installer Radio Guard] %s\n' "$*"; }
fail() { printf '[MechOS Installer Radio Guard] ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$FILE" ] || fail "graphical installer missing: $FILE"

python3 - "$FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_INSTALLER_RADIO_SIGNAL_GUARD_V1'
if marker in text:
    raise SystemExit(0)

old_init = """        # Do not select the default radio button until every widget touched by\n        # set_mode() exists. Selecting it earlier fires the Qt toggled signal\n        # during build_ui() and can abort PyQt before the installer is shown.\n        self.mode_buttons['clean'].setChecked(True)\n        self.refresh_target_labels()\n"""
new_init = """        # MECHOS_INSTALLER_RADIO_SIGNAL_GUARD_V1\n        # Python 3.14/PyQt6 can abort the process when an exception escapes a\n        # Qt signal handler. Never emit toggled while constructing the window.\n        default_button=self.mode_buttons['clean']\n        default_button.blockSignals(True)\n        default_button.setChecked(True)\n        default_button.blockSignals(False)\n        self.mode_checks['clean'].setText('✓')\n        self.ov_partition.setText('GPT • BIOS + UEFI')\n        self.ov_fs.setText('Btrfs')\n        self.refresh_target_labels()\n"""
if old_init not in text:
    raise SystemExit('[MechOS Installer Radio Guard] default radio initialization block not found')
text = text.replace(old_init, new_init, 1)

old_buttons = """    def install_card(self,mode,title,desc,detail):\n        if not hasattr(self,'mode_buttons'): self.mode_buttons={}\n"""
new_buttons = """    def install_card(self,mode,title,desc,detail):\n        if not hasattr(self,'mode_buttons'):\n            self.mode_buttons={}\n            self.mode_checks={}\n"""
if old_buttons not in text:
    raise SystemExit('[MechOS Installer Radio Guard] mode button initialization block not found')
text = text.replace(old_buttons, new_buttons, 1)

old_connect = """        check=QLabel('○'); check.setStyleSheet('font-size:26px;color:#a9b3c8'); row.addWidget(check)\n        rb.toggled.connect(lambda checked,m=mode,c=check:self.set_mode(m,checked,c)); p.mousePressEvent=lambda _event,b=rb: b.setChecked(True); self.mode_cards[mode]=p; return p\n\n    def set_mode(self,mode,checked,check=None):\n        if not checked:\n            if check is not None: check.setText('○')\n            return\n        self.install_mode=mode\n        for m in self.mode_buttons:\n            c=self.mode_cards[m].findChildren(QLabel)[-1]\n            if c.text() in ('○','✓'): c.setText('✓' if m==mode else '○')\n"""
new_connect = """        check=QLabel('○'); check.setStyleSheet('font-size:26px;color:#a9b3c8'); row.addWidget(check); self.mode_checks[mode]=check\n        rb.toggled.connect(lambda checked,m=mode:self.mode_toggled(m,checked)); p.mousePressEvent=lambda _event,b=rb: b.setChecked(True); self.mode_cards[mode]=p; return p\n\n    def mode_toggled(self,mode,checked):\n        # Never allow an exception to escape a Qt signal callback. PyQt6 may\n        # treat an unhandled slot exception as fatal and call abort().\n        try:\n            self.set_mode(mode,checked)\n        except Exception as exc:\n            print(f'[MechOS Installer] mode signal failed for {mode}: {exc!r}',file=sys.stderr,flush=True)\n\n    def set_mode(self,mode,checked):\n        if not checked:\n            if mode in self.mode_checks: self.mode_checks[mode].setText('○')\n            return\n        self.install_mode=mode\n        for m,c in self.mode_checks.items():\n            c.setText('✓' if m==mode else '○')\n"""
if old_connect not in text:
    raise SystemExit('[MechOS Installer Radio Guard] radio signal handler block not found')
text = text.replace(old_connect, new_connect, 1)

compile(text, str(path), 'exec')
path.write_text(text, encoding='utf-8')
PY

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$FILE" \
  || fail "installer Python syntax failed after radio guard"

grep -Fq 'MECHOS_INSTALLER_RADIO_SIGNAL_GUARD_V1' "$FILE" \
  || fail "radio signal guard marker missing"
grep -Fq "default_button.blockSignals(True)" "$FILE" \
  || fail "default radio signals are not blocked"
grep -Fq 'def mode_toggled(self,mode,checked):' "$FILE" \
  || fail "guarded mode callback missing"
grep -Fq 'for m,c in self.mode_checks.items()' "$FILE" \
  || fail "stable mode check mapping missing"

log "installer radio initialization is signal-blocked and callbacks are guarded"
