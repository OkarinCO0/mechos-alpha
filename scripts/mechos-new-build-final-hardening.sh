#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
POSTINSTALL="$ROOT/usr/share/mechos/install-payload/mechos-postinstall-target"

log(){ printf '[MechOS New Build Final Hardening] %s\n' "$*"; }
fail(){ printf '[MechOS New Build Final Hardening] ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$ROOT" ] || fail "ArchISO rootfs missing"
[ -s "$ARCHIVE" ] || fail "installed-system payload missing"
[ -f "$POSTINSTALL" ] || fail "postinstall target missing"

patch_tree(){
  local tree="$1"
  local helper="$tree/usr/local/bin/mechos-update-helper"
  local mode="$tree/usr/local/bin/mechos-mode-launch"
  local creator_ui="$tree/usr/local/share/mechos/ui/creator_shell.py"

  # Every permanent account created by OOBE is put in wheel. Make wheel an
  # actual administrator group on installed MechOS so users never end up with
  # a valid password but "not in the sudoers file".
  mkdir -p "$tree/etc/sudoers.d"
  cat > "$tree/etc/sudoers.d/10-mechos-wheel" <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF
  chmod 0440 "$tree/etc/sudoers.d/10-mechos-wheel"

  # Normal Update Center checks run as the desktop user. Never use root-owned
  # /var/cache for manifest discovery; root keeps that cache only for apply.
  if [ -f "$helper" ]; then
    python3 - "$helper" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_FINAL_USER_UPDATE_CACHE_V1'
if marker not in t:
    old='CACHE_DIR="/var/cache/mechos/update-center"\n'
    new='''# MECHOS_FINAL_USER_UPDATE_CACHE_V1\nif [ "$(id -u)" -eq 0 ]; then\n  CACHE_DIR="/var/cache/mechos/update-center"\nelse\n  CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/mechos/update-center"\nfi\n'''
    if old in t:
        t=t.replace(old,new,1)
p.write_text(t,encoding='utf-8')
PY
    chmod 0755 "$helper"
    bash -n "$helper" || fail "update helper invalid in $tree"
  fi

  # Final authoritative desktop launchers. Both VM and physical systems go
  # through the shared mode launcher instead of stale direct executables.
  mkdir -p "$tree/usr/share/applications" "$tree/etc/skel/Desktop"
  cat > "$tree/usr/share/applications/mechos-return-gaming.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Return to MechScope
Comment=Return to MechScope / Gaming Mode
Exec=/usr/local/bin/mechos-mode-launch gaming
TryExec=/usr/local/bin/mechos-mode-launch
Icon=applications-games
Terminal=false
StartupNotify=true
Categories=Game;System;
EOF
  cat > "$tree/usr/share/applications/mechos-creator-mode.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS Creator Mode
Comment=Open MechOS Creator Mode
Exec=/usr/local/bin/mechos-mode-launch creator
TryExec=/usr/local/bin/mechos-mode-launch
Icon=applications-graphics
Terminal=false
StartupNotify=true
Categories=Graphics;AudioVideo;Development;
EOF
  cp -f "$tree/usr/share/applications/mechos-return-gaming.desktop" "$tree/etc/skel/Desktop/Return-to-MechScope.desktop"
  cp -f "$tree/usr/share/applications/mechos-creator-mode.desktop" "$tree/etc/skel/Desktop/Creator-Mode.desktop"
  chmod 0644 "$tree/usr/share/applications/mechos-return-gaming.desktop" "$tree/usr/share/applications/mechos-creator-mode.desktop"
  chmod 0755 "$tree/etc/skel/Desktop/Return-to-MechScope.desktop" "$tree/etc/skel/Desktop/Creator-Mode.desktop"

  # Creator reference artwork and hit zones must share the same native design
  # coordinate system or the visual UI and clickable controls drift apart.
  if [ -f "$creator_ui" ]; then
    python3 - "$creator_ui" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_CREATOR_REFERENCE_NATIVE_SCALE_V1'
if marker not in t:
    old='''def rr(x, y, w, h):\n    \"\"\"Convert approved-reference pixel coordinates to the 1920x1080 canvas.\"\"\"\n    return QRect(\n        round(x / REFERENCE_W * BASE_W),\n        round(y / REFERENCE_H * BASE_H),\n        round(w / REFERENCE_W * BASE_W),\n        round(h / REFERENCE_H * BASE_H),\n    )\n'''
    new='''# MECHOS_CREATOR_REFERENCE_NATIVE_SCALE_V1\ndef rr(x, y, w, h):\n    \"\"\"Keep controls in the approved reference image coordinate system.\"\"\"\n    return QRect(x, y, w, h)\n'''
    if old in t:
        t=t.replace(old,new,1)
compile(t,str(p),'exec'); p.write_text(t,encoding='utf-8')
PY
    PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$creator_ui" || fail "Creator UI invalid in $tree"
  fi

  # If a shared launcher exists, it must expose both destinations. This keeps
  # desktop icons from silently succeeding while launching nothing.
  if [ -f "$mode" ]; then
    chmod 0755 "$mode"
    bash -n "$mode" || fail "mode launcher invalid in $tree"
    grep -Fq 'creator' "$mode" || fail "mode launcher has no Creator route in $tree"
    grep -Eq 'gaming|mechscope' "$mode" || fail "mode launcher has no MechScope route in $tree"
  fi
}

# Make account creation a mandatory first installed boot, not an optional app.
# Re-assert the postinstall OOBE setup account and Plasma handoff if a later
# integration changed them.
python3 - "$POSTINSTALL" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
required=('mechos-setup','oobe-pending','Session=plasma.desktop','mechos-oobe')
missing=[x for x in required if x not in t]
if missing:
    raise SystemExit('[MechOS New Build Final Hardening] postinstall OOBE contract missing: '+', '.join(missing))
PY

patch_tree "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xpf "$ARCHIVE" -C "$tmp"
patch_tree "$tmp"

for f in \
  "$tmp/usr/local/bin/mechos-oobe" \
  "$tmp/usr/local/libexec/mechos-oobe-apply" \
  "$tmp/usr/local/bin/mechos-mode-launch" \
  "$tmp/usr/share/applications/mechos-return-gaming.desktop" \
  "$tmp/usr/share/applications/mechos-creator-mode.desktop" \
  "$tmp/etc/sudoers.d/10-mechos-wheel"; do
  [ -e "$f" ] || fail "required installed payload file missing: ${f#$tmp}"
done

# OOBE must produce a wheel/admin account.
grep -Eq 'wheel' "$tmp/usr/local/libexec/mechos-oobe-apply" \
  || fail "OOBE apply does not grant wheel membership"

# First-boot authority must exist so account creation starts automatically on VM
# and physical hardware before normal modes are available.
[ -e "$tmp/usr/lib/systemd/system/mechos-firstboot-authority.service" ] \
  || fail "firstboot OOBE authority service missing"
[ -x "$tmp/usr/local/bin/mechos-oobe-start" ] \
  || fail "OOBE autostart launcher missing"

new="$ARCHIVE.final-hardening"
tar --zstd -cpf "$new" -C "$tmp" .
mv -f "$new" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

log 'New install contract hardened: automatic OOBE, real wheel sudo, writable update checks, working Creator/MechScope shortcuts, and Creator alignment validation'
