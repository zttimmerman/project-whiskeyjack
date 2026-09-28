#!/usr/bin/env python3
"""Asset pipeline orchestrator.

    python3 scripts/pipeline.py <asset-id> --stage <concept|multiview|model|rig|clean|validate|all> [--dry-run] [--force]
        [--concept-model banana_pro|seedream_v5] [--variants K] [--refine N --edit TEXT]
    python3 scripts/pipeline.py <asset-id> --approve-concept N

Stages:
  concept    Text-to-image concept (FORM + LIGHTING + brief prompt), or an image-to-image refine of
             concept-N. Stops until the user approves one concept (--approve-concept N).
  multiview  Image-to-multiview from the approved concept: a front/left/back/right sheet.
  model      Ingest the base mesh: the brief's source_glb, or the newest Tripo download on disk.
             Otherwise prints multiview-to-3D for the current sheet. Never text-to-3D.
  rig        Characters only: auto-rig the RAW download (Tripo's rigger expects its +X orientation).
  clean      Blender (headless): scale, pivot, facing, albedo-only, palette correction, flat shading,
             texture size, triangle budget, export GLB. Characters are cleaned from the rigged GLB.
  validate   Godot (headless): bone names, SkeletonProfileHumanoid mapping, triangle count, textures.

This script never runs a paid Tripo command. When a stage's output is missing, it prints the
exact `tripo` command; the agent runs that command through the tripo skill
(.claude/skills/tripo/), which owns spend gating. Re-running the stage then ingests the
downloaded files. Resuming is file-based: stages compare SHA-256 hashes of their inputs
and outputs on disk, never a stored task_id.

Exit codes: 0 ok or up to date, 1 error, 2 stage check failed, 3 waiting on a Tripo run,
4 waiting on the user's concept approval.
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
VIEWS_SCRIPT = ROOT / "scripts" / "blender_views.py"
VIEW_NAMES = ("front", "right", "back", "top", "clay_front", "wireframe_front")
STAGES = ["concept", "multiview", "model", "rig", "clean", "validate"]

EXIT_OK, EXIT_ERROR, EXIT_CHECK_FAILED, EXIT_AWAITING, EXIT_AWAITING_APPROVAL = 0, 1, 2, 3, 4

IMAGE_PATTERNS = ["*.png", "*.jpg", "*.jpeg", "*.webp"]
VIEWS = ("front", "left", "back", "right")  # the CLI's positional multiview order
# Concept image models (Tripo text-to-image whitelist). Character concepts are portrait; banana
# models take `aspect_ratio`, seedream takes `size` as WxH (it ignores aspect_ratio).
CONCEPT_MODELS = {
    "banana_pro": {"portrait": {"aspect_ratio": "3:4"}},
    "seedream_v5": {"portrait": {"size": "1536x2048"}},
}
DEFAULT_CONCEPT_MODEL = "banana_pro"
# Tripo auto-rig, pinned like tripo_model. The rig model follows the body plan, not recency: v1.0 is
# the humanoid (biped) rigger and the server default; v2.5 is the creature rigger (quadruped, hexapod,
# octopod, serpentine, aquatic, avian) and returned generic limb chains on a humanoid. Mixamo bone
# names are the ones Godot's BoneMap auto-mapper and godot_validate.gd's humanoid heuristic recognise.
RIG_MODEL = "v1.0-20240301"
RIG_MODELS = ("v1.0-20240301", "v2.5-20260210")  # --rig-model v2.5-20260210 for non-humanoids (the Sett-boar)
RIG_SPEC = "mixamo"


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


PALETTE_ROW = re.compile(r"^\| ([A-Z][A-Za-z ]+?) \| `#[0-9A-Fa-f]{6}` \| ([^|]+?) \|", re.M)
PALETTE_HEX = re.compile(r"^\| ([A-Z][A-Za-z ]+?) \| `(#[0-9A-Fa-f]{6})` \|", re.M)


def palette_targets(brief):
    """{name: hex} for the brief's palette subset, from docs/art-bible.md: the clean stage's color targets."""
    hexes = dict(PALETTE_HEX.findall(ART_BIBLE.read_text()))
    return {name: hexes[name] for name in brief["palette"]}


def art_bible_palette():
    """{name: plain color} from docs/art-bible.md's palette table, the only source."""
    return dict(PALETTE_ROW.findall(ART_BIBLE.read_text()))


