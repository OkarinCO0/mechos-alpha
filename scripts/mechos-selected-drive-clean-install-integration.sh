#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
BIN="$ROOT/usr/local/bin"
PROFILE="/workspace/archlive/profiledef.sh"

log() { printf '[MechOS Selected Drive Install] %s\n' "$*"; }
fail() { printf '[MechOS Selected Drive Install] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Selected Drive Install] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -f "$BIN/mechos-partition-selector" ] || fail "partition selector is missing"
[ -f "$BIN/mechos-install-selected-target" ] || fail "selected-target helper is missing"

# Make the graphical text match the new whole-disk behavior. Existing partition
# selections remain a manual/alongside path; only a whole-disk Clean Install is
# automatically erased and partitioned.
python3 - "$BIN/mechos-partition-selector" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
text = text.replace(
    'This screen is read-only: selecting a location does not format, resize, or delete anything.',
    'Selecting a location does not change the disk immediately. A whole-disk Clean Install is erased and partitioned only after the final confirmation.'
)
text = text.replace(
    'Whole disk: can be used with Clean Install.  Existing partition: MechOS switches to manual ',
    'Whole disk: Clean Install erases that selected disk and automatically creates the MechOS partitions.  Existing partition: MechOS switches to manual '
)
text = text.replace(
    "Clean Install can use this target.",
    "Clean Install will erase, partition, format, and install MechOS on this selected disk after final confirmation."
)
text = text.replace(
    "This selects the whole disk. No changes happen until the installer confirmation.",
    "This selects the whole disk. Clean Install will erase every existing partition on this disk after the final confirmation, then create the MechOS boot and root partitions and install to this disk."
)
path.write_text(text, encoding='utf-8')
PY

cat > "$BIN/mechos-install-selected-target" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

SEL=/tmp/mechos-install-target.json
PAYLOAD_DIR=/usr/share/mechos/install-payload
BASE_CONFIG="$PAYLOAD_DIR/archinstall-mechos.json"
AUTO_CONFIG=/tmp/mechos-selected-drive-archinstall.json
CREDS=/tmp/mechos-selected-drive-creds.json
PORT=45811
MNT=/mnt

fail() { echo "MechOS installer: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
[ -s "$SEL" ] || fail "No graphical install location is selected."
[ -s "$BASE_CONFIG" ] || fail "MechOS Archinstall configuration is missing."
[ -s "$PAYLOAD_DIR/mechos-rootfs.tar.zst" ] || fail "MechOS installed-system payload is missing."
[ -x "$PAYLOAD_DIR/mechos-postinstall-target" ] || fail "MechOS post-install helper is missing."

readarray -t values < <(python3 - "$SEL" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding='utf-8'))
print(p.get('kind',''))
print(p.get('path',''))
print(p.get('disk',''))
print(int(p.get('size_bytes') or 0))
PY
)
KIND="${values[0]:-}"
TARGET="${values[1]:-}"
DISK="${values[2]:-}"
SIZE_BYTES="${values[3]:-0}"

# Existing partition/alongside installs stay on the manual path. This helper
# only performs automatic destructive partitioning for a selected whole disk.
if [ "$KIND" = "partition" ]; then
  echo "Existing partition selected: $TARGET"
  echo "Opening the manual/preserve path so MechOS does not erase the parent disk."
  exec /usr/local/bin/mechos-install --terminal --preserve-home
fi

[ "$KIND" = "disk" ] || fail "Invalid selection type: $KIND"
[ -n "$DISK" ] && [ "$TARGET" = "$DISK" ] || fail "Whole-disk selection is inconsistent."
[ -b "$DISK" ] || fail "Selected target is no longer a block device: $DISK"
[ "$(lsblk -ndo TYPE "$DISK" 2>/dev/null || true)" = "disk" ] || fail "Selected target is not a whole disk: $DISK"

