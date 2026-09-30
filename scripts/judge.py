#!/usr/bin/env python3
"""Asset judge: builds the evidence packet a fresh-context judge subagent rules on, and logs its verdict.

    python3 scripts/judge.py packet <asset-id> --stage concept|multiview|model|mesh|motion
            [--subject N|PATH] [--input GLB] [--concept PATH|none] [--clip NAME --motion-dir DIR] [--replay NAME]
    python3 scripts/judge.py record <packet-dir> <verdict.json>
    python3 scripts/judge.py resolve <asset-id> --stage KEY --decision TEXT [--replay NAME]
    python3 scripts/judge.py log <asset-id> [--replay NAME]

Stages (what is judged):
  concept    a concept image (default: the newest usable concept-<n>) against the brief and palette
  multiview  the current multiview sheet against the approved concept
  model      the raw Tripo download, before rig spend: cleaned into a scratch dir and rendered
  mesh       the shipped assets/meshes/<id>.glb: the clean and validate reports and review renders
  motion     one clip's motion review (scripts/review/motion_review.tscn): strip, onion skin, plots, metrics

`packet` copies every image the judge will see into the packet directory (so the log keeps the
exact render behind each verdict; the images are gitignored and stay local, the JSON records their hashes), computes metrics and the numeric assertions (tolerances come
from docs/art-bible.md -> Judge tolerances, the only source), and writes packet.json. The agent
then spawns the `asset-judge` subagent (.claude/agents/asset-judge.md) on that packet and passes
its JSON reply to `record`, which validates it, applies the refine budget (one auto-refine per
stage, then escalate regardless) and appends it to the verdict log: the asset manifest's
`judgments`, or <replay dir>/judgments.json for a replay.

Replays (--replay NAME) judge historical inputs without touching the asset's manifest or mesh:
packets and the log go to assets/manifests/judge_replays/NAME/.

Exit codes: 0 ok, 1 error; `record` exits 0 on pass, 5 on revise (auto-refine), 6 on escalate.
"""

import argparse
import json
import re
import shlex
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pipeline as P  # noqa: E402

JUDGE_IMAGES = P.ROOT / "scripts" / "judge_images.py"
REPLAYS = P.MANIFESTS / "judge_replays"
VERDICTS = ("pass", "revise", "escalate")
REVISE_ACTIONS = ("refine_concept", "reroll", "library_change")
CHECKS = ("concept_match", "missing", "malformed", "color", "budget", "motion", "pose", "lighting", "other")
SEVERITIES = ("blocker", "major", "minor")
AUTO_REFINES_PER_STAGE = 1
EXIT_REVISE, EXIT_ESCALATE = 5, 6
TOLERANCE_ROW = re.compile(r"^\| `([a-z_]+)` \| ([0-9.]+) \|", re.M)

# What the judge is asked, per stage. Checkable questions only; style and taste escalate.
QUESTIONS = {
    "concept": [
        "Does the image show every element the brief's prompt names, in the named colors? List each element as present or absent.",
        "Is anything malformed, or too fine to survive the brief's face_limit: thin separate strands, paired parallel bones, gaps narrower than a finger, individual fingers, fused or duplicated limbs? (Art bible: judge concepts as low-poly game assets; a detailed concept makes a detailed mesh that face_limit destroys.)",
        "Characters: is it a T- or A-pose with the arms clear of the body, hands empty, the full body in frame?",
        "Lighting: flat and shadowless on a plain uniform background, per the CONCEPT LIGHTING block?",
        "Colors: do the color assertions pass? Name any brief palette color the image lacks, or any large area in a color the brief doesn't ask for.",
    ],
    "multiview": [
        "Does each view (front, left, back, right) show the same design as the approved concept? Name any element that appears in one view and is missing or different in another.",
        "Does the back view contradict the brief (e.g. the brief says an element crosses the back but the back view shows something else)?",
        "Is anything malformed in any view: extra or missing limbs, fused parts, props in the hands, cropped geometry?",
    ],
    "model": [
        "Does the mesh match the approved concept (or, with no concept, the brief's prompt) part for part? List each named element as present, absent or changed.",
        "Is anything missing or malformed: holes, fused limbs or parts that should be separate, separate pieces that should be one (see the part list), spikes, floating fragments, extra props?",
        "Budget and scale: do the triangle, texture and size assertions pass?",
        "Colors: do the color assertions pass? Name any concept or palette color the texture lost, or a large area in a color the brief doesn't ask for.",
    ],
    "motion": [
        "Onion skin: does the body stay where the clip intends (in place for in-place and death clips), or does it drift, fling or slide?",
        "Plots: do the planted feet hold still relative to the ground (foot speed near zero while the foot is in contact), and does the root follow the gameplay speed?",
        "Frame strip: any broken pose: limbs through the body, arms behind the back where the clip doesn't intend it, twisted or collapsed joints, stretched skin?",
        "Do the numeric assertions pass? Tie each failing one to what you see in the images.",
    ],
}
QUESTIONS["mesh"] = QUESTIONS["model"] + [
    "Rigged characters: does the validate report map every required humanoid bone, and do the sockets resolve?",
]

