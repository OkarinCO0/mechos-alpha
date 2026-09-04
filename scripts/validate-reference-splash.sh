#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPLASH="$ROOT/branding/mechos-splash-reference.png"
INTEGRATION="$ROOT/scripts/mechos-reference-splash-integration.sh"
FINAL="$ROOT/scripts/mechos-plymouth-boot-final.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"
fail(){ echo "[validate-reference-splash] ERROR: $*" >&2; exit 1; }

[ -s "$SPLASH" ] || fail "branding/mechos-splash-reference.png missing"
[ -f "$INTEGRATION" ] || fail "reference splash integration missing"
[ -f "$FINAL" ] || fail "final Plymouth boot-chain integration missing"
bash -n "$INTEGRATION" || fail "reference splash integration shell syntax failed"
bash -n "$FINAL" || fail "final Plymouth boot-chain shell syntax failed"

grep -Fq 'MECHOS_REFERENCE_SPLASH_V1' "$INTEGRATION" || fail "reference Plymouth marker missing"
grep -Fq 'Image("mechos-splash-reference.png")' "$INTEGRATION" || fail "Plymouth is not loading the approved reference image"
grep -Fq 'reference.original.Scale' "$INTEGRATION" || fail "reference image is not scaled for the active display"
grep -Fq 'Theme=mechos' "$INTEGRATION" || fail "Plymouth theme selection missing"

grep -Fq 'mkinitcpio.conf.d/*.conf' "$FINAL" || fail "ArchISO/native mkinitcpio drop-in support missing"
grep -Fq "for sub in ('efiboot/loader/entries','syslinux','grub')" "$FINAL" || fail "Live bootloader config coverage missing"
grep -Fq 'archisobasedir=' "$FINAL" || fail "Live ArchISO kernel-option detection missing"
grep -Fq 'quiet splash loglevel=3' "$FINAL" || fail "Live/native kernel splash options missing"
grep -Fq 'MECHOS_NATIVE_PLYMOUTH_BOOT_V1' "$FINAL" || fail "native Clean Install Plymouth marker missing"
grep -Fq 'mechos-native-install-helper' "$FINAL" || fail "native installer helper is not targeted"
grep -Fq 'GRUB_CMDLINE_LINUX_DEFAULT' "$FINAL" || fail "native GRUB splash enforcement missing"
grep -Fq 'plymouth-set-default-theme mechos' "$FINAL" || fail "native theme selection missing"

grep -Fq 'mechos-reference-splash-integration.sh' "$PATCHER" || fail "reference splash not wired into final build chain"
grep -Fq 'mechos-plymouth-boot-final.sh' "$PATCHER" || fail "final Plymouth boot-chain authority not wired"
python3 - "$PATCHER" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text()
a=text.find('mechos-reference-splash-integration.sh')
b=text.find('mechos-plymouth-boot-final.sh')
c=text.find('mechos-reference-v5-postinstall-stage.sh commit')
if min(a,b,c)<0 or not (a < b < c):
    raise SystemExit('[validate-reference-splash] final Plymouth boot-chain authority must run after theme install and before payload commit')
PY

echo '[validate-reference-splash] OK: approved artwork, Live ArchISO boot args/hooks, and native installed GRUB/initramfs Plymouth path are enforced'