def plain_colors(text):
    """Swaps each palette name for its plain color: image models can't resolve names like "Old Bone"."""
    palette = art_bible_palette()
    for name in sorted(palette, key=len, reverse=True):
        text = re.sub(rf"\b{re.escape(name)}\b", palette[name], text)
    return text


def prompt_blocks():
    """FORM and CONCEPT LIGHTING blocks from docs/art-bible.md ("### <NAME> block" + a fenced block), the
    only source. MOOD LIGHTING is deliberately not read: nothing the pipeline makes may be torchlit."""
    text = ART_BIBLE.read_text()
    blocks = {}
    for name in ("FORM", "CONCEPT LIGHTING"):
        m = re.search(rf"^### {name} block\s*\n+```\n(.*?)\n```", text, re.S | re.M)
        if not m:
            raise PipelineError(f"docs/art-bible.md has no fenced '### {name} block' section")
        blocks[name.lower().replace(" ", "_")] = " ".join(m.group(1).split())
    return blocks


def compose_prompt(brief, kind, edit=None):
    """Concept images (everything that feeds multiview-to-3D) get FORM + CONCEPT LIGHTING + description,
    and a refine swaps the description for the edit instruction (the source image carries the subject).
    3D models get FORM + description. Palette names become plain colors throughout."""
    b = prompt_blocks()
    body = edit if kind == "refine" else brief["prompt"]
    parts = [b["form"]] + ([b["concept_lighting"]] if kind in ("concept", "refine") else []) + [" ".join(body.split())]
    return plain_colors(" ".join(parts))


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
    need("triangle_budget", is_pos_int, "a positive integer (the art bible's face_limit + 10%)")
    need("tripo_model", lambda v: isinstance(v, str) and re.fullmatch(r"[A-Za-z0-9.]+-\d{8}", v),
         "a pinned Tripo wire version such as P1-20260311 (not an alias; don't rely on CLI auto-selection)")
    need("texture_size", lambda v: is_pos_int(v) and v & (v - 1) == 0, "a power of two")
    need("target_size_m", lambda v: isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0, "a positive number")
    need("pivot", lambda v: v in ("base", "center"), "base or center")
    need("palette", lambda v: isinstance(v, list) and v, "a non-empty list")
    if b.get("type") == "prop":
        need("tip_end", lambda v: v in ("top", "bottom", "symmetric"),
             "top, bottom or symmetric (where the prop's thinner end sits after placement)")
    if isinstance(b.get("palette"), list):
        unknown = [c for c in b["palette"] if c not in art_bible_palette()]
        if unknown:
            errors.append(f"palette colors not in docs/art-bible.md: {unknown}")
    if "rigid_parts" in b and not isinstance(b["rigid_parts"], bool):
        errors.append("'rigid_parts' must be true or false")
    if b.get("rigid_parts") and b.get("type") != "character":
        errors.append("'rigid_parts' applies to characters only")
    for opt in ("animations", "exclude_objects", "texture_overlays"):
        if opt in b and not (isinstance(b[opt], list) and all(isinstance(x, str) for x in b[opt])):
            errors.append(f"'{opt}' must be a list of names")
    for ov in b.get("texture_overlays") or []:
        if not (ROOT / ov).exists() or not (ROOT / ov).with_suffix(".json").exists():
            errors.append(f"texture overlay {ov} (and its .json sidecar) must exist; make it with scripts/make_texture_overlay.py")
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

BAD_STATUSES = ("rejected", "lost", "failed")


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


def cost_check(attempts):
    """Per-attempt estimate vs actual balance difference, to judge how far the estimate can be trusted."""
    rows = []
    for a in attempts:
        sp = a["spend"] or {}
        est, act, cli = sp.get("estimate_credits"), sp.get("actual_spend"), sp.get("cli_reported_credits")
        rows.append({"attempt": a["dir"].name, "status": sp.get("status"), "estimate_credits": est,
                     "actual_balance_delta": act, "cli_reported_credits": cli,
                     "estimate_error": (act - est) if isinstance(act, (int, float)) and isinstance(est, (int, float)) else None})
    return rows