# Characters only (brief: "face and hands still recognizable"). Asked separately because a general
# "does it match" pass called the player's face recognizable with the mouth flattened into the skin.
FACE_QUESTION = ("Face (characters): in the closeups (or the concept), list the eyes, nose and mouth, each as clearly "
                 "present, faint, or absent. A faint or absent feature the concept shows is a missing finding.")

ESCALATE_RULES = [
    "Open style or taste questions (is it appealing, is the silhouette strong enough, is this the right design) are not yours: escalate them.",
    "A deliberate, recorded design change (see design_notes) is not a defect: don't flag it again, but say so if the asset contradicts the note.",
    "When the evidence can't settle a question (the view that would show it is missing), escalate rather than guess.",
    "Revise only when one concrete edit would fix every blocker and major finding. Otherwise escalate.",
]


class JudgeError(Exception):
    pass


# ── Tolerances and art-bible excerpts ─────────────────────────────────────────

def tolerances():
    t = {k: float(v) for k, v in TOLERANCE_ROW.findall(P.ART_BIBLE.read_text())}
    if not t:
        raise JudgeError("docs/art-bible.md has no Judge tolerances table")
    return t


def art_bible_section(heading_regex):
    """The art-bible section whose heading matches, up to the next heading of the same or higher level."""
    text = P.ART_BIBLE.read_text()
    m = re.search(rf"^(#+) ({heading_regex}).*$", text, re.M)
    if not m:
        return None
    level = len(m.group(1))
    rest = text[m.end():]
    end = re.search(rf"^#{{1,{level}}} ", rest, re.M)
    return (m.group(0) + rest[:end.start() if end else len(rest)]).strip()


def brief_section(asset_id, drop_design_notes=False):
    """The art bible's '## Brief: ...' section whose File line names assets/meshes/<asset_id>.glb.
    drop_design_notes removes its recorded design-change bullets (for replays of inputs judged before them)."""
    text = P.ART_BIBLE.read_text()
    for m in re.finditer(r"^## Brief: .*$", text, re.M):
        rest = text[m.end():]
        end = re.search(r"^(## |---)", rest, re.M)
        body = m.group(0) + rest[:end.start() if end else len(rest)]
        if f"assets/meshes/{asset_id}.glb" in body:
            if drop_design_notes:
                body = "\n".join(line for line in body.splitlines() if "design change" not in line.lower())
            return body.strip()
    return None


def palette_hex():
    return dict(P.PALETTE_HEX.findall(P.ART_BIBLE.read_text()))


# ── Color math (pure Python; judge_images.py measures, this compares) ─────────

def hex_to_lab(h):
    rgb = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
    m = [[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]]
    xyz = [sum(m[r][c] * lin[c] for c in range(3)) / w for r, w in zip(range(3), (0.95047, 1.0, 1.08883))]
    f = [x ** (1 / 3) if x > 216 / 24389 else (24389 / 27 * x + 16) / 116 for x in xyz]
    return [116 * f[1] - 16, 500 * (f[0] - f[1]), 200 * (f[1] - f[2])]


def delta_e(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5


# ── Paths, packets, log ───────────────────────────────────────────────────────

def base_dir(asset_id, replay):
    return REPLAYS / replay if replay else P.MANIFESTS / asset_id


def next_packet_dir(base, stage_key):
    root = base / "judge"
    slug = stage_key.replace(":", "-")
    n = 1
    while (root / f"{slug}-{n}").exists():
        n += 1
    return root / f"{slug}-{n}"


def load_log(asset_id, replay):
    if replay:
        p = REPLAYS / replay / "judgments.json"
        return json.loads(p.read_text()) if p.exists() else {"replay": replay, "asset_id": asset_id, "judgments": []}
    return P.load_manifest(asset_id)


def save_log(asset_id, replay, log):
    if replay:
        p = REPLAYS / replay / "judgments.json"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(log, indent=2) + "\n")
    else:
        P.save_manifest(log)


def refines_used(log, stage_key):
    """Auto-refines taken for this stage since the user last resolved it."""
    used = 0
    for j in log.get("judgments", []):
        if j.get("stage") != stage_key:
            continue
        if j.get("kind") == "resolution":
            used = 0
        elif j.get("action") == "auto_refine":
            used += 1
    return used


def run_images(job, workdir):
    workdir.mkdir(parents=True, exist_ok=True)
    job_path, report_path = workdir / "images-job.json", workdir / "images-report.json"
    job_path.write_text(json.dumps(job, indent=2))
    cmd = [P.BLENDER, "-b", "--factory-startup", "--python-exit-code", "1", "-P", JUDGE_IMAGES, "--",
           "--job", job_path, "--report", report_path]
    report = P.run_tool(cmd, report_path, False, "judge (images)")
    if report.get("status") != "ok":
        raise JudgeError("judge_images.py failed: " + "; ".join(report.get("errors", [])))
    return report


