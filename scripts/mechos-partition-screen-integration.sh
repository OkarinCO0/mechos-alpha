#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
BIN="$ROOT/usr/local/bin"
PROFILE="/workspace/archlive/profiledef.sh"

log() { printf '[MechOS Partition Screen] %s\n' "$*"; }
fail() { printf '[MechOS Partition Screen] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Partition Screen] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -f "$BIN/mechos-live-setup" ] || fail "graphical live installer is missing"
mkdir -p "$BIN"

cat > "$BIN/mechos-partition-selector" <<'PYEOF'
#!/usr/bin/env python3
import json
import os
import subprocess
import sys
from pathlib import Path

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import (
    QApplication, QFrame, QHBoxLayout, QLabel, QMainWindow, QMessageBox,
    QPushButton, QTreeWidget, QTreeWidgetItem, QVBoxLayout, QWidget
)

SELECTION_FILE = Path('/tmp/mechos-install-target.json')

STYLE = '''
QWidget { background:#050812; color:#eef5ff; font-family:Sans Serif; }
QFrame#panel { background:#081221; border:1px solid #244c7c; border-radius:12px; }
QLabel#title { color:#ffffff; font-size:28px; font-weight:900; }
QLabel#section { color:#58c7ff; font-weight:900; }
QLabel#muted { color:#9fb2cc; }
QPushButton { background:#0d203c; border:1px solid #286fd3; border-radius:10px;
              padding:10px 14px; font-weight:700; }
QPushButton:hover { background:#17315a; border:2px solid #9b68ff; }
QPushButton#primary { background:#244fd6; border:1px solid #8bd7ff; }
QTreeWidget { background:#07111e; alternate-background-color:#0a1525;
              border:1px solid #25496f; border-radius:10px; outline:0; }
QTreeWidget::item { padding:7px; }
QTreeWidget::item:selected { background:#172f58; border:1px solid #8a66ff; }
'''


def output(args):
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ''


def human_size(value):
    try:
        n = int(value or 0)
    except Exception:
        return '?'
    for unit in ('B','KiB','MiB','GiB','TiB'):
        if n < 1024 or unit == 'TiB':
            return f'{n:.0f} {unit}' if unit == 'B' else f'{n:.1f} {unit}'
        n /= 1024.0
    return '?'


def live_media_disk():
    source = output(['findmnt','-n','-o','SOURCE','/run/archiso/bootmnt'])
    if not source.startswith('/dev/'):
        return ''
    parent = output(['lsblk','-ndo','PKNAME',source])
    if parent:
        return '/dev/' + parent
    return source


def scan_devices():
    raw = output([
        'lsblk','-J','-b','-o',
        'NAME,PATH,SIZE,TYPE,FSTYPE,FSVER,LABEL,MOUNTPOINTS,MODEL,PKNAME,PARTTYPE,PARTFLAGS'
    ])
    if not raw:
        return []
    try:
        return json.loads(raw).get('blockdevices', [])
    except Exception:
        return []


class PartitionSelector(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle('MechOS Install Location')
        self.resize(1250, 760)
        self.setMinimumSize(980, 620)
        self.setStyleSheet(STYLE)
        self.live_disk = live_media_disk()
        self.records = {}
        self.build()
        self.refresh()

    def panel(self):
        p = QFrame(); p.setObjectName('panel'); return p

    def build(self):
        root = QWidget(); self.setCentralWidget(root)
        outer = QVBoxLayout(root); outer.setContentsMargins(28,24,28,24); outer.setSpacing(14)

        title = QLabel('SELECT INSTALL LOCATION'); title.setObjectName('title'); outer.addWidget(title)
        sub = QLabel(
            'Choose the disk or existing partition where you want MechOS installed. '
            'This screen is read-only: selecting a location does not format, resize, or delete anything.'
        )
        sub.setObjectName('muted'); sub.setWordWrap(True); outer.addWidget(sub)

        note = self.panel(); nl = QVBoxLayout(note)
        n1 = QLabel('SAFETY / PARTITIONING'); n1.setObjectName('section'); nl.addWidget(n1)
        n2 = QLabel(
            'Whole disk: can be used with Clean Install.  Existing partition: MechOS switches to manual '
            'partitioning so you can choose mount points and formatting explicitly.  Unallocated space is '
            'handled through Custom or Install Alongside mode. The Live USB itself cannot be selected.'
        )
        n2.setObjectName('muted'); n2.setWordWrap(True); nl.addWidget(n2); outer.addWidget(note)

        self.tree = QTreeWidget()
        self.tree.setAlternatingRowColors(True)
        self.tree.setHeaderLabels(['Device','Size','Type','Filesystem','Label','Mounts','Model'])
        self.tree.setColumnWidth(0,230); self.tree.setColumnWidth(1,110); self.tree.setColumnWidth(2,100)
        self.tree.itemSelectionChanged.connect(self.selection_changed)
        self.tree.itemDoubleClicked.connect(lambda *_: self.use_selected())
        outer.addWidget(self.tree, 1)

        self.details = QLabel('Select a disk or partition.')
        self.details.setObjectName('muted'); self.details.setWordWrap(True); outer.addWidget(self.details)

        row = QHBoxLayout()
        refresh = QPushButton('Refresh Devices'); refresh.clicked.connect(self.refresh); row.addWidget(refresh)
        row.addStretch(1)
        cancel = QPushButton('Cancel'); cancel.clicked.connect(self.close); row.addWidget(cancel)
        self.use = QPushButton('Use Selected Location'); self.use.setObjectName('primary')
        self.use.clicked.connect(self.use_selected); self.use.setEnabled(False); row.addWidget(self.use)
        outer.addLayout(row)

    def add_node(self, parent, rec, disk_path):
        path = rec.get('path') or ''
        typ = rec.get('type') or ''
        mounts = rec.get('mountpoints') or []
        if isinstance(mounts, str): mounts = [mounts]
        mounts = ', '.join(m for m in mounts if m) or '-'
        is_live = bool(self.live_disk and disk_path == self.live_disk)
        name = path + ('   [LIVE MEDIA]' if is_live else '')
        values = [
            name,
            human_size(rec.get('size')),
            typ,
            rec.get('fstype') or '-',
            rec.get('label') or '-',
            mounts,
            rec.get('model') or '-',
        ]
        item = QTreeWidgetItem(values)
        if parent is None: self.tree.addTopLevelItem(item)
        else: parent.addChild(item)
        data = dict(rec)
        data['disk_path'] = disk_path
        data['is_live_media'] = is_live
        self.records[id(item)] = data
        item.setData(0, Qt.ItemDataRole.UserRole, id(item))
        for child in rec.get('children') or []:
            self.add_node(item, child, disk_path)
        return item

    def refresh(self):
        self.tree.clear(); self.records.clear(); self.live_disk = live_media_disk()
        devices = scan_devices()
        for rec in devices:
            if rec.get('type') != 'disk':
                continue
            disk_path = rec.get('path') or ''
            self.add_node(None, rec, disk_path)
        self.tree.expandAll()
        self.use.setEnabled(False)
        self.details.setText(
            f'Live media: {self.live_disk or "not identified"}. Select a destination disk or partition.'
        )

    def current_record(self):
        items = self.tree.selectedItems()
        if not items: return None
        key = items[0].data(0, Qt.ItemDataRole.UserRole)
        return self.records.get(key)

    def selection_changed(self):
        rec = self.current_record()
        if not rec:
            self.use.setEnabled(False); return
        typ = rec.get('type') or ''
        path = rec.get('path') or ''
        allowed = typ in ('disk','part') and bool(path) and not rec.get('is_live_media')
        # Children on the Live USB share the same disk_path and are also blocked.
        if self.live_disk and rec.get('disk_path') == self.live_disk:
            allowed = False
        self.use.setEnabled(allowed)
        if rec.get('disk_path') == self.live_disk:
            self.details.setText('This device belongs to the MechOS Live USB and cannot be selected as the install target.')
        elif typ == 'disk':
            self.details.setText(f'{path} • whole disk • {human_size(rec.get("size"))}. Clean Install can use this target.')
        elif typ == 'part':
            fs = rec.get('fstype') or 'unknown filesystem'
            self.details.setText(
                f'{path} • existing partition • {human_size(rec.get("size"))} • {fs}. '
                'MechOS will use manual partitioning so formatting and mount points remain explicit.'
            )
        else:
            self.details.setText(f'{path or "Device"} is not a selectable disk/partition target.')

    def use_selected(self):
        rec = self.current_record()
        if not rec:
            return
        typ = rec.get('type') or ''
        path = rec.get('path') or ''
        disk_path = rec.get('disk_path') or path
        if typ not in ('disk','part') or not path:
            QMessageBox.warning(self, 'MechOS Installer', 'Select a whole disk or an existing partition.')
            return
        if self.live_disk and disk_path == self.live_disk:
            QMessageBox.warning(self, 'MechOS Installer', 'The MechOS Live USB cannot be selected as the install target.')
            return

        kind = 'disk' if typ == 'disk' else 'partition'
        message = (
            f'Use {path} as the MechOS install location?\n\n'
            + ('This selects the whole disk. No changes happen until the installer confirmation.' if kind == 'disk'
               else 'This selects an existing partition. MechOS will open manual partitioning before any disk changes.')
        )
        if QMessageBox.question(self, 'Confirm Install Location', message) != QMessageBox.StandardButton.Yes:
            return

        payload = {
            'kind': kind,
            'path': path,
            'disk': disk_path,
            'size_bytes': int(rec.get('size') or 0),
            'fstype': rec.get('fstype') or '',
            'label': rec.get('label') or '',
        }
        SELECTION_FILE.write_text(json.dumps(payload, indent=2), encoding='utf-8')
        self.close()


if __name__ == '__main__':
    app = QApplication(sys.argv)
    app.setApplicationName('MechOS Partition Selector')
    w = PartitionSelector(); w.showMaximized()
    raise SystemExit(app.exec())
PYEOF
chmod 755 "$BIN/mechos-partition-selector"

# Terminal handoff used after a graphical partition target has been selected.
# It deliberately keeps Archinstall's final partition summary and confirmation
# in the loop instead of applying destructive disk operations silently.
cat > "$BIN/mechos-install-selected-target" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SEL=/tmp/mechos-install-target.json
if [ ! -s "$SEL" ]; then
  echo "No graphical install location is selected." >&2
  exit 2
fi

readarray -t values < <(python3 - "$SEL" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding='utf-8'))
print(p.get('kind',''))
print(p.get('path',''))
print(p.get('disk',''))
print(p.get('fstype',''))
PY
)
KIND="${values[0]:-}"
TARGET="${values[1]:-}"
DISK="${values[2]:-}"
FSTYPE="${values[3]:-}"

