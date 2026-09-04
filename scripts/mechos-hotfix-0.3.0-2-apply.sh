#!/usr/bin/env bash
set -Eeuo pipefail

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-2-applied"
LOG=/var/log/mechos-hotfix-0.3.0-2.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 2 apply start"
[ -e "$MARKER" ] && exit 0

is_live(){
  [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null
}
is_live && { echo "Live ISO detected; Hotfix 2 installed-system repair skipped."; exit 0; }

install_mode_launcher(){
  mkdir -p /usr/local/bin /usr/share/applications /etc/skel/Desktop

  cat > /usr/local/bin/mechos-mode-launch <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:-}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG="$STATE_DIR/mode-shortcut.log"
mkdir -p "$STATE_DIR"

log(){ printf '[%s] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"; }
notify_error(){
  local msg="$1"
  log "ERROR: $msg"
  if command -v kdialog >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    kdialog --title "MechOS Mode Launcher" --error "$msg\n\nLog: $LOG" >/dev/null 2>&1 || true
  fi
}

case "$MODE" in gaming|mechscope|creator|desktop) ;; *) echo "Usage: mechos-mode-launch {gaming|mechscope|creator|desktop}" >&2; exit 2 ;; esac

# Account creation owns first boot. A mode shortcut clicked before OOBE now
# opens setup instead of silently doing nothing.
if [ -e /var/lib/mechos/installed ] && [ ! -e /var/lib/mechos/oobe-complete ]; then
  if [ "$(id -un)" = "mechos-setup" ] && [ -x /usr/local/bin/mechos-oobe-start ]; then
    nohup /usr/local/bin/mechos-oobe-start >>"$LOG" 2>&1 </dev/null &
  fi
  if command -v kdialog >/dev/null 2>&1; then
    kdialog --title "Finish MechOS Setup" --msgbox "Create your MechOS account before switching modes." >/dev/null 2>&1 || true
  fi
  exit 0
fi

virt="$(systemd-detect-virt 2>/dev/null || true)"
if [ -n "$virt" ] && [ "$virt" != "none" ]; then
  export MECHOS_VM_MODE=1 MECHOS_DISABLE_GAMESCOPE=1 QT_OPENGL=software LIBGL_ALWAYS_SOFTWARE=1 QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software
fi

systemctl --user import-environment \
  DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS \
  XDG_SESSION_TYPE XDG_CURRENT_DESKTOP KDE_FULL_SESSION KDE_SESSION_VERSION \
  MECHOS_VM_MODE MECHOS_DISABLE_GAMESCOPE QT_OPENGL LIBGL_ALWAYS_SOFTWARE \
  QT_QUICK_BACKEND QSG_RHI_BACKEND >/dev/null 2>&1 || true

wait_for_process(){
  local pattern="$1" i
  for i in $(seq 1 24); do
    pgrep -u "$(id -u)" -f "$pattern" >/dev/null 2>&1 && return 0
    sleep 0.125
  done
  return 1
}

delayed_stop_creator(){
  systemd-run --user --quiet --collect --unit="mechos-stop-creator-$$" \
    /bin/sh -c 'sleep 0.6; systemctl --user stop mechos-creator-mode.service mechos-vm-creator.service >/dev/null 2>&1 || true; pkill -TERM -u "$(id -u)" -f "/usr/local/bin/mechos-creator-mode([[:space:]]|$)|/usr/local/bin/mechos-creator-mode.real([[:space:]]|$)" >/dev/null 2>&1 || true' \
    >/dev/null 2>&1 || true
}

