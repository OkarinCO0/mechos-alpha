#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"

log() { printf '[MechOS Redragon RGB] %s\n' "$*"; }
fail() { printf '[MechOS Redragon RGB] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Redragon RGB] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -s "$ARCHIVE" ] || fail "installed-system payload archive is missing: $ARCHIVE"

patch_rgb_helper() {
  local tree="$1"
  local helper="$tree/usr/local/bin/mechos-rgb-keyboard"
  [ -f "$helper" ] || fail "RGB helper is missing: $helper"

  python3 - "$helper" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "# MECHOS_REDRAGON_K580_RGB_COMPAT_V1"
if marker in text:
    raise SystemExit(0)

old_hints = '("keyboard", "keychron", "kbd", "huntsman", "blackwidow", "k100", "k95", "k70", "g915", "g815")'
new_hints = '("keyboard", "keychron", "kbd", "huntsman", "blackwidow", "k100", "k95", "k70", "g915", "g815", "redragon", "red dragon", "vata", "k580", "evision", "sonix", "microdia")'
if old_hints not in text:
    raise SystemExit(f"RGB keyboard hint list not found in {path}")
text = text.replace(old_hints, new_hints, 1)

old_advanced = '''def advanced():\n    if not shutil.which("openrgb"):\n        return 2\n    subprocess.Popen(["openrgb"], start_new_session=True)\n    return 0\n\n\ndef status():\n'''
new_advanced = '''def diagnostics():\n    tool = "/usr/local/bin/mechos-rgb-diagnostics"\n    if not Path(tool).is_file():\n        print("MechOS RGB diagnostics tool is missing.", file=sys.stderr)\n        return 2\n    subprocess.Popen(["konsole", "-e", "bash", "-lc", f"{tool}; echo; read -rp 'Press Enter to close...'"], start_new_session=True)\n    return 0\n\n\ndef advanced():\n    if not shutil.which("openrgb"):\n        return 2\n    subprocess.Popen(["openrgb"], start_new_session=True)\n    return 0\n\n\ndef status():\n'''
if old_advanced not in text:
    raise SystemExit(f"RGB advanced/status integration point not found in {path}")
text = text.replace(old_advanced, new_advanced, 1)

old_main = '''    if command == "advanced":\n        return advanced()\n    if command == "status":\n        return status()\n    print("Usage: mechos-rgb-keyboard {status|picker|advanced|restore|set RRGGBB}", file=sys.stderr)\n'''
new_main = '''    if command == "advanced":\n        return advanced()\n    if command == "diagnostics":\n        return diagnostics()\n    if command == "status":\n        return status()\n    print("Usage: mechos-rgb-keyboard {status|picker|advanced|diagnostics|restore|set RRGGBB}", file=sys.stderr)\n'''
if old_main not in text:
    raise SystemExit(f"RGB command dispatcher not found in {path}")
text = text.replace(old_main, new_main, 1)

# Keep the interpreter first so the helper remains directly executable.
lines = text.splitlines(True)
insert_at = 1 if lines and lines[0].startswith("#!") else 0
lines.insert(insert_at, marker + "\n")
path.write_text("".join(lines), encoding="utf-8")
PY

  python3 -m py_compile "$helper" || fail "RGB helper syntax failed after K580 compatibility patch"
  grep -Fq '"k580"' "$helper" || fail "K580 detection hint was not added"
  grep -Fq '"evision"' "$helper" || fail "EVision detection hint was not added"
}

install_diagnostics() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local apps="$tree/usr/share/applications"
  mkdir -p "$bin" "$apps"

  cat > "$bin/mechos-rgb-diagnostics" <<'EOF'
#!/usr/bin/env bash
set +e

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
REPORT="$STATE_DIR/rgb-diagnostics.txt"
mkdir -p "$STATE_DIR"

{
  echo "MECHOS RGB DIAGNOSTICS"
  echo "Generated: $(date -Is 2>/dev/null || date)"
  echo
  echo "Target model: Redragon VATA K580RGB compatibility"
  echo
  echo "== OpenRGB =="
  if command -v openrgb >/dev/null 2>&1; then
    openrgb --version 2>&1 | head -n 4
  else
    echo "OpenRGB: missing"
  fi
  echo
  echo "== OpenRGB udev rules =="
  for rule in /usr/lib/udev/rules.d/60-openrgb.rules /etc/udev/rules.d/60-openrgb.rules; do
    if [ -f "$rule" ]; then
      echo "[OK] $rule"
    else
      echo "[MISSING] $rule"
    fi
  done
  echo
  echo "== USB keyboard/controller candidates =="
  if command -v lsusb >/dev/null 2>&1; then
    lsusb | grep -Ei 'redragon|red dragon|sonix|microdia|evision|0c45' || echo "No Redragon/Sonix/Microdia candidate found by lsusb."
  else
    echo "lsusb is unavailable."
  fi
  echo
  echo "== HID raw access =="
  found=0
  for dev in /dev/hidraw*; do
    [ -e "$dev" ] || continue
    found=1
    ls -l "$dev"
  done
  [ "$found" -eq 1 ] || echo "No /dev/hidraw devices found."
  echo
  echo "== OpenRGB devices =="
  if command -v openrgb >/dev/null 2>&1; then
    timeout 12s openrgb --list-devices 2>&1
    echo "OpenRGB exit code: ${PIPESTATUS[0]}"
  else
    echo "OpenRGB is unavailable."
  fi
  echo
  echo "== MechOS notes =="
  echo "K580 hardware revisions are not guaranteed to use the same controller."
  echo "MechOS does not flash keyboard firmware automatically."
  echo "If OpenRGB reports an EVision Keyboard, MechOS now treats EVision/Redragon/VATA/K580 names as keyboard devices."
  echo "If no keyboard appears above, the USB VID:PID from this report is needed before adding a model-specific detector."
} | tee "$REPORT"

echo
echo "Saved: $REPORT"
EOF
  chmod 755 "$bin/mechos-rgb-diagnostics"

  cat > "$apps/mechos-rgb-diagnostics.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS RGB Diagnostics
Comment=Check OpenRGB, HID permissions and Redragon keyboard detection
Exec=konsole -e bash -lc '/usr/local/bin/mechos-rgb-diagnostics; echo; read -rp "Press Enter to close..."'
Icon=input-keyboard
Terminal=false
Categories=System;Settings;
Keywords=MechOS;RGB;OpenRGB;Redragon;VATA;K580;Keyboard;
EOF
}

