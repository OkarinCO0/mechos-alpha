#!/usr/bin/env bash
set -Eeuo pipefail
ISO="${1:-$(dirname "$0")/../out/MechOS-0.3.2-alpha-x86_64.iso}"
[[ -f "$ISO" ]] || { echo "ISO not found: $ISO" >&2; exit 1; }
exec qemu-system-x86_64 -enable-kvm -m 8192 -smp 8 -cpu host \
  -device virtio-vga-gl -display gtk,gl=on \
  -cdrom "$ISO" -boot d
