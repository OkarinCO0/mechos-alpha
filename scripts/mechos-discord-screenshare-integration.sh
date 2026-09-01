#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"

log() { printf '[MechOS Discord] %s\n' "$*"; }
fail() { printf '[MechOS Discord] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Discord] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -s "$ARCHIVE" ] || fail "installed-system payload archive is missing: $ARCHIVE"

install_runtime() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local apps="$tree/usr/share/applications"
  mkdir -p "$bin" "$apps"

  cat > "$bin/mechos-discord" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

APP_ID="com.discordapp.Discord"
DISCORD_URL="https://discord.com/app"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG="$STATE_DIR/discord.log"
mkdir -p "$STATE_DIR"

log() { printf '[MechOS Discord] %s\n' "$*" | tee -a "$LOG" >&2; }

portal_ready() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user start pipewire.service 2>/dev/null || true
    systemctl --user start pipewire-pulse.service 2>/dev/null || true
    systemctl --user start wireplumber.service 2>/dev/null || true
    systemctl --user start xdg-desktop-portal.service 2>/dev/null || true
  fi

  # Keep the portal attached to the persistent Plasma session. Gamescope is a
  # fullscreen layer over Plasma, so both Desktop and MechScope use the same
  # PipeWire/portal permission path instead of switching to a root helper.
  if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=KDE 2>/dev/null || true
  fi
}

flatpak_installed() {
  command -v flatpak >/dev/null 2>&1 || return 1
  flatpak info --user "$APP_ID" >/dev/null 2>&1 || \
    flatpak info --system "$APP_ID" >/dev/null 2>&1
}

install_flatpak() {
  command -v flatpak >/dev/null 2>&1 || return 1
  flatpak remote-add --user --if-not-exists \
    flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak install --user -y flathub "$APP_ID"
}

launch_web() {
  if command -v firefox >/dev/null 2>&1; then
    exec firefox "$DISCORD_URL"
  fi
  if command -v xdg-open >/dev/null 2>&1; then
    exec xdg-open "$DISCORD_URL"
  fi
  log "No browser is available to open Discord Web."
  exit 1
}

check_support() {
  portal_ready
  printf 'MECHOS DISCORD / SCREEN SHARE CHECK\n'
  printf 'Session: %s\n' "${XDG_SESSION_TYPE:-unknown}"
  printf 'Desktop: %s\n' "${XDG_CURRENT_DESKTOP:-unknown}"
  printf 'Wayland display: %s\n' "${WAYLAND_DISPLAY:-none}"
  printf 'PipeWire: '
  systemctl --user is-active pipewire.service 2>/dev/null || printf 'unknown\n'
  printf 'WirePlumber: '
  systemctl --user is-active wireplumber.service 2>/dev/null || printf 'unknown\n'
  printf 'Desktop portal: '
  systemctl --user is-active xdg-desktop-portal.service 2>/dev/null || printf 'unknown\n'
  printf 'KDE portal backend: %s\n' "$([ -x /usr/lib/xdg-desktop-portal-kde ] && echo present || echo missing)"
  printf 'Discord Flatpak: %s\n' "$(flatpak_installed && echo installed || echo not-installed)"
  printf '\nScreen sharing uses the Wayland ScreenCast portal and PipeWire.\n'
  printf 'Discord will still ask you to choose and approve a monitor/window before sharing.\n'
}

portal_ready

case "${1:-launch}" in
  --check|check)
    check_support
    exit 0
    ;;
  --web|web)
    launch_web
    ;;
  --install|install)
    install_flatpak
    exit $?
    ;;
  launch|"")
    ;;
  *)
    echo "Usage: mechos-discord [launch|--install|--web|--check]" >&2
    exit 2
    ;;
esac

# Prefer the user Flatpak because it can be installed without an administrator
# password and uses the session portal. Electron flags request the Wayland /
# PipeWire capture path where the installed Discord build supports it.
if flatpak_installed; then
  exec flatpak run "$APP_ID" \
    --ozone-platform-hint=auto \
    --enable-features=WebRTCPipeWireCapturer