launch_mechscope(){
  if [ -n "$virt" ] && [ "$virt" != "none" ] && [ -x /usr/local/bin/mechos-vm-mode-runtime ]; then
    /usr/local/bin/mechos-vm-mode-runtime gaming >>"$LOG" 2>&1 || true
    if wait_for_process '/usr/local/bin/mechscope([[:space:]]|$)'; then delayed_stop_creator; return 0; fi
  fi

  if [ -x /usr/local/bin/mechos-gaming-layer-control ]; then
    /usr/local/bin/mechos-gaming-layer-control start >>"$LOG" 2>&1 || true
    if systemctl --user is-active --quiet mechos-gaming-layer.service 2>/dev/null || wait_for_process '/usr/local/bin/mechscope([[:space:]]|$)'; then
      delayed_stop_creator
      return 0
    fi
  fi

  [ -x /usr/local/bin/mechscope ] || return 1
  nohup /usr/local/bin/mechscope >>"$LOG" 2>&1 </dev/null &
  wait_for_process '/usr/local/bin/mechscope([[:space:]]|$)' && { delayed_stop_creator; return 0; }
  return 1
}

launch_creator(){
  [ -x /usr/local/bin/mechos-creator-mode ] || return 1

  if [ -n "$virt" ] && [ "$virt" != "none" ] && [ -x /usr/local/bin/mechos-vm-mode-runtime ]; then
    /usr/local/bin/mechos-vm-mode-runtime creator >>"$LOG" 2>&1 || true
    wait_for_process '/usr/local/bin/mechos-creator-mode' && return 0
  fi

  if [ -x /usr/local/bin/mechos-gaming-layer-control ]; then
    /usr/local/bin/mechos-gaming-layer-control creator >>"$LOG" 2>&1 || true
    wait_for_process '/usr/local/bin/mechos-creator-mode' && return 0
  fi

  if systemctl --user cat mechos-creator-mode.service >/dev/null 2>&1; then
    systemctl --user reset-failed mechos-creator-mode.service >/dev/null 2>&1 || true
    systemctl --user start mechos-creator-mode.service >>"$LOG" 2>&1 || true
    wait_for_process '/usr/local/bin/mechos-creator-mode' && return 0
  fi

  nohup /usr/local/bin/mechos-creator-mode >>"$LOG" 2>&1 </dev/null &
  wait_for_process '/usr/local/bin/mechos-creator-mode' && return 0
  return 1
}

case "$MODE" in
  gaming|mechscope)
    launch_mechscope || { notify_error "MechScope could not be started."; exit 1; }
    ;;
  creator)
    launch_creator || { notify_error "Creator Mode could not be started."; exit 1; }
    ;;
  desktop)
    if [ -n "$virt" ] && [ "$virt" != "none" ] && [ -x /usr/local/bin/mechos-vm-mode-runtime ]; then
      /usr/local/bin/mechos-vm-mode-runtime desktop >>"$LOG" 2>&1 || true
    elif [ -x /usr/local/bin/mechos-gaming-layer-control ]; then
      /usr/local/bin/mechos-gaming-layer-control desktop >>"$LOG" 2>&1 || true
    fi
    ;;
esac
EOF
  chmod 0755 /usr/local/bin/mechos-mode-launch
  bash -n /usr/local/bin/mechos-mode-launch

  cat > /usr/share/applications/mechos-return-gaming.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Return to MechScope
Comment=Open MechScope / Gaming Mode
Exec=/usr/local/bin/mechos-mode-launch gaming
TryExec=/usr/local/bin/mechos-mode-launch
Icon=applications-games
Terminal=false
StartupNotify=true
Categories=Game;System;
EOF

  cat > /usr/share/applications/mechos-creator-mode.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS Creator Mode
