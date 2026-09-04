#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
POSTINSTALL="$ROOT/usr/share/mechos/install-payload/mechos-postinstall-target"
REFERENCE="/workspace/branding/mechos-splash-reference.png"

log(){ printf '[MechOS Reference Splash] %s\n' "$*"; }
fail(){ printf '[MechOS Reference Splash] ERROR: %s\n' "$*" >&2; exit 1; }

[ -s "$REFERENCE" ] || fail "approved splash reference missing: $REFERENCE"

ensure_plymouth_hook(){
  local tree="$1"
  local cfg="$tree/etc/mkinitcpio.conf"
  [ -f "$cfg" ] || return 0
  if grep -q '^HOOKS=' "$cfg" && ! grep '^HOOKS=' "$cfg" | grep -qw plymouth; then
    if grep '^HOOKS=' "$cfg" | grep -qw systemd; then
      sed -i -E '/^HOOKS=/ s/(^HOOKS=\([^)]*\bsystemd\b)/\1 plymouth/' "$cfg"
    elif grep '^HOOKS=' "$cfg" | grep -qw udev; then
      sed -i -E '/^HOOKS=/ s/(^HOOKS=\([^)]*\budev\b)/\1 plymouth/' "$cfg"
    else
      sed -i -E '/^HOOKS=/ s/\)$/ plymouth)/' "$cfg"
    fi
  fi
}

install_theme(){
  local tree="$1"
  local theme="$tree/usr/share/plymouth/themes/mechos"
  mkdir -p "$theme" "$tree/etc/plymouth" "$tree/usr/share/mechos/branding"
  install -m 0644 "$REFERENCE" "$theme/mechos-splash-reference.png"
  install -m 0644 "$REFERENCE" "$tree/usr/share/mechos/branding/mechos-splash-reference.png"

  cat > "$theme/mechos.plymouth" <<'EOF'
[Plymouth Theme]
Name=MechOS Reference Splash
Description=Approved MechOS installed-system splash screen
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/mechos
ScriptFile=/usr/share/plymouth/themes/mechos/mechos.script
EOF

  cat > "$theme/mechos.script" <<'EOF'
# MECHOS_REFERENCE_SPLASH_V1
Window.SetBackgroundTopColor(0.004, 0.008, 0.020);
Window.SetBackgroundBottomColor(0.004, 0.008, 0.020);

reference.original = Image("mechos-splash-reference.png");
screen.w = Window.GetWidth();
screen.h = Window.GetHeight();
image.w = reference.original.GetWidth();
image.h = reference.original.GetHeight();
scale.x = screen.w / image.w;
scale.y = screen.h / image.h;
scale = scale.x;
if (scale.y < scale.x) {
    scale = scale.y;
}
reference.image = reference.original.Scale(image.w * scale, image.h * scale);
reference.sprite = Sprite(reference.image);
reference.sprite.SetX((screen.w - reference.image.GetWidth()) / 2);
reference.sprite.SetY((screen.h - reference.image.GetHeight()) / 2);
reference.sprite.SetZ(-100);

message.image = Image.Text("", 0.84, 0.90, 1.00);
message.sprite = Sprite(message.image);
message.sprite.SetZ(100);

fun message_callback(text) {
    message.image = Image.Text(text, 0.84, 0.90, 1.00);
    message.sprite.SetImage(message.image);
    message.sprite.SetX(Window.GetWidth() / 2 - message.image.GetWidth() / 2);
    message.sprite.SetY(Window.GetHeight() - message.image.GetHeight() - 42);
}
Plymouth.SetMessageFunction(message_callback);
EOF

  cat > "$tree/etc/plymouth/plymouthd.conf" <<'EOF'
[Daemon]
Theme=mechos
ShowDelay=0
DeviceTimeout=8
EOF

  ensure_plymouth_hook "$tree"
}

install_theme "$ROOT"

if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xpf "$ARCHIVE" -C "$tmp"
  install_theme "$tmp"
  replacement="$ARCHIVE.reference-splash"
  tar --zstd -cpf "$replacement" -C "$tmp" .
  mv -f "$replacement" "$ARCHIVE"
  rm -rf "$tmp"
  trap - EXIT
fi

# Reassert the approved theme on the installed target, guarantee the Plymouth
# hook and kernel command line, then rebuild initramfs. This is intentionally
# done on the target because Archinstall creates the target's mkinitcpio/boot
# files independently from the Live ISO rootfs.
if [ -f "$POSTINSTALL" ] && ! grep -Fq 'MECHOS_REFERENCE_SPLASH_POSTINSTALL_V2' "$POSTINSTALL"; then
cat >> "$POSTINSTALL" <<'EOF'

# MECHOS_REFERENCE_SPLASH_POSTINSTALL_V2
mkdir -p /etc/plymouth
cat > /etc/plymouth/plymouthd.conf <<'PLYEOF'
[Daemon]
Theme=mechos
ShowDelay=0
DeviceTimeout=8
PLYEOF

# Ensure Plymouth is actually inside the installed initramfs.
if [ -f /etc/mkinitcpio.conf ] && grep -q '^HOOKS=' /etc/mkinitcpio.conf && ! grep '^HOOKS=' /etc/mkinitcpio.conf | grep -qw plymouth; then
  if grep '^HOOKS=' /etc/mkinitcpio.conf | grep -qw systemd; then
    sed -i -E '/^HOOKS=/ s/(^HOOKS=\([^)]*\bsystemd\b)/\1 plymouth/' /etc/mkinitcpio.conf
  elif grep '^HOOKS=' /etc/mkinitcpio.conf | grep -qw udev; then
    sed -i -E '/^HOOKS=/ s/(^HOOKS=\([^)]*\budev\b)/\1 plymouth/' /etc/mkinitcpio.conf
  else
    sed -i -E '/^HOOKS=/ s/\)$/ plymouth)/' /etc/mkinitcpio.conf
  fi
fi

if command -v plymouth-set-default-theme >/dev/null 2>&1; then
  plymouth-set-default-theme mechos >/dev/null 2>&1 || true
fi

# systemd-boot / kernel-install command line.
if [ -f /etc/kernel/cmdline ]; then
  if ! grep -qw splash /etc/kernel/cmdline; then
    sed -i '1 s/$/ quiet splash loglevel=3 rd.systemd.show_status=auto vt.global_cursor_default=0/' /etc/kernel/cmdline
  fi
fi
if [ -d /boot/loader/entries ]; then
  for entry in /boot/loader/entries/*.conf; do
    [ -f "$entry" ] || continue
    if grep -q '^options ' "$entry" && ! grep '^options ' "$entry" | grep -qw splash; then
      sed -i '/^options / s/$/ quiet splash loglevel=3 rd.systemd.show_status=auto vt.global_cursor_default=0/' "$entry"
    fi
  done
fi

# GRUB command line.
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

if command -v mkinitcpio >/dev/null 2>&1; then
  mkinitcpio -P || echo '[MechOS Reference Splash] WARNING: initramfs refresh failed; theme files remain installed.' >&2
fi
EOF
  bash -n "$POSTINSTALL" || fail "post-install target syntax failed after splash integration"
fi

log 'Approved splash is installed, Plymouth hook is enforced, kernel splash options are present, and installed initramfs is rebuilt'
