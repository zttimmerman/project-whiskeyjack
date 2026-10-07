#!/usr/bin/env python3
"""Lint dialogue and quest data (stdlib only).

    python3 ci/data_lint.py [--baseline ci/data-lint-baseline.txt] [--update]

Structure (always fails; never baselined):
  dialogues (data/dialogues/*.dialogue, Dialogue Manager scripts; syntax is checked by its own
  compiler at import and by ci/check_dialogue.gd): a `~ start` cue (where DialogueRunner begins),
  every jump (`=> cue`) to a cue in the file or END, every other cue jumped to from somewhere, every QuestManager call naming a quest in
  data/quests/ (and a stage of it, in `get_quest_stage("q") == "stage"`), and every flag a
  dialogue reads (`get_flag`/`has_flag`) set somewhere (`set_flag` in a dialogue or a script), and
  every `QuestManager.<name>` a func, var, const or signal of autoloads/QuestManager.gd (Dialogue
  Manager resolves it only at runtime, so a typo would otherwise ship).
  Legacy JSON dialogues (data/dialogues/*.json), if any come back: a list of nodes with unique
  string ids, a `start` node, every `next_id` null or an existing id, no node unreachable from
  `start`, and `set_quest` naming a quest in data/quests/.
  quests (data/quests/*.json): `id` matching the file name, a title and description, and stages
  with unique ids, a description and a completion_condition.
Text limits from docs/world/00-tone.md ("Keep it short"), baselined:
  at most 2 sentences per dialogue node (in a .dialogue file, per spoken line; choices are not
  counted); quest objectives (stage descriptions) 12 words or fewer.
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
QUEST_MANAGER = ROOT / "autoloads" / "QuestManager.gd"
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


# .dialogue lines that aren't spoken text (Dialogue Manager syntax)
DM_KEYWORD = re.compile(r"^(if|elif|else|while|match|when|using|import)\b")
DM_JUMP = re.compile(r"=><?\s*([\w/!]+)\s*$")
DM_TAG = re.compile(r"\[[^\]]*\]|\{\{.*?\}\}")  # BBCode, [if]/[#tag]/[ID:] markup and {{expressions}}
QUEST_CALL = re.compile(
    r"QuestManager\.(start_quest|advance_quest|complete_quest|is_quest_active|is_quest_complete|get_quest_stage)"
    r"\(\s*\"([^\"]*)\"\s*\)"
)
STAGE_CHECK = re.compile(r"get_quest_stage\(\s*\"([^\"]*)\"\s*\)\s*[!=]=\s*\"([^\"]*)\"")
FLAG_SET = re.compile(r"set_flag\(\s*\"([^\"]+)\"")
FLAG_READ = re.compile(r"(?:get_flag|has_flag)\(\s*\"([^\"]+)\"")
QUEST_MEMBER_USE = re.compile(r"\bQuestManager\.(\w+)")
GD_MEMBER = re.compile(r"^(?:static\s+)?(?:func|var|const|signal)\s+(\w+)", re.M)
_quest_manager_members = None


def quest_manager_members():
    """Names declared at the top level of the QuestManager autoload script."""
    global _quest_manager_members
    if _quest_manager_members is None:
        _quest_manager_members = set(GD_MEMBER.findall(QUEST_MANAGER.read_text()))
    return _quest_manager_members


def flags_set_in_scripts():
    """Flags set by GDScript outside addons/ and tests/ (game code may set a flag dialogue reads)."""
    found = set()
    for gd in ROOT.rglob("*.gd"):
        parts = gd.relative_to(ROOT).parts
        if parts[0] in ("addons", "tests", ".godot") or parts[0].startswith("."):
            continue
        found |= set(FLAG_SET.findall(gd.read_text(errors="replace")))
    return found


def lint_dialogue_script(path, quests, flags_set, errors, limits):
    """A Dialogue Manager .dialogue file. `quests` maps quest id -> its stage ids."""
    where = rel(path)
    lines = path.read_text().splitlines()
    cues, jumps, cue = set(), [], None
    for n, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        for name in QUEST_MEMBER_USE.findall(line):
            if name not in quest_manager_members():
                errors.append(f"{where}:{n}: QuestManager has no '{name}' (not in {rel(QUEST_MANAGER)})")
        for q in QUEST_CALL.findall(line):
            if q[1] not in quests:
                errors.append(f"{where}:{n}: QuestManager.{q[0]} names unknown quest '{q[1]}'")
        for q, stage in STAGE_CHECK.findall(line):
            if q in quests and stage not in quests[q]:
                errors.append(f"{where}:{n}: quest '{q}' has no stage '{stage}'")
        for flag in FLAG_READ.findall(line):
            if flag not in flags_set:
                errors.append(f"{where}:{n}: flag '{flag}' is read but never set (set_flag) anywhere")
        if line.startswith("~ "):
            cue = line[2:].strip()
            cues.add(cue)
            continue
        jump = DM_JUMP.search(line)
        if jump:
            jumps.append((n, jump.group(1)))
        if line.startswith(("=>", "$>", "- ", "do ", "do! ", "set ")) or DM_KEYWORD.match(line):
            continue
        # Spoken text: optional random weight (%2) or concurrent marker (|), optional "Character: "
        text = re.sub(r"^(%[\d.]*\s*|\|\s*)", "", line)
        speaker, sep, said = text.partition(": ")
        if not sep or "[" in speaker or "{" in speaker:
            speaker, said = "", text
        said = DM_TAG.sub("", said).strip()
        count = sentences(said)
        if count > MAX_SENTENCES:
            opening = " ".join(said.split()[:6])
            who = f"{speaker} " if speaker else ""
            limits.append(
                f"{where}: cue '{cue}': {who}\"{opening}...\": {count} sentences (limit {MAX_SENTENCES})"
            )
    if "start" not in cues:
        errors.append(f"{where}: no '~ start' cue (DialogueRunner.start() begins there)")
    for n, target in jumps:
        if target not in cues and target not in ("END", "END!") and "/" not in target:
            errors.append(f"{where}:{n}: jump to unknown cue '{target}'")
    for c in sorted(cues - {"start"} - {t for _, t in jumps}):
        errors.append(f"{where}: cue '{c}' is never jumped to (unreachable from 'start')")


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
    script_files = sorted(DIALOGUES.glob("*.dialogue"))
    for p in quest_files:
        lint_quest(p, errors, limits)
    for p in dialogue_files:
        lint_dialogue(p, {q.stem for q in quest_files}, errors, limits)
    quests = {}
    for q in quest_files:
        try:
            quests[q.stem] = {st.get("id") for st in json.loads(q.read_text()).get("stages", []) if isinstance(st, dict)}
        except (json.JSONDecodeError, AttributeError):
            quests[q.stem] = set()  # lint_quest already reported it
    flags_set = flags_set_in_scripts()
    for p in script_files:
        flags_set |= set(FLAG_SET.findall(p.read_text()))
    for p in script_files:
        lint_dialogue_script(p, quests, flags_set, errors, limits)
    print(f"data_lint: {len(script_files)} .dialogue files, {len(dialogue_files)} JSON dialogues, "
          f"{len(quest_files)} quests")

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
