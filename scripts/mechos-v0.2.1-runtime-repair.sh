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

log() { printf '[MechOS v0.2.1] %s\n' "$*"; }
fail() { printf '[MechOS v0.2.1] ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$ROOT" ] || fail "ArchISO rootfs does not exist at $ROOT"
mkdir -p "$BIN" "$APPS" "$AUTOSTART" "$SDDM"

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
# Recovery helper: diagnostics only unless the user explicitly launches the
# guided installer, which still keeps Archinstall's disk confirmation UI.
# ---------------------------------------------------------------------------
cat > "$BIN/mechos-recovery-helper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-help}"
case "$cmd" in
  hardware)
    exec /usr/local/bin/mechos-hardware-scan
    ;;
  network)
    echo "=== NetworkManager ==="
    systemctl --no-pager --full status NetworkManager.service 2>/dev/null || true
    echo
    nmcli device status 2>/dev/null || true
    echo
    ip addr 2>/dev/null || true
    ;;
  boot-info)
    echo "=== Firmware / boot mode ==="
    if [ -d /sys/firmware/efi ]; then echo "UEFI boot detected"; else echo "Legacy/BIOS boot detected"; fi
    echo
    echo "=== Block devices ==="
    lsblk -f 2>/dev/null || true
    echo
    echo "=== Boot entries ==="
    bootctl status 2>/dev/null || true
    ;;
  logs)
    echo "=== Failed services ==="
    systemctl --failed --no-pager 2>/dev/null || true
    echo
    echo "=== Current boot errors ==="
    journalctl -b -p err --no-pager -n 200 2>/dev/null || true
    ;;
  preserve-home)
    exec /usr/local/bin/mechos-preserve-home
    ;;
  installer)
    exec /usr/local/bin/mechos-install
    ;;
  *)
    cat <<'TXT'
Usage: mechos-recovery-helper <command>

Commands:
  hardware       Hardware report
  network        Network diagnostics
  boot-info      Boot and storage diagnostics
  logs           Failed services and current-boot errors
  preserve-home  Non-destructive reinstall guide
  installer      Launch the guided MechOS installer
TXT
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
from pathlib import Path

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import (
    QApplication,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)


def run_capture(args):
    try:
        p = subprocess.run(args, text=True, capture_output=True, timeout=25, check=False)
        out = (p.stdout or "") + (p.stderr or "")
        return out.strip() or f"Command exited with code {p.returncode}."
    except Exception as exc:
        return f"Could not run {' '.join(args)}: {exc}"