def add_images(packet, pdir, entries, measure=()):
    """entries: [(role, source path, max_size)]. Copies each into the packet and records both hashes."""
    job = {"copy": [], "colors": [str(Path(p).resolve()) for p in measure]}
    for i, (role, src, size) in enumerate(entries):
        dst = pdir / f"{i + 1:02d}_{role}.png"
        job["copy"].append({"src": str(Path(src).resolve()), "dst": str(dst), "max_size": size})
    report = run_images(job, pdir / "work")
    for (role, src, _), c in zip(entries, report["copies"]):
        packet["images"].append({"role": role, "path": P.rel(c["dst"]), "sha256": P.sha256(c["dst"]),
                                 "source": P.rel(src), "source_sha256": P.sha256(src), "size": c["size"]})
    return report["colors"]


def assertion(packet, name, passed, value, limit, detail):
    packet["assertions"].append({"name": name, "passed": bool(passed), "value": value, "limit": limit, "detail": detail})


# ── Stage packets ─────────────────────────────────────────────────────────────

def palette_presence(packet, colors, brief, tol, label):
    """Each palette color the prompt names must match a main color (share >= 3%) within concept_palette_de.
    Palette colors the prompt doesn't name come from elsewhere (props, a variant texture), so the image
    isn't expected to hold them; with no names in the prompt, the whole brief palette is checked."""
    pal = palette_hex()
    main = [c for c in colors["colors"] if c["share"] >= 0.03]
    named = [n for n in brief["palette"] if re.search(rf"\b{re.escape(n)}\b", brief["prompt"])] or brief["palette"]
    rows = []
    for name in named:
        target = hex_to_lab(pal[name])
        best = min(main, key=lambda c: delta_e(c["lab"], target), default=None)
        de = round(delta_e(best["lab"], target), 1) if best else None
        rows.append({"palette": name, "hex": pal[name], "nearest": best and best["hex"], "nearest_share": best and best["share"], "delta_e": de})
    packet["metrics"][f"{label}_palette_presence"] = rows
    for r in rows:
        assertion(packet, f"palette color present: {r['palette']}", r["delta_e"] is not None and r["delta_e"] <= tol["concept_palette_de"],
                  r["delta_e"], tol["concept_palette_de"], f"nearest main color {r['nearest']} ({r['nearest_share']:.0%} of the image)" if r["nearest"] else "no main colors")


def concept_subject(brief, subject):
    if subject and not subject.isdigit():
        return Path(subject).resolve(), None
    attempts = P.tripo_attempts(brief["asset_id"], "concept", P.IMAGE_PATTERNS)
    if subject:
        a = P.find_attempt(attempts, "concept", int(subject))
    else:
        a = P.usable(attempts)
        if a is None:
            raise JudgeError("no usable concept to judge")
    return P.concept_image(a), a["n"]


def packet_concept(packet, pdir, brief, m, args, tol):
    img, n = concept_subject(brief, args.subject)
    packet["subject"] = {"kind": "concept image", "attempt": f"concept-{n}" if n else None, **P.file_record(img)}
    packet["refine_hint"] = {"refine_of": n} if n else None
    colors = add_images(packet, pdir, [("concept", img, 1024)], measure=[img])
    colors = colors[str(img.resolve())]
    packet["metrics"]["concept_main_colors"] = colors
    palette_presence(packet, colors, brief, tol, "concept")


def packet_multiview(packet, pdir, brief, m, args, tol):
    pick, views, _, why = P.current_sheet(brief, m)
    if pick is None:
        raise JudgeError(f"no multiview sheet to judge: {why}")
    concept, _ = P.approved_concept(brief, m)
    packet["subject"] = {"kind": "multiview sheet", "attempt": pick["dir"].name,
                         "views": {k: P.file_record(v) for k, v in views.items()}}
    entries = [("approved_concept", concept, 1024)] + [(f"{v}_view", views[v], 768) for v in P.VIEWS if v in views]
    add_images(packet, pdir, entries)
    assertion(packet, "sheet has all four views", len(views) == 4, sorted(views), ["front", "left", "back", "right"], "")


def reference_concept(brief, m, args):
    if args.concept == "none":
        return None
    if args.concept:
        return Path(args.concept).resolve()
    return P.approved_concept(brief, m)[0]


