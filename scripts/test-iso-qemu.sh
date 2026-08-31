#!/usr/bin/env bash
set -Eeuo pipefail
ISO="${1:-$(dirname "$0")/../out/MechOS-Arch-Creator-x86_64.iso}"
[[ -f "$ISO" ]] || { echo "ISO not found: $ISO" >&2; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || {
  echo "qemu-system-x86_64 is required to test the ISO." >&2
  exit 1
}

qemu_args=(-m 8192 -smp 8 -cdrom "$ISO" -boot d)

if [[ -r /dev/kvm && -w /dev/kvm ]]; then
  qemu_args=(-enable-kvm -cpu host "${qemu_args[@]}")
else
  echo "KVM is unavailable; using slower software emulation." >&2
  qemu_args=(-accel tcg "${qemu_args[@]}")
fi

exec qemu-system-x86_64 "${qemu_args[@]}"
