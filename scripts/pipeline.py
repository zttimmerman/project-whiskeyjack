#!/usr/bin/env python3
"""Asset pipeline orchestrator.

    python3 scripts/pipeline.py <asset-id> --stage <concept|model|clean|validate|all> [--dry-run] [--force]

Stages:
  concept   Resolve the generation prompt from the brief; ingest a concept image if one was generated.
  model     Ingest the base mesh: the brief's source_glb, or the newest Tripo download on disk.
  clean     Blender (headless): scale, pivot, facing, albedo-only, texture size, vertex budget, export GLB.
  validate  Godot (headless): bone names, SkeletonProfileHumanoid mapping, vertex count, textures.

This script never runs a paid Tripo command. When concept or model output is missing, it
prints the exact `tripo` command; the agent runs that command through the tripo skill
(.claude/skills/tripo/), which owns spend gating. Re-running the stage then ingests the
downloaded files. Resuming is file-based: stages compare SHA-256 hashes of their inputs
and outputs on disk, never a stored task_id.

Exit codes: 0 ok or up to date, 1 error, 2 stage check failed, 3 waiting on a Tripo run.
"""

import argparse
import datetime
import hashlib
import json
import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIEFS = ROOT / "assets" / "briefs"
MANIFESTS = ROOT / "assets" / "manifests"
MESHES = ROOT / "assets" / "meshes"
TRIPO_OUT = ROOT / ".tripo-out"
ART_BIBLE = ROOT / "docs" / "art-bible.md"
BLENDER_SCRIPT = ROOT / "scripts" / "blender_cleanup.py"
GODOT_SCRIPT = ROOT / "scripts" / "godot_validate.gd"
STAGES = ["concept", "model", "clean", "validate"]

EXIT_OK, EXIT_ERROR, EXIT_CHECK_FAILED, EXIT_AWAITING = 0, 1, 2, 3


class PipelineError(Exception):
    pass


# ── Brief YAML (strict subset: top-level keys, scalars, [inline lists], "- " lists, | blocks) ──

def _parse_scalar(text):
    text = text.strip()
    if text.startswith('"') and text.endswith('"') and len(text) >= 2:
        return json.loads(text)
    if text.startswith("'") and text.endswith("'") and len(text) >= 2:
        return text[1:-1].replace("''", "'")
    if text in ("true", "false"):
        return text == "true"
    if text in ("null", "~", ""):
        return None
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    if re.fullmatch(r"-?\d+\.\d*|-?\.\d+", text):
        return float(text)
    return text


def parse_brief_yaml(text, path):
    data, lines, i = {}, text.splitlines(), 0
    while i < len(lines):
        line = lines[i]
        i += 1
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line[0] in " \t":
            raise PipelineError(f"{path}:{i}: unexpected indentation (only top-level keys are supported)")
        key, sep, rest = line.partition(":")
        if not sep or not re.fullmatch(r"[a-z_][a-z0-9_]*", key):
            raise PipelineError(f"{path}:{i}: expected 'key: value'")
        if key in data:
            raise PipelineError(f"{path}:{i}: duplicate key '{key}'")
        rest = rest.strip()
        if rest == "|":
            block = []
            while i < len(lines) and (not lines[i].strip() or lines[i][0] in " \t"):
                block.append(lines[i])
                i += 1
            body = [l for l in block if l.strip()]
            indent = min(len(l) - len(l.lstrip()) for l in body) if body else 0
            data[key] = "\n".join(l[indent:] for l in block).strip("\n")
        elif rest == "":
            items = []
            while i < len(lines) and re.match(r"^\s+- ", lines[i]):
                items.append(_parse_scalar(lines[i].strip()[2:]))
                i += 1
            data[key] = items
        elif rest.startswith("["):
            if not rest.endswith("]"):
                raise PipelineError(f"{path}:{i}: inline list must close on the same line")
            inner = rest[1:-1].strip()
            data[key] = [_parse_scalar(x) for x in inner.split(",")] if inner else []
        else:
            data[key] = _parse_scalar(rest)
    return data


def art_bible_palette():
    rows = re.findall(r"^\| ([A-Z][A-Za-z ]+?) \| `#[0-9A-Fa-f]{6}` \|", ART_BIBLE.read_text(), re.M)
    return set(rows)


