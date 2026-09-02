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

if grep -Fq 'archinstall --silent' "$NATIVE"; then
  fail "native Clean Install still invokes Archinstall"
fi

grep -Fq 'SETUP_GROUPS=' "$HOTFIX" || fail "reserved GROUPS-variable hotfix is missing"
grep -Fq 'mechos-native-installer-integration.sh final' "$PATCHER" || fail "native integration is not wired into the ISO builder"
grep -Fq 'mechos-native-installer-runtime-hotfix.sh final' "$PATCHER" || fail "native runtime hotfix is not wired into the ISO builder"

echo "Native MechOS installer source validation passed."
