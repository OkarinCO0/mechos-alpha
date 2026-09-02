#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
INSTALLER="$ROOT/usr/local/bin/mechos-live-setup"

log() { printf '[MechOS Installer Path Hotfix] %s\n' "$*"; }
fail() { printf '[MechOS Installer Path Hotfix] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Installer Path Hotfix] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -f "$INSTALLER" ] || fail "graphical Live installer is missing: $INSTALLER"

python3 - "$INSTALLER" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# The partition/location integration uses pathlib.Path at runtime when reading
# /tmp/mechos-install-target.json. Python bytecode compilation does not catch an
# undefined global name, so explicitly make the generated GUI import Path.
if "Path(" in text and "from pathlib import Path\n" not in text:
    if "import sys\n" in text:
        text = text.replace("import sys\n", "import sys\nfrom pathlib import Path\n", 1)
    elif text.startswith("#!/usr/bin/env python3\n"):
        text = text.replace(
            "#!/usr/bin/env python3\n",
            "#!/usr/bin/env python3\nfrom pathlib import Path\n",
            1,
        )
    else:
        raise SystemExit("could not find a safe Python import insertion point")

path.write_text(text, encoding="utf-8")
PY

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$INSTALLER" \
  || fail "graphical Live installer Python validation failed"

grep -Fq 'from pathlib import Path' "$INSTALLER" \
  || fail "pathlib.Path import is still missing from graphical installer"
grep -Fq 'mechos-install-target.json' "$INSTALLER" \
  || fail "selected install target handling is missing from graphical installer"

log "graphical Live installer now imports pathlib.Path before reading the selected install target"