clear 2>/dev/null || true
cat <<TXT
MECHOS — SELECTED INSTALL LOCATION
==================================
Selected: $TARGET
Parent disk: ${DISK:-unknown}
Type: $KIND
Filesystem: ${FSTYPE:-unknown}

The graphical partition screen only selected the destination. Archinstall still
shows the actual partition layout and requires confirmation before formatting.
TXT

if [ "$KIND" = "partition" ]; then
  cat <<TXT

Because an existing partition was selected, MechOS is opening MANUAL
partitioning. Select $TARGET, assign the intended root mount point, and choose
formatting only if you intend to erase that partition. Reuse an existing EFI
System Partition without formatting it when appropriate.
TXT
  read -rp "Press Enter to continue to manual partitioning, or Ctrl+C to cancel... " _
  exec /usr/local/bin/mechos-install --terminal --preserve-home
fi

if [ "$KIND" = "disk" ]; then
  cat <<TXT

The whole disk $TARGET was selected. In Archinstall, keep this disk selected and
review the final disk summary before confirming any erase/format operation.
TXT
  read -rp "Press Enter to continue, or Ctrl+C to cancel... " _
  exec /usr/local/bin/mechos-install --terminal
fi

echo "Invalid selection type: $KIND" >&2
exit 2
EOF
chmod 755 "$BIN/mechos-install-selected-target"