patch_quick_actions() {
  local tree="$1"
  local target="$tree/usr/local/bin/mechos-quick-actions"
  [ -f "$target" ] || return 0

  python3 - "$target" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "# MECHOS_REDRAGON_K580_QUICK_ACTIONS_V1"
if marker in text:
    raise SystemExit(0)

needle = '        lir.addWidget(self.button("Advanced RGB", lambda:spawn(["/usr/local/bin/mechos-rgb-keyboard","advanced"])),1,1)\n'
insert = needle + '        # MECHOS_REDRAGON_K580_QUICK_ACTIONS_V1\n        lir.addWidget(self.button("RGB Diagnostics", lambda:spawn(["/usr/local/bin/mechos-rgb-keyboard","diagnostics"])),2,0,1,2)\n'
if needle not in text:
    raise SystemExit(0)
text = text.replace(needle, insert, 1)
path.write_text(text, encoding="utf-8")
PY

  python3 -m py_compile "$target" || fail "Quick Actions syntax failed after RGB diagnostics patch"
}

patch_tree() {
  local tree="$1"
  patch_rgb_helper "$tree"
  install_diagnostics "$tree"
  patch_quick_actions "$tree"
}

patch_tree "$ROOT"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
tar --zstd -xpf "$ARCHIVE" -C "$TMP"
patch_tree "$TMP"

new_archive="$ARCHIVE.redragon-k580-rgb"
tar --zstd -cpf "$new_archive" -C "$TMP" .
mv -f "$new_archive" "$ARCHIVE"
rm -rf "$TMP"
trap - EXIT

[ -x "$ROOT/usr/local/bin/mechos-rgb-diagnostics" ] || fail "Live RGB diagnostics helper missing"
grep -Fq 'MECHOS_REDRAGON_K580_RGB_COMPAT_V1' "$ROOT/usr/local/bin/mechos-rgb-keyboard" \
  || fail "Live K580 compatibility marker missing"

log "Redragon VATA K580RGB detection hints and RGB diagnostics added without firmware flashing"
