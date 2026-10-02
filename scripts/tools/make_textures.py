#!/usr/bin/env python3
"""Tileable level-surface textures from Material Maker graphs (Phase B trial B3, docs/trials/material-maker.md).

    python3 scripts/tools/make_textures.py [NAME ...]     # regenerate (Mac, Material Maker + Godot)
    python3 scripts/tools/make_textures.py --check        # verify only (stdlib Python; runs anywhere, CI included)

Sources are committed in assets/textures/src/: one small text graph (<name>.ptex) per texture, and
textures.json, which names each texture's palette ramp (art-bible palette names, dark to light), its size
and ramp_steps, plus the pinned Material Maker release. Regenerating:
  1. Material Maker's command line (`--export`) renders each graph's Export node (suffix "albedo") at
     2048 px into the gitignored .tools/work/textures/. Only that one albedo image is exported: the graphs
     have no Material node, so there are no normal, roughness, metallic or height maps to discard.
  2. scripts/tools/palette_lock_textures.gd (headless Godot) box-filters it to the size and snaps every
     texel to the ramp, then measures CIE76 dE before and after.
  3. This script writes assets/textures/surfaces/<name>.png (GENERATED: only this script writes them) and
     assets/textures/surfaces/manifest.json (hashes of the graph, ramp, output file and pixels, plus the dE stats).
  4. Each PNG's .import is seeded lossless, with mipmaps and 3D detection off (scripts/tools/texture_imports.py,
     docs/trials/material-maker.md decision 6), and a headless import completes any it changed, so the
     editor never rewrites them.

--check needs neither tool: the graphs, the ramp colours in docs/art-bible.md and the PNGs must still match
the manifest, and every colorize stop in a graph must be one of its ramp's palette colours.

Material Maker comes from $MATERIAL_MAKER (the .app), else .tools/material-maker-<release>/Material Maker.app
in this checkout. It needs a logged-in macOS session: its renderer opens a window (`--headless` crashes,
exit 139). Godot comes from $GODOT_BIN, else /Applications/Godot.app.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import godot_timeout  # noqa: E402
import texture_imports  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/textures/src"
OUT = ROOT / "assets/textures/surfaces"
MANIFEST = OUT / "manifest.json"
WORK = ROOT / ".tools/work/textures"
ART_BIBLE = ROOT / "docs/art-bible.md"
LOCK_SCRIPT = "res://scripts/tools/palette_lock_textures.gd"
PALETTE_HEX = re.compile(r"^\| ([A-Z][A-Za-z ]+?) \| `(#[0-9A-Fa-f]{6})` \|", re.M)  # as scripts/pipeline.py


class Fail(Exception):
    pass


def run_limited(cmd, label, **kwargs):
    """Material Maker (a Godot app) and the palette lock under GODOT_TIMEOUT_RUN (scripts/tools/godot_timeout.py)."""
    try:
        return godot_timeout.run(cmd, label, "GODOT_TIMEOUT_RUN", 600, **kwargs)
    except godot_timeout.ToolTimeout as e:
        raise Fail(str(e)) from None


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def rgb(hex_):
    return [int(hex_[i:i + 2], 16) for i in (1, 3, 5)]


def load_config():
    cfg = json.loads((SRC / "textures.json").read_text())
    palette = dict(PALETTE_HEX.findall(ART_BIBLE.read_text()))
    for name, t in cfg["textures"].items():
        unknown = [c for c in t["ramp"] if c not in palette]
        if unknown:
            raise Fail(f"{name}: ramp colours not in docs/art-bible.md: {unknown}")
        t["ramp_hex"] = {c: palette[c].upper() for c in t["ramp"]}
    return cfg


def graph_stops(graph_path):
    """Every colorize gradient stop in a graph, as 8-bit sRGB."""
    graph = json.loads(Path(graph_path).read_text())
    stops = []
    for node in graph["nodes"]:
        if node["type"] == "colorize":
            for p in node["parameters"]["gradient"]["points"]:
                stops.append((node["name"], [round(p[k] * 255) for k in ("r", "g", "b")]))
    return stops


def check_graph(name, t):
    """A graph's colours must come from its ramp: the lock step snaps to it anyway, but a stop that isn't
    a palette colour means the graph and the art bible have drifted apart."""
    allowed = {tuple(rgb(h)): c for c, h in t["ramp_hex"].items()}
    errs = [f"{name}: {node} stop {c} is not a ramp colour ({', '.join(t['ramp'])})"
            for node, c in graph_stops(SRC / t["graph"]) if tuple(c) not in allowed]
    if not graph_stops(SRC / t["graph"]):
        errs.append(f"{name}: graph has no colorize node")
    return errs


def material_maker(cfg):
    app = os.environ.get("MATERIAL_MAKER") or str(ROOT / f".tools/material-maker-{cfg['release']}/Material Maker.app")
    exe = Path(app) / "Contents/MacOS/Material Maker"
    pck = Path(app) / "Contents/Resources/Material Maker.pck"
    if not exe.exists():
        raise Fail(f"Material Maker not found at {app}: download {cfg['asset']} from "
                   f"https://github.com/RodZill4/material-maker/releases/tag/{cfg['release']} "
                   f"(SHA-256 {cfg['asset_sha256']}) and copy the app there, or set $MATERIAL_MAKER")
    if sha256(pck) != cfg["pck_sha256"]:
        raise Fail(f"{pck} is not the pinned {cfg['release']} build (pck SHA-256 differs)")
    return exe


def regenerate(cfg, names):
    mm = material_maker(cfg["material_maker"])
    godot = os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot")
    errs = [e for n in names for e in check_graph(n, cfg["textures"][n])]
    if errs:
        raise Fail("\n".join(errs))
    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)
    OUT.mkdir(parents=True, exist_ok=True)
    timings = {}

    t0 = time.monotonic()
    graphs = [str(SRC / cfg["textures"][n]["graph"]) for n in names]
    log = WORK / "material_maker.log"
    with log.open("w") as fh:
        code = run_limited([mm, "--export", "-o", WORK, *graphs], "Material Maker export", stdout=fh,
                           stderr=subprocess.STDOUT).returncode
    timings["material_maker_s"] = round(time.monotonic() - t0, 2)
    missing = [n for n in names if not (WORK / f"{Path(cfg['textures'][n]['graph']).stem}_albedo.png").exists()]
    if code != 0 or missing:
        raise Fail(f"Material Maker export failed (exit {code}, missing {missing}); see {log}")

    jobs = []
    for n in names:
        t = cfg["textures"][n]
        jobs.append({"name": n, "in": str(WORK / f"{Path(t['graph']).stem}_albedo.png"), "out": str(OUT / f"{n}.png"),
                     "size": t["size"], "ramp_steps": t["ramp_steps"], "ramp": [rgb(t["ramp_hex"][c]) for c in t["ramp"]],
                     "palette": {c: rgb(t["ramp_hex"][c]) for c in t["ramp"]}})
    job_path, report_path = WORK / "job.json", WORK / "report.json"
    job_path.write_text(json.dumps({"textures": jobs, "report": str(report_path)}, indent=1))
    t0 = time.monotonic()
    proc = run_limited([godot, "--headless", "--path", ROOT, "-s", LOCK_SCRIPT, "--", "--job", job_path], "palette lock",
                       capture_output=True, text=True)
    timings["palette_lock_s"] = round(time.monotonic() - t0, 2)
    if proc.returncode != 0 or not report_path.exists():
        raise Fail(f"palette lock failed (exit {proc.returncode}):\n{proc.stdout[-2000:]}{proc.stderr[-2000:]}")
    report = {r["name"]: r for r in json.loads(report_path.read_text())["textures"]}

    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {"textures": {}}
    manifest["generator"] = "scripts/tools/make_textures.py"
    manifest["material_maker"] = cfg["material_maker"]["release"]
    manifest["lock_script_sha256"] = sha256(ROOT / "scripts/tools/palette_lock_textures.gd")
    for n in names:
        t, r = cfg["textures"][n], report[n]
        manifest["textures"][n] = {
            "graph": f"assets/textures/src/{t['graph']}", "graph_sha256": sha256(SRC / t["graph"]),
            "ramp": t["ramp_hex"], "ramp_steps": t["ramp_steps"], "size": t["size"],
            "png": f"assets/textures/surfaces/{n}.png", "png_sha256": sha256(OUT / f"{n}.png"),
            "pixels_sha256": r["pixels_sha256"], "material_maker_export_sha256": sha256(jobs[names.index(n)]["in"]),
            "distinct_colours": r["distinct_colours"], "ramp_entries": r["ramp_entries"],
            "de_before_lock": r["before"], "de_after_lock": r["after"],
        }
    manifest["textures"] = dict(sorted(manifest["textures"].items()))
    MANIFEST.write_text(json.dumps(manifest, indent=1) + "\n")
    if [n for n in names if texture_imports.seed(OUT / f"{n}.png", "lossless")]:
        t0 = time.monotonic()
        texture_imports.godot_import(godot, ROOT)
        timings["import_s"] = round(time.monotonic() - t0, 2)
    timings["total_s"] = round(sum(timings.values()), 2)
    for n in names:
        m = manifest["textures"][n]
        groups = ", ".join(f"{g['palette']} {g['share']:.0%} dE {g.get('median_de', '-')}" for g in m["de_after_lock"]["groups"])
        print(f"{n}: {m['size']}px, {m['distinct_colours']} colours; ramp dE before lock median "
              f"{m['de_before_lock']['ramp_de_median']} p95 {m['de_before_lock']['ramp_de_p95']}, after "
              f"{m['de_after_lock']['ramp_de_max']} max; groups after: {groups}")
    print("timings:", json.dumps(timings))
    return timings


def check(cfg):
    if not MANIFEST.exists():
        raise Fail(f"{MANIFEST} missing: run scripts/tools/make_textures.py")
    manifest = json.loads(MANIFEST.read_text())
    errs = []
    if manifest.get("material_maker") != cfg["material_maker"]["release"]:
        errs.append(f"manifest was made with Material Maker {manifest.get('material_maker')}, "
                    f"textures.json pins {cfg['material_maker']['release']}")
    if manifest.get("lock_script_sha256") != sha256(ROOT / "scripts/tools/palette_lock_textures.gd"):
        errs.append("scripts/tools/palette_lock_textures.gd changed since the textures were made")
    for n, t in cfg["textures"].items():
        m = manifest["textures"].get(n)
        if m is None:
            errs.append(f"{n}: not in the manifest (never generated)")
            continue
        errs += check_graph(n, t)
        for label, want, got in (("graph", m["graph_sha256"], sha256(SRC / t["graph"])),
                                 ("ramp", m["ramp"], t["ramp_hex"]), ("size", m["size"], t["size"]),
                                 ("ramp_steps", m["ramp_steps"], t["ramp_steps"])):
            if want != got:
                errs.append(f"{n}: {label} changed since it was generated (stale texture)")
        png = OUT / f"{n}.png"
        if not png.exists() or sha256(png) != m["png_sha256"]:
            errs.append(f"{n}: {png.relative_to(ROOT)} differs from the manifest (edited by hand?)")
    stray = {p.stem for p in OUT.glob("*.png")} - set(cfg["textures"])
    errs += [f"{s}.png: not made by make_textures.py" for s in sorted(stray)]
    if errs:
        raise Fail("\n".join(errs))
    print(f"make_textures --check: {len(cfg['textures'])} textures match their graphs, ramps and manifest")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*", help="textures to regenerate (default: all)")
    ap.add_argument("--check", action="store_true", help="verify only; needs neither Material Maker nor Godot")
    args = ap.parse_args()
    try:
        cfg = load_config()
        if args.check:
            check(cfg)
        else:
            names = args.names or list(cfg["textures"])
            unknown = [n for n in names if n not in cfg["textures"]]
            if unknown:
                raise Fail(f"unknown textures {unknown}; textures.json has {list(cfg['textures'])}")
            regenerate(cfg, names)
    except Fail as e:
        print(f"make_textures: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