python3 - "$BIN/mechos-live-setup" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_PARTITION_SCREEN_V1'


def require(condition, message):
    if not condition:
        raise SystemExit('[MechOS Partition Screen] ' + message)


if marker not in text:
    # Imports for selection state + child process lifecycle.
    require('import os\n' in text, 'could not locate installer imports')
    text = text.replace('import os\n', 'import json\nimport os\n', 1)
    require('from PyQt6.QtCore import Qt, QSize\n' in text, 'could not locate QtCore import')
    text = text.replace('from PyQt6.QtCore import Qt, QSize\n', 'from PyQt6.QtCore import Qt, QSize, QProcess\n', 1)

    # Runtime state.
    init_anchor = '        self.selected_disk = self.disks[0][0] if self.disks else ""\n        self.install_mode = "clean"\n'
    require(init_anchor in text, 'could not locate installer target state')
    text = text.replace(
        init_anchor,
        '        self.selected_disk = self.disks[0][0] if self.disks else ""\n'
        '        self.selected_partition = ""\n'
        '        self.partition_process = None\n'
        '        self.install_mode = "clean"\n',
        1,
    )

    # Add a dedicated partition step in the left navigation.
    nav_old = '''        nav_items = [
            "1   WELCOME",
            "2   HARDWARE SCAN",
            "3   INSTALL",
            "4   REPAIR BOOT",
            "5   RECOVERY",
            "6   REINSTALL (KEEP HOME)",
            "7   INSTALL LOGS",
            "8   FINISH",
        ]
'''
    nav_new = '''        nav_items = [
            "1   WELCOME",
            "2   HARDWARE SCAN",
            "3   PARTITIONS",
            "4   INSTALL",
            "5   REPAIR BOOT",
            "6   RECOVERY",
            "7   REINSTALL (KEEP HOME)",
            "8   INSTALL LOGS",
            "9   FINISH",
        ]
'''
    require(nav_old in text, 'could not locate installer navigation list')
    text = text.replace(nav_old, nav_new, 1)

    target_anchor = '        center.addWidget(target_label)\n\n        self.disk_buttons = []\n'
    require(target_anchor in text, 'could not locate install-target heading')
    text = text.replace(
        target_anchor,
        '        center.addWidget(target_label)\n'
        '        partition_button = QPushButton("Partition Screen  •  Choose Disk / Partition")\n'
        '        partition_button.setObjectName("secondary")\n'
        '        partition_button.clicked.connect(self.partition_screen)\n'
        '        center.addWidget(partition_button)\n\n'
        '        self.disk_buttons = []\n',
        1,
    )
    text = text.replace('        target_label = QLabel("SELECT INSTALL TARGET")\n', '        target_label = QLabel("SELECT INSTALL LOCATION")\n', 1)

    # Show partition selection separately in the overview.
    overview_anchor = '        self.target_value = QLabel(self.selected_disk or "No disk selected")\n        self.mode_value = QLabel("Clean Install")\n'
    require(overview_anchor in text, 'could not locate install overview values')
    text = text.replace(
        overview_anchor,
        '        self.target_value = QLabel(self.selected_disk or "No disk selected")\n'
        '        self.partition_value = QLabel("Whole disk")\n'
        '        self.mode_value = QLabel("Clean Install")\n',
        1,
    )
    row_anchor = '            ("Target Drive", self.target_value),\n            ("Install Type", self.mode_value),\n'
    require(row_anchor in text, 'could not locate overview rows')
    text = text.replace(
        row_anchor,
        '            ("Target Drive", self.target_value),\n'
        '            ("Partition", self.partition_value),\n'
        '            ("Install Type", self.mode_value),\n',
        1,
    )

    # New partition lifecycle methods and whole-disk selection reset.
    method_anchor = '    def select_disk(self, dev, checked):\n'
    require(method_anchor in text, 'could not locate select_disk method')
    methods = '''    # MECHOS_PARTITION_SCREEN_V1
    def partition_screen(self):
        if self.partition_process is not None:
            return
        tool = "/usr/local/bin/mechos-partition-selector"
        if not os.path.exists(tool):
            QMessageBox.warning(self, "MechOS Installer", "Partition screen is unavailable in this image.")
            return
        self.partition_process = QProcess(self)
        self.partition_process.finished.connect(self.partition_finished)
        self.partition_process.start(tool, [])

    def partition_finished(self, *args):
        self.partition_process = None
        self.load_partition_selection()

    def load_partition_selection(self, silent=False):
        selection = "/tmp/mechos-install-target.json"
        if not os.path.exists(selection):
            return False
        try:
            data = json.loads(Path(selection).read_text(encoding="utf-8"))
        except Exception as exc:
            if not silent:
                QMessageBox.warning(self, "MechOS Installer", f"Could not read the selected install location:\\n{exc}")
            return False
        kind = data.get("kind", "")
        target = data.get("path", "")
        parent = data.get("disk", "") or target
        if kind not in ("disk", "partition") or not target:
            return False
        self.selected_disk = parent
        self.selected_partition = target if kind == "partition" else ""
        self.target_value.setText(parent)
        self.partition_value.setText(target if kind == "partition" else "Whole disk")
        if kind == "partition":
            # Existing partitions always go through Archinstall manual layout.
            self.install_mode = "custom"
            self.custom.setChecked(True)
            self.warning_text.setText(
                f"Selected partition: {target}. Manual partitioning will open so mount points and formatting remain explicit."
            )
        return True

'''
    text = text.replace(method_anchor, methods + method_anchor, 1)

    select_old = '''    def select_disk(self, dev, checked):
        if checked:
            self.selected_disk = dev
            self.target_value.setText(dev)
'''
    select_new = '''    def select_disk(self, dev, checked):
        if checked:
            self.selected_disk = dev
            self.selected_partition = ""
            self.target_value.setText(dev)
            self.partition_value.setText("Whole disk")
            try:
                Path("/tmp/mechos-install-target.json").unlink(missing_ok=True)
            except Exception:
                pass
'''
    require(select_old in text, 'could not locate select_disk body')
    text = text.replace(select_old, select_new, 1)

    # Navigation now opens the graphical partition screen before Install.
    nav_method_old = '''    def nav_selected(self, row):
        if row == 1:
            subprocess.Popen(["konsole","-e","bash","-lc",
                "/usr/local/bin/mechos-hardware-scan; echo; read -rp 'Press Enter to close...'"])
        elif row == 2:
            self.install()
        elif row == 3:
            self.recovery()
        elif row == 4:
            self.recovery()
        elif row == 5:
            self.install_mode = "keep"
            self.keep.setChecked(True)
            self.install()
        elif row == 6:
            subprocess.Popen(["konsole","-e","bash","-lc",
                "/usr/local/bin/mechos-recovery-helper logs; echo; read -rp 'Press Enter to close...'"])
        elif row == 7:
            self.close()
'''
    nav_method_new = '''    def nav_selected(self, row):
        if row == 1:
            subprocess.Popen(["konsole","-e","bash","-lc",
                "/usr/local/bin/mechos-hardware-scan; echo; read -rp 'Press Enter to close...'"])
        elif row == 2:
            self.partition_screen()
        elif row == 3:
            self.install()
        elif row == 4:
            self.recovery()
        elif row == 5:
            self.recovery()
        elif row == 6:
            self.install_mode = "keep"
            self.keep.setChecked(True)
            self.install()
        elif row == 7:
            subprocess.Popen(["konsole","-e","bash","-lc",
                "/usr/local/bin/mechos-recovery-helper logs; echo; read -rp 'Press Enter to close...'"])
        elif row == 8:
            self.close()
'''
    require(nav_method_old in text, 'could not locate installer navigation handler')
    text = text.replace(nav_method_old, nav_method_new, 1)

    # Respect the graphical selection when installation starts. Partition
    # targets use the manual layout path; whole-disk targets still get the
    # normal Archinstall final confirmation.
    install_anchor = '    def install(self):\n        if not self.selected_disk and self.install_mode == "clean":\n'
    require(install_anchor in text, 'could not locate installer launch method')
    text = text.replace(
        install_anchor,
        '    def install(self):\n'
        '        self.load_partition_selection(silent=True)\n'
        '        if self.selected_partition:\n'
        '            answer = QMessageBox.question(\n'
        '                self, "Install MechOS",\n'
        '                f"Continue with selected partition {self.selected_partition}?\\n\\n"\n'
        '                "Archinstall manual partitioning will open and still requires confirmation before formatting."\n'
        '            )\n'
        '            if answer != QMessageBox.StandardButton.Yes:\n'
        '                return\n'
        '            subprocess.Popen(["konsole","-e","sudo","/usr/local/bin/mechos-install-selected-target"])\n'
        '            return\n\n'
        '        if not self.selected_disk and self.install_mode == "clean":\n',
        1,
    )

    path.write_text(text, encoding='utf-8')

