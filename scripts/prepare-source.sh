#!/usr/bin/env bash
set -Eeuo pipefail

BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${1:-$BASE/work}"
SRC="$WORK/archlive"

case "$WORK" in
  "$BASE/work"|"$BASE/work/"*) ;;
  *)
    echo "Refusing to replace a staging directory outside $BASE/work" >&2
    exit 2
    ;;
esac

command -v mkarchiso >/dev/null 2>&1 || {
  echo "mkarchiso is unavailable. Run this helper on Arch Linux with the archiso package installed." >&2
  exit 127
}
command -v rsync >/dev/null 2>&1 || {
  echo "rsync is required to stage the MechOS overlay." >&2
  exit 127
}

[[ -d /usr/share/archiso/configs/releng ]] || {
  echo "The ArchISO releng profile is missing." >&2
  exit 1
}

mkdir -p "$WORK"
rm -rf "$SRC"
cp -a /usr/share/archiso/configs/releng "$SRC"
rsync -aHAX --numeric-ids "$BASE/overlay/rootfs/" "$SRC/airootfs/"

echo "$SRC"
