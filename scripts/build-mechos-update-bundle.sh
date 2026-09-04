#!/usr/bin/env bash
set -Eeuo pipefail

usage(){
  cat <<'EOF'
Usage:
  build-mechos-update-bundle.sh VERSION ROOTFS_DIR [OUTPUT]

Example:
  ./scripts/build-mechos-update-bundle.sh 0.3.1-alpha /tmp/mechos-0.3.1-rootfs out/MechOS-0.3.1-alpha-update.tar.zst

ROOTFS_DIR must be an extracted installed MechOS root filesystem. The bundle
contains only MechOS-owned paths accepted by Update Center v1. Arch packages
and Flatpaks continue to update through their native package managers.
EOF
}

[ $# -ge 2 ] && [ $# -le 3 ] || { usage >&2; exit 2; }
VERSION="$1"
ROOTFS="$(realpath "$2")"
OUTPUT="${3:-out/MechOS-${VERSION}-update.tar.zst}"

[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){2}([.-][A-Za-z0-9]+)*$ ]] || { echo "Invalid version: $VERSION" >&2; exit 2; }
[ -d "$ROOTFS" ] || { echo "Rootfs directory not found: $ROOTFS" >&2; exit 2; }

mkdir -p "$(dirname "$OUTPUT")"
OUTPUT="$(realpath -m "$OUTPUT")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

paths=(
  usr/local
  usr/share/mechos
  usr/share/applications
  usr/share/wayland-sessions
  usr/lib/systemd
  etc/mechos
  etc/systemd
  etc/xdg
)

copied=0
for rel in "${paths[@]}"; do
  if [ -e "$ROOTFS/$rel" ]; then
    mkdir -p "$TMP/$(dirname "$rel")"
    cp -a "$ROOTFS/$rel" "$TMP/$rel"
    copied=1
  fi
done

[ "$copied" -eq 1 ] || { echo "No MechOS-owned update paths found in $ROOTFS" >&2; exit 1; }

# Version files are controlled by the verified manifest after installation,
# not by bundle contents. This prevents a bundle from claiming a different
# version than the manifest whose SHA authenticated it.
rm -f "$TMP/etc/mechos/release"

# Refuse unexpected files before creating the archive.
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
allowed=(
 'usr/local/', 'usr/share/mechos/', 'usr/share/applications/',
 'usr/share/wayland-sessions/', 'usr/lib/systemd/', 'etc/mechos/',
 'etc/systemd/', 'etc/xdg/'
)
for path in root.rglob('*'):
    rel=path.relative_to(root).as_posix()
    if path.is_dir(): rel += '/'
    if not any(rel==x.rstrip('/') or rel.startswith(x) for x in allowed):
        raise SystemExit(f'Unexpected bundle path: {rel}')
PY

rm -f "$OUTPUT" "$OUTPUT.sha256"
tar --zstd -cpf "$OUTPUT" -C "$TMP" .
sha256sum "$OUTPUT" > "$OUTPUT.sha256"
SHA="$(awk '{print $1}' "$OUTPUT.sha256")"

cat <<EOF
MechOS update bundle created.

Version: $VERSION
Bundle:  $OUTPUT
SHA256:  $SHA

Publish the bundle to an HTTPS release asset, then update updates/stable.json together:
  "version": "$VERSION",
  "bundle_url": "https://github.com/mechgod102-sketch/mechos/releases/download/v$VERSION/$(basename "$OUTPUT")",
  "bundle_sha256": "$SHA",
  "requires_reboot": true

Do not announce a newer stable manifest until the bundle URL is live and its SHA has been verified.
EOF
