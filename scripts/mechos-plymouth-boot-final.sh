#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHLIVE="/workspace/archlive"
HELPER="$ROOT/usr/local/libexec/mechos-native-install-helper"

log(){ printf '[MechOS Plymouth Final] %s\n' "$*"; }
fail(){ printf '[MechOS Plymouth Final] ERROR: %s\n' "$*" >&2; exit 1; }

ensure_hook_file(){
  local cfg="$1"
  [ -f "$cfg" ] || return 0
  grep -q '^HOOKS=' "$cfg" || return 0
  grep '^HOOKS=' "$cfg" | grep -qw plymouth && return 0
  if grep '^HOOKS=' "$cfg" | grep -qw systemd; then
    sed -i -E '/^HOOKS=/ s/(^HOOKS=\([^)]*\bsystemd\b)/\1 plymouth/' "$cfg"
  elif grep '^HOOKS=' "$cfg" | grep -qw udev; then
    sed -i -E '/^HOOKS=/ s/(^HOOKS=\([^)]*\budev\b)/\1 plymouth/' "$cfg"
  else
    sed -i -E '/^HOOKS=/ s/\)$/ plymouth)/' "$cfg"
  fi
}

# ArchISO commonly owns its initramfs hooks in mkinitcpio.conf.d rather than
# /etc/mkinitcpio.conf. Cover both so the Live ISO itself can actually start
# Plymouth.
ensure_hook_file "$ROOT/etc/mkinitcpio.conf"
for cfg in "$ROOT"/etc/mkinitcpio.conf.d/*.conf; do
  [ -e "$cfg" ] || continue
  ensure_hook_file "$cfg"
done

# Make sure every Live bootloader path tells the kernel to show Plymouth.
python3 - "$ARCHLIVE" <<'PY'
from pathlib import Path
import sys,re
root=Path(sys.argv[1])
tokens='quiet splash loglevel=3 rd.systemd.show_status=auto vt.global_cursor_default=0'
changed=[]
for sub in ('efiboot/loader/entries','syslinux','grub'):
    base=root/sub
    if not base.exists():
        continue
    for p in base.rglob('*'):
        if not p.is_file() or p.suffix.lower() not in ('.conf','.cfg'):
            continue
        try: text=p.read_text(encoding='utf-8')
        except Exception: continue
        out=[]; touched=False
        for line in text.splitlines(True):
            stripped=line.lstrip()
            is_boot=(
                stripped.startswith('options ') or
                stripped.startswith('APPEND ') or
                re.match(r'linux(?:efi)?\s', stripped, re.I)
            )
            if is_boot and ('archisobasedir=' in line or 'archisolabel=' in line) and not re.search(r'(^|\s)splash($|\s)', line):
                nl='\n' if line.endswith('\n') else ''
                line=line.rstrip('\r\n')+' '+tokens+nl
                touched=True
            out.append(line)
        if touched:
            p.write_text(''.join(out),encoding='utf-8')
            changed.append(str(p))
print('[MechOS Plymouth Final] Live boot configs patched:', ', '.join(changed) if changed else 'none-found')
PY

# Clean Install is now native. The old mechos-postinstall-target is not part of
# that path, so enforce Plymouth inside the actual native installer helper before
# its mkinitcpio and GRUB generation steps.
[ -f "$HELPER" ] || fail "native installer helper missing: $HELPER"
python3 - "$HELPER" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); text=p.read_text(encoding='utf-8')
marker='# MECHOS_NATIVE_PLYMOUTH_BOOT_V1'
if marker in text:
    raise SystemExit(0)
anchor='progress 86 "Generating initramfs"'
pos=text.find(anchor)
if pos < 0:
    raise SystemExit('[MechOS Plymouth Final] native initramfs anchor missing')
block=r'''# MECHOS_NATIVE_PLYMOUTH_BOOT_V1
# The native Clean Install path never runs the old postinstall-target script.
# Reassert the approved theme, include Plymouth in the installed initramfs, and
# add the required kernel command-line flags before bootloader generation.
mkdir -p "$MNT/etc/plymouth"
cat > "$MNT/etc/plymouth/plymouthd.conf" <<'PLYEOF'
[Daemon]
Theme=mechos
ShowDelay=0
DeviceTimeout=8
PLYEOF

ensure_target_plymouth_hook() {
  local cfg="$1"
  [ -f "$cfg" ] || return 0
  grep -q '^HOOKS=' "$cfg" || return 0
  grep '^HOOKS=' "$cfg" | grep -qw plymouth && return 0
  if grep '^HOOKS=' "$cfg" | grep -qw systemd; then
    sed -i -E '/^HOOKS=/ s/(^HOOKS=\([^)]*\bsystemd\b)/\1 plymouth/' "$cfg"
  elif grep '^HOOKS=' "$cfg" | grep -qw udev; then
    sed -i -E '/^HOOKS=/ s/(^HOOKS=\([^)]*\budev\b)/\1 plymouth/' "$cfg"
  else
    sed -i -E '/^HOOKS=/ s/\)$/ plymouth)/' "$cfg"
  fi
}
ensure_target_plymouth_hook "$MNT/etc/mkinitcpio.conf"
for cfg in "$MNT"/etc/mkinitcpio.conf.d/*.conf; do
  [ -e "$cfg" ] || continue
  ensure_target_plymouth_hook "$cfg"
done

if [ -x "$MNT/usr/bin/plymouth-set-default-theme" ]; then
  arch-chroot "$MNT" plymouth-set-default-theme mechos >/dev/null 2>&1 || true
fi

if [ -f "$MNT/etc/default/grub" ]; then
  if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$MNT/etc/default/grub"; then
    if ! grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$MNT/etc/default/grub" | grep -qw splash; then
      sed -i -E 's|^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"|GRUB_CMDLINE_LINUX_DEFAULT="\1 quiet splash loglevel=3 rd.systemd.show_status=auto vt.global_cursor_default=0"|' "$MNT/etc/default/grub"
    fi
  else
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 rd.systemd.show_status=auto vt.global_cursor_default=0"' >> "$MNT/etc/default/grub"
  fi
fi

'''
text=text[:pos]+block+text[pos:]
p.write_text(text,encoding='utf-8')
PY
bash -n "$HELPER" || fail "native installer helper syntax failed after Plymouth patch"
grep -Fq 'MECHOS_NATIVE_PLYMOUTH_BOOT_V1' "$HELPER" || fail "native Plymouth marker missing"
grep -Fq 'GRUB_CMDLINE_LINUX_DEFAULT' "$HELPER" || fail "native GRUB splash enforcement missing"
grep -Fq 'mkinitcpio.conf.d/*.conf' "$HELPER" || fail "native mkinitcpio drop-in hook enforcement missing"

log 'Plymouth is now enforced in Live ArchISO boot configs and the native installed-system boot path'
