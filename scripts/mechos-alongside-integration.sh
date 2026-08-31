#!/usr/bin/env bash
set -euo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
BIN="$ROOT/usr/local/bin"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
PROFILE="/workspace/archlive/profiledef.sh"

log() { printf '[MechOS Alongside] %s\n' "$*"; }
fail() { printf '[MechOS Alongside] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -f "$BIN/mechos-live-setup" ] || fail "graphical live installer is missing"

# ---------------------------------------------------------------------------
# Read-only dual-boot planning assistant.
# ---------------------------------------------------------------------------
cat > "$BIN/mechos-alongside-assistant" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

PLAN="/tmp/mechos-alongside-plan.txt"
MIN_GIB=40

clear 2>/dev/null || true
cat <<'TXT'
MECHOS — INSTALL ALONGSIDE EXISTING OS
======================================

This assistant does NOT resize, format, or delete partitions automatically.
It scans the disks read-only, records the target and desired MechOS size, then
opens Archinstall's manual partitioning screen so every disk change remains
visible and requires confirmation.

Before continuing, back up important files. Windows users should disable Fast
Startup/hibernation and suspend BitLocker before resizing a Windows partition.
TXT

echo
echo "Detected operating systems:"
if command -v os-prober >/dev/null 2>&1; then
  OS_OUTPUT="$(os-prober 2>/dev/null || true)"
  if [ -n "$OS_OUTPUT" ]; then
    printf '%s\n' "$OS_OUTPUT" | sed 's/^/  /'
  else
    echo "  No additional OS was identified by os-prober."
  fi
else
  echo "  os-prober is unavailable; showing filesystems instead."
fi

echo
echo "Disks and existing partitions:"
lsblk -e7 -o NAME,PATH,SIZE,TYPE,FSTYPE,FSVER,LABEL,MOUNTPOINTS,MODEL

echo
echo "Unallocated/free extents (when parted is available):"
if command -v parted >/dev/null 2>&1; then
  while read -r disk; do
    [ -b "$disk" ] || continue
    echo
    echo "  $disk"
    parted -ms "$disk" unit GiB print free 2>/dev/null \
      | awk -F: '$1 ~ /^[0-9]+$/ && $5=="free" {printf "    free: %s to %s (%s)\n", $2,$3,$4}' \
      || true
  done < <(lsblk -dpno PATH,TYPE | awk '$2=="disk" {print $1}')
else
  echo "  parted is unavailable. Archinstall will show the partition map."
fi

echo
read -rp "Target disk for the dual-boot install (example /dev/nvme0n1): " TARGET_DISK
if [ ! -b "$TARGET_DISK" ]; then
  echo "That target is not a block device: $TARGET_DISK" >&2
  exit 2
fi
if [ "$(lsblk -dno TYPE "$TARGET_DISK" 2>/dev/null || true)" != "disk" ]; then
  echo "Choose the whole disk, not an individual partition." >&2
  exit 2
fi

read -rp "Desired MechOS space in GiB (minimum ${MIN_GIB}): " SIZE_GIB
case "$SIZE_GIB" in
  ''|*[!0-9]*) echo "Enter a whole number of GiB." >&2; exit 2 ;;
esac
if [ "$SIZE_GIB" -lt "$MIN_GIB" ]; then
  echo "MechOS Alongside requires at least ${MIN_GIB} GiB in this guided flow." >&2
  exit 2
fi

cat > "$PLAN" <<EOFPLAN
MechOS Alongside Installation Plan
Generated: $(date -Is)
Target disk: $TARGET_DISK
Requested MechOS space: ${SIZE_GIB} GiB
Existing OS scan:
${OS_OUTPUT:-No OS identified by os-prober}
EOFPLAN

cat <<EOF

PLAN SUMMARY
------------
Target disk: $TARGET_DISK
MechOS allocation target: ${SIZE_GIB} GiB
Existing partitions will NOT be modified by this assistant.

Archinstall will open next. In Disk configuration:
  1. Choose Manual partitioning.
  2. Select $TARGET_DISK.
  3. Use existing unallocated space, or explicitly shrink the partition you
     intend to shrink using a trusted partitioning tool first.
  4. Create a MechOS root partition of about ${SIZE_GIB} GiB.
  5. Reuse the existing EFI System Partition WITHOUT formatting it.
  6. Choose GRUB as the bootloader for the easiest Windows/Linux dual-boot menu.
  7. Review Archinstall's final partition summary before confirming.

The plan is saved at: $PLAN
EOF

read -rp "Press Enter to open the guided installer, or Ctrl+C to cancel... " _
exec /usr/local/bin/mechos-install --terminal --preserve-home --alongside
EOF
chmod 755 "$BIN/mechos-alongside-assistant"

