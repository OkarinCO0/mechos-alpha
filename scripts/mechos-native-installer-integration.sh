#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
BIN="$ROOT/usr/local/bin"
LIBEXEC="$ROOT/usr/local/libexec"
PROFILE="/workspace/archlive/profiledef.sh"
PAYLOAD="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log() { printf '[MechOS Native Installer] %s\n' "$*"; }
fail() { printf '[MechOS Native Installer] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Native Installer] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -s "$PAYLOAD" ] || fail "installed-system payload is missing: $PAYLOAD"
[ -f "$BIN/mechos-live-setup" ] || fail "graphical Live installer is missing"
mkdir -p "$BIN" "$LIBEXEC"

cat > "$LIBEXEC/mechos-native-install-helper" <<'HELPER_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

SEL=/tmp/mechos-install-target.json
PAYLOAD=/usr/share/mechos/install-payload/mechos-rootfs.tar.zst
MNT=/mnt
LOG=/var/log/mechos-native-install.log
DEVICE=""

exec > >(tee -a "$LOG") 2>&1

progress() {
  local pct="$1"; shift
  printf 'MECHOS_PROGRESS=%s|%s\n' "$pct" "$*"
}
fail() {
  printf 'MECHOS_ERROR=%s\n' "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --device) DEVICE="${2:-}"; shift 2 ;;
    *) fail "Unknown installer argument: $1" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || fail "Native installer must run as root."
[ -s "$SEL" ] || fail "No MechOS install target has been selected."
[ -s "$PAYLOAD" ] || fail "Installed-system payload is missing from this Live image."
command -v pacstrap >/dev/null 2>&1 || fail "pacstrap is missing from the Live image."
command -v genfstab >/dev/null 2>&1 || fail "genfstab is missing from the Live image."
command -v sfdisk >/dev/null 2>&1 || fail "sfdisk is missing from the Live image."

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

[ "$KIND" = "disk" ] || fail "Native Clean Install requires a whole-disk selection. Use the MechOS Keep Home flow for an existing installation."
[ -n "$DISK" ] && [ "$TARGET" = "$DISK" ] || fail "Selected whole-disk target is inconsistent."
[ -z "$DEVICE" ] || [ "$DEVICE" = "$DISK" ] || fail "Selected disk changed between confirmation and installation."
[ -b "$DISK" ] || fail "Selected target is no longer a block device: $DISK"
[ "$(lsblk -dno TYPE "$DISK" 2>/dev/null || true)" = "disk" ] || fail "Selected target is not a whole disk: $DISK"
MIN_BYTES=$((32 * 1024 * 1024 * 1024))
[ "$SIZE_BYTES" -ge "$MIN_BYTES" ] || fail "Selected disk is smaller than the 32 GiB minimum."

# Re-identify the Live media immediately before destructive work.
LIVE_SOURCE="$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
LIVE_DISK=""
if [[ "$LIVE_SOURCE" == /dev/* ]]; then
  LIVE_PARENT="$(lsblk -ndo PKNAME "$LIVE_SOURCE" 2>/dev/null || true)"
  LIVE_DISK="${LIVE_PARENT:+/dev/$LIVE_PARENT}"
  [ -n "$LIVE_DISK" ] || LIVE_DISK="$LIVE_SOURCE"
fi
[ -z "$LIVE_DISK" ] || [ "$DISK" != "$LIVE_DISK" ] || fail "Refusing to erase the MechOS Live media: $DISK"

ROOT_SOURCE="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
if [[ "$ROOT_SOURCE" == /dev/* ]]; then
  ROOT_PARENT="$(lsblk -ndo PKNAME "$ROOT_SOURCE" 2>/dev/null || true)"
  [ -z "$ROOT_PARENT" ] || [ "$DISK" != "/dev/$ROOT_PARENT" ] || fail "Selected disk backs the running Live root filesystem."
fi

cleanup_mounts() {
  umount -R "$MNT" 2>/dev/null || true
}
trap cleanup_mounts EXIT INT TERM

progress 4 "Preparing selected disk"
# Unmount only filesystems that belong to the confirmed target disk.
while read -r mp; do
  [ -n "$mp" ] || continue
  umount -R "$mp" 2>/dev/null || fail "Could not unmount $mp from $DISK"
done < <(lsblk -lnpo MOUNTPOINTS "$DISK" | awk 'NF' | sort -r)

# Disable swap only when the swap device belongs to this disk.
while read -r sw; do
  [ -n "$sw" ] || continue
  if lsblk -nrpo NAME "$DISK" | grep -Fxq "$sw"; then
    swapoff "$sw" 2>/dev/null || true
  fi
done < <(awk 'NR>1 {print $1}' /proc/swaps 2>/dev/null || true)

wipefs --all --force "$DISK"

progress 10 "Creating universal MechOS partition layout"
# GPT layout is intentionally bootable in both firmware families:
# 1: 2 MiB BIOS Boot partition for GRUB on Legacy BIOS + GPT
# 2: 1 GiB EFI System Partition for UEFI
# 3: remaining disk space, Btrfs MechOS root
cat <<'SFDISK' | sfdisk --wipe always --wipe-partitions always "$DISK"
label: gpt
size=2MiB,type=21686148-6449-6E6F-744E-656564454649,name=MECHOS_BIOS
size=1GiB,type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B,name=MECHOS_EFI
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4,name=MECHOS_ROOT
SFDISK
partprobe "$DISK" 2>/dev/null || true
udevadm settle

mapfile -t PARTS < <(lsblk -nrpo PATH,TYPE "$DISK" | awk '$2=="part" {print $1}')
[ "${#PARTS[@]}" -eq 3 ] || fail "Expected three MechOS partitions; found ${#PARTS[@]}."
BIOS_PART="${PARTS[0]}"
EFI_PART="${PARTS[1]}"
ROOT_PART="${PARTS[2]}"

progress 16 "Formatting MechOS filesystems"
mkfs.fat -F 32 -n MECHOS_EFI "$EFI_PART"
mkfs.btrfs -f -L MECHOS "$ROOT_PART"

mkdir -p "$MNT"
mount "$ROOT_PART" "$MNT"
for subvol in @ @home @log @pkg @snapshots; do
  btrfs subvolume create "$MNT/$subvol"
done
umount "$MNT"

MOUNT_OPTS='noatime,compress=zstd:1,ssd,space_cache=v2'
mount -o "$MOUNT_OPTS,subvol=@" "$ROOT_PART" "$MNT"
mkdir -p "$MNT/home" "$MNT/var/log" "$MNT/var/cache/pacman/pkg" "$MNT/.snapshots" "$MNT/boot/efi"
mount -o "$MOUNT_OPTS,subvol=@home" "$ROOT_PART" "$MNT/home"
mount -o "$MOUNT_OPTS,subvol=@log" "$ROOT_PART" "$MNT/var/log"
mount -o "$MOUNT_OPTS,subvol=@pkg" "$ROOT_PART" "$MNT/var/cache/pacman/pkg"
mount -o "$MOUNT_OPTS,subvol=@snapshots" "$ROOT_PART" "$MNT/.snapshots"
mount "$EFI_PART" "$MNT/boot/efi"

progress 23 "Installing Arch base system internally"
PACCONF=/tmp/mechos-native-pacman.conf
cp /etc/pacman.conf "$PACCONF"
sed -i '/^#[[:space:]]*\[multilib\]/,/^#[[:space:]]*Include[[:space:]]*=[[:space:]]*\/etc\/pacman.d\/mirrorlist/ s/^#[[:space:]]*//' "$PACCONF"

PACKAGES=(
  base linux linux-headers linux-firmware linux-firmware-whence
  plasma-meta plymouth plymouth-kcm sddm konsole dolphin ark kate kdialog firefox
  networkmanager network-manager-applet bluez bluez-utils
  pipewire pipewire-alsa pipewire-pulse wireplumber
  xdg-desktop-portal xdg-desktop-portal-kde
  steam gamescope lutris gamemode lib32-gamemode mangohud lib32-mangohud
  wine wine-mono wine-gecko winetricks protontricks vulkan-tools
  mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon vulkan-intel lib32-vulkan-intel
  ntfs-3g exfatprogs btrfs-progs dosfstools e2fsprogs f2fs-tools xfsprogs
  openssh grub efibootmgr os-prober git git-lfs curl wget unzip zip p7zip sudo flatpak
  base-devel cmake ninja clang python python-pip python-pygame python-evdev
  python-websocket-client python-pyqt6 brightnessctl ffmpeg
  zram-generator power-profiles-daemon irqbalance cpupower amd-ucode intel-ucode
  switcheroo-control nvidia-prime smartmontools nvme-cli btop pacman-contrib
  polkit snapper libva-utils pciutils usbutils gpu-screen-recorder
  gpu-screen-recorder-ui intel-media-driver libva-mesa-driver
)

pacstrap -K -C "$PACCONF" "$MNT" "${PACKAGES[@]}"
rm -f "$PACCONF"

# Keep multilib enabled in the installed OS for Steam/Proton and 32-bit drivers.
sed -i '/^#[[:space:]]*\[multilib\]/,/^#[[:space:]]*Include[[:space:]]*=[[:space:]]*\/etc\/pacman.d\/mirrorlist/ s/^#[[:space:]]*//' "$MNT/etc/pacman.conf"

progress 62 "Deploying MechOS system runtime"
tar --zstd -xpf "$PAYLOAD" -C "$MNT"

# The payload can contain an Arch default pacman.conf from an older build;
# enforce multilib again after deployment.
sed -i '/^#[[:space:]]*\[multilib\]/,/^#[[:space:]]*Include[[:space:]]*=[[:space:]]*\/etc\/pacman.d\/mirrorlist/ s/^#[[:space:]]*//' "$MNT/etc/pacman.conf" 2>/dev/null || true

progress 67 "Writing filesystem and base system configuration"
genfstab -U "$MNT" > "$MNT/etc/fstab"
printf 'mechos\n' > "$MNT/etc/hostname"
if grep -q '^#en_US.UTF-8 UTF-8' "$MNT/etc/locale.gen"; then
  sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "$MNT/etc/locale.gen"
fi
arch-chroot "$MNT" locale-gen
printf 'LANG=en_US.UTF-8\n' > "$MNT/etc/locale.conf"
ln -sf /usr/share/zoneinfo/UTC "$MNT/etc/localtime"
arch-chroot "$MNT" hwclock --systohc 2>/dev/null || true

progress 72 "Configuring detected GPU"
GPU_TEXT="$(lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' || true)"
if printf '%s\n' "$GPU_TEXT" | grep -qi NVIDIA; then
  arch-chroot "$MNT" pacman -S --needed --noconfirm nvidia-open nvidia-utils lib32-nvidia-utils nvidia-prime
  mkdir -p "$MNT/etc/modprobe.d"
  printf 'options nvidia_drm modeset=1\n' > "$MNT/etc/modprobe.d/90-mechos-nvidia-drm.conf"
fi

progress 77 "Preparing first-boot MechOS setup"
# OOBE owns creation of the permanent account. This temporary account exists
# only long enough to show the graphical first-boot setup and is removed after.
if ! arch-chroot "$MNT" id mechos-setup >/dev/null 2>&1; then
  GROUPS="$(for g in wheel video audio input storage optical; do arch-chroot "$MNT" getent group "$g" >/dev/null 2>&1 && printf '%s,' "$g"; done | sed 's/,$//')"
  if [ -n "$GROUPS" ]; then
    arch-chroot "$MNT" useradd -m -s /bin/bash -G "$GROUPS" mechos-setup
  else
    arch-chroot "$MNT" useradd -m -s /bin/bash mechos-setup
  fi
fi
arch-chroot "$MNT" passwd -l mechos-setup >/dev/null 2>&1 || true
mkdir -p "$MNT/home/mechos-setup/.config/autostart" "$MNT/etc/sddm.conf.d" "$MNT/var/lib/mechos"
cat > "$MNT/home/mechos-setup/.config/autostart/mechos-oobe.desktop" <<'OOBE'
[Desktop Entry]
Type=Application
Name=MechOS First System Setup
Exec=/usr/local/bin/mechos-oobe
Terminal=false
X-KDE-autostart-after=panel
OOBE
arch-chroot "$MNT" chown -R mechos-setup:mechos-setup /home/mechos-setup
cat > "$MNT/etc/sddm.conf.d/95-mechos-oobe.conf" <<'SDDM'
[Autologin]
User=mechos-setup
Session=plasma.desktop
Relogin=false
SDDM

# The permanent account does not exist yet. Root remains locked; OOBE sets the
# real user's password on first boot.
arch-chroot "$MNT" passwd -l root >/dev/null 2>&1 || true

progress 82 "Enabling MechOS services"
for unit in NetworkManager.service sddm.service bluetooth.service fstrim.timer irqbalance.service power-profiles-daemon.service switcheroo-control.service mechos-firstboot.service; do
  arch-chroot "$MNT" systemctl enable "$unit" 2>/dev/null || true
done
arch-chroot "$MNT" systemctl disable systemd-networkd.service 2>/dev/null || true
arch-chroot "$MNT" systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true

progress 86 "Generating initramfs"
arch-chroot "$MNT" mkinitcpio -P

progress 90 "Installing MechOS bootloader"
# Always install the BIOS GRUB target because the disk includes a BIOS Boot
# partition. This makes the same installed disk bootable in Legacy BIOS/CSM.
arch-chroot "$MNT" grub-install --target=i386-pc --recheck "$DISK"

# When the Live ISO itself was booted via UEFI, also install the UEFI target.
if [ -d /sys/firmware/efi ]; then
  if ! arch-chroot "$MNT" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=MechOS --recheck; then
    # Some VMs/firmware do not expose writable NVRAM variables. The removable
    # fallback still produces a standards-compliant EFI/BOOT/BOOTX64.EFI path.
    arch-chroot "$MNT" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=MechOS --removable --no-nvram --recheck
  fi
fi
mkdir -p "$MNT/etc/default/grub.d"
printf 'GRUB_DISABLE_OS_PROBER=false\n' > "$MNT/etc/default/grub.d/90-mechos.cfg"
arch-chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg

progress 96 "Finalizing MechOS installation"
touch "$MNT/var/lib/mechos/installed"
printf '%s|native-clean-install|disk=%s|firmware=%s\n' "$(date -Is)" "$DISK" "$([ -d /sys/firmware/efi ] && echo UEFI || echo BIOS)" > "$MNT/var/lib/mechos/install-history.log"
sync
progress 100 "MechOS installation complete"
printf 'MECHOS_INSTALL_COMPLETE=1\n'
HELPER_EOF
chmod 755 "$LIBEXEC/mechos-native-install-helper"

cat > "$BIN/mechos-native-install" <<'PYEOF'
#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

from PyQt6.QtCore import QProcess, Qt
from PyQt6.QtWidgets import (
    QApplication, QLabel, QMainWindow, QMessageBox, QPlainTextEdit,
    QProgressBar, QPushButton, QVBoxLayout, QWidget
)

SELECTION = Path('/tmp/mechos-install-target.json')
HELPER = '/usr/local/libexec/mechos-native-install-helper'

STYLE = '''
QWidget { background:#070a12; color:#edf4ff; font-family:Sans Serif; }
QLabel#title { font-size:26px; font-weight:900; color:white; }
QLabel#status { color:#a9bdd7; font-size:14px; }
QProgressBar { border:1px solid #334b6c; border-radius:8px; text-align:center; min-height:26px; }
QProgressBar::chunk { background:#7352d6; border-radius:7px; }
QPlainTextEdit { background:#050810; border:1px solid #263b5a; border-radius:8px; color:#cfe4ff; }
QPushButton { background:#18233a; border:1px solid #5d58a8; border-radius:9px; padding:10px 16px; font-weight:700; }
'''

class NativeInstall(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle('MechOS Installer')
        self.setMinimumSize(900, 620)
        self.setStyleSheet(STYLE)
        self.proc = QProcess(self)
        self.disk = ''
        self.build()
        if not self.load_target():
            return
        self.confirm_and_start()

    def build(self):
        root=QWidget(); self.setCentralWidget(root)
        lay=QVBoxLayout(root); lay.setContentsMargins(28,24,28,24); lay.setSpacing(14)
        title=QLabel('INSTALLING MECHOS'); title.setObjectName('title'); lay.addWidget(title)
        self.status=QLabel('Waiting for confirmation...'); self.status.setObjectName('status'); self.status.setWordWrap(True); lay.addWidget(self.status)
        self.progress=QProgressBar(); self.progress.setRange(0,100); self.progress.setValue(0); lay.addWidget(self.progress)
        self.log=QPlainTextEdit(); self.log.setReadOnly(True); lay.addWidget(self.log,1)
        self.close_btn=QPushButton('Close'); self.close_btn.setEnabled(False); self.close_btn.clicked.connect(self.close); lay.addWidget(self.close_btn)

    def load_target(self):
        try:
            data=json.loads(SELECTION.read_text(encoding='utf-8'))
        except Exception as exc:
            QMessageBox.critical(self,'MechOS Installer',f'No valid install location is selected.\n\n{exc}')
            self.close_btn.setEnabled(True); return False
        if data.get('kind') != 'disk':
            QMessageBox.warning(self,'MechOS Installer','Native Clean Install currently requires a whole-disk selection.')
            self.close_btn.setEnabled(True); return False
        self.disk=str(data.get('disk') or data.get('path') or '')
        if not self.disk.startswith('/dev/'):
            QMessageBox.critical(self,'MechOS Installer','The selected disk is invalid.')
            self.close_btn.setEnabled(True); return False
        return True

    def confirm_and_start(self):
        info=subprocess.run(['lsblk','-dno','SIZE,MODEL',self.disk],text=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL).stdout.strip()
        answer=QMessageBox.warning(
            self,'Final Clean Install Confirmation',
            f'MechOS will erase ALL partitions and data on:\n\n{self.disk}\n{info or "Unknown disk"}\n\n'
            'MechOS will create its own BIOS/UEFI boot partitions and Btrfs system layout. '
            'The Live USB is protected by a second safety check.\n\nContinue?',
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No)
        if answer != QMessageBox.StandardButton.Yes:
            self.status.setText('Installation cancelled. No changes were made.')
            self.close_btn.setEnabled(True); return
        self.status.setText(f'Installing MechOS to {self.disk}. Keep this computer powered on.')
        self.proc.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self.proc.readyReadStandardOutput.connect(self.read_output)
        self.proc.finished.connect(self.finished)
        self.proc.start('sudo',['-n',HELPER,'--device',self.disk])

    def read_output(self):
        text=bytes(self.proc.readAllStandardOutput()).decode(errors='replace')
        for line in text.splitlines():
            if line.startswith('MECHOS_PROGRESS='):
                payload=line.split('=',1)[1]
                pct, _, message=payload.partition('|')
                try: self.progress.setValue(int(pct))
                except Exception: pass
                if message: self.status.setText(message)
            elif line.startswith('MECHOS_ERROR='):
                self.status.setText(line.split('=',1)[1])
            else:
                self.log.appendPlainText(line)

    def finished(self, code, _status):
        self.close_btn.setEnabled(True)
        if code == 0:
            self.progress.setValue(100)
            self.status.setText('MechOS is installed. Remove the Live USB and reboot into the installed system.')
            QMessageBox.information(self,'MechOS Installed','Installation completed successfully.\n\nRemove the Live USB and reboot. First boot will open MechOS account setup.')
        else:
            self.status.setText(f'Installation stopped with error code {code}. The log is shown below.')
            QMessageBox.critical(self,'MechOS Installer',f'Installation did not complete (error {code}).\n\nReview the installer log before rebooting.')

    def closeEvent(self,event):
        if self.proc.state() != QProcess.ProcessState.NotRunning:
            QMessageBox.information(self,'MechOS Installer','Installation is still running. Wait for it to finish before closing this window.')
            event.ignore(); return
        event.accept()

app=QApplication(sys.argv); app.setApplicationName('MechOS Native Installer')
w=NativeInstall(); w.show(); raise SystemExit(app.exec())
PYEOF
chmod 755 "$BIN/mechos-native-install"

# Compatibility entry point: anything still calling the old selected-target
# helper now stays inside the native MechOS installer rather than Archinstall.
cat > "$BIN/mechos-install-selected-target" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$(id -u)" -eq 0 ]; then
  exec sudo -u "${SUDO_USER:-mechos}" /usr/local/bin/mechos-native-install
fi
exec /usr/local/bin/mechos-native-install
EOF
chmod 755 "$BIN/mechos-install-selected-target"

# Patch the final graphical Live installer after every earlier integration has
# run. Clean Install launches the native MechOS progress UI directly.
python3 - "$BIN/mechos-live-setup" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
text=p.read_text(encoding='utf-8')

replacements={
    'subprocess.Popen(["konsole","-e","sudo","/usr/local/bin/mechos-install-selected-target"])':
        'subprocess.Popen(["/usr/local/bin/mechos-native-install"])',
    "The selected root/target can be erased. Review Archinstall's final disk summary before confirming.":
        "Clean Install erases only the selected whole disk after a final MechOS confirmation. MechOS handles partitioning and installation directly.",
    'Start guided installation for': 'Start MechOS installation for',
}
for old,new in replacements.items():
    text=text.replace(old,new)

# Remove old visible Archinstall wording from the clean-install path without
# changing recovery documentation that may mention old logs.
text=text.replace('Archinstall still shows the actual partition layout and requires confirmation before formatting.',
                  'MechOS handles the selected whole-disk layout and installation directly after final confirmation.')

if '/usr/local/bin/mechos-native-install' not in text:
    raise SystemExit('[MechOS Native Installer] could not wire native Clean Install into the graphical installer')
p.write_text(text,encoding='utf-8')
PY

# Update selector wording so the user is never told Clean Install will hand off.
python3 - "$BIN/mechos-partition-selector" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); text=p.read_text(encoding='utf-8')
text=text.replace('MechOS will use manual partitioning so formatting and mount points remain explicit.',
                  'Existing-partition advanced installs remain separate from native whole-disk Clean Install.')
text=text.replace('This selects an existing partition. MechOS will open manual partitioning before any disk changes.',
                  'This selects an existing partition for an advanced install path. No disk changes happen on this screen.')
p.write_text(text,encoding='utf-8')
PY

if [ -f "$PROFILE" ]; then
  for spec in \
    '/usr/local/bin/mechos-native-install:0:0:755' \
    '/usr/local/libexec/mechos-native-install-helper:0:0:755' \
    '/usr/local/bin/mechos-install-selected-target:0:0:755'; do
    path="${spec%%:*}"; rest="${spec#*:}"; owner="${rest%%:*}"; rest="${rest#*:}"; group="${rest%%:*}"; mode="${rest##*:}"
    if ! grep -Fq "file_permissions[\"$path\"]" "$PROFILE"; then
      printf '\nfile_permissions["%s"]="%s:%s:%s"\n' "$path" "$owner" "$group" "$mode" >> "$PROFILE"
    fi
  done
fi

bash -n "$LIBEXEC/mechos-native-install-helper" || fail "native installer helper shell syntax failed"
bash -n "$BIN/mechos-install-selected-target" || fail "native compatibility launcher shell syntax failed"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$BIN/mechos-native-install" || fail "native installer UI Python syntax failed"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$BIN/mechos-live-setup" || fail "Live installer Python syntax failed after native integration"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$BIN/mechos-partition-selector" || fail "partition selector Python syntax failed after native integration"

grep -Fq 'pacstrap -K -C' "$LIBEXEC/mechos-native-install-helper" || fail "native base-system provisioning is missing"
grep -Fq 'MECHOS_BIOS' "$LIBEXEC/mechos-native-install-helper" || fail "Legacy BIOS boot partition support is missing"
grep -Fq 'MECHOS_EFI' "$LIBEXEC/mechos-native-install-helper" || fail "UEFI boot partition support is missing"
grep -Fq 'grub-install --target=i386-pc' "$LIBEXEC/mechos-native-install-helper" || fail "Legacy BIOS GRUB installation is missing"
grep -Fq 'grub-install --target=x86_64-efi' "$LIBEXEC/mechos-native-install-helper" || fail "UEFI GRUB installation is missing"
if grep -Fq 'archinstall --silent' "$LIBEXEC/mechos-native-install-helper"; then
  fail "native installer still invokes Archinstall"
fi
grep -Fq 'subprocess.Popen(["/usr/local/bin/mechos-native-install"])' "$BIN/mechos-live-setup" || fail "graphical Clean Install still does not launch native installer"

log "Clean Install is now fully MechOS-native with no Archinstall handoff and dual BIOS/UEFI boot support"