def spend_fields(attempts):
    """Cost and provenance fields every Tripo-backed stage records."""
    cost, unknown = attempt_costs(attempts)
    return {"actual_cost_credits": cost, "cost_unknown_attempts": unknown, "cost_check": cost_check(attempts),
            "tripo_attempts": [a["spend"] for a in attempts if a["spend"]]}


def is_usable(a):
    return bool(a["files"]) and (a["spend"] or {}).get("status") not in BAD_STATUSES


def usable(attempts):
    ok = [a for a in attempts if is_usable(a)]
    return ok[-1] if ok else None


def tripo_params(brief):
    return {"pbr": False, "texture": True, "face_limit": brief["face_limit"]}


def param_flags(params):
    fmt = lambda v: str(v).lower() if isinstance(v, bool) else str(v)
    return " ".join(f"--param {shlex.quote(f'{k}={fmt(v)}')}" for k, v in params.items())


def next_attempt_dir(asset_id, kind, attempts, offset=0):
    n = (attempts[-1]["n"] + 1 if attempts else 1) + offset
    return f".tripo-out/{asset_id}/{kind}-{n}"


def tripo_command(*parts):
    return " ".join(p for p in parts if p)


def spend_input(a, subcommand):
    """The input file in the attempt's recorded command (`tripo generate <subcommand> <input> ...`), resolved.
    That command is how a multiview sheet is tied to the concept it came from."""
    cmd = (a["spend"] or {}).get("command")
    if not cmd:
        return None
    argv = shlex.split(cmd)
    try:
        return (ROOT / argv[argv.index(subcommand) + 1]).resolve()
    except (ValueError, IndexError):
        return None


# ── Concept images and approval ───────────────────────────────────────────────

def concept_params(brief, concept_model):
    """Characters get the T-pose template and a portrait frame; props get neither."""
    if brief["type"] != "character":
        return {}
    return {"template": "t_pose", **CONCEPT_MODELS[concept_model]["portrait"]}


def concept_image(a):
    """The one concept image in a concept attempt. The CLI also writes preview.png as a copy of it."""
    imgs = [f for f in a["files"] if f.name != "preview.png"] or a["files"]
    if len(imgs) != 1:
        raise PipelineError(f"{rel(a['dir'])} holds {len(imgs)} images {[f.name for f in imgs]}; expected one concept image")
    return imgs[0]


def find_attempt(attempts, kind, n):
    a = next((a for a in attempts if a["n"] == n), None)
    if a is None or not a["files"]:
        raise PipelineError(f"no image in {kind}-{n}")
    if not is_usable(a):
        raise PipelineError(f"{kind}-{n} is marked {a['spend']['status']}")
    return a


def approved_concept(brief, m):
    """(image path, None) when the recorded approval still matches the file on disk, else (None, reason)."""
    ap = m.get("concept_approval")
    if not ap:
        return None, "no concept approved yet"
    p = ROOT / ap["image"]["path"]
    if not p.exists():
        return None, f"the approved image {ap['image']['path']} is missing"
    if sha256(p) != ap["image"]["sha256"]:
        return None, f"the approved image {ap['image']['path']} changed after approval"
    spend_path = TRIPO_OUT / brief["asset_id"] / f"{ap['attempt']}.spend.json"
    status = json.loads(spend_path.read_text()).get("status") if spend_path.exists() else None
    if status in BAD_STATUSES:
        return None, f"{ap['attempt']} was marked {status} after approval"
    return p, None


def approve_concept(brief, m, n):
    """Records the user's approval of concept-<n>. Run only when the user has approved it in chat."""
    a = find_attempt(tripo_attempts(brief["asset_id"], "concept", IMAGE_PATTERNS), "concept", n)
    img = concept_image(a)
    sp = a["spend"] or {}
    m["concept_approval"] = {"attempt": a["dir"].name, "image": file_record(img), "approved_at": now(),
                             "approved_by": "user", "concept_model": sp.get("model_version"),
                             "prompt": sp.get("prompt"), "command": sp.get("command")}
    print(f"concept: approved {a['dir'].name} ({rel(img)}). Next: --stage multiview")