def mesh_metrics(packet, brief, clean, views, tol):
    """Budget, texture, size, parts and color assertions from the clean stage's report."""
    tri, budget = clean.get("triangle_count"), brief["triangle_budget"]
    assertion(packet, "triangles within budget", tri is not None and tri <= budget, tri, budget, "art bible: triangles after triangulation, summed across the GLB")
    tex = clean.get("textures") or []
    size_ok = len(tex) == 1 and max(tex[0]["size_after"]) <= brief["texture_size"]
    assertion(packet, "one albedo texture at the brief's size", size_ok, [t["size_after"] for t in tex], brief["texture_size"], "")
    welded = ((clean.get("mesh_health") or {}).get("totals") or {}).get("welded") or {}
    dims = (clean.get("transform") or {}).get("true_dims_m") or (clean.get("transform") or {}).get("dimensions_m")
    packet["metrics"]["mesh"] = {
        "triangles": tri, "triangle_budget": budget, "texture_sizes": [t["size_after"] for t in tex],
        "part_count": welded.get("part_count"),
        "parts": [{"triangles": p["triangles"], "size_m": p["size_m"], "boundary_loops": p.get("boundary_loops")}
                  for p in (welded.get("parts") or [])[:40]],
        "holes_boundary_loops": welded.get("boundary_loops"), "non_manifold_edges": welded.get("non_manifold_edges"),
        "true_dims_m": dims, "true_length_m": (clean.get("transform") or {}).get("true_length_m"),
        "target_size_m": brief.get("target_size_m"), "source_scale": brief.get("source_scale"), "clean_warnings": clean.get("warnings"), "clean_errors": clean.get("errors"),
        "view_coverage": {k: v["coverage"] for k, v in ((views or {}).get("views") or {}).items()},
    }
    if P.is_sourced(brief):
        # Sourced kits (art bible -> Judge tolerances): kit parts are open-backed shells (a wall body plus
        # raised blocks flush on its face), so the rule is per part; whether a loop shows is the judge's call.
        parts = welded.get("parts") or []
        per_part = [p.get("boundary_loops") for p in parts]
        worst = max((n for n in per_part if n is not None), default=0)
        limit = tol["mesh_kit_max_loops_per_part"]
        assertion(packet, "holes per part (sourced kit: open boundary loops on any one part)",
                  None not in per_part and worst <= limit, worst, limit,
                  f"{welded.get('boundary_loops')} loops over {len(parts)} parts after welding at 0.01 mm; "
                  f"parts over the limit: {sum(1 for n in per_part if n is not None and n > limit)}; "
                  "no loop may be visible in the views (judge)")
    else:
        assertion(packet, "holes (welded boundary loops)", (welded.get("boundary_loops") or 0) <= tol["mesh_max_holes"],
                  welded.get("boundary_loops"), tol["mesh_max_holes"], "open boundary loops after welding at 0.01 mm")
    # Color: the concept governs correction; the palette is the fallback for concept-less assets
    for cc in clean.get("color_correction") or []:
        rows = []
        for c in cc["clusters"]:
            rows.append({k: c.get(k) for k in ("concept", "concept_share", "texture_before", "texture_share", "texture_after",
                                                "delta_e_before", "delta_ab_after", "applied", "reason")})
            if c["concept_share"] >= tol["color_min_share"]:
                kept = c["texture_share"] >= tol["color_kept_ratio"] * c["concept_share"]
                assertion(packet, f"concept color {c['concept']} kept in the texture", kept,
                          c["texture_share"], round(tol["color_kept_ratio"] * c["concept_share"], 3),
                          f"covers {c['concept_share']:.0%} of the concept")
                if c.get("applied"):
                    assertion(packet, f"concept color {c['concept']} matched after correction", c["delta_ab_after"] <= tol["color_dab_after"],
                              c["delta_ab_after"], tol["color_dab_after"], "hue/saturation distance (Lab a, b) after correction")
                else:
                    assertion(packet, f"concept color {c['concept']} found in the texture", False, c["delta_e_before"],
                              "applied", c.get("reason") or "")
        packet["metrics"].setdefault("color_vs_concept", []).append(rows)
    for pc in clean.get("palette_correction") or []:
        packet["metrics"].setdefault("color_vs_palette", []).append(pc["groups"])
        if pc.get("measured_over") or pc.get("lightness"):
            packet["metrics"].setdefault("color_vs_palette_basis", []).append(
                {k: pc.get(k) for k in ("measured_over", "lightness", "shared_atlas")})
        for g in pc["groups"]:
            if g.get("share", 0) >= tol["color_min_share"] and not g.get("applied"):
                assertion(packet, f"palette color {g['color']} matched", False, g.get("delta_e_before"), "applied", g.get("reason", ""))
            if g.get("share", 0) >= tol["color_min_share"] and g.get("delta_e_before") is not None:
                # Correction can hide a wrong color: attempt-1's olive blade grouped under Old Bone and
                # was repainted bone. The distance before correction is the generator's real miss.
                assertion(packet, f"palette color {g['color']} close before correction", g["delta_e_before"] <= tol["palette_de_before"],
                          g["delta_e_before"], tol["palette_de_before"], f"median {g.get('median_before')} covers {g['share']:.0%} of the texture, target {g['target']}")
            if g.get("applied"):
                assertion(packet, f"palette color {g['color']} within tolerance after correction", g["delta_e_after"] <= tol["palette_de_after"],
                          g["delta_e_after"], tol["palette_de_after"], f"median {g['median_before']} -> {g['median_after']}, target {g['target']}")
        # Palette groups hold every texel, so a group that isn't there can't be judged by the groups
        # alone: the dominant group's median distance is the headline number (a green blade sits far from iron).
        big = max(pc["groups"], key=lambda g: g.get("share", 0))
        packet["metrics"]["dominant_palette_group"] = big


