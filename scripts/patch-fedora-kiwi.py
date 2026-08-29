#!/usr/bin/env python3
from pathlib import Path
import sys

repo = Path(sys.argv[1]).resolve()
fedora = repo / "Fedora.kiwi"
if not fedora.exists():
    raise SystemExit(f"Fedora.kiwi not found in {repo}")

# Copy MechOS component.
src_component = Path(sys.argv[2]).resolve()
component_dir = repo / "components"
component_dir.mkdir(parents=True, exist_ok=True)
(component_dir / "mechos.xml").write_bytes(src_component.read_bytes())

text = fedora.read_text()
include = '<include from="this://./components/mechos.xml"/>'
if include not in text:
    marker = '<packages type="bootstrap">'
    if marker not in text:
        raise SystemExit("Could not find bootstrap package marker in Fedora.kiwi")
    text = text.replace(marker, include + "\n\n" + marker, 1)
    fedora.write_text(text)
print("Patched Fedora.kiwi with MechOS component")