def model_on_disk(brief):
    return resolve_model(brief)[0] is not None


# ── Stages ────────────────────────────────────────────────────────────────────

def stage_concept(brief, m, args):
    """Stops the pipeline until the user approves a concept: iteration belongs at the image stage."""
    aid = brief["asset_id"]
    attempts = tripo_attempts(aid, "concept", IMAGE_PATTERNS)
    approved, why = approved_concept(brief, m)
    inputs = [brief["_path"], ART_BIBLE] + [a["spend_path"] for a in attempts if a["spend_path"].exists()]
    model = args.concept_model
    params = concept_params(brief, model)

    def save(status, msg, outputs=(), **extra):
        if not args.dry_run:
            record(m, "concept", status, inputs, list(outputs), msg, concept_model=model, params=params,
                   approval=m.get("concept_approval") if approved else None, **spend_fields(attempts), **extra)

    if args.refine is not None:
        src = concept_image(find_attempt(attempts, "concept", args.refine))
        prompt = compose_prompt(brief, "refine", args.edit)
        cmd = tripo_command("tripo generate image-to-image", shlex.quote(rel(src)), f"--model {model}",
                            f"--prompt {shlex.quote(prompt)}", param_flags(params),
                            f"-o {next_attempt_dir(aid, 'concept', attempts)} --no-open --json")
        print(f"concept: refine concept-{args.refine} through the tripo skill, then review the result:\n  {cmd}")
        save("awaiting", f"waiting on a Tripo refine of concept-{args.refine}", prompt=prompt, suggested_commands=[cmd])
        return EXIT_AWAITING

    candidates = [a for a in attempts if is_usable(a)]
    if args.variants is None and model_on_disk(brief):
        status, msg, outputs = "ok", "not needed: the base mesh is already on disk", []
    elif args.variants is None and approved:
        status, msg, outputs = "ok", f"approved {m['concept_approval']['attempt']} ({rel(approved)})", [approved]
    elif args.variants is None and candidates:
        print(f"concept: waiting on the user's approval ({why}). Show the user each candidate, then run "
              f"`--approve-concept N` only after they approve one in chat:")
        for a in candidates:
            print(f"  concept-{a['n']}: {rel(concept_image(a))}  "
                  f"({(a['spend'] or {}).get('model_version') or 'no spend record'})")
        print("  More options: --variants K (new concepts), --refine N --edit TEXT (image-to-image on concept-N)")
        save("awaiting_approval", f"waiting on the user's approval of one of {[a['dir'].name for a in candidates]}")
        return EXIT_AWAITING_APPROVAL
    else:
        prompt = compose_prompt(brief, "concept")
        cmds = [tripo_command("tripo generate text-to-image", shlex.quote(prompt), f"--model {model}",
                              param_flags(params), f"-o {next_attempt_dir(aid, 'concept', attempts, i)} --no-open --json")
                for i in range(args.variants or 1)]
        print("concept: generate through the tripo skill (one paid call each), then review with the user:\n  "
              + "\n  ".join(cmds))
        save("awaiting", "waiting on a Tripo concept run", prompt=prompt, suggested_commands=cmds)
        return EXIT_AWAITING

    if not args.force and up_to_date(m["stages"].get("concept"), inputs, outputs):
        print("concept: up to date")
        return EXIT_OK
    print(f"concept: {msg}")
    save(status, msg, outputs, prompt=(m.get("concept_approval") or {}).get("prompt") if approved else None)
    return EXIT_OK


def current_sheet(brief, m):
    """(attempt, views, attempts, reason) for the newest usable multiview sheet made from the approved concept."""
    attempts = tripo_attempts(brief["asset_id"], "multiview", IMAGE_PATTERNS)
    approved, why = approved_concept(brief, m)
    if not approved:
        return None, {}, attempts, why
    made_from = [a for a in attempts if is_usable(a) and spend_input(a, "image-to-multiview") == approved.resolve()]
    if not made_from:
        return None, {}, attempts, "no multiview sheet from the approved concept yet"
    pick = made_from[-1]
    views = {}
    for f in pick["files"]:
        hit = re.search(r"(front|left|back|right)_view", f.name)
        if hit and hit.group(1) not in views:
            views[hit.group(1)] = f
    return pick, views, attempts, None


