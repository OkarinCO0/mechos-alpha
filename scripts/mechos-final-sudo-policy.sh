#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log(){ printf '[MechOS Final Sudo Policy] %s\n' "$*"; }
fail(){ printf '[MechOS Final Sudo Policy] ERROR: %s\n' "$*" >&2; exit 1; }

[ -s "$ARCHIVE" ] || fail "installed-system payload missing"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xpf "$ARCHIVE" -C "$tmp"

mkdir -p "$tmp/etc/sudoers.d"
cat > "$tmp/etc/sudoers.d/10-mechos-wheel" <<'EOF'
# MechOS administrator policy. OOBE-created accounts are members of wheel.
%wheel ALL=(ALL:ALL) ALL
EOF
chmod 0440 "$tmp/etc/sudoers.d/10-mechos-wheel"

[ -f "$tmp/usr/local/libexec/mechos-oobe-apply" ] || fail "OOBE apply helper missing"
grep -Eq 'wheel' "$tmp/usr/local/libexec/mechos-oobe-apply" || fail "OOBE account is not granted wheel membership"
grep -Fqx '%wheel ALL=(ALL:ALL) ALL' "$tmp/etc/sudoers.d/10-mechos-wheel" || fail "wheel sudo policy invalid"

new="$ARCHIVE.sudo-policy"
tar --zstd -cpf "$new" -C "$tmp" .
mv -f "$new" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

log 'Installed MechOS wheel accounts now have normal password-authenticated sudo access'
