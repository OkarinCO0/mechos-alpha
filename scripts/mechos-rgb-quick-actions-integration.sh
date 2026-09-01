#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PACKAGES="/workspace/archlive/packages.x86_64"
PAYLOAD_DIR="$ROOT/usr/share/mechos/install-payload"
POSTINSTALL="$PAYLOAD_DIR/mechos-postinstall-target"
ROOTFS_ARCHIVE="$PAYLOAD_DIR/mechos-rootfs.tar.zst"
MARKER="# MECHOS_RGB_KEYBOARD_QUICK_ACTIONS_V1"

log() { printf '[MechOS RGB] %s\n' "$*"; }
fail() { printf '[MechOS RGB] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS RGB] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -f "$PACKAGES" ] || fail "ArchISO package list is missing: $PACKAGES"
[ -s "$POSTINSTALL" ] || fail "installed-system postinstall target is missing"
[ -s "$ROOTFS_ARCHIVE" ] || fail "installed-system payload archive is missing"

# OpenRGB is core MechOS hardware support, not a Creator Mode application.
if ! grep -qxF 'openrgb' "$PACKAGES"; then
  printf '%s\n' 'openrgb' >> "$PACKAGES"
fi

patch_postinstall_packages() {
  local file="$1"
  python3 - "$file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
if " openrgb " in text or " openrgb \\\n" in text:
    raise SystemExit(0)
needle = "python-pyqt6 brightnessctl \\\n"
replacement = "python-pyqt6 brightnessctl openrgb \\\n"
if needle not in text:
    raise SystemExit(f"OpenRGB post-install package integration point not found in {path}")
path.write_text(text.replace(needle, replacement, 1))
PY
}

install_rgb_stack() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local autostart="$tree/etc/xdg/autostart"
  mkdir -p "$bin" "$autostart"

  cat > "$bin/mechos-rgb-keyboard" <<'PYEOF'
#!/usr/bin/env python3
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

CONFIG = Path.home() / ".config/mechos/rgb-keyboard.json"


def run(args):
    try:
        return subprocess.run(args, text=True, capture_output=True, check=False)
    except Exception:
        return None


def list_keyboard_devices():
    if not shutil.which("openrgb"):
        return []
    proc = run(["openrgb", "--list-devices"])
    if not proc or proc.returncode != 0:
        return []
    text = (proc.stdout or "") + "\n" + (proc.stderr or "")
    headers = list(re.finditer(r"(?m)^\s*(\d+):\s*(.+?)\s*$", text))
    devices = []
    for i, match in enumerate(headers):
        start = match.start()
        end = headers[i + 1].start() if i + 1 < len(headers) else len(text)
        block = text[start:end]
        index = int(match.group(1))
        name = match.group(2).strip()
        low = block.lower()
        # Prefer OpenRGB's reported device type. Name hints are a fallback for
        # devices whose controller does not expose a Type line.
        is_keyboard = "type:" in low and "keyboard" in low
        if not is_keyboard:
            hints = ("keyboard", "keychron", "kbd", "huntsman", "blackwidow", "k100", "k95", "k70", "g915", "g815")
            is_keyboard = any(hint in name.lower() for hint in hints)
        if is_keyboard:
            devices.append((index, name))
    return devices


def normalize_color(raw):
    color = raw.strip().lstrip("#").upper()
    if not re.fullmatch(r"[0-9A-F]{6}", color):
        raise ValueError("Color must be a 6-digit RGB hex value")
    return color


def set_color(raw, save=True):
    color = normalize_color(raw)
    if not shutil.which("openrgb"):
        print("OpenRGB is not installed.", file=sys.stderr)
        return 2
    devices = list_keyboard_devices()
    if not devices:
        print("No supported RGB keyboard was detected by OpenRGB.", file=sys.stderr)
        return 3

    successes = 0
    for index, name in devices:
        proc = run([
            "openrgb", "--device", str(index),
            "--mode", "static", "--color", color,
        ])
        if proc and proc.returncode == 0:
            successes += 1
        else:
            detail = ((proc.stderr if proc else "") or "").strip()
            print(f"Could not set {name}: {detail}", file=sys.stderr)

    if successes and save:
        CONFIG.parent.mkdir(parents=True, exist_ok=True)
        CONFIG.write_text(json.dumps({"color": color}, indent=2) + "\n")
    return 0 if successes else 4


def restore():
    if not CONFIG.is_file():
        return 0
    try:
        color = json.loads(CONFIG.read_text()).get("color", "")
    except Exception:
        return 0
    if not color:
        return 0
    return set_color(color, save=False)


def picker():
    from PyQt6.QtGui import QColor
    from PyQt6.QtWidgets import QApplication, QColorDialog, QMessageBox

    app = QApplication.instance() or QApplication(sys.argv)
    initial = QColor("#7C3FFF")
    if CONFIG.is_file():
        try:
            saved = json.loads(CONFIG.read_text()).get("color", "")
            if saved:
                initial = QColor("#" + saved)
        except Exception:
            pass

    color = QColorDialog.getColor(initial, None, "MechOS Keyboard RGB Color")
    if not color.isValid():
        return 0
    value = color.name().lstrip("#").upper()
    rc = set_color(value)
    if rc == 0:
        QMessageBox.information(None, "MechOS RGB", f"Keyboard RGB set to #{value}.")
    elif rc == 2:
        QMessageBox.warning(None, "MechOS RGB", "OpenRGB is not installed on this MechOS system.")
    elif rc == 3:
        QMessageBox.information(
            None,
            "MechOS RGB",
            "No supported RGB keyboard was detected. Open Advanced RGB Controls to check whether OpenRGB recognizes the device.",
        )
    else:
        QMessageBox.warning(None, "MechOS RGB", "The keyboard was detected, but the RGB color could not be applied.")
    return rc


def advanced():
    if not shutil.which("openrgb"):
        return 2
    subprocess.Popen(["openrgb"], start_new_session=True)
    return 0


def status():
    devices = list_keyboard_devices()
    if not shutil.which("openrgb"):
        print("missing-openrgb")
    elif devices:
        print("ready")
        for index, name in devices:
            print(f"{index}: {name}")
    else:
        print("no-keyboard")
    return 0


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    if command == "set" and len(sys.argv) == 3:
        return set_color(sys.argv[2])
    if command == "restore":
        return restore()
    if command == "picker":
        return picker()
    if command == "advanced":
        return advanced()
    if command == "status":
        return status()
    print("Usage: mechos-rgb-keyboard {status|picker|advanced|restore|set RRGGBB}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
PYEOF
  chmod 755 "$bin/mechos-rgb-keyboard"

  cat > "$bin/mechos-rgb-restore" <<'EOF'
#!/usr/bin/env bash
set +e
sleep 4
exec /usr/local/bin/mechos-rgb-keyboard restore
EOF
  chmod 755 "$bin/mechos-rgb-restore"

  cat > "$autostart/mechos-rgb-restore.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS RGB Profile Restore
Comment=Restore the user's keyboard RGB color after graphical login
Exec=/usr/local/bin/mechos-rgb-restore
Terminal=false
OnlyShowIn=KDE;
X-GNOME-Autostart-enabled=true
EOF
}

patch_quick_actions() {
  local tree="$1"
  local target="$tree/usr/local/bin/mechos-quick-actions"
  [ -s "$target" ] || fail "Quick Actions target missing: $target"

  python3 - "$target" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
marker = "# MECHOS_RGB_KEYBOARD_QUICK_ACTIONS_V1"
if marker in text:
    raise SystemExit(0)

needle = '''        outer.addWidget(display)\n\n        connectivity = self.panel()\n'''
insert = '''        outer.addWidget(display)\n\n        # MECHOS_RGB_KEYBOARD_QUICK_ACTIONS_V1\n        lighting = self.panel()\n        lil = QVBoxLayout(lighting)\n        lih = QLabel("KEYBOARD RGB")\n        lih.setObjectName("section")\n        lil.addWidget(lih)\n        lir = QGridLayout()\n        lir.addWidget(self.button("Change Color", lambda:spawn(["/usr/local/bin/mechos-rgb-keyboard","picker"])),0,0)\n        lir.addWidget(self.button("MechOS Purple", lambda:spawn(["/usr/local/bin/mechos-rgb-keyboard","set","7C3FFF"])),0,1)\n        lir.addWidget(self.button("White", lambda:spawn(["/usr/local/bin/mechos-rgb-keyboard","set","FFFFFF"])),1,0)\n        lir.addWidget(self.button("Advanced RGB", lambda:spawn(["/usr/local/bin/mechos-rgb-keyboard","advanced"])),1,1)\n        lil.addLayout(lir)\n        lin = QLabel("Uses OpenRGB when the connected keyboard is supported. Your selected color is restored after login and stays active while switching between Desktop and MechScope.")\n        lin.setObjectName("muted")\n        lin.setWordWrap(True)\n        lil.addWidget(lin)\n        outer.addWidget(lighting)\n\n        connectivity = self.panel()\n'''
if needle not in text:
    raise SystemExit(f"Quick Actions display/connectivity integration point not found in {path}")
path.write_text(text.replace(needle, insert, 1))
PY

  python3 -m py_compile "$target"
  grep -qF "$MARKER" "$target" || fail "RGB marker missing after patch: $target"
}

patch_postinstall_packages "$POSTINSTALL"
install_rgb_stack "$ROOT"
patch_quick_actions "$ROOT"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

tar --zstd -xpf "$ROOTFS_ARCHIVE" -C "$TMP"
install_rgb_stack "$TMP"
patch_quick_actions "$TMP"

tar --zstd -cpf "$ROOTFS_ARCHIVE.new" -C "$TMP" .
mv -f "$ROOTFS_ARCHIVE.new" "$ROOTFS_ARCHIVE"

# Final assertions cover both the Live environment and the installed payload.
grep -qxF 'openrgb' "$PACKAGES" || fail "OpenRGB missing from Live package list"
grep -q 'brightnessctl openrgb' "$POSTINSTALL" || fail "OpenRGB missing from installed-system package list"
[ -x "$ROOT/usr/local/bin/mechos-rgb-keyboard" ] || fail "Live RGB helper missing"
grep -qF "$MARKER" "$ROOT/usr/local/bin/mechos-quick-actions" || fail "Live Quick Actions RGB control missing"

log "OpenRGB keyboard support and Quick Actions color controls are integrated"