def stage_multiview(brief, m, args):
    aid = brief["asset_id"]
    approved, why = approved_concept(brief, m)
    pick, views, attempts, reason = current_sheet(brief, m)
    inputs = ([approved] if approved else []) + [a["spend_path"] for a in attempts if a["spend_path"].exists()]
    outputs = [views[v] for v in VIEWS if v in views]

    def save(status, msg, **extra):
        if not args.dry_run:
            record(m, "multiview", status, inputs, outputs, msg, **spend_fields(attempts), **extra)

    if model_on_disk(brief):
        status, msg = "ok", "not needed: the base mesh is already on disk"
    elif not approved:
        print(f"multiview: waiting on the user's concept approval ({why}); run --stage concept")
        return EXIT_AWAITING_APPROVAL
    elif pick is None:
        cmd = tripo_command("tripo generate image-to-multiview", shlex.quote(rel(approved)),
                            f"-o {next_attempt_dir(aid, 'multiview', attempts)} --no-open --json")
        print(f"multiview: {reason}. Generate it through the tripo skill:\n  {cmd}")
        save("awaiting", "waiting on a Tripo multiview run", suggested_command=cmd)
        return EXIT_AWAITING
    elif "front" not in views or len(views) < 2:
        msg = f"{pick['dir'].name} has views {sorted(views)}; multiview-to-3D needs front plus at least one more"
        print(f"multiview: FAIL: {msg}")
        save("failed", msg)
        return EXIT_CHECK_FAILED
    else:
        status, msg = "ok", f"sheet {pick['dir'].name} from {m['concept_approval']['attempt']}: {', '.join(v for v in VIEWS if v in views)}"
    if not args.force and up_to_date(m["stages"].get("multiview"), inputs, outputs):
        print("multiview: up to date")
        return EXIT_OK
    print(f"multiview: {msg}")
    save(status, msg)
    return EXIT_OK


def resolve_model(brief):
    """Returns (model_path or None, attempts)."""
    if brief.get("source_glb"):
        return ROOT / brief["source_glb"], []
    attempts = tripo_attempts(brief["asset_id"], "attempt", ["*.glb"])
    pick = usable(attempts)
    return (pick["files"][0] if pick else None), attempts


def stage_model(brief, m, args):
    aid = brief["asset_id"]
    model, attempts = resolve_model(brief)
    params = tripo_params(brief)
    inputs = [brief["_path"], ART_BIBLE] + [a["spend_path"] for a in attempts if a["spend_path"].exists()]
    if model is None:
        # Image path only: multiview-to-3D from the approved concept's sheet, never text-to-3D.
        sheet, views, _, why = current_sheet(brief, m)
        if sheet is None or "front" not in views:
            print(f"model: no base mesh on disk, and no multiview sheet to build one from ({why or 'the sheet has no front view'}). "
                  "Run --stage concept, then --stage multiview.")
            return EXIT_AWAITING_APPROVAL if approved_concept(brief, m)[0] is None else EXIT_AWAITING
        cmd = tripo_command("tripo make", " ".join(shlex.quote(rel(views[v])) for v in VIEWS if v in views),
                            f"--model {brief['tripo_model']}", param_flags(params),
                            f"-o {next_attempt_dir(aid, 'attempt', attempts)} --no-open --json")
        print("model: no base mesh on disk yet. Generate it through the tripo skill "
              "(free dry run, then user confirmation, then the paid run):\n  " + cmd)
        if not args.dry_run:
            record(m, "model", "awaiting", inputs, [], "waiting on a Tripo run", prompt=None, params=params,
                   tripo_model=brief.get("tripo_model"), source_views=[file_record(views[v]) for v in VIEWS if v in views],
                   suggested_command=cmd, **spend_fields(attempts))
            save_manifest(m)
        return EXIT_AWAITING
    if not args.force and up_to_date(m["stages"].get("model"), inputs, [model]):
        print("model: up to date")
        return EXIT_OK
    msg = f"existing source_glb {rel(model)}" if brief.get("source_glb") else f"Tripo download {rel(model)}"
    print(f"model: {msg}")
    if args.dry_run:
        return EXIT_OK
    picked = usable(attempts)
    fields = spend_fields(attempts)
    record(m, "model", "ok", inputs, [model], msg,
           # the prompt actually sent, if any (multiview-to-3D takes none)
           prompt=((picked or {}).get("spend") or {}).get("prompt"),
           params=None if brief.get("source_glb") else params, tripo_model=brief.get("tripo_model"),
           estimate_credits=sum((r["estimate_credits"] or 0) for r in fields["cost_check"]), **fields)
    return EXIT_OK


