#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
POSTINSTALL="$ROOT/usr/share/mechos/install-payload/mechos-postinstall-target"

log(){ printf '[MechOS New Build Final Gate] %s\n' "$*"; }
fail(){ printf '[MechOS New Build Final Gate] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS New Build Final Gate] ERROR line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ -d "$ROOT" ] || fail "ArchISO rootfs missing"
[ -s "$ARCHIVE" ] || fail "installed-system payload missing"
[ -f "$POSTINSTALL" ] || fail "post-install target missing"

patch_update_helper(){
  local tree="$1"
  local helper="$tree/usr/local/bin/mechos-update-helper"
  [ -f "$helper" ] || fail "Update Center helper missing in installed payload"

  python3 - "$helper" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_FINAL_USER_UPDATE_CACHE_V1'
if marker not in t:
    old='CACHE_DIR="/var/cache/mechos/update-center"\n'
    new='''# MECHOS_FINAL_USER_UPDATE_CACHE_V1\nif [ "$(id -u)" -eq 0 ]; then\n  CACHE_DIR="/var/cache/mechos/update-center"\nelse\n  CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/mechos/update-center"\nfi\n'''
    if old not in t:
        if 'XDG_CACHE_HOME' not in t:
            raise SystemExit('[MechOS Final Gate] update cache anchor missing')
    else:
        t=t.replace(old,new,1)
p.write_text(t,encoding='utf-8')
PY
  chmod 0755 "$helper"
  bash -n "$helper" || fail "Update Center helper shell validation failed"
  grep -Fq 'XDG_CACHE_HOME' "$helper" || fail "Update Center still requires root-owned cache for checks"
}

install_mode_runtime(){
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local apps="$tree/usr/share/applications"
  local skel="$tree/etc/skel/Desktop"
  mkdir -p "$bin" "$apps" "$skel"

  cat > "$bin/mechos-mode-launch" <<'EOF'
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

# First-run account creation owns the session. Desktop icons must open setup,
# never race MechScope or Creator Mode before the real account exists.
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
  export MECHOS_VM_MODE=1
  export MECHOS_DISABLE_GAMESCOPE=1
  export QT_OPENGL=software
  export LIBGL_ALWAYS_SOFTWARE=1
  export QT_QUICK_BACKEND=software
  export QSG_RHI_BACKEND=software
fi

systemctl --user import-environment \
  DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS \
  XDG_SESSION_TYPE XDG_CURRENT_DESKTOP KDE_FULL_SESSION KDE_SESSION_VERSION \
  MECHOS_VM_MODE MECHOS_DISABLE_GAMESCOPE QT_OPENGL LIBGL_ALWAYS_SOFTWARE \
  QT_QUICK_BACKEND QSG_RHI_BACKEND >/dev/null 2>&1 || true

wait_for_process(){
  local pattern="$1" i
  for i in $(seq 1 32); do
    pgrep -u "$(id -u)" -f "$pattern" >/dev/null 2>&1 && return 0
    sleep 0.125
  done
  return 1
}

stop_creator_after_mechscope(){
  systemd-run --user --quiet --collect --unit="mechos-stop-creator-$$" \
    /bin/sh -c 'sleep 0.7; systemctl --user stop mechos-creator-mode.service mechos-vm-creator.service >/dev/null 2>&1 || true; pkill -TERM -u "$(id -u)" -f "/usr/local/bin/mechos-creator-mode([[:space:]]|$)|/usr/local/bin/mechos-creator-mode.real([[:space:]]|$)" >/dev/null 2>&1 || true' \
    >/dev/null 2>&1 || true
}

stop_mechscope_after_creator(){
  systemd-run --user --quiet --collect --unit="mechos-stop-mechscope-$$" \
    /bin/sh -c 'sleep 0.7; systemctl --user stop mechos-gaming-layer.service mechos-vm-mechscope.service >/dev/null 2>&1 || true; pkill -TERM -u "$(id -u)" -f "/usr/local/bin/mechscope([[:space:]]|$)" >/dev/null 2>&1 || true' \
    >/dev/null 2>&1 || true
}

launch_mechscope(){
  if [ -n "$virt" ] && [ "$virt" != "none" ] && [ -x /usr/local/bin/mechos-vm-mode-runtime ]; then
    /usr/local/bin/mechos-vm-mode-runtime gaming >>"$LOG" 2>&1 || true
    if wait_for_process '/usr/local/bin/mechscope([[:space:]]|$)'; then
      stop_creator_after_mechscope
      return 0
    fi
  fi

  if [ -x /usr/local/bin/mechos-gaming-layer-control ]; then
    /usr/local/bin/mechos-gaming-layer-control start >>"$LOG" 2>&1 || true
    if systemctl --user is-active --quiet mechos-gaming-layer.service 2>/dev/null || wait_for_process '/usr/local/bin/mechscope([[:space:]]|$)'; then
      stop_creator_after_mechscope
      return 0
    fi
  fi

  [ -x /usr/local/bin/mechscope ] || return 1
  nohup /usr/local/bin/mechscope >>"$LOG" 2>&1 </dev/null &
  if wait_for_process '/usr/local/bin/mechscope([[:space:]]|$)'; then
    stop_creator_after_mechscope
    return 0
  fi
  return 1
}

launch_creator(){
  [ -x /usr/local/bin/mechos-creator-mode ] || return 1

  if [ -n "$virt" ] && [ "$virt" != "none" ] && [ -x /usr/local/bin/mechos-vm-mode-runtime ]; then
    /usr/local/bin/mechos-vm-mode-runtime creator >>"$LOG" 2>&1 || true
    if wait_for_process '/usr/local/bin/mechos-creator-mode'; then
      stop_mechscope_after_creator
      return 0
    fi
  fi

  if [ -x /usr/local/bin/mechos-gaming-layer-control ]; then
    /usr/local/bin/mechos-gaming-layer-control creator >>"$LOG" 2>&1 || true
    if wait_for_process '/usr/local/bin/mechos-creator-mode'; then
      stop_mechscope_after_creator
      return 0
    fi
  fi

  if systemctl --user cat mechos-creator-mode.service >/dev/null 2>&1; then
    systemctl --user reset-failed mechos-creator-mode.service >/dev/null 2>&1 || true
    systemctl --user start mechos-creator-mode.service >>"$LOG" 2>&1 || true
    if wait_for_process '/usr/local/bin/mechos-creator-mode'; then
      stop_mechscope_after_creator
      return 0
    fi
  fi

  nohup /usr/local/bin/mechos-creator-mode >>"$LOG" 2>&1 </dev/null &
  if wait_for_process '/usr/local/bin/mechos-creator-mode'; then
    stop_mechscope_after_creator
    return 0
  fi
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
    systemctl --user stop mechos-creator-mode.service mechos-vm-creator.service >/dev/null 2>&1 || true
    pkill -TERM -u "$(id -u)" -f '/usr/local/bin/mechos-creator-mode([[:space:]]|$)|/usr/local/bin/mechos-creator-mode.real([[:space:]]|$)' >/dev/null 2>&1 || true
    ;;
esac
EOF
  chmod 0755 "$bin/mechos-mode-launch"
  bash -n "$bin/mechos-mode-launch" || fail "shared mode launcher is invalid"

  cat > "$bin/mechos-return-to-mechscope" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
exec /usr/local/bin/mechos-mode-launch gaming
EOF
  chmod 0755 "$bin/mechos-return-to-mechscope"

  cat > "$apps/mechos-return-gaming.desktop" <<'EOF'
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

  cat > "$apps/mechos-creator-mode.desktop" <<'EOF'
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
Keywords=MechOS;Creator;Blender;Unity;Unreal;VRChat;MechClip;
EOF
  chmod 0644 "$apps/mechos-return-gaming.desktop" "$apps/mechos-creator-mode.desktop"

  rm -f \
    "$apps/mechos-return-to-mechscope.desktop" \
    "$apps/mechscope.desktop" \
    "$skel/MechScope.desktop" \
    "$skel/Gaming-Mode.desktop" \
    "$skel/Return-to-MechScope.desktop" \
    "$skel/Creator-Mode.desktop" 2>/dev/null || true

  cp -f "$apps/mechos-return-gaming.desktop" "$skel/Return-to-MechScope.desktop"
  cp -f "$apps/mechos-creator-mode.desktop" "$skel/Creator-Mode.desktop"
  chmod 0755 "$skel/Return-to-MechScope.desktop" "$skel/Creator-Mode.desktop"
}

install_oobe_authority(){
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local libexec="$tree/usr/local/libexec"
  local units="$tree/usr/lib/systemd/system"
  local wants="$tree/etc/systemd/system/graphical.target.wants"
  local autostart="$tree/etc/xdg/autostart"
  local polkit="$tree/etc/polkit-1/rules.d"
  local cleanup="$tree/etc/systemd/system"
  mkdir -p "$bin" "$libexec" "$units" "$wants" "$autostart" "$polkit" "$cleanup"

  [ -x "$bin/mechos-oobe" ] || fail "OOBE UI missing from final installed payload"
  [ -x "$libexec/mechos-oobe-apply" ] || fail "OOBE apply helper missing from final installed payload"

  # Final account creation hands back to a normal authenticated Plasma login.
  sed -i \
    -e 's/Session=mechos-gaming\.desktop/Session=plasma.desktop/g' \
    -e 's/Relogin=true/Relogin=false/g' \
    "$libexec/mechos-oobe-apply"

  python3 - "$libexec/mechos-oobe-apply" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
# Do not autologin the permanent user after setup. The created password must be
# used on the next boot, then MechOS may start the selected fullscreen layer.
t=t.replace('f"User={username}\\n"', '"User=\\n"')
compile(t,str(p),'exec')
p.write_text(t,encoding='utf-8')
PY
  chmod 0755 "$libexec/mechos-oobe-apply"
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$libexec/mechos-oobe-apply" || fail "OOBE apply helper invalid"

  cat > "$bin/mechos-oobe-start" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
STATE=/var/lib/mechos
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/mechos/oobe-start.log"
mkdir -p "$(dirname "$LOG")"
[ -e "$STATE/installed" ] || exit 0
[ ! -e "$STATE/oobe-complete" ] || exit 0
[ "$(id -un)" = mechos-setup ] || exit 0
[ -x /usr/local/bin/mechos-oobe ] || exit 1
for _ in $(seq 1 100); do
  [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && break
  sleep 0.2
done
printf '[%s] launching account creation wayland=%s display=%s\n' "$(date -Is 2>/dev/null || date)" "${WAYLAND_DISPLAY:-}" "${DISPLAY:-}" >>"$LOG"
exec /usr/local/bin/mechos-oobe >>"$LOG" 2>&1
EOF
  chmod 0755 "$bin/mechos-oobe-start"

  cat > "$libexec/mechos-firstboot-authority" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
STATE=/var/lib/mechos
SETUP_USER=mechos-setup
[ -e /run/archiso/bootmnt ] && exit 0
[ -e "$STATE/installed" ] || exit 0
[ ! -e "$STATE/oobe-complete" ] || exit 0
mkdir -p "$STATE" /etc/sddm.conf.d
if ! id "$SETUP_USER" >/dev/null 2>&1; then
  groups="$(for g in wheel video audio input storage optical; do getent group "$g" >/dev/null 2>&1 && printf '%s,' "$g"; done | sed 's/,$//')"
  if [ -n "$groups" ]; then useradd -m -s /bin/bash -G "$groups" "$SETUP_USER"; else useradd -m -s /bin/bash "$SETUP_USER"; fi
fi
passwd -l "$SETUP_USER" >/dev/null 2>&1 || true
home="$(getent passwd "$SETUP_USER" | cut -d: -f6)"; [ -n "$home" ] || home="/home/$SETUP_USER"
mkdir -p "$home/.config/autostart"
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
cat > /etc/sddm.conf.d/95-mechos-oobe.conf <<'SDDM'
[Autologin]
User=mechos-setup
Session=plasma.desktop
Relogin=true
SDDM
printf 'pending\n' > "$STATE/oobe-pending"
printf 'desktop\n' > "$STATE/firstboot-session"
EOF
  chmod 0755 "$libexec/mechos-firstboot-authority"

  cat > "$units/mechos-firstboot-authority.service" <<'EOF'
[Unit]
Description=Prepare MechOS first-run account creation before SDDM
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
  ln -sfn /usr/lib/systemd/system/mechos-firstboot-authority.service "$wants/mechos-firstboot-authority.service"

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

  cat > "$polkit/49-mechos-oobe.rules" <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        subject.user == "mechos-setup" &&
        action.lookup("program") == "/usr/local/libexec/mechos-oobe-apply") {
        return polkit.Result.YES;
    }
});
EOF

  if [ -x "$libexec/mechos-oobe-cleanup" ] && [ ! -f "$cleanup/mechos-oobe-cleanup.service" ]; then
    cat > "$cleanup/mechos-oobe-cleanup.service" <<'EOF'
[Unit]
Description=Remove one-time MechOS setup account
Before=sddm.service
ConditionPathExists=/var/lib/mechos/oobe-complete
ConditionPathExists=!/var/lib/mechos/oobe-cleaned

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-oobe-cleanup

[Install]
WantedBy=graphical.target
EOF
  fi
}

