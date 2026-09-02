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
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_REDRAGON_K580_RGB_COMPAT_V2'

# Current MechOS already contains a Redragon hint in some builds. Extend the
# existing tuple structurally instead of depending on quote style or an exact
# historical tuple.
hint_match = re.search(r'(?m)^(?P<indent>\s*)hints\s*=\s*\((?P<body>[^)]*)\)', text)
if not hint_match:
    raise SystemExit(f'RGB keyboard hint tuple not found in {path}')

existing = re.findall(r"['\"]([^'\"]+)['\"]", hint_match.group('body'))
required = [
    'keyboard', 'keychron', 'kbd', 'huntsman', 'blackwidow',
    'k100', 'k95', 'k70', 'g915', 'g815',
    'redragon', 'red dragon', 'vata', 'k580', 'evision', 'sonix', 'microdia',
]
items = []
for item in existing + required:
    if item not in items:
        items.append(item)
replacement = hint_match.group('indent') + 'hints = (' + ', '.join(repr(x) for x in items) + ')'
text = text[:hint_match.start()] + replacement + text[hint_match.end():]

# Add diagnostics without depending on whether the helper uses single or
# double quotes.
if 'def diagnostics():' not in text:
    advanced = re.search(r'(?m)^def advanced\(\):\s*$', text)
    if not advanced:
        raise SystemExit(f'RGB advanced() integration point not found in {path}')
    diagnostics = '''def diagnostics():
    tool = '/usr/local/bin/mechos-rgb-diagnostics'
    if not Path(tool).is_file():
        print('MechOS RGB diagnostics tool is missing.', file=sys.stderr)
        return 2
    subprocess.Popen([
        'konsole', '-e', 'bash', '-lc',
        f"{tool}; echo; read -rp 'Press Enter to close...'",
    ], start_new_session=True)
    return 0


'''
    text = text[:advanced.start()] + diagnostics + text[advanced.start():]

if not re.search(r"command\s*==\s*['\"]diagnostics['\"]", text):
    status_cmd = re.search(r"(?m)^(?P<indent>\s*)if command == ['\"]status['\"]:\s*$", text)
    if not status_cmd:
        raise SystemExit(f'RGB command dispatcher/status branch not found in {path}')
    indent = status_cmd.group('indent')
    dispatch = indent + "if command == 'diagnostics':\n" + indent + "    return diagnostics()\n"
    text = text[:status_cmd.start()] + dispatch + text[status_cmd.start():]

text = text.replace(
    '{status|picker|advanced|restore|set RRGGBB}',
    '{status|picker|advanced|diagnostics|restore|set RRGGBB}',
)

# Keep exactly one current compatibility marker directly after the shebang.
text = text.replace('# MECHOS_REDRAGON_K580_RGB_COMPAT_V1\n', '')
text = text.replace(marker + '\n', '')
lines = text.splitlines(True)
insert_at = 1 if lines and lines[0].startswith('#!') else 0
lines.insert(insert_at, marker + '\n')
path.write_text(''.join(lines), encoding='utf-8')
PY

  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$helper" \
    || fail "RGB helper syntax failed after K580 compatibility patch"
  grep -Eq "['\"]k580['\"]" "$helper" || fail "K580 detection hint was not added"
  grep -Eq "['\"]evision['\"]" "$helper" || fail "EVision detection hint was not added"
  grep -Fq "def diagnostics():" "$helper" || fail "RGB diagnostics dispatcher was not added"
  grep -Eq "command[[:space:]]*==[[:space:]]*['\"]diagnostics['\"]" "$helper" \
    || fail "RGB diagnostics command was not added"
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
  echo "If OpenRGB reports an EVision Keyboard, MechOS treats EVision/Redragon/VATA/K580 names as keyboard devices."
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
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_REDRAGON_K580_QUICK_ACTIONS_V2'
if marker in text or 'RGB Diagnostics' in text:
    raise SystemExit(0)

lines = text.splitlines(True)
inserted = False
for index, line in enumerate(lines):
    if 'Advanced RGB' not in line or 'mechos-rgb-keyboard' not in line:
        continue
    indent = line[:len(line) - len(line.lstrip())]
    block = (
        indent + marker + '\n' +
        indent + 'lir.addWidget(self.button("RGB Diagnostics", lambda:spawn(["/usr/local/bin/mechos-rgb-keyboard","diagnostics"])),2,0,1,2)\n'
    )
    lines.insert(index + 1, block)
    inserted = True
    break

# Quick Actions may be post-install-only or may have moved this control in a
# future reference layout. That must not block the ISO as long as the helper
# and diagnostics app are valid.
if inserted:
    path.write_text(''.join(lines), encoding='utf-8')
PY

  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$target" \
    || fail "Quick Actions syntax failed after RGB diagnostics patch"
}

patch_tree() {
  local tree="$1"
  patch_rgb_helper "$tree"
  install_diagnostics "$tree"
  patch_quick_actions "$tree"
}

patch_tree "$ROOT"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

tar --zstd -xpf "$ARCHIVE" -C "$TMP"
patch_tree "$TMP"

new_archive="$ARCHIVE.redragon-k580-rgb"
tar --zstd -cpf "$new_archive" -C "$TMP" .
mv -f "$new_archive" "$ARCHIVE"
rm -rf "$TMP"
trap - EXIT

[ -x "$ROOT/usr/local/bin/mechos-rgb-diagnostics" ] || fail "Live RGB diagnostics helper missing"
grep -Fq 'MECHOS_REDRAGON_K580_RGB_COMPAT_V2' "$ROOT/usr/local/bin/mechos-rgb-keyboard" \
  || fail "Live K580 compatibility marker missing"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$ROOT/usr/local/bin/mechos-rgb-keyboard" \
  || fail "Final Live RGB helper syntax validation failed"

log "Redragon VATA K580RGB detection hints and RGB diagnostics added without firmware flashing"