Comment=Open the MechOS creator workstation
Exec=/usr/local/bin/mechos-mode-launch creator
TryExec=/usr/local/bin/mechos-mode-launch
Icon=applications-graphics
Terminal=false
StartupNotify=true
Categories=Graphics;AudioVideo;Development;
EOF
  chmod 0644 /usr/share/applications/mechos-return-gaming.desktop /usr/share/applications/mechos-creator-mode.desktop

  cp -f /usr/share/applications/mechos-return-gaming.desktop /etc/skel/Desktop/Return-to-MechScope.desktop
  cp -f /usr/share/applications/mechos-creator-mode.desktop /etc/skel/Desktop/Creator-Mode.desktop
  chmod 0755 /etc/skel/Desktop/Return-to-MechScope.desktop /etc/skel/Desktop/Creator-Mode.desktop

  # Repair existing desktop copies as well as future accounts created by OOBE.
  while IFS=: read -r user _ uid _ _ home _; do
    [ "$uid" -ge 1000 ] 2>/dev/null || continue
    [ "$uid" -lt 60000 ] 2>/dev/null || continue
    [ "$user" != nobody ] || continue
    [ -d "$home" ] || continue
    mkdir -p "$home/Desktop"
    cp -f /usr/share/applications/mechos-return-gaming.desktop "$home/Desktop/Return-to-MechScope.desktop"
    cp -f /usr/share/applications/mechos-creator-mode.desktop "$home/Desktop/Creator-Mode.desktop"
    chmod 0755 "$home/Desktop/Return-to-MechScope.desktop" "$home/Desktop/Creator-Mode.desktop"
    chown "$user:$(id -gn "$user" 2>/dev/null || echo "$user")" "$home/Desktop/Return-to-MechScope.desktop" "$home/Desktop/Creator-Mode.desktop" 2>/dev/null || true
  done < /etc/passwd
}

repair_creator_alignment(){
  local file=/usr/local/share/mechos/ui/creator_shell.py
  [ -f "$file" ] || return 0
  python3 - "$file" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_CREATOR_REFERENCE_NATIVE_SCALE_V1'
if marker in t: raise SystemExit(0)
old='''def rr(x, y, w, h):\n    \"\"\"Convert approved-reference pixel coordinates to the 1920x1080 canvas.\"\"\"\n    return QRect(\n        round(x / REFERENCE_W * BASE_W),\n        round(y / REFERENCE_H * BASE_H),\n        round(w / REFERENCE_W * BASE_W),\n        round(h / REFERENCE_H * BASE_H),\n    )\n'''
new='''# MECHOS_CREATOR_REFERENCE_NATIVE_SCALE_V1\ndef rr(x, y, w, h):\n    \"\"\"Keep hit-zones in the approved reference image's native coordinates.\"\"\"\n    return QRect(x, y, w, h)\n'''
if old not in t: raise SystemExit(0)
t=t.replace(old,new,1)
needle='''class ReferenceHome(FixedCanvas):\n    \"\"\"Pixel-faithful Creator Mode home using the approved reference image.\"\"\"\n\n'''
insert='''class ReferenceHome(FixedCanvas):\n    \"\"\"Pixel-faithful Creator Mode home using the approved reference image.\"\"\"\n\n    def scale_factor(self):\n        if not self.width() or not self.height(): return 1.0\n        return min(self.width()/REFERENCE_W, self.height()/REFERENCE_H)\n\n    def origin(self):\n        s=self.scale_factor()\n        return int((self.width()-REFERENCE_W*s)/2), int((self.height()-REFERENCE_H*s)/2)\n\n'''
if needle in t: t=t.replace(needle,insert,1)
t=t.replace("target = self.scale_rect(QRect(0, 0, BASE_W, BASE_H))\n        painter.fillRect(target, QColor('#030711'))\n        if not self.reference.isNull():",
            "target = self.scale_rect(QRect(0, 0, REFERENCE_W, REFERENCE_H))\n        painter.fillRect(self.rect(), QColor('#030711'))\n        if not self.reference.isNull():",1)
compile(t,str(p),'exec'); p.write_text(t,encoding='utf-8')
PY
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$file" || true
}