# ---------------------------------------------------------------------------
# Add a fourth graphical installer choice without replacing the current UI.
# ---------------------------------------------------------------------------
python3 - "$BIN/mechos-live-setup" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "Install Alongside Existing OS"
if marker not in text:
    old = '''        self.custom = QRadioButton("Custom Install\\
Advanced/manual partitioning")
        self.clean.setChecked(True)
        self.clean.toggled.connect(lambda v: self.set_mode("clean", v))
        self.keep.toggled.connect(lambda v: self.set_mode("keep", v))
        self.custom.toggled.connect(lambda v: self.set_mode("custom", v))
        for w in (self.clean, self.keep, self.custom):'''
    new = '''        self.custom = QRadioButton("Custom Install\\
Advanced/manual partitioning")
        self.alongside = QRadioButton("Install Alongside Existing OS\\
Guided Windows/Linux dual-boot setup")
        self.clean.setChecked(True)
        self.clean.toggled.connect(lambda v: self.set_mode("clean", v))
        self.keep.toggled.connect(lambda v: self.set_mode("keep", v))
        self.custom.toggled.connect(lambda v: self.set_mode("custom", v))
        self.alongside.toggled.connect(lambda v: self.set_mode("alongside", v))
        for w in (self.clean, self.keep, self.custom, self.alongside):'''
    if old not in text:
        raise SystemExit("could not locate installer option block")
    text = text.replace(old, new, 1)

    old = 'names = {"clean":"Clean Install","keep":"Keep Personal Data","custom":"Custom Install"}'
    new = 'names = {"clean":"Clean Install","keep":"Keep Personal Data","custom":"Custom Install","alongside":"Install Alongside Existing OS"}'
    if old not in text:
        raise SystemExit("could not locate installer mode-name map")
    text = text.replace(old, new, 1)

    old = '''        if mode == "clean":
            self.warning_text.setText("The selected root/target can be erased. Review Archinstall's final disk summary before confirming.")
        else:
            self.warning_text.setText("MechOS will open manual partitioning so existing personal data is never silently formatted.")'''
    new = '''        if mode == "clean":
            self.warning_text.setText("The selected root/target can be erased. Review Archinstall's final disk summary before confirming.")
        elif mode == "alongside":
            self.warning_text.setText("Alongside mode scans existing systems and guides a dual-boot layout. No partition is resized or formatted automatically.")
        else:
            self.warning_text.setText("MechOS will open manual partitioning so existing personal data is never silently formatted.")'''
    if old not in text:
        raise SystemExit("could not locate installer warning block")
    text = text.replace(old, new, 1)

    old = '''        if self.install_mode == "keep":
            subprocess.Popen(["konsole","-e","sudo","/usr/local/bin/mechos-preserve-home"])
            return

        if self.install_mode == "custom":'''
    new = '''        if self.install_mode == "alongside":
            subprocess.Popen(["konsole","-e","sudo","/usr/local/bin/mechos-alongside-assistant"])
            return

        if self.install_mode == "keep":
            subprocess.Popen(["konsole","-e","sudo","/usr/local/bin/mechos-preserve-home"])
            return

        if self.install_mode == "custom":'''
    if old not in text:
        raise SystemExit("could not locate installer launch block")
    text = text.replace(old, new, 1)

    path.write_text(text, encoding="utf-8")
PY

# ---------------------------------------------------------------------------
# GRUB dual-boot discovery. This is harmless on non-GRUB installs and makes
# Windows/Linux entries visible automatically when the user selects GRUB.
# ---------------------------------------------------------------------------
if [ -f "$PAYLOAD/mechos-postinstall-target" ] && \
   ! grep -Fq 'MECHOS_ALONGSIDE_BOOTMENU' "$PAYLOAD/mechos-postinstall-target"; then
  cat >> "$PAYLOAD/mechos-postinstall-target" <<'POSTEOF'

# MECHOS_ALONGSIDE_BOOTMENU
# Enable discovery of other installed operating systems when GRUB is the
# selected bootloader. Non-GRUB installations simply skip this block.
if command -v grub-mkconfig >/dev/null 2>&1 && [ -d /boot/grub ]; then
  mkdir -p /etc/default/grub.d
  cat > /etc/default/grub.d/90-mechos-dualboot.cfg <<'EOF'
GRUB_DISABLE_OS_PROBER=false
EOF
  if command -v os-prober >/dev/null 2>&1; then
    os-prober || true
  fi
  grub-mkconfig -o /boot/grub/grub.cfg || true
fi
POSTEOF
  chmod 755 "$PAYLOAD/mechos-postinstall-target"
fi

# ArchISO executable permission for the new live helper.
if [ -f "$PROFILE" ] && \
   ! grep -Fq 'file_permissions["/usr/local/bin/mechos-alongside-assistant"]' "$PROFILE"; then
  printf '\nfile_permissions["/usr/local/bin/mechos-alongside-assistant"]="0:0:755"\n' >> "$PROFILE"
fi

bash -n "$BIN/mechos-alongside-assistant" || fail "Alongside helper shell syntax failed"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$BIN/mechos-live-setup" \
  || fail "graphical installer Python validation failed"
bash -n "$PAYLOAD/mechos-postinstall-target" \
  || fail "post-install script syntax failed after dual-boot integration"
grep -Fq 'Install Alongside Existing OS' "$BIN/mechos-live-setup" \
  || fail "Alongside option is missing from graphical installer"
grep -Fq 'MECHOS_ALONGSIDE_BOOTMENU' "$PAYLOAD/mechos-postinstall-target" \
  || fail "dual-boot post-install integration is missing"

log "Install Alongside Existing OS option added"