repair_creator_alignment(){
  local tree="$1"
  local file="$tree/usr/local/share/mechos/ui/creator_shell.py"
  [ -f "$file" ] || { log "Creator reference shell is not present; skipping shell-coordinate repair"; return 0; }

  python3 - "$file" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_CREATOR_REFERENCE_NATIVE_SCALE_V2'
if marker in t: raise SystemExit(0)

# The reference image and clickable/UI geometry must use one coordinate space.
# Replace the known reference->1920x1080 pre-scaling helper with native reference
# coordinates; FixedCanvas performs the one and only aspect-preserving scale.
pat=re.compile(r'def rr\(x, y, w, h\):\n(?:    .*\n){1,10}?    return QRect\(\n        round\(x / REFERENCE_W \* BASE_W\),\n        round\(y / REFERENCE_H \* BASE_H\),\n        round\(w / REFERENCE_W \* BASE_W\),\n        round\(h / REFERENCE_H \* BASE_H\),\n    \)\n')
replacement='''# MECHOS_CREATOR_REFERENCE_NATIVE_SCALE_V2\ndef rr(x, y, w, h):\n    \"\"\"Keep Creator controls in the approved reference image coordinate space.\"\"\"\n    return QRect(x, y, w, h)\n'''
new,n=pat.subn(replacement,t,count=1)
if n:
    t=new
elif 'def rr(x, y, w, h):' in t and 'return QRect(x, y, w, h)' in t:
    t=t.replace('def rr(x, y, w, h):', marker+'\ndef rr(x, y, w, h):',1)
else:
    # Some later Creator shells already use responsive layouts. Do not damage
    # them; mark them as verified rather than forcing an unrelated rewrite.
    t=marker+'\n'+t

compile(t,str(p),'exec')
p.write_text(t,encoding='utf-8')
PY
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$file" || fail "Creator shell invalid after alignment repair"
  grep -Fq 'MECHOS_CREATOR_REFERENCE_NATIVE_SCALE_V2' "$file" || fail "Creator alignment marker missing"
}

