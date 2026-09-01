#!/usr/bin/env python3
from pathlib import Path
import sys

MARKER = "# MECHOS_RGB_QUICK_ACTIONS_INTEGRATION"
BLOCK = f'''\n{MARKER}\n# Add OpenRGB-backed keyboard lighting controls to MechScope Quick Actions\n# after the other UI/post-install integrations have finished.\nbash /workspace/scripts/mechos-rgb-quick-actions-integration.sh final\n'''


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: patch-mechos-rgb-quick-actions.py <build-mechos-archiso.sh>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    text = path.read_text()

    # Idempotently remove the exact block if this patcher has already run.
    text = text.replace(BLOCK, "\n")

    lines = text.splitlines(keepends=True)
    mk_indexes = [
        i for i, line in enumerate(lines)
        if line.lstrip().startswith("mkarchiso ") and not line.lstrip().startswith("#")
    ]
    if not mk_indexes:
        raise SystemExit("Could not find final mkarchiso command")

    index = mk_indexes[-1]
    lines.insert(index, BLOCK)
    patched = "".join(lines)

    if patched.count(MARKER) != 1:
        raise SystemExit("RGB Quick Actions integration marker count is not exactly one")

    path.write_text(patched)
    print(f"Wired MechScope RGB Quick Actions into {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
