#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(f"[MechOS Discord wrapper hotfix] ERROR: {message}")


def main() -> None:
    target = Path(
        sys.argv[1]
        if len(sys.argv) > 1
        else "scripts/mechos-discord-screenshare-integration.sh"
    )
    if not target.is_file():
        fail(f"Discord integration not found: {target}")

    text = target.read_text(encoding="utf-8")
    marker = "# MECHOS_DISCORD_CREATOR_WRAPPER_HOTFIX_V1"
    if marker in text:
        print(f"[MechOS Discord wrapper hotfix] already applied to {target}")
        return

    old_target = '''  local target="$tree/usr/local/bin/mechos-creator-mode"\n  [ -f "$target" ] || return 0\n'''
    new_target = '''  local target=""\n  # Tutorial integration wraps Creator Mode in Bash and keeps the real PyQt\n  # application as mechos-creator-mode.real. Patch the Python implementation,\n  # never the public Bash wrapper.\n  for candidate in "$tree/usr/local/bin/mechos-creator-mode.real" "$tree/usr/local/bin/mechos-creator-mode"; do\n    [ -f "$candidate" ] || continue\n    if head -n1 "$candidate" | grep -Eq '^#!.*python'; then\n      target="$candidate"\n      break\n    fi\n  done\n  [ -n "$target" ] || return 0\n'''
    if old_target not in text:
        fail("Creator Mode target block was not found; refusing a blind patch")
    text = text.replace(old_target, new_target, 1)

    old_marker = '''text = marker + "\\n" + text\npath.write_text(text, encoding="utf-8")\n'''
    new_marker = '''lines = text.splitlines(True)\ninsert_at = 1 if lines and lines[0].startswith("#!") else 0\nlines.insert(insert_at, marker + "\\n")\npath.write_text("".join(lines), encoding="utf-8")\n'''
    if old_marker not in text:
        fail("Creator Mode marker insertion block was not found")
    text = text.replace(old_marker, new_marker, 1)

    old_compile = '''  python3 -m py_compile "$target" || fail "Creator Mode syntax failed after Discord integration"\n'''
    new_compile = '''  python3 -m py_compile "$target" || fail "Creator Mode syntax failed after Discord integration: $target"\n'''
    if old_compile not in text:
        fail("Creator Mode compile validation block was not found")
    text = text.replace(old_compile, new_compile, 1)

    # Leave an explicit source marker so repeated build patching is safe and
    # future regressions are obvious in build logs/source inspection.
    anchor = 'patch_creator_mode() {\n'
    if anchor not in text:
        fail("Creator Mode patch function is missing")
    text = text.replace(anchor, anchor + f"  {marker}\n", 1)

    target.write_text(text, encoding="utf-8")
    print(
        "[MechOS Discord wrapper hotfix] Creator Mode Discord integration now "
        f"targets the real Python app: {target}"
    )


if __name__ == "__main__":
    main()