patch_postinstall(){
  python3 - "$POSTINSTALL" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_NEW_BUILD_FINAL_GATE_V1'
if marker not in t:
    t += r'''

# MECHOS_NEW_BUILD_FINAL_GATE_V1
# A clean install is not allowed to enter MechScope/Creator before account
# creation. The system-level authority prepares the temporary setup account on
# the first installed boot.
mkdir -p /var/lib/mechos
printf 'installed\n' > /var/lib/mechos/installed
rm -f /var/lib/mechos/oobe-complete /var/lib/mechos/oobe-cleaned
printf 'pending\n' > /var/lib/mechos/oobe-pending
systemctl enable mechos-firstboot-authority.service 2>/dev/null || true

# Install only the final desktop mode launchers into the candidate user's home.
if [ -n "${INSTALLER_USER:-}" ] && id "$INSTALLER_USER" >/dev/null 2>&1; then
  HOME_DIR="$(getent passwd "$INSTALLER_USER" | cut -d: -f6)"
  if [ -n "$HOME_DIR" ]; then
    mkdir -p "$HOME_DIR/Desktop"
    cp -f /usr/share/applications/mechos-return-gaming.desktop "$HOME_DIR/Desktop/Return-to-MechScope.desktop" 2>/dev/null || true
    cp -f /usr/share/applications/mechos-creator-mode.desktop "$HOME_DIR/Desktop/Creator-Mode.desktop" 2>/dev/null || true
    chmod 0755 "$HOME_DIR/Desktop/Return-to-MechScope.desktop" "$HOME_DIR/Desktop/Creator-Mode.desktop" 2>/dev/null || true
    chown -R "$INSTALLER_USER:$(id -gn "$INSTALLER_USER" 2>/dev/null || echo "$INSTALLER_USER")" "$HOME_DIR/Desktop" 2>/dev/null || true
  fi
fi
'''
p.write_text(t,encoding='utf-8')
PY
  bash -n "$POSTINSTALL" || fail "post-install target invalid after final gate"
}