def stage_params(brief):
    keys = ("asset_id", "type", "face_limit", "triangle_budget", "texture_size", "target_size_m", "pivot",
            "palette", "socket_map", "animations", "exclude_objects", "tip_end", "rigid_parts")
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


def current_rig(brief, model):
    """(attempt, glb, attempts) for the newest usable rig-<n> whose spend record's command rigged this raw download."""
    attempts = tripo_attempts(brief["asset_id"], "rig", ["*.glb"])
    made_from = [a for a in attempts if is_usable(a) and spend_input(a, "rig") == Path(model).resolve()]
    pick = made_from[-1] if made_from else None
    return pick, (pick["files"][0] if pick else None), attempts


def needs_rig(brief):
    return brief["type"] == "character" and not brief.get("source_glb")


def clean_input(brief):
    """What the clean stage reads: characters are rigged from the RAW download first (Tripo's rigger
    expects Tripo's +X orientation, and a cleaned, rotated GLB rig-checks as unriggable)."""
    model, _ = resolve_model(brief)
    if model is None or not needs_rig(brief):
        return model
    return current_rig(brief, model)[1]


def stage_rig(brief, m, args):
    aid = brief["asset_id"]
    if not needs_rig(brief):
        print(f"rig: not needed ({'existing source_glb' if brief.get('source_glb') else 'props have no skeleton'})")
        return EXIT_OK
    model, _ = resolve_model(brief)
    if model is None:
        print("rig: no raw download yet; run the model stage first")
        return EXIT_AWAITING
    pick, glb, attempts = current_rig(brief, model)
    inputs = [model] + [a["spend_path"] for a in attempts if a["spend_path"].exists()]
    rig_model = args.rig_model or RIG_MODEL
    params = {"rig_type": "biped", "spec": RIG_SPEC, "model": rig_model, "out_format": "glb"}

    def save(status, msg, outputs=(), **extra):
        if not args.dry_run:
            record(m, "rig", status, inputs, list(outputs), msg, params=params, **spend_fields(attempts), **extra)

    if pick is None:
        cmd = tripo_command("tripo anim rig", shlex.quote(rel(model)), "--rig-type biped", f"--spec {RIG_SPEC}",
                            "--out-format glb", param_flags({"model": rig_model}),
                            f"-o {next_attempt_dir(aid, 'rig', attempts)} --no-open --json")
        print("rig: the raw download isn't rigged yet. Rig-check it (free: `tripo anim check <glb>`), then run "
              "through the tripo skill:\n  " + cmd)
        save("awaiting", "waiting on a Tripo rig run", suggested_command=cmd)
        return EXIT_AWAITING
    if not args.force and up_to_date(m["stages"].get("rig"), inputs, [glb]):
        print("rig: up to date")
        return EXIT_OK
    msg = f"rigged {rel(glb)} from {rel(model)}"
    print(f"rig: {msg}")
    save("ok", msg, [glb])
    return EXIT_OK


def source_forward(task_json):
    """Which way a Tripo download faces, from the task.json the CLI writes beside it. Tripo exports
    along +x unless the request set export_orientation (API default), so a Tripo task without the
    parameter still has a known facing. None for anything that isn't a Tripo download."""
    if not task_json.exists():
        return None
    task_input = json.loads(task_json.read_text()).get("input") or {}
    if "export_orientation" in task_input:
        return {"axis": task_input["export_orientation"], "source": f"{rel(task_json)} export_orientation"}
    return {"axis": "+x", "source": f"Tripo API default ({rel(task_json)} sets no export_orientation)"}


