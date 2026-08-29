#!/usr/bin/env bash
set -Eeuo pipefail
BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK="${MECHOS_WORKDIR:-$BASE/work}"
OUT="${MECHOS_OUTDIR:-$BASE/out}"

source /etc/os-release
if [[ "${ID:-}" != "fedora" || "${VERSION_ID:-}" != "44" ]]; then
  cat >&2 <<MSG
MechOS 0.3.2 uses Fedora 44's KIWI live-image tooling.
Run this builder on Fedora 44 (native or a Fedora 44 VM).
Current host: ${PRETTY_NAME:-unknown}
MSG
  exit 1
fi

for cmd in git rsync python3 kiwi-ng; do
  command -v "$cmd" >/dev/null || {
    echo "Missing $cmd. Run: sudo ./scripts/setup-build-host.sh" >&2
    exit 1
  }
done

mkdir -p "$OUT"
SRC="$("$BASE/scripts/prepare-source.sh" "$WORK" | tail -n 1)"
cd "$SRC"

echo "Building MechOS 0.3.2 from Fedora KDE-Desktop-Live..."
sudo ./kiwi-build \
  --kiwi-file=Fedora.kiwi \
  --image-type=iso \
  --image-profile=KDE-Desktop-Live \
  --image-release=0.3.2 \
  --output-dir="$OUT"

ISO="$(find "$OUT" -maxdepth 1 -type f -name '*.iso' -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-)"
if [[ -z "$ISO" ]]; then
  echo "KIWI finished but no ISO was found in $OUT" >&2
  exit 1
fi
NEW="$OUT/MechOS-0.3.2-alpha-x86_64.iso"
cp -f "$ISO" "$NEW"
sha256sum "$NEW" > "$NEW.sha256"
echo "Built: $NEW"
echo "Checksum: $NEW.sha256"
