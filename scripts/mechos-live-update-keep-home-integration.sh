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
DEVICE="${2:-}"
MODE="${1:-}"
MOUNTS=()

exec > >(tee -a "$LOG") 2>&1
say() { printf '[MechOS Live Update] %s\n' "$*"; }
fail() { say "ERROR: $*" >&2; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || fail "Administrator privileges are required."
  exec sudo "$0" "$@"
fi

[ -s "$PAYLOAD" ] || fail "This Live image does not contain the MechOS installed-system payload."

cleanup() {
  local i
  for ((i=${#MOUNTS[@]}-1; i>=0; i--)); do
    mountpoint -q "${MOUNTS[$i]}" 2>/dev/null && umount "${MOUNTS[$i]}" 2>/dev/null || true
  done
  MOUNTS=()
  mountpoint -q "$MNT" 2>/dev/null && umount -R "$MNT" 2>/dev/null || true
  rm -rf "$MNT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

is_mechos() {
  [ -f "$MNT/etc/mechos/mechos.conf" ] || \
  [ -f "$MNT/etc/mechos-release" ] || \
  grep -Eqi 'MechOS' "$MNT/etc/os-release" 2>/dev/null
}

mount_root() {
  local dev="$1" fs="$2" mode="${3:-ro}"
  cleanup
  mkdir -p "$MNT"

  # New MechOS clean installs use the @ Btrfs root subvolume. Try it first so
  # the updater does not accidentally mount the Btrfs top level as the root.
  if [ "$fs" = "btrfs" ]; then
    if mount -o "$mode,subvol=@" "$dev" "$MNT" 2>/dev/null; then
      [ -f "$MNT/etc/os-release" ] && is_mechos && return 0
      umount "$MNT" 2>/dev/null || true
    fi
  fi

  if mount -o "$mode" "$dev" "$MNT" 2>/dev/null; then
    [ -f "$MNT/etc/os-release" ] && is_mechos && return 0
    umount "$MNT" 2>/dev/null || true
  fi
  return 1
}

scan_roots() {
  local dev type fs pretty
  while read -r dev type fs; do
    case "$type" in part|lvm|crypt) ;; *) continue ;; esac
    case "$fs" in btrfs|ext4|xfs|f2fs) ;; *) continue ;; esac
    if mount_root "$dev" "$fs" ro; then
      pretty="$(. "$MNT/etc/os-release" 2>/dev/null; printf '%s' "${PRETTY_NAME:-MechOS}")"
      printf '%s|%s|%s\n' "$dev" "$fs" "$pretty"
    fi
  done < <(lsblk -prno NAME,TYPE,FSTYPE)
  cleanup
}

choose_root() {
  local rows=() row dev fs pretty choice n
  mapfile -t rows < <(scan_roots)
  [ "${#rows[@]}" -gt 0 ] || fail "No existing MechOS installation was found."

  if [ "${#rows[@]}" -eq 1 ]; then
    IFS='|' read -r dev fs pretty <<<"${rows[0]}"
    printf '%s\n' "$dev"
    return
  fi

  if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v kdialog >/dev/null 2>&1; then
    local args=()
    for row in "${rows[@]}"; do
      IFS='|' read -r dev fs pretty <<<"$row"
      args+=("$dev" "$pretty — $dev — $fs")
    done
    choice="$(kdialog --title 'MechOS Live Update' --menu 'Choose the installed MechOS system to update while preserving /home:' "${args[@]}" 2>/dev/null || true)"
    [ -n "$choice" ] || exit 2
    printf '%s\n' "$choice"
    return
  fi

  echo "Detected MechOS installations:" >&2
  n=1
  for row in "${rows[@]}"; do
    IFS='|' read -r dev fs pretty <<<"$row"
    printf '  %d) %s  %s  %s\n' "$n" "$dev" "$fs" "$pretty" >&2
    n=$((n+1))
  done
  read -r -p "Choose installation number: " choice
  [[ "$choice" =~ ^[0-9]+$ ]] || exit 2
  [ "$choice" -ge 1 ] && [ "$choice" -le "${#rows[@]}" ] || exit 2
  IFS='|' read -r dev fs pretty <<<"${rows[$((choice-1))]}"
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

mount_support_filesystems() {
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
    [ -b "$resolved" ] || continue
    target="$MNT$mp"
    mkdir -p "$target"
    mountpoint -q "$target" 2>/dev/null && continue
    if [ -n "${opts:-}" ] && [ "$opts" != defaults ]; then
      mount -t "$fs" -o "$opts" "$resolved" "$target" 2>/dev/null || continue
    else
      mount -t "$fs" "$resolved" "$target" 2>/dev/null || continue
    fi
    MOUNTS+=("$target")
  done < <(grep -Ev '^[[:space:]]*(#|$)' "$MNT/etc/fstab" 2>/dev/null || true)
}

confirm_update() {
  local dev="$1" pretty home_desc msg
  pretty="$(. "$MNT/etc/os-release" 2>/dev/null; printf '%s' "${PRETTY_NAME:-MechOS}")"
  home_desc="$(awk '$2=="/home" {print $1" ("$3")"; exit}' "$MNT/etc/fstab" 2>/dev/null || true)"
  [ -n "$home_desc" ] || home_desc="stored inside the root filesystem"
  msg="Update $pretty from this Live image?\n\nRoot: $dev\nHome: $home_desc\n\n/home will NOT be formatted or replaced. User accounts, passwords, hostname, machine identity, network connections, and completed first-boot state are preserved."
  if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v kdialog >/dev/null 2>&1; then
    kdialog --title 'MechOS Live Update — Keep Home' --warningyesno "$msg" || exit 2
  else
    printf '%b\n' "$msg"
    read -r -p "Type UPDATE to continue: " answer
    [ "$answer" = UPDATE ] || exit 2
  fi
}

if [ "$MODE" != "--device" ] || [ -z "$DEVICE" ]; then
  DEVICE="$(choose_root)"
fi
FS="$(lsblk -no FSTYPE "$DEVICE" 2>/dev/null | head -n1 || true)"
[ -n "$FS" ] || fail "Could not determine filesystem type for $DEVICE."
mount_root "$DEVICE" "$FS" ro || fail "$DEVICE is not a recognizable MechOS root filesystem."
confirm_update "$DEVICE"
cleanup
mount_root "$DEVICE" "$FS" rw || fail "Could not mount $DEVICE read-write."

# Mount boot/EFI and other support filesystems from the installed fstab, but
# deliberately never mount /home. The update itself never formats partitions.
mount_support_filesystems
if mountpoint -q "$MNT/home" 2>/dev/null; then
  fail "Safety check failed: /home was mounted by the updater. No refresh was performed."
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
SAVE="$(mktemp -d)"
trap 'rm -rf "$SAVE" 2>/dev/null || true; cleanup' EXIT INT TERM
mkdir -p "$SAVE/etc" "$SAVE/var/lib/mechos"

# Back up identity/account configuration before touching the root filesystem.
for rel in \
  etc/fstab etc/crypttab etc/hostname etc/machine-id \
  etc/passwd etc/group etc/shadow etc/gshadow etc/subuid etc/subgid \
  etc/NetworkManager/system-connections etc/ssh \
  var/lib/NetworkManager var/lib/bluetooth \
  var/lib/mechos/oobe-complete var/lib/mechos/oobe-cleaned; do
  if [ -e "$MNT/$rel" ]; then
    mkdir -p "$SAVE/$(dirname "$rel")"
    cp -a "$MNT/$rel" "$SAVE/$rel"
  fi
done

mkdir -p "$MNT/var/lib/mechos/live-update-backups"
tar --zstd -cpf "$MNT/var/lib/mechos/live-update-backups/$STAMP-preserved-config.tar.zst" -C "$SAVE" .
chmod 600 "$MNT/var/lib/mechos/live-update-backups/$STAMP-preserved-config.tar.zst"

if [ -x "$MNT/usr/bin/snapper" ]; then
  arch-chroot "$MNT" snapper -c root create --type single --description "Before MechOS Live update $STAMP" 2>/dev/null || true
fi

say "Refreshing MechOS system files from the Live image. /home is excluded."
tar --zstd \
  --exclude='./home' --exclude='./home/*' \
  --exclude='./root' --exclude='./root/*' \
  --exclude='./etc/fstab' --exclude='./etc/crypttab' \
  --exclude='./etc/hostname' --exclude='./etc/machine-id' \
  --exclude='./etc/passwd' --exclude='./etc/group' \
  --exclude='./etc/shadow' --exclude='./etc/gshadow' \
  --exclude='./etc/subuid' --exclude='./etc/subgid' \
  --exclude='./etc/NetworkManager/system-connections' \
  --exclude='./etc/ssh' \
  --exclude='./var/lib/NetworkManager' --exclude='./var/lib/bluetooth' \
  --exclude='./var/lib/mechos/oobe-complete' --exclude='./var/lib/mechos/oobe-cleaned' \
  --exclude='./var/lib/mechos/oobe-pending' \
  --exclude='./etc/sddm.conf.d/95-mechos-oobe.conf' \
  -xpf "$PAYLOAD" -C "$MNT"

# Restore the backed-up identity files in case an older tar implementation or
# payload layout differed from the expected exclusions.
cp -a "$SAVE/." "$MNT/"

mkdir -p "$MNT/var/lib/mechos"
if [ -e "$SAVE/var/lib/mechos/oobe-complete" ]; then
  rm -f "$MNT/var/lib/mechos/oobe-pending" "$MNT/etc/sddm.conf.d/95-mechos-oobe.conf"
fi
printf '%s|iso-refresh|root=%s|home=preserved\n' "$(date -Is)" "$DEVICE" >> "$MNT/var/lib/mechos/live-update-history.log"

PKG_RESULT="offline/skipped"
if command -v curl >/dev/null 2>&1 && curl -fsI --max-time 6 https://archlinux.org/ >/dev/null 2>&1; then
  say "Internet detected; updating installed Arch packages."
  if arch-chroot "$MNT" pacman -Syu --noconfirm; then
    PKG_RESULT="updated"
  else
    PKG_RESULT="failed; ISO runtime refresh still applied"
    say "WARNING: package refresh failed. Use MechOS Update Center after reboot."
  fi
else
  say "No Internet detected; applying the ISO runtime only."
fi

if [ -x "$MNT/usr/bin/mkinitcpio" ]; then
  arch-chroot "$MNT" mkinitcpio -P || say "WARNING: initramfs refresh reported an error."
fi
if [ -f "$MNT/boot/grub/grub.cfg" ] && [ -x "$MNT/usr/bin/grub-mkconfig" ]; then
  arch-chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg || say "WARNING: GRUB refresh reported an error."
elif [ -d "$MNT/boot/loader" ] && [ -x "$MNT/usr/bin/bootctl" ]; then
  arch-chroot "$MNT" bootctl update || say "WARNING: systemd-boot refresh reported an error."
fi

sync
say "Live update complete."
say "Root updated: $DEVICE"
say "Home: PRESERVED"
say "Package refresh: $PKG_RESULT"
say "Backup: /var/lib/mechos/live-update-backups/$STAMP-preserved-config.tar.zst"

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
if text == original and 'UPDATE / REINSTALL (KEEP HOME)' not in text:
    raise SystemExit('[MechOS Live Update] graphical Live installer was not updated')
path.write_text(text, encoding='utf-8')
PY

if [ -f "$PROFILE" ]; then
  if ! grep -Fq 'file_permissions["/usr/local/bin/mechos-live-update-keep-home"]' "$PROFILE"; then
    printf '\nfile_permissions["/usr/local/bin/mechos-live-update-keep-home"]="0:0:755"\n' >> "$PROFILE"
  fi
  if ! grep -Fq 'file_permissions["/usr/share/applications/mechos-live-update-keep-home.desktop"]' "$PROFILE"; then
    printf '\nfile_permissions["/usr/share/applications/mechos-live-update-keep-home.desktop"]="0:0:644"\n' >> "$PROFILE"
  fi
fi

bash -n "$BIN/mechos-live-update-keep-home" || fail "Live update helper shell syntax failed"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$BIN/mechos-live-setup" || fail "Live installer syntax failed after Keep Home integration"
grep -Fq '/usr/local/bin/mechos-live-update-keep-home' "$BIN/mechos-live-setup" || fail "Live installer Keep Home action is not wired"
# The '--' below is required because the literal search pattern begins with --.
grep -Fq -- "--exclude='./home'" "$BIN/mechos-live-update-keep-home" || fail "/home exclusion is missing"
grep -Fq -- "--exclude='./home/*'" "$BIN/mechos-live-update-keep-home" || fail "/home contents exclusion is missing"
if grep -Eq '(^|[[:space:]])(mkfs|wipefs|sfdisk|fdisk|parted)([[:space:]]|$)' "$BIN/mechos-live-update-keep-home"; then
  fail "destructive partition/format command found in Keep Home updater"
fi
grep -Fq 'live-update-backups' "$BIN/mechos-live-update-keep-home" || fail "preserved configuration backup is missing"
grep -Fq 'pacman -Syu' "$BIN/mechos-live-update-keep-home" || fail "online package refresh is missing"

log "Live Update / Reinstall (Keep Home) refreshes MechOS without formatting or replacing /home"
