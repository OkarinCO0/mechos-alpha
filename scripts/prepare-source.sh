#!/usr/bin/env bash
set -Eeuo pipefail
BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${1:-$BASE/work}"
SRC="$WORK/fedora-kiwi-descriptions"
mkdir -p "$WORK"
rm -rf "$SRC"

# Fail closed: MechOS 0.3.2 is a Fedora 44 build and must never silently
# fall back to Rawhide or another release branch.
URLS=(
  "https://forge.fedoraproject.org/releng/kiwi-descriptions.git"
  "https://pagure.io/fedora-kiwi-descriptions.git"
)
for url in "${URLS[@]}"; do
  echo "Trying Fedora 44 KIWI source: $url" >&2
  if git clone --depth 1 --branch f44 "$url" "$SRC" 2>/dev/null; then
    break
  fi
  rm -rf "$SRC"
done
[[ -d "$SRC/.git" ]] || {
  echo "Could not clone the Fedora 44 (f44) KIWI descriptions. Refusing to build from another release." >&2
  exit 1
}

[[ -f "$SRC/Fedora.kiwi" ]] || { echo "Fedora.kiwi missing from Fedora source." >&2; exit 1; }
grep -Eq '<(version|release-version)>44</(version|release-version)>' "$SRC/Fedora.kiwi" || {
  echo "Fedora source does not identify itself as release 44. Refusing to continue." >&2
  exit 1
}
grep -Rqs 'KDE-Desktop-Live' "$SRC" || {
  echo "KDE-Desktop-Live profile not found in Fedora source." >&2
  exit 1
}

rsync -a "$BASE/overlay/rootfs/" "$SRC/root/"
python3 "$BASE/scripts/patch-fedora-kiwi.py" "$SRC" "$BASE/kiwi/mechos.xml"

if ! grep -q 'MECHOS-0.3.2-CONFIG' "$SRC/config.sh"; then
cat >> "$SRC/config.sh" <<'FRAG'

# MECHOS-0.3.2-CONFIG
if [[ " ${kiwi_profiles:-} " == *" KDE-Desktop-Live "* ]] || [[ "${kiwi_profiles:-}" == *"KDE-Desktop-Live"* ]]; then
    chmod +x /usr/local/bin/mechscope-session /usr/local/bin/mechos-session-select \
      /usr/local/bin/steamos-session-select /usr/local/bin/mechos-firstboot \
      /usr/local/bin/mechos-gpu-setup /usr/local/bin/mechos-creator-setup \
      /usr/local/bin/mechos-snapshot /usr/local/bin/mechos-update \
      /usr/local/bin/mechos-install /usr/local/bin/mechos-live-welcome \
      /usr/local/bin/mechos-live-shortcuts /usr/local/lib/mechos/runtime.sh || true
    systemctl enable sddm.service || true
    systemctl enable mechos-firstboot.service || true
    plymouth-set-default-theme mechos || true
fi
# END-MECHOS-0.3.2-CONFIG
FRAG
fi

python3 - "$SRC/Fedora.kiwi" <<'PY'
import sys, xml.etree.ElementTree as ET
ET.parse(sys.argv[1])
print("Patched Fedora.kiwi is well-formed XML", file=sys.stderr)
PY

echo "$SRC"
