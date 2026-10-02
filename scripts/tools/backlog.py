#!/usr/bin/env python3
"""The project backlog: one Markdown file per item in docs/backlog/, YAML front-matter on top.

    python3 scripts/tools/backlog.py next          # ready items whose `after` are all done or in-review
    python3 scripts/tools/backlog.py status        # counts, then a table per status
    python3 scripts/tools/backlog.py show <id>     # one item, front-matter and body
    python3 scripts/tools/backlog.py lint          # schema check (CI's data-lint job runs this)

Every command takes --json. Schema and workflow: docs/backlog/README.md. Stdlib only; the front-matter
is a small YAML subset (scalars, quoted strings, null, integers and inline [a, b] lists).
"""
import argparse
import datetime
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_DIR = os.path.join(ROOT, "docs", "backlog")
DEFAULT_BIBLE = os.path.join(ROOT, "docs", "design-bible.md")

# Display order for `status`; `next` reads only ready ones.
STATUSES = ["in-progress", "in-review", "needs-user", "ready", "proposed", "done", "dropped"]
KINDS = ["feature", "fix", "chore", "spike", "asset", "docs", "decision"]
# Phases in the order work happens; `next` sorts by this, then by id.
PHASES = ["A", "gameplay-1", "B", "gameplay-2", "C", "later"]
KEYS = ["id", "title", "status", "kind", "targets", "after", "phase", "branch", "pr", "updated"]
LIST_KEYS = ("targets", "after")
SATISFIES_AFTER = ("done", "in-review")
NO_PR_KINDS = ("decision", "docs")
SECTIONS = {
    "work": ["Goal", "Scope", "Acceptance", "Serves"],
    "finished": ["Goal", "Outcome"],
    "needs-user": ["Question", "Options", "Recommendation"],
}
ID_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
TARGET_ROW_RE = re.compile(r"^\|\s*`([a-z][a-z0-9_]*)`\s*\|")
INT_RE = re.compile(r"^-?\d+$")


def _scalar(text):
    text = text.strip()
    if text in ("", "null", "~"):
        return None
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'":
        inner = text[1:-1]
        return inner.replace('\\"', '"') if text[0] == '"' else inner.replace("''", "'")
    if INT_RE.match(text):
        return int(text)
    return text


def parse_front_matter(text):
    """Returns (meta, body). Raises ValueError on a missing block or a line it can't read."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        raise ValueError("no front-matter (the file must start with ---)")
    meta = {}
    for n, line in enumerate(lines[1:], start=2):
        if line.strip() == "---":
            return meta, "\n".join(lines[n:])
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, sep, value = line.partition(":")
        if not sep or not re.match(r"^[a-z_]+$", key):
            raise ValueError(f"line {n}: expected 'key: value', got {line!r}")
        value = value.strip()
        if value.startswith("["):
            if not value.endswith("]"):
                raise ValueError(f"line {n}: lists are inline, [a, b]")
            inner = value[1:-1].strip()
            meta[key] = [_scalar(v) for v in inner.split(",")] if inner else []
        else:
            meta[key] = _scalar(value)
    raise ValueError("front-matter is not closed with ---")


def load_items(directory):
    """Returns (items, errors). README.md is the schema, not an item."""
    items, errors = [], []
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".md") or name == "README.md":
            continue
        path = os.path.join(directory, name)
        with open(path, encoding="utf-8") as f:
            text = f.read()
        try:
            meta, body = parse_front_matter(text)
        except ValueError as e:
            errors.append(f"{name}: {e}")
            continue
        meta["body"] = body
        meta["file"] = name
        items.append(meta)
    return items, errors


def bible_targets(path):
    """Target IDs from the design bible's §9 table: the backticked first cell of each row."""
    with open(path, encoding="utf-8") as f:
        return {m.group(1) for line in f if (m := TARGET_ROW_RE.match(line))}


def _sections_for(status):
    if status == "needs-user":
        return SECTIONS["needs-user"]
    if status in ("done", "dropped"):
        return SECTIONS["finished"]
    return SECTIONS["work"]


def _find_cycles(items):
    graph = {i.get("id"): [a for a in (i.get("after") or []) if isinstance(a, str)] for i in items}
    errors, state = [], {}

    def visit(node, stack):
        state[node] = "open"
        stack.append(node)
        for nxt in graph.get(node, []):
            if nxt not in graph:
                continue
            if state.get(nxt) == "open":
                errors.append("after cycle: " + " -> ".join(stack[stack.index(nxt):] + [nxt]))
            elif nxt not in state:
                visit(nxt, stack)
        stack.pop()
        state[node] = "closed"

    for node in sorted(k for k in graph if isinstance(k, str)):
        if node not in state:
            visit(node, [])
    return errors