def prompt_blocks():
    """FORM and LIGHTING blocks from docs/art-bible.md ("### FORM block" / "### LIGHTING block"), the only source."""
    text = ART_BIBLE.read_text()
    blocks = {}
    for name in ("FORM", "LIGHTING"):
        m = re.search(rf"^### {name} block\s*\n+```\n(.*?)\n```", text, re.S | re.M)
        if not m:
            raise PipelineError(f"docs/art-bible.md has no fenced '### {name} block' section")
        blocks[name.lower()] = " ".join(m.group(1).split())
    return blocks


def compose_prompt(brief, kind):
    """Concept images get FORM + LIGHTING + description; 3D models get FORM + description."""
    b = prompt_blocks()
    parts = [b["form"]] + ([b["lighting"]] if kind == "concept" else []) + [" ".join(brief["prompt"].split())]
    return " ".join(parts)


def load_brief(asset_id):
    path = BRIEFS / f"{asset_id}.yaml"
    if not path.exists():
        raise PipelineError(f"no brief at {path.relative_to(ROOT)} (every asset needs one; numbers come from docs/art-bible.md)")
    b = parse_brief_yaml(path.read_text(), path.relative_to(ROOT))
    errors = []

    def need(key, check, desc):
        if key not in b:
            errors.append(f"missing '{key}'")
        elif not check(b[key]):
            errors.append(f"'{key}' must be {desc} (got {b[key]!r})")

    is_pos_int = lambda v: isinstance(v, int) and not isinstance(v, bool) and v > 0
    need("asset_id", lambda v: v == asset_id, f"'{asset_id}' (the file name)")
    need("type", lambda v: v in ("character", "prop"), "character or prop")
    need("brief", lambda v: isinstance(v, str) and v.strip(), "non-empty text")
    need("prompt", lambda v: isinstance(v, str) and v.strip(), "non-empty text")
    need("face_limit", is_pos_int, "a positive integer")
    need("vertex_budget", is_pos_int, "a positive integer")
    need("texture_size", lambda v: is_pos_int(v) and v & (v - 1) == 0, "a power of two")
    need("target_size_m", lambda v: isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0, "a positive number")
    need("pivot", lambda v: v in ("base", "center"), "base or center")
    need("palette", lambda v: isinstance(v, list) and v, "a non-empty list")
    if isinstance(b.get("palette"), list):
        unknown = [c for c in b["palette"] if c not in art_bible_palette()]
        if unknown:
            errors.append(f"palette colors not in docs/art-bible.md: {unknown}")
    for opt in ("animations", "exclude_objects"):
        if opt in b and not (isinstance(b[opt], list) and all(isinstance(x, str) for x in b[opt])):
            errors.append(f"'{opt}' must be a list of names")
    for opt in ("source_glb", "socket_map"):
        if b.get(opt) and not (ROOT / b[opt]).exists():
            errors.append(f"'{opt}' points at a missing file: {b[opt]}")
    if errors:
        raise PipelineError(f"invalid brief {path.relative_to(ROOT)}:\n  - " + "\n  - ".join(errors))
    b["_path"] = path
    return b


# ── Files, hashes, tool versions ──────────────────────────────────────────────

def rel(p):
    return str(Path(p).resolve().relative_to(ROOT))


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def file_record(path):
    return {"path": rel(path), "sha256": sha256(path)}


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def tool_path(env_var, name, fallback):
    return os.environ.get(env_var) or shutil.which(name) or fallback


BLENDER = tool_path("BLENDER", "blender", "/Applications/Blender.app/Contents/MacOS/Blender")
GODOT = tool_path("GODOT", "godot", "/Applications/Godot.app/Contents/MacOS/Godot")
_versions = None


def tool_versions():
    global _versions
    if _versions is None:
        def first_line(cmd):
            try:
                out = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
                lines = (out.stdout or out.stderr).strip().splitlines()
                return lines[0].strip() if lines else None
            except (OSError, subprocess.TimeoutExpired):
                return None
        _versions = {
            "python": platform.python_version(),
            "blender": first_line([BLENDER, "--version"]),
            "godot": first_line([GODOT, "--version"]),
            # `tripo --version` is local and free; null means the CLI isn't installed.
            "tripo": first_line(["tripo", "--version"]) if shutil.which("tripo") else None,
        }
    return _versions


