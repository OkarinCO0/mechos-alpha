#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
BIN="$ROOT/usr/local/bin"
APPS="$ROOT/usr/share/applications"
PROFILE="/workspace/archlive/profiledef.sh"
PAYLOAD="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log() { printf '[MechOS Live Update] %s\n' "$*"; }
fail() { printf '[MechOS Live Update] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Live Update] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -s "$PAYLOAD" ] || fail "installed-system payload archive is missing: $PAYLOAD"
[ -f "$BIN/mechos-live-setup" ] || fail "graphical Live installer is missing"
mkdir -p "$BIN" "$APPS"

cat > "$BIN/mechos-live-update-keep-home" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

MNT=/mnt/mechos-live-update
PAYLOAD=/usr/share/mechos/install-payload/mechos-rootfs.tar.zst
LOG=/var/log/mechos-live-update.log
MODE="${1:-}"
DEVICE="${2:-}"
TARGET_MOUNTS=()

exec > >(tee -a "$LOG") 2>&1

say() { printf '[MechOS Live Update] %s\n' "$*"; }
fail() { say "ERROR: $*" >&2; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo "$0" "$@"
  fi
  fail "Administrator privileges are required."
fi

[ -s "$PAYLOAD" ] || fail "This Live image does not contain the MechOS installed-system payload."

cleanup() {
  local i
  for ((i=${#TARGET_MOUNTS[@]}-1; i>=0; i--)); do
    mountpoint -q "${TARGET_MOUNTS[$i]}" 2>/dev/null && umount "${TARGET_MOUNTS[$i]}" 2>/dev/null || true
  done
  mountpoint -q "$MNT" 2>/dev/null && umount -R "$MNT" 2>/dev/null || true
  rm -rf "$MNT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mechos_marker_present() {
  local tree="$1"
  [ -f "$tree/etc/mechos/mechos.conf" ] || \
  [ -f "$tree/etc/mechos-release" ] || \
  grep -Eqi '(^|[=" ])MechOS([ " ]|$)' "$tree/etc/os-release" 2>/dev/null
}

try_mount_root() {
  local dev="$1"
  local fs="${2:-}"
  local mode="${3:-ro}"
  local opts="$mode"

  cleanup
  mkdir -p "$MNT"

  if mount -o "$opts" "$dev" "$MNT" 2>/dev/null; then
    if [ -f "$MNT/etc/os-release" ] && mechos_marker_present "$MNT"; then
      return 0
    fi
    umount "$MNT" 2>/dev/null || true
  fi

  if [ "$fs" = "btrfs" ]; then
    if mount -o "$opts,subvol=@" "$dev" "$MNT" 2>/dev/null; then
      if [ -f "$MNT/etc/os-release" ] && mechos_marker_present "$MNT"; then
        return 0
      fi
      umount "$MNT" 2>/dev/null || true
    fi
  fi

  return 1
}

scan_roots() {
  local dev type fs pretty version
  while read -r dev type fs; do
    case "$type" in part|lvm|crypt) ;; *) continue ;; esac
    case "$fs" in ext4|btrfs|xfs|f2fs) ;; *) continue ;; esac
    if try_mount_root "$dev" "$fs" ro; then
      pretty="$(. "$MNT/etc/os-release" 2>/dev/null; printf '%s' "${PRETTY_NAME:-MechOS}")"
      version="unknown"
      if [ -f "$MNT/etc/mechos/mechos.conf" ]; then
        version="$(awk -F= '$1 ~ /^(MECHOS_VERSION|VERSION)$/ {gsub(/[\"\r]/,"",$2); print $2; exit}' "$MNT/etc/mechos/mechos.conf" 2>/dev/null || true)"
      fi
      [ -n "$version" ] || version="unknown"
      printf '%s|%s|%s|%s\n' "$dev" "$fs" "$pretty" "$version"
    fi
  done < <(lsblk -prno NAME,TYPE,FSTYPE)
  cleanup
}

choose_root() {
  local rows=() line dev fs pretty version choice
  mapfile -t rows < <(scan_roots)
  [ "${#rows[@]}" -gt 0 ] || fail "No existing MechOS installation was found."

  if [ "${#rows[@]}" -eq 1 ]; then
    IFS='|' read -r dev fs pretty version <<<"${rows[0]}"
    printf '%s\n' "$dev"
    return 0
  fi

  if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v kdialog >/dev/null 2>&1; then
    local args=()
    for line in "${rows[@]}"; do
      IFS='|' read -r dev fs pretty version <<<"$line"
      args+=("$dev" "$pretty — $dev — $fs")
    done
    choice="$(kdialog --title 'MechOS Live Update' --menu 'Choose the installed MechOS system to update while preserving /home:' "${args[@]}" 2>/dev/null || true)"
    [ -n "$choice" ] || exit 2
    printf '%s\n' "$choice"
    return 0
  fi

  echo "Detected MechOS installations:" >&2
  local n=1
  for line in "${rows[@]}"; do
    IFS='|' read -r dev fs pretty version <<<"$line"
    printf '  %d) %s  %s  %s\n' "$n" "$dev" "$fs" "$pretty" >&2
    n=$((n+1))
  done
  read -r -p "Choose installation number: " choice
  [[ "$choice" =~ ^[0-9]+$ ]] || exit 2
  [ "$choice" -ge 1 ] && [ "$choice" -le "${#rows[@]}" ] || exit 2
  IFS='|' read -r dev fs pretty version <<<"${rows[$((choice-1))]}"
  printf '%s\n' "$dev"
}

resolve_source() {
  local src="$1"
  case "$src" in
    UUID=*) blkid -U "${src#UUID=}" 2>/dev/null || true ;;
    PARTUUID=*) blkid -t "PARTUUID=${src#PARTUUID=}" -o device 2>/dev/null | head -n1 ;;
    LABEL=*) blkid -L "${src#LABEL=}" 2>/dev/null || true ;;
    /dev/*) printf '%s\n' "$src" ;;
    *) printf '%s\n' "" ;;
  esac
}

mount_target_filesystems_except_home() {
  local src mp fs opts resolved target
  [ -f "$MNT/etc/fstab" ] || return 0

  while read -r src mp fs opts _; do
    [ -n "${src:-}" ] || continue
    [[ "$src" == \#* ]] && continue
    [ "$mp" != "/" ] || continue
    [ "$mp" != "/home" ] || continue
    case "$fs" in swap|proc|sysfs|tmpfs|devtmpfs|devpts|cgroup|cgroup2|overlay|squashfs) continue ;; esac
    case ",${opts:-}," in *,noauto,*) continue ;; esac
    [[ "$mp" == /* ]] || continue

    resolved="$(resolve_source "$src")"
    [ -n "$resolved" ] || continue
    [ -b "$resolved" ] || continue
    target="$MNT$mp"
    mkdir -p "$target"
    mountpoint -q "$target" 2>/dev/null && continue

    if [ -n "${opts:-}" ] && [ "$opts" != "defaults" ]; then
      if mount -t "$fs" -o "$opts" "$resolved" "$target" 2>/dev/null; then
        TARGET_MOUNTS+=("$target")
      fi
    elif mount -t "$fs" "$resolved" "$target" 2>/dev/null; then
      TARGET_MOUNTS+=("$target")
    fi
  done < <(grep -Ev '^[[:space:]]*(#|$)' "$MNT/etc/fstab" 2>/dev/null || true)
}

preserve_copy() {
  local rel="$1" save="$2"
  [ -e "$MNT/$rel" ] || return 0
  mkdir -p "$save/$(dirname "$rel")"
  cp -a "$MNT/$rel" "$save/$rel"
}

restore_copy() {
  local rel="$1" save="$2"
  [ -e "$save/$rel" ] || return 0
  mkdir -p "$MNT/$(dirname "$rel")"
  if [ -d "$save/$rel" ]; then
    mkdir -p "$MNT/$rel"
    cp -a "$save/$rel/." "$MNT/$rel/"
  else
    cp -a "$save/$rel" "$MNT/$rel"
  fi
}

confirm_update() {
  local dev="$1" pretty home_desc disk model
  pretty="$(. "$MNT/etc/os-release" 2>/dev/null; printf '%s' "${PRETTY_NAME:-MechOS}")"
  home_desc="$(awk '$2=="/home" {print $1" ("$3")"; exit}' "$MNT/etc/fstab" 2>/dev/null || true)"
  [ -n "$home_desc" ] || home_desc="/home inside the root filesystem"
  disk="$(lsblk -ndo PKNAME "$dev" 2>/dev/null | head -n1 || true)"
  model="$( [ -n "$disk" ] && lsblk -ndo MODEL "/dev/$disk" 2>/dev/null | sed 's/[[:space:]]*$//' || true )"

  local text="Update $pretty from this MechOS Live image?\n\nRoot: $dev\nDisk: ${model:-unknown}\nHome: $home_desc\n\n/home will NOT be formatted or replaced. User account credentials, machine identity, network connections, and existing OOBE-complete state are preserved. System files will be refreshed."

  if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v kdialog >/dev/null 2>&1; then
    kdialog --title 'MechOS Live Update — Keep Home' --warningyesno "$text" || exit 2
  else
    printf '%b\n' "$text"
    read -r -p "Type UPDATE to continue: " answer
    [ "$answer" = "UPDATE" ] || exit 2
  fi
}

if [ "$MODE" != "--device" ] || [ -z "$DEVICE" ]; then
  DEVICE="$(choose_root)"
fi

FS="$(lsblk -no FSTYPE "$DEVICE" 2>/dev/null | head -n1 || true)"
[ -n "$FS" ] || fail "Could not determine filesystem type for $DEVICE."
try_mount_root "$DEVICE" "$FS" ro || fail "$DEVICE is not a recognizable MechOS root filesystem."
confirm_update "$DEVICE"
cleanup
try_mount_root "$DEVICE" "$FS" rw || fail "Could not mount $DEVICE read-write."
mount_target_filesystems_except_home

# Verify that /home was never mounted by this updater. Existing user data may be
# inside the root filesystem or on a separate partition/subvolume; both cases
# are preserved by excluding /home from the ISO payload refresh.
if mountpoint -q "$MNT/home" 2>/dev/null; then
  fail "Safety check failed: /home became mounted by the updater. No refresh was performed."
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
SAVE="$(mktemp -d)"
trap 'rm -rf "$SAVE" 2>/dev/null || true; cleanup' EXIT INT TERM

PRESERVE=(
  etc/fstab
  etc/crypttab
  etc/hostname
  etc/machine-id
  etc/passwd
  etc/group
  etc/shadow
  etc/gshadow
  etc/subuid
  etc/subgid
  etc/NetworkManager/system-connections
  etc/ssh
  var/lib/NetworkManager
  var/lib/bluetooth
  var/lib/mechos/oobe-complete
  var/lib/mechos/oobe-cleaned
  var/lib/mechos/installer-user
)

for rel in "${PRESERVE[@]}"; do
  preserve_copy "$rel" "$SAVE"
done

mkdir -p "$MNT/var/lib/mechos/live-update-backups"
tar --zstd -cpf "$MNT/var/lib/mechos/live-update-backups/$STAMP-preserved-config.tar.zst" -C "$SAVE" .
chmod 600 "$MNT/var/lib/mechos/live-update-backups/$STAMP-preserved-config.tar.zst"

# Ask Snapper for a pre-update snapshot when the installed system already has a
# working root configuration. Failure is non-fatal because not every filesystem
# or older MechOS install is snapshot-capable.
if [ -x "$MNT/usr/bin/snapper" ]; then
  arch-chroot "$MNT" snapper -c root create --type single --description "Before MechOS Live update $STAMP" 2>/dev/null || true
fi

say "Refreshing MechOS system files from the Live image. /home is excluded."
tar --zstd \
  --exclude='./home' --exclude='./home/*' \
  --exclude='./root' --exclude='./root/*' \
  --exclude='./etc/fstab' --exclude='./etc/crypttab' \
  --exclude='./etc/passwd' --exclude='./etc/group' \
  --exclude='./etc/shadow' --exclude='./etc/gshadow' \
  --exclude='./etc/machine-id' --exclude='./etc/hostname' \
  -xpf "$PAYLOAD" -C "$MNT"

for rel in "${PRESERVE[@]}"; do
  restore_copy "$rel" "$SAVE"
done

mkdir -p "$MNT/var/lib/mechos"
printf '%s|iso-refresh|root=%s|home=preserved\n' "$(date -Is)" "$DEVICE" \
  >> "$MNT/var/lib/mechos/live-update-history.log"

# When online, update the installed Arch package set as part of the Live update.
# The ISO payload refresh still succeeds offline; package refresh can be done
# later from the installed MechOS Update Center.
PKG_RESULT="offline/skipped"
if command -v curl >/dev/null 2>&1 && curl -fsI --max-time 6 https://archlinux.org/ >/dev/null 2>&1; then
  say "Internet detected; updating installed Arch packages."
  if arch-chroot "$MNT" pacman -Syu --noconfirm; then
    PKG_RESULT="updated"
  else
    PKG_RESULT="failed; ISO runtime refresh still applied"
    say "WARNING: package refresh failed. MechOS runtime from the ISO is installed; use Update Center after reboot."
  fi
else
  say "No Internet detected; skipping Arch package refresh and applying the ISO runtime only."
fi

# Regenerate boot artifacts without repartitioning or formatting anything.
if [ -x "$MNT/usr/bin/mkinitcpio" ]; then
  arch-chroot "$MNT" mkinitcpio -P || say "WARNING: initramfs regeneration reported an error."
fi
if [ -f "$MNT/boot/grub/grub.cfg" ] && [ -x "$MNT/usr/bin/grub-mkconfig" ]; then
  arch-chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg || say "WARNING: GRUB configuration refresh reported an error."
elif [ -d "$MNT/boot/loader" ] && [ -x "$MNT/usr/bin/bootctl" ]; then
  arch-chroot "$MNT" bootctl update || say "WARNING: systemd-boot update reported an error."
fi

sync
say "Live update complete."
say "Root updated: $DEVICE"
say "Home: PRESERVED"
say "Package refresh: $PKG_RESULT"
say "Preserved-config backup: /var/lib/mechos/live-update-backups/$STAMP-preserved-config.tar.zst"

if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v kdialog >/dev/null 2>&1; then
  kdialog --title 'MechOS Live Update' --msgbox "MechOS update completed.\n\n/home was preserved.\nPackage refresh: $PKG_RESULT\n\nReboot into the installed system when ready." || true
fi
EOF
chmod 755 "$BIN/mechos-live-update-keep-home"

cat > "$APPS/mechos-live-update-keep-home.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Update MechOS (Keep Home)
Comment=Refresh an installed MechOS system from this Live image without formatting or replacing /home
Exec=konsole -e /usr/local/bin/mechos-live-update-keep-home
Icon=system-software-update
Terminal=false
Categories=System;Settings;
StartupNotify=true
EOF
chmod 644 "$APPS/mechos-live-update-keep-home.desktop"

# Turn the existing Reinstall (Keep Home) area of the graphical Live installer
# into the actual Live update/reinstall workflow. The original helper was only a
# manual Archinstall guide; this path now performs a non-formatting ISO refresh.
python3 - "$BIN/mechos-live-setup" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
original = text

text = text.replace('REINSTALL (KEEP HOME)', 'UPDATE / REINSTALL (KEEP HOME)')
text = text.replace('Reinstall (Keep Home)', 'Update / Reinstall (Keep Home)')
text = text.replace('Reinstall MechOS (Keep Home)', 'Update MechOS (Keep Home)')
text = text.replace('/usr/local/bin/mechos-preserve-home', '/usr/local/bin/mechos-live-update-keep-home')
text = text.replace('mechos-preserve-home', 'mechos-live-update-keep-home')

if '/usr/local/bin/mechos-live-update-keep-home' not in text:
    raise SystemExit('[MechOS Live Update] could not wire the Keep Home action to the Live update helper')
if text == original:
    raise SystemExit('[MechOS Live Update] graphical Live installer was not changed')

path.write_text(text, encoding='utf-8')
PY

if [ -f "$PROFILE" ]; then
  for entry in \
    '/usr/local/bin/mechos-live-update-keep-home:0:0:755' \
    '/usr/share/applications/mechos-live-update-keep-home.desktop:0:0:644'; do
    path="${entry%%:*}"
    rest="${entry#*:}"
    owner="${rest%%:*}"
    rest="${rest#*:}"
    group="${rest%%:*}"
    mode="${rest##*:}"
    if ! grep -Fq "file_permissions[\"$path\"]" "$PROFILE"; then
      printf '\nfile_permissions["%s"]="%s:%s:%s"\n' "$path" "$owner" "$group" "$mode" >> "$PROFILE"
    fi
  done
fi

bash -n "$BIN/mechos-live-update-keep-home" || fail "Live update helper shell syntax failed"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$BIN/mechos-live-setup" || fail "Live installer syntax failed after Keep Home integration"
grep -Fq '/usr/local/bin/mechos-live-update-keep-home' "$BIN/mechos-live-setup" || fail "Live installer Keep Home action is not wired"
grep -Fq "--exclude='./home'" "$BIN/mechos-live-update-keep-home" || fail "/home exclusion is missing"
if grep -Eq '(^|[[:space:]])(mkfs|wipefs|sfdisk|fdisk|parted)([[:space:]]|$)' "$BIN/mechos-live-update-keep-home"; then
  fail "destructive partition/format command found in Keep Home updater"
fi
grep -Fq 'live-update-backups' "$BIN/mechos-live-update-keep-home" || fail "preserved configuration backup is missing"
grep -Fq 'pacman -Syu' "$BIN/mechos-live-update-keep-home" || fail "online package refresh is missing"

log "Live Update / Reinstall (Keep Home) now refreshes MechOS without formatting or replacing /home"