def stage_clean(brief, m, args):
    dry_run, force = args.dry_run, args.force
    aid = brief["asset_id"]
    model = clean_input(brief)
    if model is None:
        print("clean: no " + ("rigged mesh yet; run the rig stage first" if needs_rig(brief) and resolve_model(brief)[0]
                              else "base mesh yet; run the model stage first"))
        return EXIT_AWAITING
    out = MESHES / f"{aid}.glb"
    if out.resolve() == model.resolve():
        raise PipelineError(f"clean would overwrite its own input {rel(model)}; give the asset a different id")
    task_json = model.parent / "task.json"
    # The approved concept is the color reference (art bible: the concept governs correction)
    reference, _ = approved_concept(brief, m)
    overlays = [ROOT / ov for ov in brief.get("texture_overlays") or []]
    inputs = ([brief["_path"], model, BLENDER_SCRIPT] + ([task_json] if task_json.exists() else []) + ([reference] if reference else [])
              + overlays + [ov.with_suffix(".json") for ov in overlays])
    if not force and up_to_date(m["stages"].get("clean"), inputs, [out]):
        print("clean: up to date")
        return EXIT_OK
    wd = work_dir(aid)
    params_path, report_path = wd / "clean-params.json", wd / "clean-report.json"
    params = {**stage_params(brief), "source_forward": source_forward(task_json),
              "palette_targets": palette_targets(brief), "reference_image": str(reference) if reference else None,
              "texture_overlays": [str(ov) for ov in overlays]}
    if not dry_run:
        wd.mkdir(parents=True, exist_ok=True)
        params_path.write_text(json.dumps(params, indent=2))
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
    for label, t in (report.get("mesh_health") or {}).get("totals", {}).items():
        print(f"clean: health ({label}): {t['vertices']} verts, {t['faces']} faces "
              f"(tri {t['triangles']} / quad {t['quads']} / ngon {t['ngons']}, quad ratio {t['quad_ratio']}), "
              f"non-manifold {t['non_manifold_edges']}, boundary {t['boundary_edges']} in {t['boundary_loops']} loops, "
              f"loose verts {t['loose_vertices']}, degenerate faces {t['degenerate_faces']}"
              + (f", parts {t['part_count']} " + str([p['triangles'] for p in t['parts']]) + " tris" if 'parts' in t else ""))
    record(m, "clean", "ok" if passed else "failed", inputs, [out] if passed else [], msg,
           params=params, report=report)
    return EXIT_OK if passed else EXIT_CHECK_FAILED


def stage_validate(brief, m, args):
    dry_run, force = args.dry_run, args.force
    aid = brief["asset_id"]
    glb = MESHES / f"{aid}.glb"
    if not glb.exists():
        if dry_run:
            print(f"validate: would validate {rel(glb)} once the clean stage has exported it")
            return EXIT_OK
        print(f"validate: {rel(glb)} doesn't exist; run the clean stage first")
        return EXIT_AWAITING
    inputs = [brief["_path"], glb, GODOT_SCRIPT, VIEWS_SCRIPT] + ([ROOT / brief["socket_map"]] if brief.get("socket_map") else [])
    views_dir = MANIFESTS / aid
    view_pngs = [views_dir / f"{n}.png" for n in VIEW_NAMES]
    if not force and up_to_date(m["stages"].get("validate"), inputs, view_pngs):
        print("validate: up to date")
        return EXIT_OK
    wd = work_dir(aid)
    params_path, report_path = wd / "validate-params.json", wd / "validate-report.json"
    params = stage_params(brief)
    params["blender_triangle_count"] = (m["stages"].get("clean", {}).get("report") or {}).get("triangle_count")
    if not dry_run:
        wd.mkdir(parents=True, exist_ok=True)
        params_path.write_text(json.dumps(params, indent=2))
    cmd = [GODOT, "--headless", "--path", ROOT, "-s", GODOT_SCRIPT, "--",
           "--glb", glb, "--params", params_path, "--report", report_path]
    report = run_tool(cmd, report_path, dry_run, "validate")
    views_cmd = [BLENDER, "-b", "--factory-startup", "--python-exit-code", "1", "-P", VIEWS_SCRIPT, "--",
                 "--input", glb, "--outdir", views_dir, "--report", wd / "views-report.json"]
    views = run_tool(views_cmd, wd / "views-report.json", dry_run, "validate (views)")
    if report is None:
        return EXIT_OK
    report["views"] = views
    report["gross_flags"] = gross_flags(views, m)
    for flag in report["gross_flags"]:
        report["warnings"].append(f"gross check: {flag}")
    passed = report.get("status") == "pass"
    msg = "; ".join(report.get("errors", [])) or "all checks passed"
    print(f"validate: {'PASS' if passed else 'FAIL'}: {msg}")
    print(f"validate: views in {rel(views_dir)}/ " + ", ".join(
        f"{k} {v['coverage']:.1%}" for k, v in (views.get("views") or {}).items()) +
        f"; welded pieces: {views.get('pieces_welded')}")
    for w in report.get("warnings", []):
        print(f"validate: warning: {w}")
    record(m, "validate", "ok" if passed else "failed", inputs, [p for p in view_pngs if p.exists()], msg,
           params=params, report=report)
    return EXIT_OK if passed else EXIT_CHECK_FAILED


