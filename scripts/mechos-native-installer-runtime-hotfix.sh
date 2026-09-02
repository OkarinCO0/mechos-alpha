#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
HELPER="$ROOT/usr/local/libexec/mechos-native-install-helper"
UI="$ROOT/usr/local/bin/mechos-native-install"
PHASE2="/workspace/scripts/mechos-phase2-optimization-integration.sh"

log() { printf '[MechOS Native Installer Hotfix] %s\n' "$*"; }
fail() { printf '[MechOS Native Installer Hotfix] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$PHASE" = "final" ] || exit 0
[ -f "$HELPER" ] || fail "native installer helper is missing"
[ -f "$UI" ] || fail "native installer UI is missing"

# GROUPS is a Bash special variable. Never use it for the temporary OOBE group
# list or some shells will reject/ignore the assignment at installation time.
sed -i \
  -e 's/^  GROUPS=/  SETUP_GROUPS=/' \
  -e 's/\$GROUPS/\$SETUP_GROUPS/g' \
  "$HELPER"

# VirtualBox commonly creates a roughly 25 GB default test disk. The old 32 GiB
# hard stop happened before the first progress event, producing a useless 0%
# error. Allow 20 GiB for VM/development installs while keeping 64 GiB as the
# recommended floor for a real gaming installation.
sed -i \
  -e 's/MIN_BYTES=$((32 \* 1024 \* 1024 \* 1024))/MIN_BYTES=$((20 * 1024 * 1024 * 1024))/' \
  -e 's/Selected disk is smaller than the 32 GiB minimum\./Selected disk is smaller than the 20 GiB minimum. Use at least 64 GiB for a normal MechOS gaming install./' \
  "$HELPER"

# Give BIOS GRUB more embedding room than the original 2 MiB partition. This is
# still tiny relative to the disk but avoids marginal core-image/module layouts
# on BIOS+GPT VMs and physical systems.
sed -i \
  -e 's/size=2MiB,type=21686148-6449-6E6F-744E-656564454649,name=MECHOS_BIOS/size=8MiB,type=21686148-6449-6E6F-744E-656564454649,name=MECHOS_BIOS/' \
  "$HELPER"

python3 - "$HELPER" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_DUAL_FIRMWARE_BOOT_V2'
if marker not in text:
    start = text.find('progress 90 "Installing MechOS bootloader"')
    end = text.find('\nprogress 96 "Finalizing MechOS installation"', start)
    if start < 0 or end < 0:
        raise SystemExit('[MechOS Native Installer Hotfix] could not locate bootloader section')

    replacement = r'''progress 90 "Installing MechOS bootloader"
# MECHOS_DUAL_FIRMWARE_BOOT_V2
# The clean-install disk is deliberately bootable in BOTH Legacy BIOS and UEFI,
# regardless of which firmware mode was used to boot the Live ISO.
BIOS_GUID='21686148-6449-6e6f-744e-656564454649'
BIOS_TYPE="$(lsblk -nro PARTTYPE "$BIOS_PART" 2>/dev/null | head -n1 | tr '[:upper:]' '[:lower:]')"
[ "$BIOS_TYPE" = "$BIOS_GUID" ] \
  || fail "Legacy BIOS boot partition is missing or has the wrong GPT type: $BIOS_PART"

# Install BIOS GRUB into the disk MBR and embed core.img in the BIOS Boot
# partition. Explicit modules guarantee GPT+Btrfs discovery on first boot.
if ! arch-chroot "$MNT" grub-install \
    --target=i386-pc \
    --boot-directory=/boot \
    --modules='biosdisk part_gpt btrfs normal configfile' \
    --recheck "$DISK"; then
  fail "Legacy BIOS GRUB installation failed on $DISK"
fi

[ -s "$MNT/boot/grub/i386-pc/core.img" ] \
  || fail "Legacy BIOS GRUB core image was not generated."
[ -s "$MNT/boot/grub/i386-pc/normal.mod" ] \
  || fail "Legacy BIOS GRUB modules were not installed."

# Always create a removable UEFI loader too. When booted in UEFI mode we first
# try the normal NVRAM entry; otherwise (or if NVRAM is unavailable) we install
# the firmware-independent EFI/BOOT/BOOTX64.EFI fallback.
UEFI_OK=0
if [ -d /sys/firmware/efi ]; then
  if arch-chroot "$MNT" grub-install \
      --target=x86_64-efi \
      --efi-directory=/boot/efi \
      --bootloader-id=MechOS \
      --recheck; then
    UEFI_OK=1
  fi
fi

if [ "$UEFI_OK" -ne 1 ]; then
  arch-chroot "$MNT" grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=MechOS \
    --removable --no-nvram --recheck \
    || fail "UEFI removable fallback installation failed."
fi

# Ensure the removable UEFI path exists even when the normal NVRAM install
# succeeded, making the disk portable between firmware implementations.
if [ ! -s "$MNT/boot/efi/EFI/BOOT/BOOTX64.EFI" ]; then
  arch-chroot "$MNT" grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=MechOS \
    --removable --no-nvram --recheck \
    || fail "Could not create EFI/BOOT/BOOTX64.EFI fallback."
fi

mkdir -p "$MNT/etc/default/grub.d"
printf 'GRUB_DISABLE_OS_PROBER=false\n' > "$MNT/etc/default/grub.d/90-mechos.cfg"
arch-chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg \
  || fail "GRUB configuration generation failed."
arch-chroot "$MNT" grub-script-check /boot/grub/grub.cfg \
  || fail "Generated GRUB configuration did not validate."

[ -s "$MNT/boot/grub/grub.cfg" ] || fail "GRUB configuration is missing."
sync
'''
    text = text[:start] + replacement + text[end:]
    path.write_text(text, encoding='utf-8')
PY

python3 - "$UI" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_NATIVE_ERROR_UI_V2'

if marker not in text:
    old = """        self.proc = QProcess(self)\n        self.disk = ''\n"""
    new = """        self.proc = QProcess(self)\n        # MECHOS_NATIVE_ERROR_UI_V2\n        self.disk = ''\n        self.size_bytes = 0\n        self.last_error = ''\n"""
    if old not in text:
        raise SystemExit('[MechOS Native Installer Hotfix] could not locate native installer state')
    text = text.replace(old, new, 1)

    old = """        self.disk=str(data.get('disk') or data.get('path') or '')\n        if not self.disk.startswith('/dev/'):\n"""
    new = """        self.disk=str(data.get('disk') or data.get('path') or '')\n        self.size_bytes=int(data.get('size_bytes') or 0)\n        if not self.disk.startswith('/dev/'):\n"""
    if old not in text:
        raise SystemExit('[MechOS Native Installer Hotfix] could not locate selected disk state')
    text = text.replace(old, new, 1)

    old = """    def confirm_and_start(self):\n        info=subprocess.run(['lsblk','-dno','SIZE,MODEL',self.disk],text=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL).stdout.strip()\n"""
    new = """    def confirm_and_start(self):\n        minimum = 20 * 1024 * 1024 * 1024\n        recommended = 64 * 1024 * 1024 * 1024\n        if self.size_bytes and self.size_bytes < minimum:\n            gib = self.size_bytes / (1024 ** 3)\n            message = (\n                f'The selected disk is only {gib:.1f} GiB. MechOS needs at least 20 GiB to install.\\n\\n'\n                'For a normal gaming system, 64 GiB or more is recommended. Increase the virtual disk size and try again.'\n            )\n            self.last_error = message\n            self.status.setText(message)\n            self.log.appendPlainText('PRE-FLIGHT ERROR: ' + message.replace('\\n', ' '))\n            QMessageBox.critical(self, 'MechOS Installer', message)\n            self.close_btn.setEnabled(True)\n            return\n        if self.size_bytes and self.size_bytes < recommended:\n            gib = self.size_bytes / (1024 ** 3)\n            warning = (\n                f'This disk is {gib:.1f} GiB. That is enough for a VM/test installation, but 64 GiB or more '\n                'is recommended for a normal MechOS gaming system.\\n\\nContinue with this test-sized disk?'\n            )\n            if QMessageBox.question(\n                self, 'Small MechOS Install Disk', warning,\n                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,\n                QMessageBox.StandardButton.No\n            ) != QMessageBox.StandardButton.Yes:\n                self.status.setText('Installation cancelled. No changes were made.')\n                self.close_btn.setEnabled(True)\n                return\n        info=subprocess.run(['lsblk','-dno','SIZE,MODEL',self.disk],text=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL).stdout.strip()\n"""
    if old not in text:
        raise SystemExit('[MechOS Native Installer Hotfix] could not locate confirmation preflight')
    text = text.replace(old, new, 1)

    old = """            elif line.startswith('MECHOS_ERROR='):\n                self.status.setText(line.split('=',1)[1])\n            else:\n                self.log.appendPlainText(line)\n"""
    new = """            elif line.startswith('MECHOS_ERROR='):\n                self.last_error=line.split('=',1)[1].strip()\n                self.status.setText(self.last_error)\n                self.log.appendPlainText('ERROR: ' + self.last_error)\n            else:\n                self.log.appendPlainText(line)\n"""
    if old not in text:
        raise SystemExit('[MechOS Native Installer Hotfix] could not locate error-output handler')
    text = text.replace(old, new, 1)

    # Do not match the old QMessageBox text literally: the generated installer
    # contains escaped physical line continuations whose representation changes
    # depending on which integration pass produced the file. Patch the failure
    # branch structurally inside finished() instead.
    finished_start = text.find("    def finished(self, code, _status):\n")
    close_start = text.find("    def closeEvent(self,event):", finished_start)
    if finished_start < 0 or close_start < 0:
        raise SystemExit('[MechOS Native Installer Hotfix] could not locate installer finished function boundaries')

    finished_block = text[finished_start:close_start]
    else_pos = finished_block.rfind("        else:\n")
    if else_pos < 0:
        raise SystemExit('[MechOS Native Installer Hotfix] could not locate installer finished failure branch')

    finished_prefix = finished_block[:else_pos]
    finished_error = """        else:\n            # MECHOS_NATIVE_FINISHED_HANDLER_V2\n            reason = self.last_error or f'Installation stopped with error code {code}.'\n            self.status.setText(reason)\n            if not self.last_error:\n                self.log.appendPlainText(f'ERROR: installer exited with code {code} before reporting a detailed reason.')\n            QMessageBox.critical(\n                self, 'MechOS Installer',\n                f'Installation did not complete.\\n\\n{reason}\\n\\nThe full installer output is shown in this window.'\n            )\n\n"""
    text = text[:finished_start] + finished_prefix + finished_error + text[close_start:]

path.write_text(text, encoding='utf-8')
PY

bash -n "$HELPER" || fail "native installer helper syntax failed after runtime hotfix"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$UI" \
  || fail "native installer UI syntax failed after error-reporting hotfix"
grep -Fq 'SETUP_GROUPS=' "$HELPER" || fail "safe setup group variable is missing"
if grep -Eq '^[[:space:]]*GROUPS=' "$HELPER"; then
  fail "reserved Bash GROUPS variable is still assigned"
fi
grep -Fq 'MIN_BYTES=$((20 * 1024 * 1024 * 1024))' "$HELPER" \
  || fail "20 GiB VM/test minimum is missing"
grep -Fq 'size=8MiB,type=21686148-6449-6E6F-744E-656564454649,name=MECHOS_BIOS' "$HELPER" \
  || fail "8 MiB Legacy BIOS embedding partition is missing"
grep -Fq 'MECHOS_DUAL_FIRMWARE_BOOT_V2' "$HELPER" \
  || fail "dual-firmware bootloader hardening is missing"
grep -Fq -- '--target=i386-pc' "$HELPER" \
  || fail "Legacy BIOS GRUB target is missing"
grep -Fq 'boot/grub/i386-pc/core.img' "$HELPER" \
  || fail "Legacy BIOS GRUB verification is missing"
grep -Fq 'EFI/BOOT/BOOTX64.EFI' "$HELPER" \
  || fail "removable UEFI fallback verification is missing"
grep -Fq 'grub-script-check /boot/grub/grub.cfg' "$HELPER" \
  || fail "GRUB config validation is missing"
grep -Fq 'MECHOS_NATIVE_ERROR_UI_V2' "$UI" \
  || fail "native installer detailed error UI is missing"
grep -Fq 'MECHOS_NATIVE_FINISHED_HANDLER_V2' "$UI" \
  || fail "native installer finished-handler hardening is missing"
grep -Fq "self.last_error=line.split('=',1)[1].strip()" "$UI" \
  || fail "native installer no longer preserves helper failure reasons"

# Phase 2 must run here, after the native installer helper exists. This lets it
# switch new installs from the graphical-target firstboot service to the
# non-blocking post-graphical timer while also patching the installed payload.
[ -f "$PHASE2" ] || fail "Phase 2 optimization integration is missing"
bash "$PHASE2" final

log "native installer VM preflight, verified dual-firmware boot, detailed errors, setup-user variables and Phase 2 optimization applied"