# ── Manifest ──────────────────────────────────────────────────────────────────

def manifest_path(asset_id):
    return MANIFESTS / f"{asset_id}.json"


def load_manifest(asset_id):
    p = manifest_path(asset_id)
    if p.exists():
        return json.loads(p.read_text())
    return {"asset_id": asset_id, "stages": {}}


def save_manifest(m):
    MANIFESTS.mkdir(parents=True, exist_ok=True)
    m["total_cost_credits"] = sum((s.get("actual_cost_credits") or 0) for s in m["stages"].values())
    m["updated_at"] = now()
    p = manifest_path(m["asset_id"])
    tmp = p.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(m, indent=2) + "\n")
    os.replace(tmp, p)


def up_to_date(entry, inputs, outputs):
    """A stage is current when it last passed and every recorded input/output hash still matches disk."""
    if not entry or entry.get("status") != "ok":
        return False
    want = sorted((r["path"], r["sha256"]) for r in entry.get("inputs", []) + entry.get("outputs", []))
    try:
        have = sorted((rel(p), sha256(p)) for p in inputs + outputs)
    except FileNotFoundError:
        return False
    return want == have


def record(m, stage, status, inputs, outputs, message, **extra):
    m["stages"][stage] = {
        "status": status,
        "timestamp": now(),
        "inputs": [file_record(p) for p in inputs if Path(p).exists()],
        "outputs": [file_record(p) for p in outputs if Path(p).exists()],
        "tool_versions": tool_versions(),
        "message": message,
        "actual_cost_credits": extra.pop("actual_cost_credits", 0),
        **extra,
    }


# ── Tripo attempt files (written by the tripo skill; read-only here) ─────────

def tripo_attempts(asset_id, kind, patterns):
    """Attempts under .tripo-out/<asset-id>/<kind>-<n>/, each with an optional <kind>-<n>.spend.json."""
    base = TRIPO_OUT / asset_id
    attempts = []
    if not base.exists():
        return attempts
    for d in base.iterdir():
        match = re.fullmatch(rf"{kind}-(\d+)", d.name)
        if not (d.is_dir() and match):
            continue
        spend_path = base / f"{d.name}.spend.json"
        spend = json.loads(spend_path.read_text()) if spend_path.exists() else None
        files = sorted(f for pat in patterns for f in d.rglob(pat))
        attempts.append({"n": int(match.group(1)), "dir": d, "files": files, "spend": spend, "spend_path": spend_path})
    return sorted(attempts, key=lambda a: a["n"])


def attempt_costs(attempts):
    total, unknown = 0, []
    for a in attempts:
        spent = (a["spend"] or {}).get("actual_spend")
        if spent is None:
            unknown.append(a["dir"].name)
        else:
            total += spent
    return total, unknown


def usable(attempts):
    ok = [a for a in attempts if a["files"] and (a["spend"] or {}).get("status") not in ("rejected", "lost", "failed")]
    return ok[-1] if ok else None


def tripo_params(brief):
    return {"pbr": False, "texture": True, "face_limit": brief["face_limit"]}


def next_attempt_dir(asset_id, kind, attempts):
    n = (attempts[-1]["n"] + 1) if attempts else 1
    return f".tripo-out/{asset_id}/{kind}-{n}"


# ── Stages ────────────────────────────────────────────────────────────────────

def stage_concept(brief, m, dry_run, force):
    """Optional stage: never blocks the model stage."""
    aid = brief["asset_id"]
    attempts = tripo_attempts(aid, "concept", ["*.png", "*.jpg", "*.jpeg", "*.webp"])
    pick = usable(attempts)
    prompt = compose_prompt(brief, "concept")
    inputs = [brief["_path"], ART_BIBLE] + ([a["spend_path"] for a in attempts if a["spend_path"].exists()])
    outputs = [pick["files"][0]] if pick else []
    if not force and up_to_date(m["stages"].get("concept"), inputs, outputs):
        print("concept: up to date")
        return EXIT_OK
    if brief.get("source_glb"):
        msg = "existing source_glb; no concept needed"
    elif pick:
        msg = f"concept image ingested from {pick['dir'].name}"
    else:
        cmd = f'tripo generate text-to-image {shlex.quote(prompt)} -o {next_attempt_dir(aid, "concept", attempts)} --no-open --json'
        msg = "no concept image (optional). To make one, run through the tripo skill: " + cmd
    print(f"concept: {msg}")
    if dry_run:
        return EXIT_OK
    cost, unknown = attempt_costs(attempts)
    record(m, "concept", "ok", inputs, outputs, msg, prompt=prompt, params={},
           actual_cost_credits=cost, cost_unknown_attempts=unknown,
           tripo_attempts=[a["spend"] for a in attempts if a["spend"]])
    return EXIT_OK


