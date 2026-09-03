#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
POSTINSTALL="$ROOT/usr/share/mechos/install-payload/mechos-postinstall-target"
REFERENCE="/workspace/branding/mechos-splash-reference.png"

log(){ printf '[MechOS Reference Splash] %s\n' "$*"; }
fail(){ printf '[MechOS Reference Splash] ERROR: %s\n' "$*" >&2; exit 1; }

[ -s "$REFERENCE" ] || fail "approved splash reference missing: $REFERENCE"

install_theme(){
  local tree="$1"
  local theme="$tree/usr/share/plymouth/themes/mechos"
  mkdir -p "$theme" "$tree/etc/plymouth"
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
# The approved reference artwork is the visual authority. Preserve its aspect
# ratio and letterbox it instead of reconstructing the design with text/widgets.
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

# Keep boot prompts readable without changing the approved artwork during a
# normal boot. This text appears only when Plymouth explicitly sends a message.
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

# Reassert the approved theme on the installed target and rebuild initramfs so
# the first reboot after installation already shows the reference splash.
if [ -f "$POSTINSTALL" ] && ! grep -Fq 'MECHOS_REFERENCE_SPLASH_POSTINSTALL_V1' "$POSTINSTALL"; then
cat >> "$POSTINSTALL" <<'EOF'

# MECHOS_REFERENCE_SPLASH_POSTINSTALL_V1
mkdir -p /etc/plymouth
cat > /etc/plymouth/plymouthd.conf <<'PLYEOF'
[Daemon]
Theme=mechos
ShowDelay=0
DeviceTimeout=8
PLYEOF
if command -v plymouth-set-default-theme >/dev/null 2>&1; then
  plymouth-set-default-theme mechos >/dev/null 2>&1 || true
fi
if command -v mkinitcpio >/dev/null 2>&1; then
  mkinitcpio -P || echo '[MechOS Reference Splash] WARNING: initramfs refresh failed; theme files remain installed.' >&2
fi
EOF
  bash -n "$POSTINSTALL" || fail "post-install target syntax failed after splash integration"
fi

log 'Approved mechos-splash-reference.png is now the final Plymouth visual authority'