def gross_flags(views, m):
    """Baseline flags only (recorded as warnings, never failures): missing geometry and holes.
    Fused parts have no reliable automatic test; the renders and the welded piece count are for review."""
    flags = []
    if views.get("status") != "ok":
        flags.append("review renders failed: " + "; ".join(views.get("errors", [])))
        return flags
    if not views.get("triangles"):
        flags.append("missing geometry: no triangles")
    for name, v in (views.get("views") or {}).items():
        if v["coverage"] < 0.005:
            flags.append(f"missing geometry: the {name} view is almost empty ({v['coverage']:.2%} of the frame)")
    welded = (((m["stages"].get("clean") or {}).get("report") or {}).get("mesh_health") or {}).get("totals", {}).get("welded", {})
    if welded.get("boundary_loops"):
        flags.append(f"holes: {welded['boundary_loops']} open boundary loops after welding")
    return flags


STAGE_FUNCS = {"concept": stage_concept, "multiview": stage_multiview, "model": stage_model, "rig": stage_rig,
               "clean": stage_clean, "validate": stage_validate}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("asset_id")
    ap.add_argument("--stage", choices=STAGES + ["all"])
    ap.add_argument("--dry-run", action="store_true", help="print what would run; write nothing")
    ap.add_argument("--force", action="store_true", help="re-run even if inputs and outputs are unchanged")
    ap.add_argument("--concept-model", choices=sorted(CONCEPT_MODELS), default=DEFAULT_CONCEPT_MODEL,
                    help=f"text-to-image model for concepts (default {DEFAULT_CONCEPT_MODEL}; seedream_v5 for cheap variants)")
    ap.add_argument("--variants", type=int, metavar="K", help="print K new concept commands (1-4), even if concepts exist")
    ap.add_argument("--refine", type=int, metavar="N", help="print an image-to-image refine of concept-N (needs --edit)")
    ap.add_argument("--edit", metavar="TEXT", help="the refine instruction, e.g. from the user's review")
    ap.add_argument("--rig-model", choices=RIG_MODELS,
                    help=f"rig stage only: rig model to print (default {RIG_MODEL}, humanoids; v2.5 for creatures)")
    ap.add_argument("--approve-concept", type=int, metavar="N",
                    help="record the user's approval of concept-N; only after they approve it in chat")
    args = ap.parse_args()
    if (args.stage is None) == (args.approve_concept is None):
        ap.error("give exactly one of --stage or --approve-concept")
    if args.variants is not None and not 1 <= args.variants <= 4:
        ap.error("--variants must be 1-4")
    if (args.refine is None) != (args.edit is None):
        ap.error("--refine and --edit go together")
    if (args.refine is not None or args.variants is not None) and args.stage != "concept":
        ap.error("--refine and --variants apply to --stage concept only")
    try:
        brief = load_brief(args.asset_id)
        m = load_manifest(args.asset_id)
        m["brief"] = file_record(brief["_path"])
        if args.approve_concept is not None:
            approve_concept(brief, m, args.approve_concept)
            if not args.dry_run:
                save_manifest(m)
            return EXIT_OK
        for stage in STAGES if args.stage == "all" else [args.stage]:
            code = STAGE_FUNCS[stage](brief, m, args)
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