fi

if command -v discord >/dev/null 2>&1; then
  exec discord \
    --ozone-platform-hint=auto \
    --enable-features=WebRTCPipeWireCapturer
fi

# Installed MechOS can add Discord as a user Flatpak with no root authorization.
# The Live ISO stays disposable and uses Discord Web instead of downloading an app.
if [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null; then
  launch_web
fi

if command -v kdialog >/dev/null 2>&1; then
  if kdialog --title "Discord on MechOS" --yesno \
      "Discord is not installed yet. Install the Discord Flatpak for this user?\n\nNo administrator password is required."; then
    if install_flatpak; then
      exec flatpak run "$APP_ID" \
        --ozone-platform-hint=auto \
        --enable-features=WebRTCPipeWireCapturer
    fi
  fi
fi

launch_web
EOF
  chmod 755 "$bin/mechos-discord"

  cat > "$apps/mechos-discord.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Discord
Comment=Discord chat, voice and screen sharing for MechOS
Exec=/usr/local/bin/mechos-discord
Icon=com.discordapp.Discord
Terminal=false
Categories=Network;Chat;Game;
Keywords=Discord;Voice;Chat;Screen Share;MechScope;MechOS;
EOF

  cat > "$apps/mechos-discord-screenshare-check.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Discord Screen Share Check
Comment=Verify PipeWire and desktop portal support for Discord screen sharing
Exec=konsole -e bash -lc '/usr/local/bin/mechos-discord --check; echo; read -rp "Press Enter to close..."'
Icon=video-display
Terminal=false
Categories=System;Network;
Keywords=Discord;PipeWire;Portal;Screen Share;Wayland;
EOF
}

patch_mechscope() {
  local tree="$1"
  local target=""
  for candidate in "$tree/usr/local/bin/mechscope.real" "$tree/usr/local/bin/mechscope"; do
    [ -f "$candidate" ] || continue
    if grep -Fq 'MECHSCOPE 2.0' "$candidate" || grep -Fq 'Ctrl+Shift+M' "$candidate"; then
      target="$candidate"
      break
    fi
  done
  [ -n "$target" ] || fail "could not locate the MechScope Python target"

  python3 - "$target" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "# MECHOS_DISCORD_SCREENSHARE_INTEGRATION"
if marker in text:
    raise SystemExit(0)

# Ctrl+Shift+G is reserved for Discord in MechScope. Keep the integration next
# to the existing global MechScope hotkeys so it works regardless of focus.
anchor = '''            if event.key() == Qt.Key.Key_B:\n                spawn(["/usr/local/bin/mechos-stream-center"])\n                return\n'''
insert = '''            if event.key() == Qt.Key.Key_G:\n                spawn(["/usr/local/bin/mechos-discord"])\n                return\n'''
if anchor in text:
    text = text.replace(anchor, anchor + insert, 1)
else:
    # Older/newer MechScope variants may not have the streaming-center hotkey;
    # place Discord immediately before the stream start hotkey instead.
    anchor2 = '''            if event.key() == Qt.Key.Key_L:\n                spawn(["/usr/local/bin/mechos-stream-control", "start-stream"])\n                return\n'''
    if anchor2 not in text:
        raise SystemExit("MechScope hotkey anchor not found")
    text = text.replace(anchor2, insert + anchor2, 1)

# Add a visible Discord launch button when the current MechScope footer/action
# row is present. The hotkey above remains authoritative if the UI layout changes.
visible_anchors = [
    '("Desktop Mode",lambda:self.switch_mode("desktop"))',
    '("Desktop Mode", self.desktop)',
]
for a in visible_anchors:
    if a in text and '"Discord",lambda:spawn(["/usr/local/bin/mechos-discord"])' not in text:
        text = text.replace(a, '("Discord",lambda:spawn(["/usr/local/bin/mechos-discord"])), ' + a, 1)
        break

# Put the marker by the interpreter line without changing Python semantics.
if text.startswith("#!"):
    nl = text.find("\n")
    text = text[:nl+1] + marker + "\n" + text[nl+1:]
else:
    text = marker + "\n" + text

path.write_text(text, encoding="utf-8")
PY

  python3 -m py_compile "$target" || fail "MechScope syntax failed after Discord integration: $target"
  grep -Fq '/usr/local/bin/mechos-discord' "$target" || fail "MechScope Discord launcher was not added"
  grep -Fq 'Qt.Key.Key_G' "$target" || fail "MechScope Ctrl+Shift+G Discord hotkey was not added"
}