# Re-identify the Live USB at the last possible moment. Never trust stale UI
# state for a destructive operation.
LIVE_SOURCE="$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
LIVE_DISK=""
if [[ "$LIVE_SOURCE" == /dev/* ]]; then
  LIVE_PARENT="$(lsblk -ndo PKNAME "$LIVE_SOURCE" 2>/dev/null || true)"
  if [ -n "$LIVE_PARENT" ]; then
    LIVE_DISK="/dev/$LIVE_PARENT"
  else
    LIVE_DISK="$LIVE_SOURCE"
  fi
fi
[ -z "$LIVE_DISK" ] || [ "$DISK" != "$LIVE_DISK" ] || fail "Refusing to erase the MechOS Live USB: $DISK"

# Require enough room for the EFI partition plus a usable installed system.
MIN_BYTES=$((32 * 1024 * 1024 * 1024))
[ "$SIZE_BYTES" -ge "$MIN_BYTES" ] || fail "Selected disk is smaller than the 32 GiB minimum for this Clean Install path."

MODEL="$(lsblk -ndo MODEL "$DISK" 2>/dev/null | sed 's/[[:space:]]*$//' || true)"
SIZE="$(lsblk -ndo SIZE "$DISK" 2>/dev/null || true)"
clear 2>/dev/null || true
cat <<TXT
MECHOS — CLEAN INSTALL
======================
Selected disk: $DISK
Model: ${MODEL:-unknown}
Size: ${SIZE:-unknown}

WARNING: CLEAN INSTALL WILL ERASE EVERY PARTITION AND ALL DATA ON $DISK.
The MechOS Live USB is protected and cannot be selected here.

Type the exact disk path below to confirm the erase.
TXT
read -r -p "Confirm disk [$DISK]: " CONFIRM
[ "$CONFIRM" = "$DISK" ] || { echo "Install cancelled. No disk changes were made."; exit 2; }

# Refuse a disk that somehow became the backing device for the current root or
# Live media after selection.
ROOT_SOURCE="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
if [[ "$ROOT_SOURCE" == /dev/* ]]; then
  ROOT_PARENT="$(lsblk -ndo PKNAME "$ROOT_SOURCE" 2>/dev/null || true)"
  [ -z "$ROOT_PARENT" ] || [ "$DISK" != "/dev/$ROOT_PARENT" ] || fail "Selected disk backs the running root filesystem."
fi

# Unmount only mountpoints belonging to the explicitly confirmed target disk.
while read -r mp; do
  [ -n "$mp" ] || continue
  umount -R "$mp" 2>/dev/null || fail "Could not unmount $mp from $DISK"
done < <(lsblk -lnpo MOUNTPOINTS "$DISK" | awk 'NF' | sort -r)

swapoff --all 2>/dev/null || true
wipefs --all --force "$DISK"

# GPT: 1 GiB EFI System Partition + remaining space for MechOS Btrfs root.
printf 'label: gpt\n,1GiB,C12A7328-F81F-11D2-BA4B-00A0C93EC93B,*\n,,0FC63DAF-8483-4772-8E79-3D69D8477DE4\n' \
  | sfdisk --wipe always --wipe-partitions always "$DISK"
partprobe "$DISK" 2>/dev/null || true
udevadm settle

mapfile -t PARTS < <(lsblk -nrpo PATH,TYPE "$DISK" | awk '$2=="part" {print $1}')
[ "${#PARTS[@]}" -eq 2 ] || fail "Expected two partitions after formatting $DISK; found ${#PARTS[@]}."
EFI_PART="${PARTS[0]}"
ROOT_PART="${PARTS[1]}"

mkfs.fat -F 32 -n MECHOS_EFI "$EFI_PART"
mkfs.btrfs -f -L MECHOS "$ROOT_PART"

umount -R "$MNT" 2>/dev/null || true
mkdir -p "$MNT"
mount "$ROOT_PART" "$MNT"
btrfs subvolume create "$MNT/@"
btrfs subvolume create "$MNT/@home"
btrfs subvolume create "$MNT/@log"
btrfs subvolume create "$MNT/@pkg"
btrfs subvolume create "$MNT/@snapshots"
umount "$MNT"

MOUNT_OPTS='noatime,compress=zstd:1,ssd,space_cache=v2'
mount -o "$MOUNT_OPTS,subvol=@" "$ROOT_PART" "$MNT"
mkdir -p "$MNT/boot" "$MNT/home" "$MNT/var/log" "$MNT/var/cache/pacman/pkg" "$MNT/.snapshots"
mount -o "$MOUNT_OPTS,subvol=@home" "$ROOT_PART" "$MNT/home"
mount -o "$MOUNT_OPTS,subvol=@log" "$ROOT_PART" "$MNT/var/log"
mount -o "$MOUNT_OPTS,subvol=@pkg" "$ROOT_PART" "$MNT/var/cache/pacman/pkg"
mount -o "$MOUNT_OPTS,subvol=@snapshots" "$ROOT_PART" "$MNT/.snapshots"
mount "$EFI_PART" "$MNT/boot"

# Preserve the existing MechOS custom_commands and package payload, but force
# Archinstall to use only the already-mounted selected drive. This prevents a
# second disk-selection screen from redirecting installation to another disk.
python3 - "$BASE_CONFIG" "$AUTO_CONFIG" <<'PY'
import json, sys
src, dst = sys.argv[1:3]
with open(src, encoding='utf-8') as f:
    cfg = json.load(f)
cfg.update({
    'archinstall-language': 'English',
    'bootloader_config': {
        'bootloader': 'Grub',
        'uki': False,
        'removable': False,
        'plymouth': True,
    },
    'disk_config': {
        'config_type': 'pre_mounted_config',
        'mountpoint': '/mnt',
    },
    'hostname': 'mechos',
    'kernels': ['linux'],
    'locale_config': {
        'kb_layout': 'us',
        'sys_enc': 'UTF-8',
        'sys_lang': 'en_US.UTF-8',
    },
    'network_config': {'type': 'iso'},
    'ntp': True,
    'offline': False,
    'profile_config': None,
    'script': 'guided',
    'services': ['NetworkManager'],
    'silent': True,
    'swap': {'enabled': True, 'algorithm': 'zstd'},
    'timezone': 'UTC',
})
packages = list(dict.fromkeys((cfg.get('packages') or []) + ['curl','grub','efibootmgr','btrfs-progs','networkmanager']))
cfg['packages'] = packages
with open(dst, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, indent=2)
PY

# Archinstall requires at least root credentials or a sudo user. Give root a
# random throwaway password hash; MechOS OOBE creates the real owner account and
# password on first boot.
RANDOM_PASS="$(head -c 48 /dev/urandom | base64 | tr -d '\n=/+' | head -c 32)"
ROOT_HASH="$(openssl passwd -6 "$RANDOM_PASS")"
python3 - "$CREDS" "$ROOT_HASH" <<'PY'
import json, sys
with open(sys.argv[1], 'w', encoding='utf-8') as f:
    json.dump({'root_enc_password': sys.argv[2]}, f)
PY
chmod 600 "$CREDS"
unset RANDOM_PASS ROOT_HASH

cleanup_server() {
  if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup_server EXIT INT TERM
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$PAYLOAD_DIR" \
  >/tmp/mechos-installer-http.log 2>&1 &
SERVER_PID=$!
sleep 1
curl -fsS "http://127.0.0.1:${PORT}/mechos-postinstall-target" >/dev/null \
  || fail "Local MechOS installer payload server did not start."

printf '\nInstalling MechOS to %s...\n' "$DISK"
archinstall --silent --config "$AUTO_CONFIG" --creds "$CREDS"

sync
printf '\nMechOS installation completed on %s.\n' "$DISK"
printf 'Remove the Live USB and reboot when ready.\n'
EOF
chmod 755 "$BIN/mechos-install-selected-target"

# Keep executable permissions authoritative in ArchISO.
if [ -f "$PROFILE" ] && ! grep -Fq 'file_permissions["/usr/local/bin/mechos-install-selected-target"]' "$PROFILE"; then
  printf '\nfile_permissions["/usr/local/bin/mechos-install-selected-target"]="0:0:755"\n' >> "$PROFILE"
fi

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$BIN/mechos-partition-selector" \
  || fail "partition selector Python validation failed after selected-drive patch"
bash -n "$BIN/mechos-install-selected-target" \
  || fail "selected-drive install helper shell validation failed"
grep -Fq 'Refusing to erase the MechOS Live USB' "$BIN/mechos-install-selected-target" \
  || fail "Live USB destructive-operation guard is missing"
grep -Fq 'pre_mounted_config' "$BIN/mechos-install-selected-target" \
  || fail "selected drive is not forced as the mounted Archinstall target"
grep -Fq 'sfdisk --wipe always' "$BIN/mechos-install-selected-target" \
  || fail "whole-disk clean partitioning path is missing"
grep -Fq 'mkfs.btrfs' "$BIN/mechos-install-selected-target" \
  || fail "MechOS root formatting path is missing"

log "whole-disk Live selection now erases, partitions, formats and installs only to the confirmed selected disk"