patched = path.read_text(encoding='utf-8')
for required in (
    '# MECHOS_PARTITION_SCREEN_V1',
    'Partition Screen  •  Choose Disk / Partition',
    '"3   PARTITIONS"',
    'mechos-partition-selector',
    'mechos-install-selected-target',
):
    require(required in patched, f'graphical installer is missing marker: {required}')
PY

# Keep executable permissions explicit in ArchISO.
if [ -f "$PROFILE" ]; then
  for path in /usr/local/bin/mechos-partition-selector /usr/local/bin/mechos-install-selected-target; do
    if ! grep -Fq "file_permissions[\"$path\"]" "$PROFILE"; then
      printf '\nfile_permissions["%s"]="0:0:755"\n' "$path" >> "$PROFILE"
    fi
  done
fi

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$BIN/mechos-partition-selector" \
  || fail "partition selector Python validation failed"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$BIN/mechos-live-setup" \
  || fail "graphical installer Python validation failed"
bash -n "$BIN/mechos-install-selected-target" \
  || fail "selected-target helper shell validation failed"
grep -Fq 'MECHOS_PARTITION_SCREEN_V1' "$BIN/mechos-live-setup" \
  || fail "partition screen integration marker is missing"
grep -Fq 'SELECT INSTALL LOCATION' "$BIN/mechos-live-setup" \
  || fail "install-location heading is missing"

log "graphical disk/partition selection screen added to Live installer"
