#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INTEGRATION="$ROOT/scripts/mechos-source-owned-system-ui.sh"
FALLBACK="$ROOT/scripts/mechos-live-installer-crash-fallback.sh"
fail(){ echo "[validate-live-installer-owner] ERROR: $*" >&2; exit 1; }

bash -n "$INTEGRATION" || fail "source UI integration shell syntax failed"
bash -n "$FALLBACK" || fail "installer fallback shell syntax failed"
grep -Fq 'local libexec_v5="$tree/usr/local/libexec/${name}-v5.py"' "$INTEGRATION" || fail "libexec v5 owner path is not searched"
grep -Fq 'grep -Fq "class $cls(" "$libexec_v5"' "$INTEGRATION" || fail "libexec v5 class owner check missing"
grep -Fq 'REAL="$ROOT/usr/local/libexec/mechos-live-setup-v5.py"' "$FALLBACK" || fail "installer fallback real path no longer matches resolver convention"
grep -Fq 'p="$(owner_file "$ROOT" mechos-live-setup Installer)"' "$INTEGRATION" || fail "Live Installer final patch lookup missing"

echo '[validate-live-installer-owner] OK: guarded Live Installer Python owner is resolvable after crash-wrapper integration'