def resolve_model(brief):
    """Returns (model_path or None, attempts)."""
    if brief.get("source_glb"):
        return ROOT / brief["source_glb"], []
    attempts = tripo_attempts(brief["asset_id"], "attempt", ["*.glb"])
    pick = usable(attempts)
    return (pick["files"][0] if pick else None), attempts


def stage_model(brief, m, dry_run, force):
    aid = brief["asset_id"]
    model, attempts = resolve_model(brief)
    prompt = compose_prompt(brief, "model")
    params = tripo_params(brief)
    inputs = [brief["_path"], ART_BIBLE] + [a["spend_path"] for a in attempts if a["spend_path"].exists()]
    if model is None:
        concept = m["stages"].get("concept", {}).get("outputs") or []
        source = shlex.quote(concept[0]["path"] if concept else prompt)
        flags = " ".join(f"--param {k}={str(v).lower()}" for k, v in params.items())
        cmd = f"tripo make {source} {flags} -o {next_attempt_dir(aid, 'attempt', attempts)} --no-open --json"
        print("model: no base mesh on disk yet. Generate it through the tripo skill "
              "(free dry run, then user confirmation, then the paid run):\n  " + cmd)
        if not dry_run:
            cost, unknown = attempt_costs(attempts)
            record(m, "model", "awaiting", inputs, [], "waiting on a Tripo run", prompt=prompt, params=params,
                   actual_cost_credits=cost, cost_unknown_attempts=unknown, suggested_command=cmd)
            save_manifest(m)
        return EXIT_AWAITING
    if not force and up_to_date(m["stages"].get("model"), inputs, [model]):
        print("model: up to date")
        return EXIT_OK
    msg = f"existing source_glb {rel(model)}" if brief.get("source_glb") else f"Tripo download {rel(model)}"
    print(f"model: {msg}")
    if dry_run:
        return EXIT_OK
    cost, unknown = attempt_costs(attempts)
    record(m, "model", "ok", inputs, [model], msg, prompt=None if brief.get("source_glb") else prompt,
           params=None if brief.get("source_glb") else params, actual_cost_credits=cost,
           cost_unknown_attempts=unknown, tripo_attempts=[a["spend"] for a in attempts if a["spend"]])
    return EXIT_OK


def stage_params(brief):
    keys = ("asset_id", "type", "face_limit", "vertex_budget", "texture_size", "target_size_m", "pivot",
            "palette", "socket_map", "animations", "exclude_objects")
    return {k: brief.get(k) for k in keys}


def run_tool(cmd, report_path, dry_run, label):
    print(f"{label}: " + " ".join(str(c) for c in cmd))
    if dry_run:
        return None
    report_path.parent.mkdir(parents=True, exist_ok=True)
    if report_path.exists():
        report_path.unlink()
    proc = subprocess.run([str(c) for c in cmd], capture_output=True, text=True)
    log = report_path.with_suffix(".log")
    log.write_text(proc.stdout + "\n--- stderr ---\n" + proc.stderr)
    if not report_path.exists():
        raise PipelineError(f"{label} wrote no report (exit {proc.returncode}); see {rel(log)}")
    return json.loads(report_path.read_text())


def work_dir(asset_id):
    return TRIPO_OUT / asset_id / "work"


