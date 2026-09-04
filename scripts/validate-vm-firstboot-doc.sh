#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT/docs/VM-FIRSTBOOT-RUNTIME.md"
[ -f "$DOC" ] || { echo '[validate-vm-firstboot-doc] ERROR: documentation missing' >&2; exit 1; }
grep -Fq 'mechos-firstboot-authority.service' "$DOC"
grep -Fq 'mechos-oobe-start' "$DOC"
grep -Fq 'mechos-vm-mode-runtime' "$DOC"
echo '[validate-vm-firstboot-doc] OK'
