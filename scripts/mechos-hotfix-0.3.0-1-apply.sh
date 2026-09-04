#!/usr/bin/env bash
set -Eeuo pipefail

# Runs once on the first boot after MechOS v0.3.0-hotfix.1 is installed through
# Update Center. It only repairs installed-system runtime state that Update
# Center v1 intentionally does not write directly (boot/initramfs config and
# in-place routing of generated controller/session scripts).

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-1-applied"
LOG=/var/log/mechos-hotfix-0.3.0-1.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 1 apply start"
[ -e "$MARKER" ] && exit 0

patch_control(){
  local control=/usr/local/bin/mechos-gaming-layer-control
  [ -f "$control" ] || return 0
  python3 - "$control" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_VM_MODE_RUNTIME_ROUTER_V1'
if marker in t: raise SystemExit(0)
lines=t.splitlines(True)
insert=1
if len(lines)>1 and lines[1].lstrip().startswith('set '): insert=2
block=r'''# MECHOS_VM_MODE_RUNTIME_ROUTER_V1
_mechos_virt="$(systemd-detect-virt 2>/dev/null || true)"
if [ -n "$_mechos_virt" ] && [ "$_mechos_virt" != "none" ] && \
   [ ! -e /run/archiso/bootmnt ] && ! grep -q 'archiso' /proc/cmdline 2>/dev/null; then
  exec /usr/local/bin/mechos-vm-mode-runtime "${1:-start}"
fi

'''
lines.insert(insert,block)
p.write_text(''.join(lines),encoding='utf-8')
PY
  chmod 755 "$control"
  bash -n "$control"
}

patch_session(){
  local session=/usr/local/bin/mechscope-session
  [ -f "$session" ] || return 0
  python3 - "$session" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_VM_PLASMA_HOST_V2'
if marker in t: raise SystemExit(0)
pat=re.compile(r'''VIRT="\$\(systemd-detect-virt 2>/dev/null \|\| true\)"\nif \[\[ -n "\$VIRT" && "\$VIRT" != "none" \]\]; then\n.*?\n  start_plasma_mechscope\nfi''',re.S)
replacement=r'''VIRT="$(systemd-detect-virt 2>/dev/null || true)"
if [[ -n "$VIRT" && "$VIRT" != "none" ]]; then
  # MECHOS_VM_PLASMA_HOST_V2
  export MECHOS_VM_MODE=1
  export MECHOS_DISABLE_GAMESCOPE=1
  export QT_OPENGL=software
  export LIBGL_ALWAYS_SOFTWARE=1
  export QT_QUICK_BACKEND=software
  export QSG_RHI_BACKEND=software
  printf '[MechOS] virtualization=%s; Plasma hosts VM modes; graphical autostart owns MechScope launch.\n' "$VIRT" >>"$LOG_FILE"
  exec /usr/bin/startplasma-wayland
fi'''
new,n=pat.subn(replacement,t,count=1)
if n==1: p.write_text(new,encoding='utf-8')
PY
  chmod 755 "$session"
  bash -n "$session"
}

repair_splash(){
  if [ -f /etc/mkinitcpio.conf ] && grep -q '^HOOKS=' /etc/mkinitcpio.conf && ! grep '^HOOKS=' /etc/mkinitcpio.conf | grep -qw plymouth; then
    if grep '^HOOKS=' /etc/mkinitcpio.conf | grep -qw systemd; then
      sed -i -E '/^HOOKS=/ s/(^HOOKS=\([^)]*\bsystemd\b)/\1 plymouth/' /etc/mkinitcpio.conf
    elif grep '^HOOKS=' /etc/mkinitcpio.conf | grep -qw udev; then
      sed -i -E '/^HOOKS=/ s/(^HOOKS=\([^)]*\budev\b)/\1 plymouth/' /etc/mkinitcpio.conf
    else
      sed -i -E '/^HOOKS=/ s/\)$/ plymouth)/' /etc/mkinitcpio.conf
    fi
  fi

  mkdir -p /etc/plymouth
  cat > /etc/plymouth/plymouthd.conf <<'EOF'
[Daemon]
Theme=mechos
ShowDelay=0
DeviceTimeout=8
EOF
  command -v plymouth-set-default-theme >/dev/null 2>&1 && plymouth-set-default-theme mechos >/dev/null 2>&1 || true

  if [ -f /etc/kernel/cmdline ] && ! grep -qw splash /etc/kernel/cmdline; then
    sed -i '1 s/$/ quiet splash loglevel=3 rd.systemd.show_status=auto vt.global_cursor_default=0/' /etc/kernel/cmdline
  fi
  if [ -d /boot/loader/entries ]; then
    for entry in /boot/loader/entries/*.conf; do
      [ -f "$entry" ] || continue
      if grep -q '^options ' "$entry" && ! grep '^options ' "$entry" | grep -qw splash; then
        sed -i '/^options / s/$/ quiet splash loglevel=3 rd.systemd.show_status=auto vt.global_cursor_default=0/' "$entry"
      fi
    done
  fi
  if [ -f /etc/default/grub ]; then
    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
      if ! grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | grep -qw splash; then
        sed -i -E 's|^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"|GRUB_CMDLINE_LINUX_DEFAULT="\1 quiet splash loglevel=3 rd.systemd.show_status=auto vt.global_cursor_default=0"|' /etc/default/grub
      fi
    else
      echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 rd.systemd.show_status=auto vt.global_cursor_default=0"' >> /etc/default/grub
    fi
    command -v grub-mkconfig >/dev/null 2>&1 && grub-mkconfig -o /boot/grub/grub.cfg || true
  fi
  command -v mkinitcpio >/dev/null 2>&1 && mkinitcpio -P || true
}

patch_control
patch_session
repair_splash
systemctl daemon-reload || true
touch "$MARKER"
echo "[$(date -Is)] Hotfix 1 apply complete"