def render_views(glb, wd, brief):
    """The pipeline's review renders, plus head-and-chest closeups for characters."""
    return P.run_tool([P.BLENDER, "-b", "--factory-startup", "--python-exit-code", "1", "-P", P.VIEWS_SCRIPT, "--",
                       "--input", glb, "--outdir", wd / "views", "--report", wd / "views-report.json"]
                      + (["--closeups"] if brief["type"] == "character" else []),
                      wd / "views-report.json", False, "judge (views)")


def view_entries(views_dir, concept):
    entries = [("approved_concept", concept, 1024)] if concept else []
    for name in P.VIEW_NAMES + ("closeup_front", "closeup_back"):
        if (views_dir / f"{name}.png").exists():
            entries.append((name, views_dir / f"{name}.png", 512))
    return entries


def packet_model(packet, pdir, brief, m, args, tol):
    """The raw download, cleaned into the packet's scratch dir with the brief's own parameters, so it's
    judged before any rig spend. Unrigged, so the weight steps (rigid rebind, skirt) and overlays are off."""
    model = Path(args.input).resolve() if args.input else P.resolve_model(brief)[0]
    if model is None:
        raise JudgeError("no model download to judge")
    concept = reference_concept(brief, m, args)
    wd = pdir / "work"
    wd.mkdir(parents=True, exist_ok=True)
    task_json = model.parent / "task.json"
    params = {**P.stage_params(brief), "rigid_parts": False, "skirt_reweight": False, "texture_overlays": [],
              "source_forward": P.source_forward(task_json), "palette_targets": P.palette_targets(brief),
              "reference_image": str(concept) if concept else None}
    (wd / "clean-params.json").write_text(json.dumps(params, indent=2))
    out = wd / "preview.glb"
    clean = P.run_tool([P.BLENDER, "-b", "--factory-startup", "--python-exit-code", "1", "-P", P.BLENDER_SCRIPT, "--",
                        "--input", model, "--output", out, "--params", wd / "clean-params.json", "--report", wd / "clean-report.json"],
                       wd / "clean-report.json", False, "judge (clean preview)")
    views = None
    if out.exists():
        views = render_views(out, wd, brief)
    packet["subject"] = {"kind": "raw model download (preview-cleaned, unrigged)", **P.file_record(model),
                         "concept": P.file_record(concept) if concept else None}
    assertion(packet, "preview clean passed", clean.get("status") == "pass", clean.get("status"), "pass", "; ".join(clean.get("errors", [])))
    # Tripo's own render of the download shows the texture before color correction
    preview = next((model.parent / n for n in ("preview.png", "rendered_image.webp") if (model.parent / n).exists()), None)
    if views:
        add_images(packet, pdir, view_entries(wd / "views", concept) + ([("tripo_preview_uncorrected", preview, 512)] if preview else []))
    elif concept:
        add_images(packet, pdir, [("approved_concept", concept, 1024)])
    mesh_metrics(packet, brief, clean, views, tol)


def packet_mesh(packet, pdir, brief, m, args, tol):
    glb = P.MESHES / f"{brief['asset_id']}.glb"
    clean = (m["stages"].get("clean") or {}).get("report")
    val = (m["stages"].get("validate") or {}).get("report")
    if not (glb.exists() and clean and val):
        raise JudgeError("run the clean and validate stages first")
    concept = reference_concept(brief, m, args)
    packet["subject"] = {"kind": "shipped mesh", **P.file_record(glb), "concept": P.file_record(concept) if concept else None}
    # Rendered afresh (the same deterministic views as the validate stage, plus character closeups)
    views = render_views(glb, pdir / "work", brief)
    add_images(packet, pdir, view_entries(pdir / "work" / "views", concept))
    mesh_metrics(packet, brief, clean, views, tol)
    rig = val.get("rig") or {}
    packet["metrics"]["validate"] = {"status": val.get("status"), "errors": val.get("errors"), "warnings": val.get("warnings"),
                                     "humanoid_mappable": rig.get("humanoid_mappable"), "missing_required": rig.get("missing_required"),
                                     "sockets": val.get("sockets") or rig.get("sockets")}
    assertion(packet, "validate stage passed", val.get("status") == "pass", val.get("status"), "pass", "; ".join(val.get("errors", [])))


