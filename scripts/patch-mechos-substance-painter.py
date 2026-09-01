#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

MARKER = "# MECHOS_SUBSTANCE_PAINTER_INTEGRATION"
CALL = f"""{MARKER}
# Add Adobe Substance 3D Painter's Steam Linux storefront entry to Creator
# Mode after all other Creator/UI integrations have finished.
bash /workspace/scripts/mechos-substance-painter-integration.sh final

"""


def fail(message: str) -> None:
    raise SystemExit(f"[MechOS Substance Painter patcher] ERROR: {message}")


def main() -> None:
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "scripts/build-mechos-archiso.sh")
    if not target.is_file():
        fail(f"builder not found: {target}")

    text = target.read_text(encoding="utf-8")
    if not text.startswith("#!"):
        fail("target does not look like a shell builder")

    text = re.sub(
        rf"\n{re.escape(MARKER)}\n"
        r"# Add Adobe Substance 3D Painter's Steam Linux storefront entry to Creator\n"
        r"# Mode after all other Creator/UI integrations have finished\.\n"
        r"bash /workspace/scripts/mechos-substance-painter-integration\.sh final\n\n",
        "\n",
        text,
    )

    mk_matches = list(re.finditer(r"(?m)^(?!\s*#).*\bmkarchiso\b.*$", text))
    if not mk_matches:
        fail("could not locate mkarchiso; refusing a blind patch")

    match = mk_matches[-1]
    text = text[: match.start()] + CALL + text[match.start() :]
    target.write_text(text, encoding="utf-8")

    if text.count(MARKER) != 1:
        fail("Substance Painter integration marker count is not exactly one")

    print(f"[MechOS Substance Painter patcher] Creator Mode store integration added to {target}")


if __name__ == "__main__":
    main()