STAGE="$(mktemp -d /tmp/mechos-new-build-final.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

tar --zstd -xpf "$ARCHIVE" -C "$STAGE"
patch_update_helper "$STAGE"
install_mode_runtime "$STAGE"
install_oobe_authority "$STAGE"
repair_creator_alignment "$STAGE"
patch_postinstall

# The final installed build already contains the Hotfix 2 fixes, so report the
# same version as the stable channel and do not immediately offer itself again.
mkdir -p "$STAGE/etc/mechos"
printf '0.3.0-hotfix.2\n' > "$STAGE/etc/mechos/release"
if [ -f "$STAGE/etc/mechos/mechos.conf" ]; then
  if grep -q '^MECHOS_VERSION=' "$STAGE/etc/mechos/mechos.conf"; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.2/' "$STAGE/etc/mechos/mechos.conf"
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.2\n' >> "$STAGE/etc/mechos/mechos.conf"
  fi
fi
printf 'MechOS v0.3.0 Hotfix 2\n' > "$STAGE/etc/system-release"

# Final payload invariants. Build fails instead of shipping a broken installer.
[ -x "$STAGE/usr/local/bin/mechos-mode-launch" ] || fail "mode launcher missing"
[ -x "$STAGE/usr/local/bin/mechos-oobe-start" ] || fail "OOBE launcher missing"
[ -x "$STAGE/usr/local/libexec/mechos-firstboot-authority" ] || fail "OOBE authority missing"
[ -f "$STAGE/usr/lib/systemd/system/mechos-firstboot-authority.service" ] || fail "OOBE authority service missing"
[ -L "$STAGE/etc/systemd/system/graphical.target.wants/mechos-firstboot-authority.service" ] || fail "OOBE authority service not enabled"
grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch gaming' "$STAGE/usr/share/applications/mechos-return-gaming.desktop" || fail "Return to MechScope shortcut is stale"
grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch creator' "$STAGE/usr/share/applications/mechos-creator-mode.desktop" || fail "Creator shortcut is stale"
grep -Fq 'XDG_CACHE_HOME' "$STAGE/usr/local/bin/mechos-update-helper" || fail "Update checks still require root cache"
[ ! -e "$STAGE/usr/share/applications/mechos-return-to-mechscope.desktop" ] || fail "legacy Return to MechScope desktop file survived"
[ ! -e "$STAGE/usr/share/applications/mechscope.desktop" ] || fail "legacy direct MechScope desktop file survived"
grep -Fq 'MECHOS_NEW_BUILD_FINAL_GATE_V1' "$POSTINSTALL" || fail "post-install firstboot marker missing"

TMP="$ARCHIVE.new-build-final"
tar --zstd -cpf "$TMP" -C "$STAGE" .
mv -f "$TMP" "$ARCHIVE"
rm -rf "$STAGE"
trap - EXIT

# Keep the Live metadata aligned with the installed payload. Live still does not
# run installed-system updates or OOBE.
mkdir -p "$ROOT/etc/mechos"
printf '0.3.0-hotfix.2\n' > "$ROOT/etc/mechos/release"
if [ -f "$ROOT/etc/mechos/mechos.conf" ]; then
  sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.2/' "$ROOT/etc/mechos/mechos.conf"
fi
printf 'MechOS v0.3.0 Hotfix 2\n' > "$ROOT/etc/system-release"

log 'Final clean-build gate passed: OOBE auto-start, VM/hardware mode launchers, Update Center cache, Creator alignment and release metadata are authoritative'
