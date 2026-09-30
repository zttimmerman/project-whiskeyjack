#!/usr/bin/env python3
"""Check Godot logs for errors and for warnings missing from the committed baseline.

    python3 ci/check_log.py --baseline ci/warnings-baseline.txt LOG [LOG ...]
    python3 ci/check_log.py --baseline ci/warnings-baseline.txt --update LOG [LOG ...]

Fails (exit 1) when a log has any `ERROR:` or `SCRIPT ERROR:` line, when a warning isn't in the
baseline (a new warning), or when a baseline entry no longer appears (a fixed warning: delete
its line so the baseline only shrinks). The baseline is the list of warnings to burn down.

Warnings are normalized so the baseline survives unrelated edits: ANSI colors and the
`debug> ` prompt are stripped, the checkout's absolute path becomes `<project>`, and line
numbers after `res://` paths are dropped. A GDScript warning (printed under `-d`) is keyed on its
message plus the script it's in, taken from the `at: GDScript::reload (res://...)` line after it.
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ANSI = re.compile(r"\x1b\[[0-9;]*m")
PROMPT = re.compile(r"^(debug> )+")
ERROR = re.compile(r"^(SCRIPT )?ERROR: ")
WARNING = re.compile(r"^WARNING: (.*)$")
GDSCRIPT_AT = re.compile(r"^\s*at: GDScript::reload \((res://[^)]+)\)")
RES_LINE = re.compile(r"(res://[^\s:()\"']+):\d+")


def clean(line):
    return PROMPT.sub("", ANSI.sub("", line.rstrip("\n")))


def normalize(text):
    text = text.replace(str(ROOT), "<project>")
    return RES_LINE.sub(r"\1", text)


def scan(path):
    """(errors, warnings) in one log: error lines as printed, warnings as a set of normalized keys."""
    lines = [clean(l) for l in Path(path).read_text(errors="replace").splitlines()]
    errors, warnings = [], set()
    for i, line in enumerate(lines):
        if ERROR.match(line):
            errors.append(line)
            continue
        m = WARNING.match(line)
        if not m:
            continue
        key = m.group(1)
        at = GDSCRIPT_AT.match(lines[i + 1]) if i + 1 < len(lines) else None
        if at:
            key += f" ({at.group(1)})"
        warnings.add(normalize(key))
    return errors, warnings


def read_baseline(path):
    if not path.exists():
        return set()
    return {l.strip() for l in path.read_text().splitlines() if l.strip() and not l.startswith("#")}


def write_baseline(path, warnings):
    header = ("# Known Godot warnings on main, to burn down (ci/check_log.py). New warnings fail CI;\n"
              "# a fixed warning must be deleted here. Regenerate with --update only to remove lines.\n")
    path.write_text(header + "".join(w + "\n" for w in sorted(warnings)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--baseline", type=Path, required=True)
    ap.add_argument("--update", action="store_true", help="rewrite the baseline from these logs (errors still fail)")
    ap.add_argument("logs", nargs="+")
    args = ap.parse_args()

    errors, seen = [], set()
    for log in args.logs:
        e, w = scan(log)
        errors += [f"{log}: {line}" for line in e]
        seen |= w
        print(f"check_log: {log}: {len(e)} errors, {len(w)} distinct warnings")

    baseline = read_baseline(args.baseline)
    if args.update:
        write_baseline(args.baseline, seen)
        print(f"check_log: wrote {len(seen)} warnings to {args.baseline}")
        new, fixed = set(), set()
    else:
        new, fixed = seen - baseline, baseline - seen

    for line in errors:
        print(f"::error::{line}")
    for w in sorted(new):
        print(f"::error::new warning (fix it; the baseline only shrinks): {w}")
    for w in sorted(fixed):
        print(f"::error::fixed warning still in {args.baseline} (delete this line): {w}")
    known = len(seen & baseline)
    print(f"check_log: {len(errors)} errors, {len(new)} new warnings, {len(fixed)} fixed warnings to remove, "
          f"{known} known warnings in the baseline")
    return 1 if errors or new or fixed else 0


if __name__ == "__main__":
    sys.exit(main())