def packet_motion(packet, pdir, brief, m, args, tol):
    if not (args.clip and args.motion_dir):
        raise JudgeError("--stage motion needs --clip and --motion-dir (scripts/review/motion_review.tscn output)")
    d = Path(args.motion_dir).resolve()
    metrics_path = d / f"{args.clip}_metrics.json"
    if not metrics_path.exists():
        raise JudgeError(f"no {P.rel(metrics_path)}; run the motion review first")
    mm = json.loads(metrics_path.read_text())
    packet["subject"] = {"kind": "animation clip", "clip": args.clip, "source": mm.get("source"), "model": mm.get("model"),
                         "metrics_file": P.file_record(metrics_path)}
    add_images(packet, pdir, [("frame_strip", d / f"{args.clip}_strip.png", 2400), ("onion_skin", d / f"{args.clip}_onion.png", 1600),
                              ("plots", d / f"{args.clip}_plots.png", 1600)]
                 + ([("stretch_detail", d / f"{args.clip}_stretch.png", 1600)] if (d / f"{args.clip}_stretch.png").exists() else []))
    packet["metrics"]["motion"] = {k: v for k, v in mm.items() if k != "series"}
    kind = mm.get("kind")
    if kind in ("death", "in_place"):
        assertion(packet, "root stays in place (horizontal hips travel)", mm["root_travel_max_m"] <= tol["motion_root_travel_m"],
                  mm["root_travel_max_m"], tol["motion_root_travel_m"], f"final offset {mm['root_travel_final_m']} m")
    # Action clips (attacks, rolls) pivot on planted feet on purpose, and a death's feet kick out as the
    # body collapses onto its pinned Hips (Death01 can't meet both limits: keeping 30% of its travel still
    # slid 0.80 m/s). Their slide is reported, not asserted; root travel is what catches a fling.
    if kind == "in_place" and mm.get("contact_frames"):
        assertion(packet, "planted feet don't slide", mm["foot_slide_p90_mps"] <= tol["motion_foot_slide_mps"],
                  mm["foot_slide_p90_mps"], tol["motion_foot_slide_mps"],
                  f"90th percentile ground-relative foot speed over {mm['contact_frames']} contact frames at ground speed {mm['ground_speed_mps']} m/s")
    assertion(packet, "vertex deviation from bind pose (Hips frame)", mm["bind_deviation_max_m"] <= tol["motion_bind_deviation_m"],
              mm["bind_deviation_max_m"], tol["motion_bind_deviation_m"], f"p99 {mm['bind_deviation_p99_m']} m; worst vertex on {mm.get('bind_deviation_worst_bone')}")
    assertion(packet, "skin stretch (edge length vs bind pose)", mm["edge_stretch_max"] <= tol["motion_edge_stretch"],
              mm["edge_stretch_max"], tol["motion_edge_stretch"], f"p99 {mm['edge_stretch_p99']}; worst edge on {mm.get('edge_stretch_worst_bone')}")


STAGE_PACKETS = {"concept": packet_concept, "multiview": packet_multiview, "model": packet_model, "mesh": packet_mesh, "motion": packet_motion}


def design_notes(asset_id):
    """Recorded design decisions the judge must not re-flag: the brief's 'Shipped design change' notes."""
    sec = brief_section(asset_id) or ""
    return [line.strip("- ").strip() for line in sec.splitlines() if "design change" in line.lower()]


