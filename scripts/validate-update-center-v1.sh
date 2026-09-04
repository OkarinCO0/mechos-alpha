#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INTEGRATION="$ROOT/scripts/mechos-update-center-v1-integration.sh"
GUARD="$ROOT/scripts/mechos-update-center-v1-runtime-guard.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"
SOURCE_UI="$ROOT/src/mechos_ui/update_shell.py"
SOURCE_OWNER="$ROOT/scripts/mechos-source-owned-system-ui.sh"
MANIFEST="$ROOT/updates/stable.json"
RELEASE="$ROOT/overlay/rootfs/etc/mechos/release"

fail(){ echo "[validate-update-center-v1] ERROR: $*" >&2; exit 1; }

for f in "$INTEGRATION" "$GUARD" "$PATCHER" "$SOURCE_UI" "$SOURCE_OWNER" "$MANIFEST" "$RELEASE"; do
  [ -f "$f" ] || fail "missing $f"
done

bash -n "$INTEGRATION" || fail "Update Center v1 integration syntax failed"
bash -n "$GUARD" || fail "Update Center v1 runtime guard syntax failed"
python3 -m py_compile "$PATCHER" "$SOURCE_UI" || fail "Update Center v1 Python source syntax failed"

python3 - "$MANIFEST" "$RELEASE" <<'PY'
import json,re,subprocess,sys
from urllib.parse import urlparse
manifest,release=sys.argv[1:]
with open(manifest,encoding='utf-8') as f: data=json.load(f)
if data.get('schema') != 1: raise SystemExit('[validate-update-center-v1] manifest schema must be 1')
if data.get('channel') != 'stable': raise SystemExit('[validate-update-center-v1] manifest channel must be stable')
version=str(data.get('version','')).strip()
if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){2}(?:[-.][A-Za-z0-9]+)*',version):
    raise SystemExit('[validate-update-center-v1] invalid stable manifest version')
current=open(release,encoding='utf-8').read().strip()
if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){2}(?:[-.][A-Za-z0-9]+)*',current):
    raise SystemExit('[validate-update-center-v1] invalid ISO release version')
ordered=subprocess.check_output(['sort','-V'],input=f'{current}\n{version}\n',text=True).splitlines()
if ordered[-1] != version:
    raise SystemExit(f'[validate-update-center-v1] stable manifest {version} must not be older than ISO release {current}')
url=str(data.get('bundle_url','')).strip(); sha=str(data.get('bundle_sha256','')).strip()
if bool(url) != bool(sha): raise SystemExit('[validate-update-center-v1] bundle URL/SHA must be published together')
if version != current and (not url or not sha):
    raise SystemExit('[validate-update-center-v1] a newer stable version must publish its HTTPS bundle and SHA together')
if url:
    u=urlparse(url)
    if u.scheme != 'https' or not u.netloc: raise SystemExit('[validate-update-center-v1] bundle URL must be HTTPS')
    if not re.fullmatch(r'[0-9a-fA-F]{64}',sha): raise SystemExit('[validate-update-center-v1] bundle SHA must be SHA-256')
PY

grep -Fq 'MANIFEST_URL=https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/stable.json' "$INTEGRATION" || fail "stable manifest URL missing"
grep -Fq 'CURRENT_MECHOS_VERSION=' "$INTEGRATION" || fail "current version reporting missing"
grep -Fq 'LATEST_MECHOS_VERSION=' "$INTEGRATION" || fail "latest version reporting missing"
grep -Fq 'MECHOS_UPDATE_AVAILABLE=' "$INTEGRATION" || fail "MechOS update availability reporting missing"
grep -Fq "curl --fail --show-error --location --proto '=https'" "$INTEGRATION" || fail "HTTPS bundle download enforcement missing"
grep -Fq 'checksum mismatch' "$INTEGRATION" || fail "bundle checksum guard missing"
grep -Fq 'validate_bundle_archive' "$INTEGRATION" || fail "bundle path validation missing"
grep -Fq 'path outside MechOS update allowlist' "$INTEGRATION" || fail "bundle path allowlist missing"
grep -Fq 'create_snapshot_if_possible' "$INTEGRATION" || fail "pre-update snapshot support missing"
grep -Fq 'rollback-pending' "$INTEGRATION" || fail "rollback marker support missing"
grep -Fq 'flatpak update --system -y' "$INTEGRATION" || fail "system Flatpak update missing"
grep -Fq 'flatpak update --user -y' "$INTEGRATION" || fail "user Flatpak update missing"
grep -Fq 'Updates are disabled in the MechOS live ISO' "$INTEGRATION" || fail "Live ISO update block missing"
grep -Fq 'MECHOS_UPDATE_CENTER_V1_BACKEND' "$INTEGRATION" || fail "Update Center backend overlay missing"
grep -Fq "'version_label'" "$SOURCE_OWNER" || fail "source-owned Update Center version binding missing"
grep -Fq 'self.version_label=' "$SOURCE_UI" || fail "Update Center version display missing"
grep -Fq 'HTTPS + SHA-256 verification' "$SOURCE_UI" || fail "verified bundle safety copy missing from UI"

grep -Fq 'MECHOS_UPDATE_CENTER_V1_RC_GUARD' "$GUARD" || fail "runtime failure-code guard missing"
grep -Fq 'cp -a "$stage/." /' "$GUARD" || fail "dependency-free bundle copy guard missing"
grep -Fq '! grep -Fq '\''if ! pacman -Syu' "$GUARD" || fail "unsafe pacman status regression check missing"
grep -Fq '! grep -Fq '\''if ! apply_mechos_bundle' "$GUARD" || fail "unsafe bundle status regression check missing"

python3 - "$PATCHER" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
items=[
 'mechos-source-owned-system-ui.sh',
 'mechos-update-center-v1-integration.sh',
 'mechos-update-center-v1-runtime-guard.sh',
 'mechos-installed-mechscope-launch-hotfix.sh',
 'mechos-reference-splash-integration.sh',
 'mechos-finalize-install-payload.sh final',
]
pos=[text.find(x) for x in items]
if any(p < 0 for p in pos): raise SystemExit('[validate-update-center-v1] final update build stages incomplete')
if pos != sorted(pos): raise SystemExit('[validate-update-center-v1] Update Center v1 is in the wrong final build order')
PY

echo '[validate-update-center-v1] OK: stable MechOS channel, verified bundles, Arch/Flatpak updates, snapshots, rollback markers, version UI and final build authority are enforced'
