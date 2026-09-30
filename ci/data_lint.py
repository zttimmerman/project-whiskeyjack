#!/usr/bin/env python3
"""Lint dialogue and quest data (stdlib only).

    python3 ci/data_lint.py [--baseline ci/data-lint-baseline.txt] [--update]

Structure (always fails; never baselined):
  dialogues (data/dialogues/*.json): a list of nodes with unique string ids, a `start` node (where
  DialogueRunner begins), every `next_id` (on a node or a choice) null or an existing id, no node
  unreachable from `start`, and `set_quest` naming a quest in data/quests/.
  quests (data/quests/*.json): `id` matching the file name, a title and description, and stages
  with unique ids, a description and a completion_condition.
Text limits from docs/world/00-tone.md ("Keep it short"), baselined:
  at most 2 sentences per dialogue node; quest objectives (stage descriptions) 12 words or fewer.
  Existing violations are listed in the baseline instead of rewriting content; new ones fail, and
  a fixed one must be deleted from the baseline.
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIALOGUES = ROOT / "data" / "dialogues"
QUESTS = ROOT / "data" / "quests"
MAX_SENTENCES = 2
MAX_OBJECTIVE_WORDS = 12
# A sentence ends at . ! ? (or a run such as ?! or ...) followed by a space, a closing quote or the end.
SENTENCE_END = re.compile(r"[.!?]+(?=[\"'’”)]*(\s|$))")


def rel(p):
    return str(Path(p).relative_to(ROOT))


def sentences(text):
    text = text.strip()
    if not text:
        return 0
    n = len(SENTENCE_END.findall(text))
    ends_with_stop = re.search(r"[.!?][\"'\u2019\u201d)]*$", text)
    return n + (0 if ends_with_stop else 1)  # trailing text without a stop is a sentence too


def load_json(path, errors):
    try:
        return json.loads(path.read_text())
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        errors.append(f"{rel(path)}: invalid JSON: {e}")
        return None


def lint_dialogue(path, quest_ids, errors, limits):
    data = load_json(path, errors)
    if data is None:
        return
    where = rel(path)
    if not isinstance(data, list):
        errors.append(f"{where}: must be a list of dialogue nodes")
        return
    nodes = {}
    for i, node in enumerate(data):
        if not isinstance(node, dict) or not isinstance(node.get("id"), str) or not node["id"]:
            errors.append(f"{where}: node #{i} needs a non-empty string 'id'")
            continue
        nid = node["id"]
        if nid in nodes:
            errors.append(f"{where}: duplicate id '{nid}'")
        nodes[nid] = node
        for key in ("speaker", "text"):
            if not isinstance(node.get(key), str) or not node[key].strip():
                errors.append(f"{where}: node '{nid}' needs a non-empty '{key}'")
        if "set_quest" in node and node["set_quest"] not in quest_ids:
            errors.append(f"{where}: node '{nid}' sets unknown quest '{node['set_quest']}'")
        choices = node.get("choices")
        if choices is not None and (not isinstance(choices, list) or not choices):
            errors.append(f"{where}: node '{nid}': 'choices' must be a non-empty list")
        for j, c in enumerate(choices if isinstance(choices, list) else []):
            if not isinstance(c, dict) or not isinstance(c.get("text"), str) or not c["text"].strip():
                errors.append(f"{where}: node '{nid}' choice #{j} needs a non-empty 'text'")
        if isinstance(node.get("text"), str) and sentences(node["text"]) > MAX_SENTENCES:
            limits.append(f"{where}: node '{nid}': {sentences(node['text'])} sentences (limit {MAX_SENTENCES})")

    def targets(node):
        out = [node.get("next_id")]
        for c in node.get("choices") or []:
            if isinstance(c, dict):
                out.append(c.get("next_id"))
        return [t for t in out if t is not None and t != ""]

    for nid, node in nodes.items():
        for t in targets(node):
            if not isinstance(t, str) or t not in nodes:
                errors.append(f"{where}: node '{nid}' points at missing next_id {t!r}")
    if "start" not in nodes:
        errors.append(f"{where}: no 'start' node (DialogueRunner.start() begins there)")
        return
    reached, todo = set(), ["start"]
    while todo:
        nid = todo.pop()
        if nid in reached or nid not in nodes:
            continue
        reached.add(nid)
        todo += [t for t in targets(nodes[nid]) if isinstance(t, str)]
    for nid in nodes:
        if nid not in reached:
            errors.append(f"{where}: node '{nid}' is unreachable from 'start'")


def lint_quest(path, errors, limits):
    data = load_json(path, errors)
    if data is None:
        return
    where = rel(path)
    if not isinstance(data, dict):
        errors.append(f"{where}: must be an object")
        return
    if data.get("id") != path.stem:
        errors.append(f"{where}: 'id' must be '{path.stem}' (the file name), got {data.get('id')!r}")
    for key in ("title", "description"):
        if not isinstance(data.get(key), str) or not data[key].strip():
            errors.append(f"{where}: needs a non-empty '{key}'")
    stages = data.get("stages")
    if not isinstance(stages, list) or not stages:
        errors.append(f"{where}: 'stages' must be a non-empty list")
        return
    seen = set()
    for i, st in enumerate(stages):
        if not isinstance(st, dict) or not isinstance(st.get("id"), str) or not st["id"]:
            errors.append(f"{where}: stage #{i} needs a non-empty string 'id'")
            continue
        sid = st["id"]
        if sid in seen:
            errors.append(f"{where}: duplicate stage id '{sid}'")
        seen.add(sid)
        for key in ("description", "completion_condition"):
            if not isinstance(st.get(key), str) or not st[key].strip():
                errors.append(f"{where}: stage '{sid}' needs a non-empty '{key}'")
        words = len(str(st.get("description", "")).split())
        if words > MAX_OBJECTIVE_WORDS:
            limits.append(f"{where}: stage '{sid}': objective is {words} words (limit {MAX_OBJECTIVE_WORDS})")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--baseline", type=Path, default=ROOT / "ci" / "data-lint-baseline.txt")
    ap.add_argument("--update", action="store_true", help="rewrite the baseline with today's text-limit violations")
    args = ap.parse_args()

    errors, limits = [], []
    quest_files = sorted(QUESTS.glob("*.json"))
    dialogue_files = sorted(DIALOGUES.glob("*.json"))
    for p in quest_files:
        lint_quest(p, errors, limits)
    for p in dialogue_files:
        lint_dialogue(p, {q.stem for q in quest_files}, errors, limits)
    print(f"data_lint: {len(dialogue_files)} dialogues, {len(quest_files)} quests")

    baseline = set()
    if args.baseline.exists():
        baseline = {l.strip() for l in args.baseline.read_text().splitlines() if l.strip() and not l.startswith("#")}
    if args.update:
        args.baseline.write_text("# Known text-limit violations (ci/data_lint.py) to fix; new ones fail CI,\n"
                                 "# and a fixed one must be deleted here.\n" + "".join(l + "\n" for l in sorted(limits)))
        print(f"data_lint: wrote {len(limits)} violations to {args.baseline}")
        baseline = set(limits)
    new, fixed = set(limits) - baseline, baseline - set(limits)

    for e in errors:
        print(f"::error::{e}")
    for v in sorted(new):
        print(f"::error::new text-limit violation: {v}")
    for v in sorted(fixed):
        print(f"::error::fixed violation still in {rel(args.baseline)} (delete this line): {v}")
    for v in sorted(set(limits) & baseline):
        print(f"data_lint: known (baselined): {v}")
    print(f"data_lint: {len(errors)} structure errors, {len(new)} new and {len(fixed)} fixed text-limit violations, "
          f"{len(set(limits) & baseline)} baselined")
    return 1 if errors or new or fixed else 0


if __name__ == "__main__":
    sys.exit(main())