def cmd_packet(args):
    brief = P.load_brief(args.asset_id)
    m = P.load_manifest(args.asset_id)
    tol = tolerances()
    stage_key = f"motion:{args.clip}" if args.stage == "motion" else args.stage
    base = base_dir(args.asset_id, args.replay)
    pdir = next_packet_dir(base, stage_key)
    pdir.mkdir(parents=True)
    log = load_log(args.asset_id, args.replay)
    pal = palette_hex()
    packet = {
        "asset_id": args.asset_id, "stage": stage_key, "created_at": P.now(), "replay": args.replay,
        "packet_dir": P.rel(pdir),
        "brief": {k: brief.get(k) for k in ("type", "brief", "prompt", "face_limit", "triangle_budget", "texture_size",
                                            "target_size_m", "pivot", "tip_end", "rigid_parts", "skirt_reweight",
                                            "source", "source_scale", "orientation")},
        "brief_palette": {n: {"hex": pal[n], "plain": P.art_bible_palette().get(n)} for n in brief["palette"]},
        "art_bible": {"brief_section": brief_section(args.asset_id, args.no_design_notes), "form_block": P.prompt_blocks()["form"],
                      "concept_lighting_block": P.prompt_blocks()["concept_lighting"],
                      "tolerances": art_bible_section("Judge tolerances")},
        # A replay of an input judged before a decision was made must not see that decision
        "design_notes": [] if args.no_design_notes else design_notes(args.asset_id),
        "images": [], "metrics": {}, "assertions": [],
        "questions": QUESTIONS[args.stage] + ([FACE_QUESTION] if brief["type"] == "character" and args.stage != "motion" else []),
        "escalate_rules": ESCALATE_RULES,
        "refine_budget": {"per_stage": AUTO_REFINES_PER_STAGE, "used": refines_used(log, stage_key)},
        "tool_versions": P.tool_versions(),
    }
    if P.is_sourced(brief):
        # Downloaded kit pieces: nothing was generated, so there's no concept; the prompt describes the piece
        packet["sourcing"] = {"note": "sourced, no concept: judge against the brief's prompt and palette",
                              "colors": "palette metrics cover only the texels this piece's UVs sample (on a shared "
                                        "atlas, not the whole atlas); correction may darken as well as lift",
                              "holes": "open boundary loops are allowed per part up to mesh_kit_max_loops_per_part, "
                                       "only where none is visible in the views: check the views for any gap",
                              **{k: brief.get(k) for k in ("pack", "source_url", "author", "license", "source_file")},
                              "orientation": P.orientation(brief), "pivot": brief.get("pivot"), "atlas": brief.get("atlas")}
    STAGE_PACKETS[args.stage](packet, pdir, brief, m, args, tol)
    failed = [a for a in packet["assertions"] if not a["passed"]]
    packet["assertions_failed"] = len(failed)
    (pdir / "packet.json").write_text(json.dumps(packet, indent=2) + "\n")
    print(f"packet: {P.rel(pdir / 'packet.json')} ({len(packet['images'])} images, "
          f"{len(packet['assertions'])} assertions, {len(failed)} failed)")
    for a in failed:
        print(f"  FAIL {a['name']}: {a['value']} (limit {a['limit']}) {a['detail']}")
    print(f"next: spawn the asset-judge subagent on {P.rel(pdir / 'packet.json')}, save its JSON reply to "
          f"{P.rel(pdir / 'verdict.json')}, then run: python3 scripts/judge.py record {P.rel(pdir)} {P.rel(pdir / 'verdict.json')}")
    return 0


# ── Verdicts ──────────────────────────────────────────────────────────────────

def parse_verdict(text):
    """The judge's reply, tolerating a ```json fence around it."""
    m = re.search(r"\{.*\}", text, re.S)
    if not m:
        raise JudgeError("the verdict holds no JSON object")
    v = json.loads(m.group(0))
    # A subagent's hand-back can wrap the reply in an envelope ({"message": "<the JSON as a string>"})
    while "verdict" not in v and len(v) == 1 and isinstance(next(iter(v.values())), str):
        inner = re.search(r"\{.*\}", next(iter(v.values())), re.S)
        if not inner:
            break
        v = json.loads(inner.group(0))
    errs = []
    if v.get("verdict") not in VERDICTS:
        errs.append(f"verdict must be one of {VERDICTS}")
    if not isinstance(v.get("findings"), list):
        errs.append("findings must be a list")
    for i, f in enumerate(v.get("findings") or []):
        if f.get("check") not in CHECKS:
            errs.append(f"findings[{i}].check must be one of {CHECKS}")
        if f.get("severity") not in SEVERITIES:
            errs.append(f"findings[{i}].severity must be one of {SEVERITIES}")
        if not f.get("observation") or not f.get("evidence"):
            errs.append(f"findings[{i}] needs observation and evidence")
    if v.get("verdict") == "revise":
        r = v.get("revise") or {}
        if r.get("action") not in REVISE_ACTIONS:
            errs.append(f"revise.action must be one of {REVISE_ACTIONS}")
        if r.get("action") != "reroll" and not r.get("edit_prompt"):
            errs.append("revise.edit_prompt is required unless the action is reroll")
    if v.get("verdict") == "escalate" and not v.get("escalation_reason"):
        errs.append("escalate needs escalation_reason")
    if not isinstance(v.get("images_seen"), list):
        errs.append("images_seen must list the packet images the judge read")
    if errs:
        raise JudgeError("invalid verdict:\n  - " + "\n  - ".join(errs))
    return v


def next_action(packet, final, v):
    aid, stage = packet["asset_id"], packet["stage"]
    if final == "pass":
        return "proceed to the next stage"
    if final == "escalate":
        return "surface to the user: the escalation reason and findings"
    r = v["revise"]
    if r["action"] == "refine_concept":
        n = (packet.get("refine_hint") or {}).get("refine_of") or "<approved concept n>"
        return ("paid (confirm with the user through the tripo skill): python3 scripts/pipeline.py "
                f"{aid} --stage concept --refine {n} --edit {shlex.quote(r['edit_prompt'])}")
    if r["action"] == "reroll":
        return f"paid (confirm with the user through the tripo skill): mark the {stage} attempt rejected and re-run the {stage} stage"
    return f"free: apply the library change, rebuild (scripts/tools/build_animation_library.gd), re-run the motion review: {r['edit_prompt']}"


