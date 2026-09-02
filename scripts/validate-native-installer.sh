#!/usr/bin/env bash
set -Eeuo pipefail

BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE="$BASE/scripts/mechos-native-installer-integration.sh"
HOTFIX="$BASE/scripts/mechos-native-installer-runtime-hotfix.sh"
PATCHER="$BASE/scripts/patch-mechos-current.py"

fail() { echo "Native installer validation error: $*" >&2; exit 1; }

[ -f "$NATIVE" ] || fail "native installer integration is missing"
[ -f "$HOTFIX" ] || fail "native installer runtime hotfix is missing"
[ -f "$PATCHER" ] || fail "cumulative builder patcher is missing"

bash -n "$NATIVE" || fail "native installer integration shell syntax failed"
bash -n "$HOTFIX" || fail "native installer runtime hotfix shell syntax failed"

grep -Fq 'pacstrap -K -C' "$NATIVE" || fail "native package provisioning is missing"
grep -Fq 'MECHOS_BIOS' "$NATIVE" || fail "Legacy BIOS partition support is missing"
grep -Fq 'MECHOS_EFI' "$NATIVE" || fail "UEFI partition support is missing"
grep -Fq 'mkfs.btrfs' "$NATIVE" || fail "Btrfs root formatting is missing"
grep -Fq 'genfstab -U' "$NATIVE" || fail "fstab generation is missing"
grep -Fq 'grub-install --target=i386-pc' "$NATIVE" || fail "Legacy BIOS GRUB path is missing"
grep -Fq 'grub-install --target=x86_64-efi' "$NATIVE" || fail "UEFI GRUB path is missing"
grep -Fq 'mechos-oobe' "$NATIVE" || fail "first-boot OOBE handoff is missing"
grep -Fq 'subprocess.Popen(["/usr/local/bin/mechos-native-install"])' "$NATIVE" || fail "graphical installer native launch patch is missing"

# Match only a real command line in the generated helper. The integration
# source intentionally contains the words "archinstall --silent" inside its own
# negative build-time guard, which must not count as an invocation.
if grep -Eq '^[[:space:]]*archinstall[[:space:]]+--silent([[:space:]]|$)' "$NATIVE"; then
  fail "native Clean Install still invokes Archinstall"
fi

grep -Fq 'SETUP_GROUPS=' "$HOTFIX" || fail "reserved GROUPS-variable hotfix is missing"
grep -Fq 'MIN_BYTES=$((20 * 1024 * 1024 * 1024))' "$HOTFIX" || fail "VM/test disk minimum hotfix is missing"
grep -Fq 'MECHOS_NATIVE_ERROR_UI_V2' "$HOTFIX" || fail "native detailed-error UI hotfix is missing"
grep -Fq "self.last_error=line.split('=',1)[1].strip()" "$HOTFIX" || fail "helper error preservation is missing"
grep -Fq '64 GiB or more is recommended' "$HOTFIX" || fail "normal gaming disk-size recommendation is missing"
grep -Fq 'size=8MiB,type=21686148-6449-6E6F-744E-656564454649,name=MECHOS_BIOS' "$HOTFIX" \
  || fail "Legacy BIOS embedding partition was not enlarged"
grep -Fq 'MECHOS_DUAL_FIRMWARE_BOOT_V2' "$HOTFIX" || fail "dual-firmware boot hardening marker is missing"
grep -Fq -- '--target=i386-pc' "$HOTFIX" || fail "verified Legacy BIOS GRUB install is missing"
grep -Fq 'boot/grub/i386-pc/core.img' "$HOTFIX" || fail "Legacy BIOS core image verification is missing"
grep -Fq 'EFI/BOOT/BOOTX64.EFI' "$HOTFIX" || fail "removable UEFI fallback is missing"
grep -Fq 'grub-script-check /boot/grub/grub.cfg' "$HOTFIX" || fail "generated GRUB config validation is missing"
grep -Fq 'mechos-native-installer-integration.sh final' "$PATCHER" || fail "native integration is not wired into the ISO builder"
grep -Fq 'mechos-native-installer-runtime-hotfix.sh final' "$PATCHER" || fail "native runtime hotfix is not wired into the ISO builder"

echo "Native MechOS installer source validation passed."
