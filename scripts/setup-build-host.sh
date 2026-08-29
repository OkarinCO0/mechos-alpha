#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi
source /etc/os-release
if [[ "${ID:-}" != "fedora" || "${VERSION_ID:-}" != "44" ]]; then
  echo "MechOS 0.3.2 ISO builder is designed for a Fedora 44 build host." >&2
  exit 1
fi
dnf -y install kiwi kiwi-systemdeps distribution-gpg-keys git rsync python3 qemu-kvm libvirt-client
