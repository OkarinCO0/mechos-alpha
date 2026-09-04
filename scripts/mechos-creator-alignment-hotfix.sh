#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log(){ printf '[MechOS Creator Alignment] %s\n' "$*"; }
fail(){ printf '[MechOS Creator Alignment] ERROR: %s\n' "$*" >&2; exit 1; }

patch_file(){
  local file="$1"
  [ -f "$file" ] || return 0
  python3 - "$file" <<'PY'
from pathlib import Path
import sys

p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')
marker='# MECHOS_CREATOR_REFERENCE_NATIVE_SCALE_V1'
if marker in t:
    raise SystemExit(0)

old='''def rr(x, y, w, h):\n    \"\"\"Convert approved-reference pixel coordinates to the 1920x1080 canvas.\"\"\"\n    return QRect(\n        round(x / REFERENCE_W * BASE_W),\n        round(y / REFERENCE_H * BASE_H),\n        round(w / REFERENCE_W * BASE_W),\n        round(h / REFERENCE_H * BASE_H),\n    )\n'''
new='''# MECHOS_CREATOR_REFERENCE_NATIVE_SCALE_V1\ndef rr(x, y, w, h):\n    \"\"\"Keep hit-zones in the approved reference image's native coordinates.\"\"\"\n    return QRect(x, y, w, h)\n'''
if old not in t:
    raise SystemExit('[MechOS Creator Alignment] reference coordinate helper not found')
t=t.replace(old,new,1)

needle='''class ReferenceHome(FixedCanvas):\n    \"\"\"Pixel-faithful Creator Mode home using the approved reference image.\"\"\"\n\n'''
insert='''class ReferenceHome(FixedCanvas):\n    \"\"\"Pixel-faithful Creator Mode home using the approved reference image.\"\"\"\n\n    # Use the artwork's native 1672x941 coordinate system for both painting and\n    # interactive hit-zones. This avoids the previous two-stage 1672->1920->\n    # window rounding that made hover/focus outlines drift away from cards.\n    def scale_factor(self):\n        if not self.width() or not self.height():\n            return 1.0\n        return min(self.width() / REFERENCE_W, self.height() / REFERENCE_H)\n\n    def origin(self):\n        s = self.scale_factor()\n        return int((self.width() - REFERENCE_W * s) / 2), int((self.height() - REFERENCE_H * s) / 2)\n\n'''
if needle not in t:
    raise SystemExit('[MechOS Creator Alignment] ReferenceHome anchor not found')
t=t.replace(needle,insert,1)

t=t.replace('target = self.scale_rect(QRect(0, 0, BASE_W, BASE_H))\n        painter.fillRect(target, QColor(\'#030711\'))\n        if not self.reference.isNull():',
            'target = self.scale_rect(QRect(0, 0, REFERENCE_W, REFERENCE_H))\n        painter.fillRect(self.rect(), QColor(\'#030711\'))\n        if not self.reference.isNull():',1)

compile(t,str(p),'exec')
p.write_text(t,encoding='utf-8')
PY
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$file" || fail "Creator UI syntax failed: $file"
  grep -Fq 'MECHOS_CREATOR_REFERENCE_NATIVE_SCALE_V1' "$file" || fail "alignment marker missing: $file"
}

patch_tree(){
  local tree="$1"
  patch_file "$tree/usr/local/share/mechos/ui/creator_shell.py"
}

patch_tree "$ROOT"
if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xpf "$ARCHIVE" -C "$tmp"
  patch_tree "$tmp"
  replacement="$ARCHIVE.creator-alignment"
  tar --zstd -cpf "$replacement" -C "$tmp" .
  mv -f "$replacement" "$ARCHIVE"
  rm -rf "$tmp"; trap - EXIT
fi

log 'Creator Mode artwork and interactive regions now share one native reference coordinate system'