def stage_clean(brief, m, dry_run, force):
    aid = brief["asset_id"]
    model, _ = resolve_model(brief)
    if model is None:
        print("clean: no base mesh yet; run the model stage first")
        return EXIT_AWAITING
    out = MESHES / f"{aid}.glb"
    if out.resolve() == model.resolve():
        raise PipelineError(f"clean would overwrite its own input {rel(model)}; give the asset a different id")
    inputs = [brief["_path"], model, BLENDER_SCRIPT]
    if not force and up_to_date(m["stages"].get("clean"), inputs, [out]):
        print("clean: up to date")
        return EXIT_OK
    wd = work_dir(aid)
    params_path, report_path = wd / "clean-params.json", wd / "clean-report.json"
    if not dry_run:
        wd.mkdir(parents=True, exist_ok=True)
        params_path.write_text(json.dumps(stage_params(brief), indent=2))
    cmd = [BLENDER, "-b", "--factory-startup", "--python-exit-code", "1", "-P", BLENDER_SCRIPT, "--",
           "--input", model, "--output", out, "--params", params_path, "--report", report_path]
    report = run_tool(cmd, report_path, dry_run, "clean")
    if report is None:
        return EXIT_OK
    passed = report.get("status") == "pass"
    msg = "; ".join(report.get("errors", [])) or f"exported {rel(out)}"
    print(f"clean: {'PASS' if passed else 'FAIL'}: {msg}")
    for w in report.get("warnings", []):
        print(f"clean: warning: {w}")
    record(m, "clean", "ok" if passed else "failed", inputs, [out] if passed else [], msg,
           params=stage_params(brief), report=report)
    return EXIT_OK if passed else EXIT_CHECK_FAILED


def stage_validate(brief, m, dry_run, force):
    aid = brief["asset_id"]
    glb = MESHES / f"{aid}.glb"
    if not glb.exists():
        if dry_run:
            print(f"validate: would validate {rel(glb)} once the clean stage has exported it")
            return EXIT_OK
        print(f"validate: {rel(glb)} doesn't exist; run the clean stage first")
        return EXIT_AWAITING
    inputs = [brief["_path"], glb, GODOT_SCRIPT] + ([ROOT / brief["socket_map"]] if brief.get("socket_map") else [])
    if not force and up_to_date(m["stages"].get("validate"), inputs, []):
        print("validate: up to date")
        return EXIT_OK
    wd = work_dir(aid)
    params_path, report_path = wd / "validate-params.json", wd / "validate-report.json"
    params = stage_params(brief)
    params["blender_vertex_count"] = (m["stages"].get("clean", {}).get("report") or {}).get("vertex_count")
    if not dry_run:
        wd.mkdir(parents=True, exist_ok=True)
        params_path.write_text(json.dumps(params, indent=2))
    cmd = [GODOT, "--headless", "--path", ROOT, "-s", GODOT_SCRIPT, "--",
           "--glb", glb, "--params", params_path, "--report", report_path]
    report = run_tool(cmd, report_path, dry_run, "validate")
    if report is None:
        return EXIT_OK
    passed = report.get("status") == "pass"
    msg = "; ".join(report.get("errors", [])) or "all checks passed"
    print(f"validate: {'PASS' if passed else 'FAIL'}: {msg}")
    for w in report.get("warnings", []):
        print(f"validate: warning: {w}")
    record(m, "validate", "ok" if passed else "failed", inputs, [], msg, params=params, report=report)
    return EXIT_OK if passed else EXIT_CHECK_FAILED


STAGE_FUNCS = {"concept": stage_concept, "model": stage_model, "clean": stage_clean, "validate": stage_validate}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("asset_id")
    ap.add_argument("--stage", required=True, choices=STAGES + ["all"])
    ap.add_argument("--dry-run", action="store_true", help="print what would run; write nothing")
    ap.add_argument("--force", action="store_true", help="re-run even if inputs and outputs are unchanged")
    args = ap.parse_args()
    try:
        brief = load_brief(args.asset_id)
        m = load_manifest(args.asset_id)
        m["brief"] = file_record(brief["_path"])
        for stage in STAGES if args.stage == "all" else [args.stage]:
            code = STAGE_FUNCS[stage](brief, m, args.dry_run, args.force)
            if not args.dry_run:
                save_manifest(m)
            if code != EXIT_OK:
                return code
        return EXIT_OK
    except PipelineError as e:
        print(f"error: {e}", file=sys.stderr)
        return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())
