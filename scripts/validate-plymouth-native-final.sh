#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FINAL="$ROOT/scripts/mechos-plymouth-boot-final.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"
fail(){ echo "[validate-plymouth-native-final] ERROR: $*" >&2; exit 1; }

bash -n "$FINAL" || fail "final Plymouth integration syntax failed"
grep -Fq 'MECHOS_NATIVE_PLYMOUTH_BOOT_V1' "$FINAL" || fail "native Plymouth marker missing"
grep -Fq 'progress 86 "Generating initramfs"' "$FINAL" || fail "native initramfs insertion anchor missing"
grep -Fq 'GRUB_CMDLINE_LINUX_DEFAULT' "$FINAL" || fail "GRUB splash option injection missing"
grep -Fq 'archisobasedir=' "$FINAL" || fail "Live ArchISO boot entry patch missing"
grep -Fq 'mkinitcpio.conf.d/*.conf' "$FINAL" || fail "mkinitcpio drop-in coverage missing"
grep -Fq 'mechos-plymouth-boot-final.sh' "$PATCHER" || fail "final Plymouth integration not wired into ISO build"

echo '[validate-plymouth-native-final] OK: Live and installed native boot paths both request Plymouth'
