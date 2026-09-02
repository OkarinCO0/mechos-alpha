#!/usr/bin/env bash
set -Eeuo pipefail

TARGET="${1:-scripts/build-mechos-archiso.sh}"

[[ -f "$TARGET" ]] || {
  echo "MechOS builder not found: $TARGET" >&2
  exit 2
}

# KDE Partition Manager should be available in both the live ISO and the
# installed MechOS system. The first replacement targets the ArchISO package
# heredoc; the second targets the installed-system pacman package list.
if ! grep -qxF 'partitionmanager' "$TARGET"; then
  sed -i '0,/^kdialog$/s//kdialog\npartitionmanager/' "$TARGET"
fi
sed -i \
  's/plasma-meta sddm konsole dolphin ark kate kdialog firefox/plasma-meta sddm konsole dolphin ark kate kdialog partitionmanager firefox/g' \
  "$TARGET"

# Current Arch/SDDM examples use the session entry name (plasma), while the
# actual desktop file remains /usr/share/wayland-sessions/plasma.desktop.
# Keeping the live config on the session entry name avoids SDDM falling back
# to the password greeter when automatic login cannot resolve the session.
sed -i 's/Session=plasma\.desktop/Session=plasma/g' "$TARGET"

# Fail the build early if this patch did not land where expected.
grep -qxF 'partitionmanager' "$TARGET"
grep -Fq 'kdialog partitionmanager firefox' "$TARGET"
grep -Fq 'Session=plasma' "$TARGET"

echo "MechOS live autologin + KDE Partition Manager patch applied."
