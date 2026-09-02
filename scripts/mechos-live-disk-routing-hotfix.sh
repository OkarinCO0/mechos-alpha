#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
BIN="$ROOT/usr/local/bin"
PROFILE="/workspace/archlive/profiledef.sh"

log() { printf '[MechOS Live Disk Routing] %s\n' "$*"; }
fail() { printf '[MechOS Live Disk Routing] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Live Disk Routing] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -f "$BIN/mechos-live-setup" ] || fail "graphical Live installer is missing"
[ -x "$BIN/mechos-native-install" ] || fail "native MechOS installer launcher is missing"

# The original disk_list() parsed NAME,SIZE,MODEL,TYPE with whitespace fields.
# Models such as "VBOX HARDDISK" or "VMware Virtual disk" contain spaces, so
# TYPE shifted to another field and the UI incorrectly reported no disks.
python3 - "$BIN/mechos-live-setup" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
pattern = re.compile(r"def disk_list\(\):\n.*?\n    return disks\n", re.S)
replacement = '''def disk_list():
    # Read TYPE separately from MODEL so multi-word virtual/physical disk model
    # names cannot shift columns. This works with VirtualBox, VMware, SATA,
    # NVMe and USB-attached destination disks.
    live_source = cmd_output(["findmnt", "-n", "-o", "SOURCE", "/run/archiso/bootmnt"])
    live_disk = ""
    if live_source.startswith("/dev/"):
        parent = cmd_output(["lsblk", "-ndo", "PKNAME", live_source])
        live_disk = f"/dev/{parent}" if parent else live_source

    out = cmd_output(["lsblk", "-dnpo", "NAME,SIZE,TYPE"])
    disks = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 3 or parts[-1] != "disk":
            continue
        dev, size = parts[0], parts[1]
        if live_disk and dev == live_disk:
            continue
        model = cmd_output(["lsblk", "-dnpo", "MODEL", dev]).strip() or "Disk"
        disks.append((dev, size, model))
    return disks
'''

if not pattern.search(text):
    raise SystemExit('[MechOS Live Disk Routing] could not locate disk_list()')
text = pattern.sub(replacement, text, count=1)
path.write_text(text, encoding='utf-8')
PY

# Belt-and-suspenders routing: even if an older GUI hook calls the selected-
# target helper, a whole-disk Clean Install is forced into the native MechOS
# installer and can never fall through to Archinstall.
cat > "$BIN/mechos-install-selected-target" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
SEL=/tmp/mechos-install-target.json

[ -s "$SEL" ] || { echo "No MechOS install target has been selected." >&2; exit 2; }
readarray -t values < <(python3 - "$SEL" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding='utf-8'))
print(p.get('kind',''))
print(p.get('path',''))
PY
)
KIND="${values[0]:-}"
TARGET="${values[1]:-}"

case "$KIND" in
  disk)
    exec /usr/local/bin/mechos-native-install
    ;;
  partition)
    echo "Existing-partition Clean Install is not allowed through the whole-disk installer." >&2
    echo "Use Update / Reinstall (Keep Home) for an existing MechOS install, or choose a whole disk for Clean Install." >&2
    exit 2
    ;;
  *)
    echo "Invalid MechOS install target: ${TARGET:-unknown}" >&2
    exit 2
    ;;
esac
EOF
chmod 755 "$BIN/mechos-install-selected-target"

if [ -f "$PROFILE" ] && ! grep -Fq 'file_permissions["/usr/local/bin/mechos-install-selected-target"]' "$PROFILE"; then
  printf '\nfile_permissions["/usr/local/bin/mechos-install-selected-target"]="0:0:755"\n' >> "$PROFILE"
fi

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$BIN/mechos-live-setup" \
  || fail "graphical installer syntax failed after disk-detection repair"
bash -n "$BIN/mechos-install-selected-target" \
  || fail "selected-target native dispatcher syntax failed"
grep -Fq 'lsblk", "-dnpo", "NAME,SIZE,TYPE"' "$BIN/mechos-live-setup" \
  || fail "model-safe disk scan was not installed"
grep -Fq 'exec /usr/local/bin/mechos-native-install' "$BIN/mechos-install-selected-target" \
  || fail "whole-disk native dispatcher is missing"
if grep -Eq '^[[:space:]]*(exec[[:space:]]+)?archinstall([[:space:]]|$)' "$BIN/mechos-install-selected-target"; then
  fail "selected-target dispatcher still contains an executable Archinstall handoff"
fi

log "VirtualBox/VMware-safe disk detection installed; whole-disk routing is native-only"
