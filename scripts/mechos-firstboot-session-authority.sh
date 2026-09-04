#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log(){ printf '[MechOS Firstboot Authority] %s\n' "$*"; }
fail(){ printf '[MechOS Firstboot Authority] ERROR: %s\n' "$*" >&2; exit 1; }

install_authority(){
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local libexec="$tree/usr/local/libexec"
  local systemd="$tree/usr/lib/systemd/system"
  local wants="$tree/etc/systemd/system/graphical.target.wants"
  local autostart="$tree/etc/xdg/autostart"
  mkdir -p "$bin" "$libexec" "$systemd" "$wants" "$autostart"

  cat > "$libexec/mechos-firstboot-authority" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

STATE=/var/lib/mechos
SDDM=/etc/sddm.conf.d/95-mechos-oobe.conf
SETUP_USER=mechos-setup

is_live(){
  [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null
}

is_live && exit 0
mkdir -p "$STATE"
[ -e "$STATE/installed" ] || exit 0
[ ! -e "$STATE/oobe-complete" ] || exit 0

if ! id "$SETUP_USER" >/dev/null 2>&1; then
  groups="$(for g in wheel video audio input storage optical; do getent group "$g" >/dev/null 2>&1 && printf '%s,' "$g"; done | sed 's/,$//')"
  if [ -n "$groups" ]; then
    useradd -m -s /bin/bash -G "$groups" "$SETUP_USER"
  else
    useradd -m -s /bin/bash "$SETUP_USER"
  fi
fi
passwd -l "$SETUP_USER" >/dev/null 2>&1 || true

home="$(getent passwd "$SETUP_USER" | cut -d: -f6)"
[ -n "$home" ] || home="/home/$SETUP_USER"
mkdir -p "$home/.config/autostart" /etc/sddm.conf.d
cat > "$home/.config/autostart/mechos-oobe.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=MechOS First System Setup
Exec=/usr/local/bin/mechos-oobe-start
TryExec=/usr/local/bin/mechos-oobe-start
Terminal=false
X-KDE-autostart-after=panel
DESKTOP
chown -R "$SETUP_USER:$SETUP_USER" "$home/.config"

cat > "$SDDM" <<'SDDMEOF'
[Autologin]
User=mechos-setup
Session=plasma.desktop
Relogin=true
SDDMEOF

printf 'pending\n' > "$STATE/oobe-pending"
printf 'desktop\n' > "$STATE/firstboot-session"
EOF
  chmod 0755 "$libexec/mechos-firstboot-authority"

  cat > "$bin/mechos-oobe-start" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

STATE=/var/lib/mechos
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/mechos/oobe-start.log"
mkdir -p "$(dirname "$LOG")"

[ -e "$STATE/installed" ] || exit 0
[ ! -e "$STATE/oobe-complete" ] || exit 0
[ "$(id -un)" = "mechos-setup" ] || exit 0
[ -x /usr/local/bin/mechos-oobe ] || {
  printf '[%s] mechos-oobe executable missing\n' "$(date -Is 2>/dev/null || date)" >>"$LOG"
  exit 1
}

for _ in $(seq 1 80); do
  if [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    break
  fi
  sleep 0.25
done

printf '[%s] launching first-run account setup wayland=%s display=%s\n' \
  "$(date -Is 2>/dev/null || date)" "${WAYLAND_DISPLAY:-}" "${DISPLAY:-}" >>"$LOG"
exec /usr/local/bin/mechos-oobe >>"$LOG" 2>&1
EOF
  chmod 0755 "$bin/mechos-oobe-start"

  cat > "$systemd/mechos-firstboot-authority.service" <<'EOF'
[Unit]
Description=Prepare MechOS first-boot account setup before SDDM
After=local-fs.target
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/oobe-complete

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-firstboot-authority

[Install]
WantedBy=graphical.target
EOF

  ln -sfn /usr/lib/systemd/system/mechos-firstboot-authority.service \
    "$wants/mechos-firstboot-authority.service"

  cat > "$autostart/mechos-oobe-authority.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS First System Setup Authority
Exec=/usr/local/bin/mechos-oobe-start
TryExec=/usr/local/bin/mechos-oobe-start
Terminal=false
NoDisplay=true
OnlyShowIn=KDE;
X-KDE-autostart-after=panel
EOF
}

patch_vm_gate(){
  local tree="$1"
  local runtime="$tree/usr/local/bin/mechos-vm-mode-runtime"
  [ -f "$runtime" ] || fail "VM mode runtime missing in $tree"
  python3 - "$runtime" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_VM_OOBE_GATE_V1'
if marker in t:
    raise SystemExit(0)
needle='export MECHOS_VM_MODE=1\n'
idx=t.find(needle)
if idx < 0:
    raise SystemExit('[MechOS Firstboot Authority] VM runtime environment anchor missing')
block=r'''# MECHOS_VM_OOBE_GATE_V1
# First boot owns the VM session until account creation is complete. Never let
# MechScope or Creator race the temporary setup account/Plasma session.
if [ -e /var/lib/mechos/installed ] && [ ! -e /var/lib/mechos/oobe-complete ]; then
  if [ "$(id -un)" = "mechos-setup" ]; then
    /usr/local/bin/mechos-oobe-start >/dev/null 2>&1 &
  fi
  log "OOBE incomplete; VM mode launch blocked until account creation finishes"
  exit 0
fi

'''
t=t[:idx]+block+t[idx:]
p.write_text(t,encoding='utf-8')
PY
  chmod 0755 "$runtime"
  bash -n "$runtime" || fail "VM runtime invalid after OOBE gate"
}

patch_tree(){
  local tree="$1"
  install_authority "$tree"
  patch_vm_gate "$tree"
}

patch_tree "$ROOT"
if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xpf "$ARCHIVE" -C "$tmp"
  patch_tree "$tmp"
  replacement="$ARCHIVE.firstboot-authority"
  tar --zstd -cpf "$replacement" -C "$tmp" .
  mv -f "$replacement" "$ARCHIVE"
  rm -rf "$tmp"; trap - EXIT
fi

log 'Account creation is now a system-level pre-SDDM gate; VM MechScope/Creator remain blocked until OOBE completes'