patch_creator_mode() {
  local tree="$1"
  local target="$tree/usr/local/bin/mechos-creator-mode"
  [ -f "$target" ] || return 0

  python3 - "$target" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "# MECHOS_CREATOR_DISCORD_LAUNCHER"
if marker in text:
    raise SystemExit(0)

# Creator Mode already has a Community -> Discord item. Route that item through
# the same MechOS launcher used by MechScope/Desktop so screen-share readiness
# and the user-Flatpak/browser fallback are identical in every mode.
old = 'b.clicked.connect(lambda _,u=url:open_url(u)); v.addWidget(b)'
if old not in text or '("Discord", "https://discord.com/")' not in text:
    raise SystemExit(0)

# The loop contains multiple community URLs, so keep the loop but special-case
# Discord by name at click time.
new = 'b.clicked.connect(lambda _,u=url,n=name:spawn(["/usr/local/bin/mechos-discord"]) if n=="Discord" else open_url(u)); v.addWidget(b)'
text = text.replace(old, new, 1)
text = marker + "\n" + text
path.write_text(text, encoding="utf-8")
PY

  python3 -m py_compile "$target" || fail "Creator Mode syntax failed after Discord integration"
}

validate_tree() {
  local tree="$1"
  [ -x "$tree/usr/local/bin/mechos-discord" ] || fail "Discord launcher is missing"
  bash -n "$tree/usr/local/bin/mechos-discord" || fail "Discord launcher shell syntax failed"
  [ -f "$tree/usr/share/applications/mechos-discord.desktop" ] || fail "Discord desktop entry is missing"
  grep -Fq 'com.discordapp.Discord' "$tree/usr/local/bin/mechos-discord" || fail "Discord Flatpak ID is missing"
  grep -Fq 'WebRTCPipeWireCapturer' "$tree/usr/local/bin/mechos-discord" || fail "PipeWire capture flag is missing"
  grep -Fq 'xdg-desktop-portal.service' "$tree/usr/local/bin/mechos-discord" || fail "desktop portal readiness is missing"

  local mechscope=""
  [ -f "$tree/usr/local/bin/mechscope.real" ] && mechscope="$tree/usr/local/bin/mechscope.real"
  [ -n "$mechscope" ] || mechscope="$tree/usr/local/bin/mechscope"
  grep -Fq '/usr/local/bin/mechos-discord' "$mechscope" || fail "MechScope does not expose Discord"
}

# Existing package set already contains PipeWire, WirePlumber,
# xdg-desktop-portal and xdg-desktop-portal-kde. Refuse a misleading build if a
# future package cleanup removes the screen-cast stack.
for pkg in pipewire wireplumber xdg-desktop-portal xdg-desktop-portal-kde flatpak firefox; do
  grep -Fxq "$pkg" /workspace/archlive/packages.x86_64 \
    || fail "required Discord/screen-share package is missing from ArchISO: $pkg"
done

install_runtime "$ROOT"
patch_mechscope "$ROOT"
patch_creator_mode "$ROOT"
validate_tree "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xf "$ARCHIVE" -C "$tmp"
install_runtime "$tmp"
patch_mechscope "$tmp"
patch_creator_mode "$tmp"
validate_tree "$tmp"

new_archive="$ARCHIVE.discord-screenshare"
tar --zstd -cpf "$new_archive" -C "$tmp" .
mv -f "$new_archive" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

log "Discord integrated with MechScope/Desktop/Creator Mode using the shared PipeWire portal screen-share path"
