#!/usr/bin/env python3
from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

MARKER_EARLY = "# MECHOS_V0_2_2_REPAIR_EARLY"
MARKER_LATE = "# MECHOS_V0_2_2_REPAIR_LATE"
CALL_EARLY = f'''\n{MARKER_EARLY}\n# Apply the v0.2.2 runtime repair after the legacy live-welcome block is written.\nbash /workspace/scripts/mechos-v0.2.2-runtime-repair.sh early\n\n'''
CALL_LATE = f'''\n{MARKER_LATE}\n# Re-apply at the end so later legacy blocks cannot overwrite the repaired files.\nbash /workspace/scripts/mechos-v0.2.2-runtime-repair.sh final\n\n'''


def fail(message: str) -> None:
    raise SystemExit(f"[MechOS patcher] ERROR: {message}")


def main() -> None:
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "scripts/build-mechos-archiso.sh")
    if not target.is_file():
        fail(f"builder not found: {target}")

    text = target.read_text(encoding="utf-8")
    if not text.startswith("#!"):
        fail("target does not look like a shell builder")

    backup = target.with_suffix(target.suffix + ".pre-v0.2.2.bak")
    if not backup.exists():
        shutil.copy2(target, backup)

    changed = False

    # Insert an early repair immediately before the existing installer block.
    if MARKER_EARLY not in text:
        installer_patterns = [
            r'(?m)^cat > /workspace/archlive/airootfs/usr/local/bin/mechos-install << ["\']?EOF["\']?\s*$',
            r'(?m)^cat > .*?/usr/local/bin/mechos-install << ["\']?EOF["\']?\s*$',
        ]
        match = None
        for pattern in installer_patterns:
            match = re.search(pattern, text)
            if match:
                break
        if not match:
            fail("could not locate the mechos-install heredoc; refusing a blind patch")
        text = text[:match.start()] + CALL_EARLY + text[match.start():]
        changed = True

    # Insert a final repair immediately before the last real mkarchiso command.
    if MARKER_LATE not in text:
        mk_matches = list(re.finditer(r'(?m)^(?!\s*#).*\bmkarchiso\b.*$', text))
        if not mk_matches:
            fail("could not locate mkarchiso; refusing a blind patch")
        match = mk_matches[-1]
        text = text[:match.start()] + CALL_LATE + text[match.start():]
        changed = True

    if changed:
        target.write_text(text, encoding="utf-8")
        print(f"[MechOS patcher] patched {target}")
    else:
        print(f"[MechOS patcher] {target} is already patched")


if __name__ == "__main__":
    main()