def lint(items, targets):
    errors = []
    by_id = {}
    for item in items:
        name = item["file"]
        item_id = item.get("id")
        label = item_id if isinstance(item_id, str) else name
        for key in KEYS:
            if key not in item:
                errors.append(f"{label}: missing key '{key}'")
        for key in item:
            if key not in KEYS and key not in ("body", "file"):
                errors.append(f"{label}: unknown key '{key}'")
        if not isinstance(item_id, str) or not ID_RE.match(item_id):
            errors.append(f"{name}: id {item_id!r} is not kebab-case")
        elif item_id + ".md" != name:
            errors.append(f"{label}: id does not match the file name {name}")
        if isinstance(item_id, str):
            if item_id in by_id:
                errors.append(f"{label}: duplicate id (also {by_id[item_id]['file']})")
            by_id[item_id] = item
        if not isinstance(item.get("title"), str) or not item.get("title"):
            errors.append(f"{label}: title must be a non-empty string")
        status, kind, phase = item.get("status"), item.get("kind"), item.get("phase")
        if status not in STATUSES:
            errors.append(f"{label}: unknown status {status!r}; one of {', '.join(STATUSES)}")
        if kind not in KINDS:
            errors.append(f"{label}: unknown kind {kind!r}; one of {', '.join(KINDS)}")
        if phase not in PHASES:
            errors.append(f"{label}: unknown phase {phase!r}; one of {', '.join(PHASES)}")
        for key in LIST_KEYS:
            if key in item and not (isinstance(item[key], list) and all(isinstance(v, str) for v in item[key])):
                errors.append(f"{label}: {key} must be an inline list of names, e.g. [a, b]")
        for target in item.get("targets") or []:
            if isinstance(target, str) and target not in targets:
                errors.append(f"{label}: unknown design-bible target {target!r}")
        branch, pr = item.get("branch"), item.get("pr")
        if branch is not None and not isinstance(branch, str):
            errors.append(f"{label}: branch must be a name or null")
        if pr is not None and (not isinstance(pr, int) or pr <= 0):
            errors.append(f"{label}: pr must be a PR number or null, not {pr!r}")
        if status in ("done", "in-review") and pr is None and kind not in NO_PR_KINDS:
            errors.append(f"{label}: status {status} needs a pr (only {'/'.join(NO_PR_KINDS)} items may omit it)")
        updated = item.get("updated")
        try:
            datetime.date.fromisoformat(str(updated))
        except ValueError:
            errors.append(f"{label}: updated must be a YYYY-MM-DD date, not {updated!r}")
        if status in STATUSES:
            for section in _sections_for(status):
                if not re.search(rf"^## {re.escape(section)}\s*$", item["body"], re.M):
                    errors.append(f"{label}: body lacks '## {section}' (status {status})")
    for item in items:
        label = item.get("id") or item["file"]
        for dep in item.get("after") or []:
            if not isinstance(dep, str):
                continue
            if dep not in by_id:
                errors.append(f"{label}: after names a missing item {dep!r}")
            elif by_id[dep].get("status") == "dropped" and item.get("status") not in ("done", "dropped"):
                errors.append(f"{label}: after names {dep!r}, which is dropped (it can never unblock)")
    errors += _find_cycles(items)
    return errors


def _phase_key(item):
    phase = item.get("phase")
    return (PHASES.index(phase) if phase in PHASES else len(PHASES), item.get("id") or "")


def next_items(items):
    status = {i.get("id"): i.get("status") for i in items}
    ready = [
        i
        for i in items
        if i.get("status") == "ready" and all(status.get(a) in SATISFIES_AFTER for a in i.get("after") or [])
    ]
    return sorted(ready, key=_phase_key)


def _public(item, body=False):
    out = {k: item.get(k) for k in KEYS}
    if body:
        out["body"] = item["body"]
    return out


def _cell(text):
    return str(text).replace("|", "\\|")


def _table(items):
    rows = ["| id | kind | phase | title | pr |", "|---|---|---|---|---|"]
    for i in items:
        pr = f"#{i['pr']}" if i.get("pr") else ""
        rows.append(f"| {i.get('id')} | {i.get('kind')} | {i.get('phase')} | {_cell(i.get('title'))} | {pr} |")
    return "\n".join(rows)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--dir", default=DEFAULT_DIR, help="backlog directory (default docs/backlog)")
    parser.add_argument("--bible", default=DEFAULT_BIBLE, help="design bible with the §9 target table")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("next", "status", "lint"):
        sub.add_parser(name).add_argument("--json", action="store_true")
    show = sub.add_parser("show")
    show.add_argument("id")
    show.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    items, load_errors = load_items(args.dir)

    if args.command == "lint":
        errors = load_errors + lint(items, bible_targets(args.bible))
        if args.json:
            print(json.dumps({"items": len(items), "errors": errors}, indent=2))
        else:
            for e in errors:
                print(f"backlog: {e}")
            print(f"backlog lint: {len(items)} items, {len(errors)} error(s)")
        return 1 if errors else 0

    for e in load_errors:
        print(f"backlog: skipped {e}", file=sys.stderr)

    if args.command == "next":
        ready = next_items(items)
        if args.json:
            print(json.dumps([_public(i) for i in ready], indent=2))
        else:
            for i in ready:
                print(f"{i['id']}  [{i['phase']}, {i['kind']}]  {i['title']}")
            if not ready:
                print("nothing is ready: see `status` for proposed and needs-user items")
        return 0

    if args.command == "status":
        grouped = {s: sorted((i for i in items if i.get("status") == s), key=_phase_key) for s in STATUSES}
        if args.json:
            print(json.dumps({
                "counts": {s: len(v) for s, v in grouped.items()},
                "items": {s: [_public(i) for i in v] for s, v in grouped.items()},
            }, indent=2))
        else:
            print(" · ".join(f"{s} {len(v)}" for s, v in grouped.items()) + f" · total {len(items)}")
            for s, v in grouped.items():
                if v:
                    print(f"\n### {s} ({len(v)})\n\n{_table(v)}")
        return 0

    # show
    match = [i for i in items if i.get("id") == args.id]
    if not match:
        print(f"backlog: no item {args.id!r}", file=sys.stderr)
        return 1
    item = match[0]
    if args.json:
        print(json.dumps(_public(item, body=True), indent=2))
    else:
        print(f"{item['id']}: {item.get('title')}")
        for k in KEYS[2:]:
            print(f"  {k}: {item.get(k)}")
        print(item["body"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