repair_oobe(){
  [ -e "$STATE/installed" ] || return 0
  [ ! -e "$STATE/oobe-complete" ] || { echo "OOBE already complete; account creation will not be repeated."; return 0; }

  echo "OOBE incomplete; configuring account creation to start automatically on this boot."
  [ -x /usr/local/bin/mechos-oobe ] || { echo "ERROR: /usr/local/bin/mechos-oobe is missing from Hotfix 2 payload."; return 1; }
  [ -x /usr/local/libexec/mechos-oobe-apply ] || { echo "ERROR: OOBE apply helper is missing from Hotfix 2 payload."; return 1; }

  # Final OOBE handoff remains inside Plasma; MechScope/Creator start as the
  # selected fullscreen layer after setup. This works on physical and VM hosts.
  sed -i \
    -e 's/Session=mechos-gaming\.desktop/Session=plasma.desktop/g' \
    -e 's/Relogin=true/Relogin=false/g' \
    /usr/local/libexec/mechos-oobe-apply 2>/dev/null || true

  mkdir -p /etc/polkit-1/rules.d /etc/sddm.conf.d /etc/xdg/autostart "$STATE"
  cat > /etc/polkit-1/rules.d/49-mechos-oobe.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        subject.user == "mechos-setup" &&
        action.lookup("program") == "/usr/local/libexec/mechos-oobe-apply") {
        return polkit.Result.YES;
    }
});
EOF

  if ! id mechos-setup >/dev/null 2>&1; then
    groups="$(for g in wheel video audio input storage optical; do getent group "$g" >/dev/null 2>&1 && printf '%s,' "$g"; done | sed 's/,$//')"
    if [ -n "$groups" ]; then useradd -m -s /bin/bash -G "$groups" mechos-setup; else useradd -m -s /bin/bash mechos-setup; fi
  fi
  passwd -l mechos-setup >/dev/null 2>&1 || true

  cat > /usr/local/bin/mechos-oobe-start <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
STATE=/var/lib/mechos
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/mechos/oobe-start.log"
mkdir -p "$(dirname "$LOG")"
[ -e "$STATE/installed" ] || exit 0
[ ! -e "$STATE/oobe-complete" ] || exit 0
[ "$(id -un)" = mechos-setup ] || exit 0
[ -x /usr/local/bin/mechos-oobe ] || exit 1

# KDE normally passes these values to autostart directly. If this launcher is
# started by a repair/user service, import the live Plasma environment too.
for _ in $(seq 1 80); do
  if [ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && systemctl --user show-environment >/dev/null 2>&1; then
    while IFS='=' read -r key value; do
      case "$key" in
        DISPLAY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS|XDG_SESSION_TYPE|XDG_CURRENT_DESKTOP|KDE_FULL_SESSION|KDE_SESSION_VERSION)
          printf -v "$key" '%s' "$value"; export "$key" ;;
      esac
    done < <(systemctl --user show-environment)
  fi
  [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && break
  sleep 0.25
done
printf '[%s] launching account creation wayland=%s display=%s\n' "$(date -Is 2>/dev/null || date)" "${WAYLAND_DISPLAY:-}" "${DISPLAY:-}" >>"$LOG"
exec /usr/local/bin/mechos-oobe >>"$LOG" 2>&1
EOF
  chmod 0755 /usr/local/bin/mechos-oobe-start

  home="$(getent passwd mechos-setup | cut -d: -f6)"; [ -n "$home" ] || home=/home/mechos-setup
  mkdir -p "$home/.config/autostart"
  cat > "$home/.config/autostart/mechos-oobe.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS First System Setup
Exec=/usr/local/bin/mechos-oobe-start
TryExec=/usr/local/bin/mechos-oobe-start
Terminal=false
X-KDE-autostart-after=panel
EOF
  chown -R mechos-setup:mechos-setup "$home/.config" 2>/dev/null || true

  cat > /etc/xdg/autostart/mechos-oobe-authority.desktop <<'EOF'
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

  cat > /etc/sddm.conf.d/95-mechos-oobe.conf <<'EOF'
[Autologin]
User=mechos-setup
Session=plasma.desktop
Relogin=true
EOF

  printf 'pending\n' > "$STATE/oobe-pending"
  printf 'desktop\n' > "$STATE/firstboot-session"
  echo "Account creation is armed for the mechos-setup Plasma session."
}

install_mode_launcher
repair_creator_alignment
repair_oobe
systemctl daemon-reload >/dev/null 2>&1 || true

touch "$MARKER"
echo "[$(date -Is)] Hotfix 2 apply complete"