def cmd_record(args):
    pdir = Path(args.packet_dir).resolve()
    packet = json.loads((pdir / "packet.json").read_text())
    text = Path(args.verdict).read_text() if args.verdict != "-" else sys.stdin.read()
    v = parse_verdict(text)
    (pdir / "verdict.json").write_text(json.dumps(v, indent=2) + "\n")
    aid, replay, stage = packet["asset_id"], packet.get("replay"), packet["stage"]
    log = load_log(aid, replay)
    used = refines_used(log, stage)
    final, override = v["verdict"], None
    failed = [a["name"] for a in packet["assertions"] if not a["passed"]]
    if v["verdict"] == "pass" and failed:
        final, override = "escalate", f"the judge passed an asset with failing numeric assertions: {failed}"
    elif v["verdict"] == "revise" and used >= AUTO_REFINES_PER_STAGE:
        final, override = "escalate", f"refine budget spent ({used} of {AUTO_REFINES_PER_STAGE} auto-refine for {stage}); escalating regardless"
    packet_images = {i["path"] for i in packet["images"]}
    unseen = sorted(packet_images - {str(p) for p in v["images_seen"]})
    action = {"pass": "proceed", "revise": "auto_refine", "escalate": "escalate"}[final]
    entry = {"kind": "verdict", "stage": stage, "recorded_at": P.now(), "packet": P.rel(pdir / "packet.json"),
             "packet_sha256": P.sha256(pdir / "packet.json"), "subject": packet.get("subject"),
             "images": [{"role": i["role"], "path": i["path"], "sha256": i["sha256"], "source": i["source"]} for i in packet["images"]],
             "images_unseen": unseen, "assertions_failed": failed,
             "judge_verdict": v["verdict"], "verdict": final, "override": override, "action": action,
             "findings": v["findings"], "revise": v.get("revise"), "escalation_reason": override or v.get("escalation_reason"),
             "summary": v.get("summary"), "next": next_action(packet, final, v)}
    log.setdefault("judgments", []).append(entry)
    save_log(aid, replay, log)
    print(f"verdict: {final}" + (f" (judge said {v['verdict']}: {override})" if override else ""))
    if unseen:
        print(f"warning: the judge didn't report reading {unseen}")
    for f in v["findings"]:
        print(f"  [{f['severity']}] {f['check']}: {f['observation']}")
    print(f"next: {entry['next']}")
    return {"pass": 0, "revise": EXIT_REVISE, "escalate": EXIT_ESCALATE}[final]


def cmd_resolve(args):
    log = load_log(args.asset_id, args.replay)
    log.setdefault("judgments", []).append({"kind": "resolution", "stage": args.stage, "recorded_at": P.now(), "decision": args.decision})
    save_log(args.asset_id, args.replay, log)
    print(f"resolved {args.stage}: {args.decision} (refine budget reset)")
    return 0


def cmd_log(args):
    for j in load_log(args.asset_id, args.replay).get("judgments", []):
        if j["kind"] == "resolution":
            print(f"{j['recorded_at']} {j['stage']:<14} RESOLVED: {j['decision']}")
        else:
            print(f"{j['recorded_at']} {j['stage']:<14} {j['verdict'].upper():<9} {len(j['findings'])} findings  {j['packet']}")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("packet")
    p.add_argument("asset_id")
    p.add_argument("--stage", required=True, choices=sorted(STAGE_PACKETS))
    p.add_argument("--subject", help="concept stage: concept attempt N or an image path (default: newest usable)")
    p.add_argument("--input", help="model stage: a GLB to judge instead of the newest usable download")
    p.add_argument("--concept", help="reference concept image instead of the approved one, or 'none'")
    p.add_argument("--clip", help="motion stage: the clip name")
    p.add_argument("--motion-dir", help="motion stage: the motion review's output directory")
    p.add_argument("--no-design-notes", action="store_true",
                   help="leave out the brief's recorded design decisions (replaying an input judged before they were made)")
    p.add_argument("--replay", help="judge historical inputs; packets and log go to assets/manifests/judge_replays/NAME/")
    r = sub.add_parser("record")
    r.add_argument("packet_dir")
    r.add_argument("verdict", help="the judge's JSON reply (a file, or - for stdin)")
    s = sub.add_parser("resolve")
    s.add_argument("asset_id")
    s.add_argument("--stage", required=True)
    s.add_argument("--decision", required=True)
    s.add_argument("--replay")
    lg = sub.add_parser("log")
    lg.add_argument("asset_id")
    lg.add_argument("--replay")
    args = ap.parse_args()
    try:
        return {"packet": cmd_packet, "record": cmd_record, "resolve": cmd_resolve, "log": cmd_log}[args.cmd](args)
    except (JudgeError, P.PipelineError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