class RecoveryCenter(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MechOS Recovery Center")
        self.resize(1050, 700)

        root = QWidget()
        self.setCentralWidget(root)
        layout = QHBoxLayout(root)

        sidebar = QVBoxLayout()
        title = QLabel("MECHOS\nRECOVERY")
        title.setFont(QFont("Sans", 22, QFont.Weight.Bold))
        sidebar.addWidget(title)

        actions = [
            ("Hardware Scan", lambda: self.show_cmd("hardware")),
            ("Network Diagnostics", lambda: self.show_cmd("network")),
            ("Boot / Disk Info", lambda: self.show_cmd("boot-info")),
            ("System Logs", lambda: self.show_cmd("logs")),
            ("Preserve Home Guide", lambda: self.show_cmd("preserve-home")),
            ("Open Terminal", self.open_terminal),
            ("Install MechOS", self.install_mechos),
        ]
        for text, callback in actions:
            btn = QPushButton(text)
            btn.setMinimumHeight(48)
            btn.clicked.connect(callback)
            sidebar.addWidget(btn)
        sidebar.addStretch(1)

        self.output = QTextEdit()
        self.output.setReadOnly(True)
        self.output.setPlainText(
            "MechOS Recovery Center Alpha\n\n"
            "Use the diagnostic tools on the left. Recovery diagnostics do not "
            "change disks. Installation remains guided by Archinstall so disk "
            "selection and formatting choices stay visible before confirmation."
        )

        left = QWidget()
        left.setLayout(sidebar)
        left.setMaximumWidth(300)
        layout.addWidget(left)
        layout.addWidget(self.output, 1)

        self.setStyleSheet("""
            QMainWindow, QWidget { background: #090b16; color: #eef0ff; }
            QPushButton {
                background: #171a33; border: 1px solid #6657ff;
                border-radius: 8px; padding: 10px; text-align: left;
            }
            QPushButton:hover { background: #26204a; }
            QTextEdit { background: #0d1020; border: 1px solid #34365d; padding: 12px; }
        """)

    def show_cmd(self, name):
        self.output.setPlainText(run_capture(["/usr/local/bin/mechos-recovery-helper", name]))

    def open_terminal(self):
        for cmd in (["konsole"], ["xterm"]):
            if shutil_which(cmd[0]):
                subprocess.Popen(cmd)
                return
        QMessageBox.warning(self, "Terminal", "No supported terminal launcher was found.")

    def install_mechos(self):
        reply = QMessageBox.warning(
            self,
            "Install MechOS",
            "The installer can erase a disk depending on the choices you make. "
            "Use a VM or spare disk for Alpha testing and review Archinstall's "
            "final disk summary before confirming.\n\nOpen the installer?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        if reply == QMessageBox.StandardButton.Yes:
            subprocess.Popen(["/usr/local/bin/mechos-install"])


def shutil_which(name):
    from shutil import which
    return which(name)


app = QApplication(sys.argv)
app.setApplicationName("MechOS Recovery Center")
win = RecoveryCenter()
win.show()
sys.exit(app.exec())
PYEOF

# ---------------------------------------------------------------------------
# Live Setup Center GUI. The live ISO stays in the desktop session and this
# center is automatically launched. Installed MechOS is still switched to the
# MechScope Gaming session by the existing post-install stage.
# ---------------------------------------------------------------------------
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
            ("Creator Mode", lambda: launch("/usr/local/bin/mechos-creator-mode")),
            ("Performance Center", lambda: launch("/usr/local/bin/mechos-performance-center")),
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
        foot = QLabel("MechOS v0.2.1 Alpha • Live environment")
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

# If the full installer payload has already been staged, expose the repaired
# scripts through the installer's existing loopback HTTP server and teach the
# post-install target to fetch them. This keeps installed MechOS repaired even
# when the old rootfs tarball was created earlier in the builder.
if [ -d "$PAYLOAD" ]; then
  for name in \
    mechos-return-to-mechscope \
    mechos-hardware-scan \
    mechos-preserve-home \
    mechos-recovery-helper \
    mechos-recovery-center; do
    cp -f "$BIN/$name" "$PAYLOAD/$name"
    chmod 644 "$PAYLOAD/$name"
  done

  if [ -f "$PAYLOAD/mechos-postinstall-target" ] && ! grep -Fq 'MECHOS_V0_2_1_POSTINSTALL' "$PAYLOAD/mechos-postinstall-target"; then
    cat >> "$PAYLOAD/mechos-postinstall-target" <<'POSTEOF'

# MECHOS_V0_2_1_POSTINSTALL
# Pull repaired installed-system runtime tools from the live installer's
# loopback-only payload server. Live-only setup UI stays on the ISO.
MECHOS_PAYLOAD_BASE="http://127.0.0.1:45811"
for name in \
  mechos-return-to-mechscope \
  mechos-hardware-scan \
  mechos-preserve-home \
  mechos-recovery-helper \
  mechos-recovery-center; do
  if command -v curl >/dev/null 2>&1; then
    curl -fsS "$MECHOS_PAYLOAD_BASE/$name" -o "/usr/local/bin/$name" || true
    chmod 755 "/usr/local/bin/$name" 2>/dev/null || true
  fi
done

# Never carry the live desktop override into an installed system.
rm -f /etc/sddm.conf.d/99-mechos-live.conf
rm -f /etc/xdg/autostart/mechos-live-setup.desktop
rm -f /etc/xdg/autostart/mechos-live-welcome.desktop

mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/90-mechos-installed.conf <<'SDDMEOF'
[Autologin]
User=mechos
Session=mechos-gaming.desktop
Relogin=true
SDDMEOF
POSTEOF
    chmod 755 "$PAYLOAD/mechos-postinstall-target"
  fi
fi

# Build-time runtime validation. A syntax error in any generated script now
# stops the ISO build before mkarchiso spends time creating a broken image.
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
  mechos-live-welcome; do
  [ -x "$BIN/$required" ] || fail "missing executable: $BIN/$required"
done

log "runtime repair applied ($PHASE)"
