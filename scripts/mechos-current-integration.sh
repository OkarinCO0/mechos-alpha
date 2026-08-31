#!/usr/bin/env bash
set -euo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
BIN="$ROOT/usr/local/bin"
APPS="$ROOT/usr/share/applications"
AUTOSTART="$ROOT/etc/xdg/autostart"
SDDM="$ROOT/etc/sddm.conf.d"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
PROFILE="/workspace/archlive/profiledef.sh"

log() { printf '[MechOS v0.3.0] %s\n' "$*"; }
fail() { printf '[MechOS v0.3.0] ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$ROOT" ] || fail "ArchISO rootfs does not exist at $ROOT"
mkdir -p "$BIN" "$APPS" "$AUTOSTART" "$SDDM"

# The integration performs Python syntax validation on generated PyQt tools.
# Install Arch's Python package if an older/custom builder did not bootstrap it.
if ! command -v python3 >/dev/null 2>&1; then
  log "python3 is missing in the build container; installing Arch package: python"
  if command -v pacman >/dev/null 2>&1; then
    pacman -S --needed --noconfirm python
  fi
fi

command -v python3 >/dev/null 2>&1 || fail "python3 is required for GUI validation"

# ---------------------------------------------------------------------------
# Fixed Return to MechScope
# ---------------------------------------------------------------------------
cat > "$BIN/mechos-return-to-mechscope" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# SDDM is configured to auto-login to the MechOS Gaming session on an
# installed system. Try each logout method in order and only stop when one
# actually succeeds. Do not hide a failed qdbus call with "|| true".
if command -v qdbus6 >/dev/null 2>&1; then
  if qdbus6 org.kde.Shutdown /Shutdown logout >/dev/null 2>&1; then
    exit 0
  fi
fi

if command -v qdbus >/dev/null 2>&1; then
  if qdbus org.kde.Shutdown /Shutdown logout >/dev/null 2>&1; then
    exit 0
  fi
fi

if [ -n "${XDG_SESSION_ID:-}" ] && command -v loginctl >/dev/null 2>&1; then
  if loginctl terminate-session "$XDG_SESSION_ID" >/dev/null 2>&1; then
    exit 0
  fi
fi

echo "MechOS could not close the current desktop session cleanly." >&2
echo "Log out normally, then MechScope should auto-start." >&2
exit 1
EOF

# ---------------------------------------------------------------------------
# Hardware scanner
# ---------------------------------------------------------------------------
cat > "$BIN/mechos-hardware-scan" <<'EOF'
#!/usr/bin/env bash
set -u

section() { printf '\n=== %s ===\n' "$1"; }
run() { "$@" 2>/dev/null || true; }

printf 'MechOS Hardware Scan\nGenerated: %s\n' "$(date -Is 2>/dev/null || date)"

section "System"
run uname -a
if [ -r /etc/os-release ]; then run cat /etc/os-release; fi

section "CPU"
if command -v lscpu >/dev/null 2>&1; then
  run lscpu
else
  run grep -m1 -E 'model name|Hardware' /proc/cpuinfo
fi

section "Memory"
run free -h

section "Graphics"
if command -v lspci >/dev/null 2>&1; then
  run lspci -nnk
fi

section "Storage"
if command -v lsblk >/dev/null 2>&1; then
  run lsblk -o NAME,SIZE,TYPE,FSTYPE,FSVER,LABEL,MOUNTPOINTS,MODEL
fi

section "Network"
if command -v nmcli >/dev/null 2>&1; then
  run nmcli -f DEVICE,TYPE,STATE,CONNECTION device status
else
  run ip link
fi

section "Audio"
if command -v wpctl >/dev/null 2>&1; then
  run wpctl status
elif command -v pactl >/dev/null 2>&1; then
  run pactl info
fi

section "Virtualization"
if command -v systemd-detect-virt >/dev/null 2>&1; then
  run systemd-detect-virt
fi

printf '\nScan complete. No hardware settings were changed.\n'
EOF

# ---------------------------------------------------------------------------
# Preserve-home reinstall guide: intentionally non-destructive.
# ---------------------------------------------------------------------------
cat > "$BIN/mechos-preserve-home" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cat <<'TXT'
MechOS Preserve-Home Reinstall Assistant (Alpha)
=================================================

This assistant does NOT format, repartition, or mount disks automatically.
It is designed to keep disk selection and destructive confirmations visible
inside Archinstall.

For a preserve-home reinstall:
  1. Back up anything important first.
  2. Start the MechOS installer.
  3. In Archinstall, choose manual partitioning.
  4. Reuse the existing home partition WITHOUT formatting it.
  5. Format only the system/root partition you intentionally want replaced.
  6. Re-check the final disk summary before confirming installation.

Mounted paths currently visible under /mnt:
TXT

find /mnt -maxdepth 3 -mindepth 1 -type d 2>/dev/null | sed 's/^/  /' || true

printf '\nNo disk changes were made.\n'
EOF


# ---------------------------------------------------------------------------
# Installed desktop checker
# ---------------------------------------------------------------------------
cat > "$BIN/mechos-desktop-check" <<'EOF'
#!/usr/bin/env bash
set +e

echo "=== MechOS Desktop Check ==="

echo
echo "-- Commands --"
for cmd in startplasma-wayland sddm konsole dolphin; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "[OK] $cmd -> $(command -v "$cmd")"
  else
    echo "[MISSING] $cmd"
  fi
done

echo
echo "-- Wayland sessions --"
for f in \
  /usr/share/wayland-sessions/plasma.desktop \
  /usr/share/wayland-sessions/mechos-gaming.desktop; do
  if [ -f "$f" ]; then
    echo "[OK] $f"
  else
    echo "[MISSING] $f"
  fi
done

echo
echo "-- Display manager --"
systemctl --no-pager --full status display-manager.service 2>/dev/null || true

echo
echo "-- Installed SDDM configuration --"
cat /etc/sddm.conf.d/90-mechos-installed.conf 2>/dev/null || echo "Not present"

echo
echo "-- Desktop install marker --"
if [ -f /var/lib/mechos/desktop-installed ]; then
  echo "[OK] /var/lib/mechos/desktop-installed"
else
  echo "[MISSING] /var/lib/mechos/desktop-installed"
fi

echo
echo "-- MechOS core runtime --"
for f in   /usr/local/bin/mechscope   /usr/local/bin/mechos-gaming-session   /usr/local/bin/mechos-performance-center   /usr/local/bin/mechos-update   /usr/local/bin/mechos-update-center   /usr/local/bin/mechos-gpu-setup   /usr/local/bin/mechos-firstboot; do
  if [ -x "$f" ]; then
    echo "[OK] $f"
  else
    echo "[MISSING] $f"
  fi
done

echo
echo "-- Desktop install log --"
cat /var/log/mechos-desktop-install.log 2>/dev/null || true
EOF
chmod 755 "$BIN/mechos-desktop-check"

# ---------------------------------------------------------------------------
# Recovery helper: diagnostics only unless the user explicitly launches the
# guided installer, which still keeps Archinstall's disk confirmation UI.
# ---------------------------------------------------------------------------
cat > "$BIN/mechos-recovery-helper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

MNT="/mnt/mechos-recovery"

cleanup_mounts() {
  umount -R "$MNT" 2>/dev/null || true
  rm -rf "$MNT" 2>/dev/null || true
}

trap cleanup_mounts EXIT

mount_root() {
  local dev="$1"
  local mode="${2:-rw}"
  cleanup_mounts
  mkdir -p "$MNT"

  local opts=""
  [ "$mode" = "ro" ] && opts="-o ro"

  if mount $opts "$dev" "$MNT" 2>/dev/null; then
    if [ -f "$MNT/etc/os-release" ]; then
      return 0
    fi
    umount "$MNT" 2>/dev/null || true
  fi

  # Common Archinstall Btrfs root layout.
  if [ "$(lsblk -no FSTYPE "$dev" 2>/dev/null || true)" = "btrfs" ]; then
    local bopts="subvol=@"
    [ "$mode" = "ro" ] && bopts="ro,subvol=@"
    if mount -o "$bopts" "$dev" "$MNT" 2>/dev/null && [ -f "$MNT/etc/os-release" ]; then
      return 0
    fi
  fi

  echo "Unable to mount an installed root filesystem from $dev" >&2
  return 1
}

resolve_fstab_source() {
  local src="$1"
  case "$src" in
    UUID=*) blkid -U "${src#UUID=}" 2>/dev/null || true ;;
    PARTUUID=*) blkid -t "PARTUUID=${src#PARTUUID=}" -o device 2>/dev/null | head -n1 ;;
    LABEL=*) blkid -L "${src#LABEL=}" 2>/dev/null || true ;;
    /dev/*) printf '%s\n' "$src" ;;
    *) printf '%s\n' "" ;;
  esac
}

mount_target_esp() {
  local provided="${1:-}"
  local esp_mp=""
  local esp_src=""

  # Prefer the target's own fstab mapping.
  while read -r src mp fs rest; do
    case "$mp:$fs" in
      /efi:vfat|/boot/efi:vfat|/boot:vfat|/efi:fat|/boot/efi:fat|/boot:fat)
        esp_mp="$mp"
        esp_src="$(resolve_fstab_source "$src")"
        break
        ;;
    esac
  done < <(grep -Ev '^[[:space:]]*(#|$)' "$MNT/etc/fstab" 2>/dev/null || true)

  if [ -n "$provided" ]; then
    esp_src="$provided"
  fi
  [ -n "$esp_mp" ] || esp_mp="/boot"

  if [ -n "$esp_src" ]; then
    mkdir -p "$MNT$esp_mp"
    if ! mountpoint -q "$MNT$esp_mp"; then
      mount "$esp_src" "$MNT$esp_mp"
    fi
  fi

  printf '%s\n' "$esp_mp"
}

scan_roots() {
  local tmp="/tmp/mechos-root-scan"
  mkdir -p "$tmp"

  while read -r dev type fs; do
    [ "$type" = "part" ] || [ "$type" = "lvm" ] || [ "$type" = "crypt" ] || continue
    case "$fs" in
      ext4|btrfs|xfs|f2fs) ;;
      *) continue ;;
    esac

    cleanup_mounts
    mkdir -p "$MNT"

    if mount -o ro "$dev" "$MNT" 2>/dev/null; then
      :
    elif [ "$fs" = "btrfs" ] && mount -o ro,subvol=@ "$dev" "$MNT" 2>/dev/null; then
      :
    else
      continue
    fi

    if [ -f "$MNT/etc/os-release" ]; then
      os="$(. "$MNT/etc/os-release"; printf '%s' "${PRETTY_NAME:-${NAME:-Linux}}")"
      home_line="$(awk '$2=="/home" {print $1" "$3" "$4; exit}' "$MNT/etc/fstab" 2>/dev/null || true)"
      mechos="no"
      [ -f "$MNT/etc/mechos-release" ] && mechos="yes"
      printf '%s|%s|%s|%s|%s\n' "$dev" "$fs" "$os" "$mechos" "${home_line:-none}"
    fi

    cleanup_mounts
  done < <(lsblk -prno NAME,TYPE,FSTYPE)
}

scan_esps() {
  while read -r dev type fs label size; do
    [ "$type" = "part" ] || continue
    case "$fs" in
      vfat|fat|fat32) printf '%s|%s|%s|%s\n' "$dev" "$fs" "${label:-EFI}" "$size" ;;
    esac
  done < <(lsblk -prno NAME,TYPE,FSTYPE,LABEL,SIZE)
}

repair_boot() {
  local rootdev="$1"
  local espdev="${2:-}"

  mount_root "$rootdev" rw
  local esp_mp
  esp_mp="$(mount_target_esp "$espdev")"

  echo "Mounted root at $MNT"
  echo "EFI mountpoint: $esp_mp"

  # Refresh initramfs first.
  arch-chroot "$MNT" mkinitcpio -P

  if [ -f "$MNT$esp_mp/loader/loader.conf" ] || \
     [ -d "$MNT$esp_mp/EFI/systemd" ] || \
     [ -d "$MNT/boot/loader" ]; then
    echo "Detected systemd-boot."
    arch-chroot "$MNT" bootctl install
  elif [ -f "$MNT/boot/grub/grub.cfg" ] || arch-chroot "$MNT" pacman -Q grub >/dev/null 2>&1; then
    echo "Detected GRUB."
    if [ -d /sys/firmware/efi ]; then
      arch-chroot "$MNT" grub-install \
        --target=x86_64-efi \
        --efi-directory="$esp_mp" \
        --bootloader-id=MechOS
    else
      parent="$(lsblk -no PKNAME "$rootdev" 2>/dev/null | head -n1)"
      [ -n "$parent" ] || {
        echo "Could not determine BIOS boot disk." >&2
        return 1
      }
      arch-chroot "$MNT" grub-install "/dev/$parent"
    fi
    arch-chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg
  else
    echo "No supported installed bootloader was detected." >&2
    return 1
  fi

  echo "Boot repair completed."
}

show_logs() {
  local rootdev="${1:-}"
  echo "=== Live installer logs ==="
  for f in \
    /var/log/mechos-installer.log \
    /var/log/mechos-installer-hardware.log \
    /var/log/archinstall/install.log \
    /tmp/mechos-installer-http.log; do
    if [ -f "$f" ]; then
      echo
      echo "----- $f -----"
      tail -n 250 "$f"
    fi
  done

  if [ -n "$rootdev" ]; then
    mount_root "$rootdev" ro || return 0
    for f in \
      "$MNT/var/log/mechos-postinstall.log" \
      "$MNT/var/log/mechos-update.log" \
      "$MNT/var/lib/mechos/update-history.log"; do
      if [ -f "$f" ]; then
        echo
        echo "----- ${f#"$MNT"} -----"
        tail -n 250 "$f"
      fi
    done
  fi
}

rollback_failed_update() {
  local rootdev="$1"
  mount_root "$rootdev" rw

  local marker="$MNT/var/lib/mechos/rollback-pending"
  if [ ! -s "$marker" ]; then
    echo "No failed-update rollback marker exists." >&2
    return 2
  fi

  local snap
  snap="$(head -n1 "$marker" | tr -cd '0-9')"
  [ -n "$snap" ] || {
    echo "Rollback marker is invalid." >&2
    return 1
  }

  if [ "$(findmnt -n -o FSTYPE -T "$MNT" 2>/dev/null || true)" != "btrfs" ]; then
    echo "Automatic rollback is available only for a Btrfs root filesystem." >&2
    return 3
  fi

  if ! arch-chroot "$MNT" snapper -c root list >/dev/null 2>&1; then
    echo "The target does not have a working Snapper root configuration." >&2
    return 4
  fi

  echo "Rolling the target back to pre-update snapshot $snap..."
  arch-chroot "$MNT" snapper -c root rollback "$snap"
  arch-chroot "$MNT" mkinitcpio -P || true

  mv "$marker" "$marker.applied-$(date +%s)"
  echo "Rollback prepared. Reboot the installed system."
}

case "${1:-}" in
  scan-roots) scan_roots ;;
  scan-esps) scan_esps ;;
  repair-boot)
    [ "$#" -ge 2 ] || { echo "Usage: $0 repair-boot ROOTDEV [ESPDEV]" >&2; exit 2; }
    repair_boot "$2" "${3:-}"
    ;;
  logs) show_logs "${2:-}" ;;
  rollback)
    [ "$#" -eq 2 ] || { echo "Usage: $0 rollback ROOTDEV" >&2; exit 2; }
    rollback_failed_update "$2"
    ;;
  *)
    echo "Usage: $0 {scan-roots|scan-esps|repair-boot|logs|rollback}" >&2
    exit 2
    ;;
esac
EOF

# ---------------------------------------------------------------------------
# Recovery Center GUI
# ---------------------------------------------------------------------------
cat > "$BIN/mechos-recovery-center" <<'PYEOF'
#!/usr/bin/env python3
import os
import subprocess
import sys

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import (
    QApplication, QComboBox, QFrame, QHBoxLayout, QLabel, QMainWindow,
    QMessageBox, QPlainTextEdit, QPushButton, QVBoxLayout, QWidget
)

HELPER = "/usr/local/bin/mechos-recovery-helper"
STYLE = """
QWidget { background:#09060f; color:#f3eaff; font-family:Sans Serif; }
QFrame#panel { background:#15101f; border:1px solid #39254a; border-radius:14px; }
QPushButton { background:#251533; border:1px solid #714394; border-radius:10px;
              padding:11px 16px; font-weight:600; }
QPushButton:hover { background:#352047; border-color:#a45bd5; }
QComboBox,QPlainTextEdit { background:#0b0810; border:1px solid #39254a;
                          border-radius:8px; padding:8px; }
"""

class Recovery(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MechOS Recovery Center")
        self.resize(1050, 720)
        self.setStyleSheet(STYLE)
        self.roots = []
        self.esps = []
        self.build_ui()
        self.rescan()

    def build_ui(self):
        root = QWidget()
        outer = QVBoxLayout(root)
        outer.setContentsMargins(28,24,28,24)
        outer.setSpacing(15)

        title = QLabel("MECHOS RECOVERY CENTER")
        title.setFont(QFont("Sans Serif", 24, QFont.Weight.Bold))
        outer.addWidget(title)
        sub = QLabel("Repair boot • inspect installations • recover failed updates • view logs")
        sub.setStyleSheet("color:#b5a4c1;")
        outer.addWidget(sub)

        p = QFrame(); p.setObjectName("panel")
        pl = QVBoxLayout(p)
        row = QHBoxLayout()
        row.addWidget(QLabel("Installed system"))
        self.root_combo = QComboBox()
        row.addWidget(self.root_combo, 2)
        row.addWidget(QLabel("EFI partition"))
        self.esp_combo = QComboBox()
        row.addWidget(self.esp_combo, 2)
        rescan = QPushButton("Rescan")
        rescan.clicked.connect(self.rescan)
        row.addWidget(rescan)
        pl.addLayout(row)
        outer.addWidget(p)

        actions = QHBoxLayout()
        repair = QPushButton("Repair Boot")
        repair.clicked.connect(self.repair_boot)
        actions.addWidget(repair)
        rollback = QPushButton("Rollback Failed Update")
        rollback.clicked.connect(self.rollback)
        actions.addWidget(rollback)
        logs = QPushButton("Load Install / Update Logs")
        logs.clicked.connect(self.load_logs)
        actions.addWidget(logs)
        hw = QPushButton("Hardware Scan")
        hw.clicked.connect(self.hardware)
        actions.addWidget(hw)
        outer.addLayout(actions)

        self.output = QPlainTextEdit()
        self.output.setReadOnly(True)
        self.output.setPlaceholderText("Recovery output appears here.")
        outer.addWidget(self.output, 1)

        note = QLabel(
            "Boot Repair does not repartition or format disks. Rollback is offered only when "
            "MechOS recorded a valid pre-update Snapper snapshot on a Btrfs installation."
        )
        note.setWordWrap(True)
        note.setStyleSheet("color:#a995b6;")
        outer.addWidget(note)
        self.setCentralWidget(root)

    def run(self, args, privileged=False):
        cmd = [HELPER] + args
        if privileged:
            cmd = ["sudo", "-n"] + cmd
        try:
            out = subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT)
            self.output.setPlainText(out)
            return True
        except subprocess.CalledProcessError as e:
            self.output.setPlainText(e.output or str(e))
            return False

    def rescan(self):
        self.root_combo.clear(); self.esp_combo.clear()
        self.roots = []
        self.esps = []
        try:
            out = subprocess.check_output([HELPER, "scan-roots"], text=True)
            for line in out.splitlines():
                if not line.strip(): continue
                fields = line.split("|")
                dev = fields[0]
                self.roots.append(dev)
                desc = " • ".join(fields[:4])
                self.root_combo.addItem(desc, dev)
        except Exception as e:
            self.output.setPlainText(str(e))

        try:
            out = subprocess.check_output([HELPER, "scan-esps"], text=True)
            for line in out.splitlines():
                if not line.strip(): continue
                fields = line.split("|")
                dev = fields[0]
                self.esps.append(dev)
                self.esp_combo.addItem(" • ".join(fields), dev)
        except Exception:
            pass

        self.esp_combo.insertItem(0, "Auto-detect from installed fstab", "")
        self.output.setPlainText(
            f"Detected {len(self.roots)} Linux root candidate(s) and "
            f"{len(self.esps)} EFI partition candidate(s)."
        )

    def selected_root(self):
        return self.root_combo.currentData() or ""

    def selected_esp(self):
        return self.esp_combo.currentData() or ""

    def repair_boot(self):
        root = self.selected_root()
        if not root:
            QMessageBox.warning(self, "MechOS Recovery", "Select an installed system first.")
            return
        if QMessageBox.question(
            self, "Repair boot",
            f"Repair the boot files for:\n{root}\n\n"
            "This rebuilds initramfs and reinstalls the detected bootloader. "
            "It does not format partitions."
        ) != QMessageBox.StandardButton.Yes:
            return
        args = ["repair-boot", root]
        esp = self.selected_esp()
        if esp: args.append(esp)
        self.run(args, True)

    def rollback(self):
        root = self.selected_root()
        if not root:
            QMessageBox.warning(self, "MechOS Recovery", "Select an installed system first.")
            return
        if QMessageBox.question(
            self, "Rollback failed update",
            "Use the pre-update snapshot recorded by MechOS?\n\n"
            "This is available only on compatible Btrfs/Snapper installations."
        ) != QMessageBox.StandardButton.Yes:
            return
        self.run(["rollback", root], True)

    def load_logs(self):
        root = self.selected_root()
        args = ["logs"]
        if root: args.append(root)
        self.run(args, False)

    def hardware(self):
        try:
            out = subprocess.check_output(
                ["/usr/local/bin/mechos-hardware-scan"], text=True, stderr=subprocess.STDOUT
            )
            self.output.setPlainText(out)
        except Exception as e:
            self.output.setPlainText(str(e))

def main():
    app = QApplication(sys.argv)
    w = Recovery()
    w.show()
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
PYEOF

# ---------------------------------------------------------------------------
# Live Setup Center GUI. The live ISO stays in the desktop session and this
# center is automatically launched. Installed MechOS is still switched to the
# MechScope Gaming session by the existing post-install stage.
# ---------------------------------------------------------------------------
# Preserve the newer branded graphical installer during the final pass.
# The fallback below is only created early or when no current installer exists.
if [ "$PHASE" != "final" ] || [ ! -f "$BIN/mechos-live-setup" ] || ! grep -Fq "MECHOS INSTALLER" "$BIN/mechos-live-setup"; then
cat > "$BIN/mechos-live-setup" <<'PYEOF'
#!/usr/bin/env python3
import os
import subprocess
import sys

from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import (
    QApplication,
    QLabel,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)


def launch(path, args=None):
    args = args or []
    try:
        subprocess.Popen([path, *args])
    except Exception as exc:
        QMessageBox.warning(None, "MechOS", f"Could not launch {path}: {exc}")


class SetupCenter(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MechOS Setup Center")
        self.resize(720, 650)

        root = QWidget()
        self.setCentralWidget(root)
        layout = QVBoxLayout(root)
        layout.setContentsMargins(44, 38, 44, 38)
        layout.setSpacing(14)

        title = QLabel("MECHOS")
        title.setFont(QFont("Sans", 34, QFont.Weight.Bold))
        sub = QLabel("LIVE SETUP & RECOVERY")
        sub.setFont(QFont("Sans", 15, QFont.Weight.Bold))
        desc = QLabel(
            "Try MechOS from the desktop, inspect your hardware, open recovery "
            "tools, or start the guided installer. Installed MechOS boots into MechScope."
        )
        desc.setWordWrap(True)

        layout.addWidget(title)
        layout.addWidget(sub)
        layout.addWidget(desc)

        buttons = [
            ("Install MechOS", self.install),
            ("Open MechScope", lambda: launch("/usr/local/bin/mechscope")),
            ("Performance Center", lambda: launch("/usr/local/bin/mechos-performance-center")),
            ("Update Center", lambda: launch("/usr/local/bin/mechos-update-center")),
            ("Recovery Center", lambda: launch("/usr/local/bin/mechos-recovery-center")),
            ("Hardware Scan", self.hardware),
            ("Continue to Desktop", self.close),
        ]
        for text, callback in buttons:
            btn = QPushButton(text)
            btn.setMinimumHeight(52)
            btn.clicked.connect(callback)
            layout.addWidget(btn)

        layout.addStretch(1)
        foot = QLabel("MechOS v0.3.0 Alpha • Live environment")
        layout.addWidget(foot)

        self.setStyleSheet("""
            QMainWindow, QWidget { background: #090b16; color: #f1f1ff; }
            QPushButton {
                background: #171a33; border: 1px solid #725cff;
                border-radius: 10px; padding: 12px; font-size: 16px;
            }
            QPushButton:hover { background: #27214d; }
        """)

    def install(self):
        reply = QMessageBox.warning(
            self,
            "Install MechOS Alpha",
            "Operating-system installation can erase the disk you select. "
            "For Alpha testing, use a VM or spare disk and verify Archinstall's "
            "final disk summary before confirming.\n\nStart the guided installer?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        if reply == QMessageBox.StandardButton.Yes:
            launch("/usr/local/bin/mechos-install")

    def hardware(self):
        for terminal in ("konsole", "xterm"):
            from shutil import which
            if which(terminal):
                if terminal == "konsole":
                    launch(terminal, ["-e", "bash", "-lc", "/usr/local/bin/mechos-hardware-scan; echo; read -rp 'Press Enter to close...' "])
                else:
                    launch(terminal, ["-e", "/usr/local/bin/mechos-hardware-scan"])
                return
        QMessageBox.information(self, "Hardware Scan", "Run: /usr/local/bin/mechos-hardware-scan")


app = QApplication(sys.argv)
app.setApplicationName("MechOS Setup Center")
win = SetupCenter()
win.show()
sys.exit(app.exec())
PYEOF
fi

# Compatibility wrapper: old callers now open the graphical setup center.
cat > "$BIN/mechos-live-welcome" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if ! { [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null; }; then
  exit 0
fi
exec /usr/local/bin/mechos-live-setup
EOF

# Desktop entries.
cat > "$APPS/mechos-live-setup.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Install / Set Up MechOS
Comment=Open the MechOS live setup and recovery center
Exec=/usr/local/bin/mechos-live-setup
Icon=system-software-install
Terminal=false
Categories=System;Settings;
Keywords=MechOS;Install;Setup;Recovery;
EOF

cat > "$APPS/mechos-recovery-center.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS Recovery Center
Comment=MechOS diagnostics and recovery tools
Exec=/usr/local/bin/mechos-recovery-center
Icon=system-reboot
Terminal=false
Categories=System;Settings;
Keywords=MechOS;Recovery;Repair;Diagnostics;
EOF

# Autostart the graphical setup center in the live desktop. Do not restrict it
# to OnlyShowIn=KDE, because that previously caused the launcher to disappear
# depending on the session environment.
rm -f "$AUTOSTART/mechos-live-welcome.desktop"
cat > "$AUTOSTART/mechos-live-setup.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS Live Setup
Exec=/usr/local/bin/mechos-live-welcome
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

# Live ISO boots to Plasma desktop so the setup center is always usable.
# The post-install hook below removes this live-only override; installed MechOS
# continues to use the MechScope Gaming session.
cat > "$SDDM/99-mechos-live.conf" <<'EOF'
[Autologin]
User=mechos
Session=plasma.desktop
Relogin=true
EOF

chmod 755 \
  "$BIN/mechos-return-to-mechscope" \
  "$BIN/mechos-hardware-scan" \
  "$BIN/mechos-preserve-home" \
  "$BIN/mechos-recovery-helper" \
  "$BIN/mechos-recovery-center" \
  "$BIN/mechos-live-setup" \
  "$BIN/mechos-live-welcome"

# Make archiso permissions authoritative.
if [ -f "$PROFILE" ]; then
  for path in \
    /usr/local/bin/mechos-return-to-mechscope \
    /usr/local/bin/mechos-hardware-scan \
    /usr/local/bin/mechos-preserve-home \
    /usr/local/bin/mechos-recovery-helper \
    /usr/local/bin/mechos-recovery-center \
    /usr/local/bin/mechos-live-setup \
    /usr/local/bin/mechos-live-welcome; do
    if ! grep -Fq "file_permissions[\"$path\"]" "$PROFILE"; then
      printf '\nfile_permissions["%s"]="0:0:755"\n' "$path" >> "$PROFILE"
    fi
  done
fi


if [ -f "$PROFILE" ] && ! grep -Fq 'file_permissions["/usr/local/bin/mechos-desktop-check"]' "$PROFILE"; then
  printf '\nfile_permissions["/usr/local/bin/mechos-desktop-check"]="0:0:755"\n' >> "$PROFILE"
fi

# ---------------------------------------------------------------------------
# v0.3.0 cumulative installed-system integration
# ---------------------------------------------------------------------------

# Make the desktop checker authoritative in ArchISO too.
if [ -f "$PROFILE" ] && ! grep -Fq 'file_permissions["/usr/local/bin/mechos-desktop-check"]' "$PROFILE"; then
  printf '\nfile_permissions["/usr/local/bin/mechos-desktop-check"]="0:0:755"\n' >> "$PROFILE"
fi

# Runtime validation is scope-aware.
#
# Live-required tools must remain directly in the final ArchISO rootfs.
# Post-install-only tools are intentionally removed from the Live rootfs and
# must instead exist in mechos-rootfs.tar.zst.
LIVE_CORE_RUNTIME=(
  mechscope
  mechos-gaming-session
  mechos-performance-center
  mechos-update
  mechos-update-center
  mechos-gpu-setup
  mechos-firstboot
  mechos-install-graphical
)

POSTINSTALL_ONLY_RUNTIME=(
  usr/local/bin/mechos-quick-actions
  usr/local/bin/mechos-quick-actions-daemon
  usr/local/bin/mechos-stream-control
  usr/local/bin/mechos-stream-center
  usr/local/bin/mechos-stream-optimize
  usr/local/bin/mechos-creator-mode
  usr/local/bin/mechos-creator-app
  usr/local/libexec/mechos-creator-app-installer
  usr/local/bin/mechos-creator-session
  usr/local/bin/mechos-creator-setup
  usr/share/applications/mechos-creator-mode.desktop
  usr/share/wayland-sessions/mechos-creator.desktop
)

if [ "$PHASE" = "final" ]; then
  for name in "${LIVE_CORE_RUNTIME[@]}"; do
    [ -x "$BIN/$name" ] || fail "current builder lost required LIVE runtime: $name"
  done

  ROOTFS_ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"
  [ -s "$ROOTFS_ARCHIVE" ] || fail "installed-system payload archive is missing"

  for member in "${POSTINSTALL_ONLY_RUNTIME[@]}"; do
    if ! tar --zstd -tf "$ROOTFS_ARCHIVE" "./$member" >/dev/null 2>&1; then
      fail "installed-system payload lost required post-install runtime: $member"
    fi
  done

  # These are deliberately absent from Live after payload staging.
  for name in     mechos-quick-actions     mechos-quick-actions-daemon     mechos-stream-control     mechos-stream-center     mechos-stream-optimize     mechos-creator-mode     mechos-creator-app     mechos-creator-session     mechos-creator-setup; do
    [ ! -e "$BIN/$name" ] || fail "post-install-only runtime leaked back into Live: $name"
  done

  [ ! -e "$ROOT/usr/local/libexec/mechos-creator-app-installer" ] ||     fail "Creator app installer leaked back into Live"
  [ ! -e "$APPS/mechos-creator-mode.desktop" ] ||     fail "Creator Mode launcher leaked back into Live"
  [ ! -e "$ROOT/usr/share/wayland-sessions/mechos-creator.desktop" ] ||     fail "Creator Mode session leaked back into Live"
fi

if [ "$PHASE" = "final" ]; then
  grep -q "repair-boot" "$BIN/mechos-recovery-helper" || fail "Recovery Boot Repair command missing"
  grep -q "rollback_failed_update" "$BIN/mechos-recovery-helper" || fail "Recovery rollback command missing"
  grep -q "Repair Boot" "$BIN/mechos-recovery-center" || fail "Recovery Center Repair Boot UI missing"
  grep -q "Rollback Failed Update" "$BIN/mechos-recovery-center" || fail "Recovery Center rollback UI missing"
fi

# Stage cumulative repaired tools through the existing install payload.
if [ -d "$PAYLOAD" ]; then
  for name in \
    mechos-return-to-mechscope \
    mechos-hardware-scan \
    mechos-preserve-home \
    mechos-recovery-helper \
    mechos-recovery-center \
    mechos-desktop-check; do
    cp -f "$BIN/$name" "$PAYLOAD/$name"
    chmod 644 "$PAYLOAD/$name"
  done

  if [ -f "$PAYLOAD/mechos-postinstall-target" ]; then
    # Remove old cumulative tails left by v0.2.1/v0.2.2 patch packages.
    python3 - "$PAYLOAD/mechos-postinstall-target" <<'PYEOF'
from pathlib import Path
import sys

p = Path(sys.argv[1])
text = p.read_text()

markers = (
    "# MECHOS_V0_2_1_POSTINSTALL",
    "# MECHOS_V0_2_2_DESKTOP_POSTINSTALL",
    "# MECHOS_V0_2_3_CUMULATIVE_POSTINSTALL",
    "# MECHOS_V0_3_0_CUMULATIVE_POSTINSTALL",
)

positions = [text.find(m) for m in markers if text.find(m) >= 0]
if positions:
    text = text[:min(positions)].rstrip() + "\n"

p.write_text(text)
PYEOF

    cat >> "$PAYLOAD/mechos-postinstall-target" <<'POSTEOF'

# MECHOS_V0_3_0_CUMULATIVE_POSTINSTALL
set -euo pipefail

echo "[MechOS] Applying cumulative v0.3.0 installed-system integration..."

MECHOS_PAYLOAD_BASE="http://127.0.0.1:45811"

# Pull only repair/recovery utilities from the live payload. Existing/newer
# MechScope, updater, performance, GPU and first-boot implementations remain
# those already delivered by the main MechOS rootfs payload.
for name in \
  mechos-return-to-mechscope \
  mechos-hardware-scan \
  mechos-preserve-home \
  mechos-recovery-helper \
  mechos-recovery-center \
  mechos-desktop-check; do
  if command -v curl >/dev/null 2>&1; then
    curl -fsS "$MECHOS_PAYLOAD_BASE/$name" -o "/usr/local/bin/$name"
    chmod 755 "/usr/local/bin/$name"
  fi
done

# Never carry LIVE-only setup/session overrides into the installed system.
rm -f /etc/sddm.conf.d/99-mechos-live.conf
rm -f /etc/xdg/autostart/mechos-live-setup.desktop
rm -f /etc/xdg/autostart/mechos-live-welcome.desktop

# Guarantee a complete KDE Plasma desktop inside the INSTALLED target.
DESKTOP_PACKAGES=(
  plasma-desktop
  plasma-workspace
  plasma-nm
  plasma-pa
  kscreen
  bluedevil
  xdg-desktop-portal-kde
  xorg-xwayland
  sddm
  sddm-kcm
  konsole
  dolphin
  networkmanager
  pipewire
  pipewire-alsa
  pipewire-pulse
  wireplumber
  polkit
)

pacman -Syy --noconfirm

missing_desktop=()
for pkg in "${DESKTOP_PACKAGES[@]}"; do
  if ! pacman -Si "$pkg" >/dev/null 2>&1; then
    missing_desktop+=("$pkg")
  fi
done

if [ "${#missing_desktop[@]}" -gt 0 ]; then
  echo "[MechOS] ERROR: required desktop packages are unavailable:" >&2
  printf '  - %s\n' "${missing_desktop[@]}" >&2
  exit 61
fi

pacman -S --needed --noconfirm "${DESKTOP_PACKAGES[@]}"

# Detect the real Archinstall-created desktop user. Never hard-code "mechos"
# for an installed target.
TARGET_USER="$(
  awk -F: '
    $3 >= 1000 && $3 < 60000 &&
    $6 ~ /^\/home\// &&
    $7 !~ /(nologin|false)$/ {
      print $1
      exit
    }
  ' /etc/passwd
)"

if [ -z "$TARGET_USER" ]; then
  echo "[MechOS] ERROR: no normal installed user was found." >&2
  echo "[MechOS] Create a normal user in the installer before completion." >&2
  exit 62
fi

echo "[MechOS] Installed desktop user: $TARGET_USER"

mkdir -p /usr/share/wayland-sessions
if [ ! -f /usr/share/wayland-sessions/mechos-gaming.desktop ]; then
  cat > /usr/share/wayland-sessions/mechos-gaming.desktop <<'SESSIONEOF'
[Desktop Entry]
Name=MechOS Gaming
Comment=MechScope gaming shell
Exec=/usr/local/bin/mechos-gaming-session
Type=Application
DesktopNames=KDE;MechOS;
SESSIONEOF
fi

# Refuse to call the install complete if the desktop or MechOS core vanished.
required_installed=(
  /usr/bin/startplasma-wayland
  /usr/bin/sddm
  /usr/local/bin/mechscope
  /usr/local/bin/mechos-gaming-session
  /usr/local/bin/mechos-performance-center
  /usr/local/bin/mechos-update
  /usr/local/bin/mechos-update-center
  /usr/local/bin/mechos-gpu-setup
  /usr/local/bin/mechos-firstboot
  /usr/local/bin/mechos-install-graphical
  /usr/local/bin/mechos-quick-actions
  /usr/local/bin/mechos-quick-actions-daemon
  /usr/local/bin/mechos-stream-control
  /usr/local/bin/mechos-stream-center
  /usr/local/bin/mechos-stream-optimize
)

for path in "${required_installed[@]}"; do
  if [ ! -x "$path" ]; then
    echo "[MechOS] ERROR: required installed runtime is missing: $path" >&2
    exit 63
  fi
done

if [ ! -f /usr/share/wayland-sessions/plasma.desktop ]; then
  echo "[MechOS] ERROR: Plasma Wayland session file is missing." >&2
  exit 64
fi

if [ ! -f /usr/share/wayland-sessions/mechos-gaming.desktop ]; then
  echo "[MechOS] ERROR: MechOS Gaming session file is missing." >&2
  exit 65
fi

# Correct installed SDDM configuration every time this cumulative stage runs.
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/90-mechos-installed.conf <<SDDMEOF
[Autologin]
User=$TARGET_USER
Session=mechos-gaming.desktop
Relogin=true
SDDMEOF

systemctl disable plasmalogin.service 2>/dev/null || true
systemctl enable sddm.service
systemctl enable NetworkManager.service
systemctl enable mechos-firstboot.service 2>/dev/null || true
systemctl set-default graphical.target

rm -f /etc/systemd/system/display-manager.service
ln -s /usr/lib/systemd/system/sddm.service /etc/systemd/system/display-manager.service

# Let the existing GPU setup apply target-hardware configuration.
if [ -x /usr/local/bin/mechos-gpu-setup ]; then
  /usr/local/bin/mechos-gpu-setup --apply || true
fi

mkdir -p /var/lib/mechos /var/log

DESKTOP_LOG="/var/log/mechos-desktop-install.log"
{
  echo "MechOS cumulative desktop/runtime verification"
  echo "Version: v0.3.0"
  echo "Date: $(date -Is)"
  echo "User: $TARGET_USER"
  echo "Default target: $(systemctl get-default 2>/dev/null || true)"
  echo "Display manager: $(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)"
  echo "startplasma-wayland: $(command -v startplasma-wayland || true)"
  echo "sddm: $(command -v sddm || true)"
  echo "plasma.desktop: $(test -f /usr/share/wayland-sessions/plasma.desktop && echo present || echo missing)"
  echo "mechos-gaming.desktop: $(test -f /usr/share/wayland-sessions/mechos-gaming.desktop && echo present || echo missing)"
  echo
  echo "Core MechOS runtime:"
  for path in \
    /usr/local/bin/mechscope \
    /usr/local/bin/mechos-performance-center \
    /usr/local/bin/mechos-update-center \
    /usr/local/bin/mechos-gpu-setup \
    /usr/local/bin/mechos-firstboot \
    /usr/local/bin/mechos-creator-mode \
    /usr/local/bin/mechos-creator-session \
    /usr/local/bin/mechos-creator-app; do
    test -x "$path" && echo "OK  $path" || echo "MISSING  $path"
  done
  echo
  pacman -Q plasma-desktop plasma-workspace sddm konsole dolphin 2>&1 || true
} > "$DESKTOP_LOG"

test -x /usr/local/bin/mechos-creator-mode
test -x /usr/local/bin/mechos-creator-session
test -x /usr/local/bin/mechos-creator-app
test -f /usr/share/wayland-sessions/mechos-creator.desktop
test -f /usr/share/applications/mechos-creator-mode.desktop

touch /var/lib/mechos/desktop-installed
printf '%s\n' "0.3.0" > /var/lib/mechos/runtime-baseline
echo "[MechOS] Cumulative installed-system verification passed."
if [ -n "${SUCCESS_TOKEN:-}" ]; then
  curl -sS "http://127.0.0.1:45811/${SUCCESS_TOKEN}" >/dev/null 2>&1 || true
fi
POSTEOF

    chmod 755 "$PAYLOAD/mechos-postinstall-target"
  fi
fi

# ---------------------------------------------------------------------------
# Cumulative build-time validation
# ---------------------------------------------------------------------------
bash -n "$BIN/mechos-desktop-check" || fail "bash validation failed: $BIN/mechos-desktop-check"
[ -x "$BIN/mechos-desktop-check" ] || fail "missing executable: $BIN/mechos-desktop-check"

for script in \
  "$BIN/mechos-return-to-mechscope" \
  "$BIN/mechos-hardware-scan" \
  "$BIN/mechos-preserve-home" \
  "$BIN/mechos-recovery-helper" \
  "$BIN/mechos-live-welcome"; do
  bash -n "$script" || fail "bash validation failed: $script"
done

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  "$BIN/mechos-recovery-center" \
  "$BIN/mechos-live-setup" \
  || fail "Python GUI validation failed"

for required in \
  mechos-return-to-mechscope \
  mechos-hardware-scan \
  mechos-preserve-home \
  mechos-recovery-helper \
  mechos-recovery-center \
  mechos-live-setup \
  mechos-live-welcome \
  mechos-desktop-check; do
  [ -x "$BIN/$required" ] || fail "missing executable: $BIN/$required"
done

# Validate the post-install target itself after cumulative injection.
if [ -f "$PAYLOAD/mechos-postinstall-target" ]; then
  bash -n "$PAYLOAD/mechos-postinstall-target" \
    || fail "post-install target failed bash syntax validation"
  grep -Fq 'MECHOS_V0_3_0_CUMULATIVE_POSTINSTALL' "$PAYLOAD/mechos-postinstall-target" \
    || fail "cumulative post-install marker missing"
fi

log "cumulative integration applied ($PHASE)"
