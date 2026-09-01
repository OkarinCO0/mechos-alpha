#!/usr/bin/env python3
from pathlib import Path
import re
import sys

MARKER = "# MECHOS_PARTITION_SCREEN_INTEGRATION"
CALL = f"""{MARKER}
# Add a dedicated read-only disk/partition selection screen to the Live
# graphical installer while keeping Archinstall's destructive confirmation.
bash /workspace/scripts/mechos-partition-screen-integration.sh final
# Apply the responsive spacing/scroll layout after the partition step has
# finished modifying the graphical installer so the final UI cannot be squashed.
bash /workspace/scripts/mechos-installer-layout-hotfix.sh final
"""


def fail(message: str) -> None:
    raise SystemExit(f"[MechOS partition patcher] ERROR: {message}")


def main() -> None:
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "scripts/build-mechos-archiso.sh")
    if not target.is_file():
        fail(f"builder not found: {target}")

    text = target.read_text(encoding="utf-8")

    # Idempotency: remove any previously injected block before reinserting it.
    text = re.sub(
        r"\n# MECHOS_PARTITION_SCREEN_INTEGRATION\n"
        r"# Add a dedicated read-only disk/partition selection screen[^\n]*\n"
        r"# graphical installer while keeping Archinstall's destructive confirmation\.\n"
        r"bash /workspace/scripts/mechos-partition-screen-integration\.sh final\n"
        r"(?:# Apply the responsive spacing/scroll layout after the partition step has\n"
        r"# finished modifying the graphical installer so the final UI cannot be squashed\.\n"
        r"bash /workspace/scripts/mechos-installer-layout-hotfix\.sh final\n)?",
        "\n",
        text,
    )

    anchor = "bash /workspace/scripts/mechos-alongside-integration.sh final\n"
    if anchor not in text:
        fail("could not locate Install Alongside integration anchor")

    text = text.replace(anchor, anchor + CALL, 1)
    target.write_text(text, encoding="utf-8")

    if text.count(MARKER) != 1:
        fail("partition screen integration marker is not unique")
    if text.count("bash /workspace/scripts/mechos-installer-layout-hotfix.sh final") != 1:
        fail("installer layout hotfix call is not unique")

    print(f"[MechOS partition patcher] partition screen and responsive installer layout wired into {target}")


if __name__ == "__main__":
    main()
