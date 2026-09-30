#!/usr/bin/env python3
"""Run the pipeline's Godot validate check on every committed asset (CI; no Blender, no writes).

    python3 ci/validate_assets.py [asset-id ...]

For each brief in assets/briefs/ whose GLB is in assets/meshes/, this makes the same Godot call as
`scripts/pipeline.py <id> --stage validate` (same params, built by pipeline.stage_params, and the
clean stage's triangle count from the committed manifest), but skips the Blender review renders and
never writes the manifest: CI checks the committed assets, it doesn't re-record them.
Exit code: 0 all pass, 2 any validate failure, 1 usage or tool error.
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import pipeline  # noqa: E402


def validate(asset_id, tmp):
    brief = pipeline.load_brief(asset_id)
    glb = pipeline.MESHES / f"{asset_id}.glb"
    if not glb.exists():
        print(f"validate: {asset_id}: SKIP, no {pipeline.rel(glb)} yet (asset not cleaned)")
        return True
    m = pipeline.load_manifest(asset_id)
    params = pipeline.stage_params(brief)
    params["blender_triangle_count"] = (m["stages"].get("clean", {}).get("report") or {}).get("triangle_count")
    params_path, report_path = tmp / f"{asset_id}-params.json", tmp / f"{asset_id}-report.json"
    params_path.write_text(json.dumps(params, indent=2))
    cmd = [pipeline.GODOT, "--headless", "--path", ROOT, "-s", pipeline.GODOT_SCRIPT, "--",
           "--glb", glb, "--params", params_path, "--report", report_path]
    print(f"validate: {asset_id}: " + " ".join(str(c) for c in cmd), flush=True)
    proc = subprocess.run([str(c) for c in cmd], capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if not report_path.exists():
        print(proc.stdout + proc.stderr)
        raise pipeline.PipelineError(f"{asset_id}: godot_validate.gd wrote no report (exit {proc.returncode})")
    report = json.loads(report_path.read_text())
    passed = report.get("status") == "pass"
    for w in report.get("warnings", []):
        print(f"validate: {asset_id}: warning: {w}")
    for e in report.get("errors", []):
        print(f"::error::validate {asset_id}: {e}")
    print(f"validate: {asset_id}: {'PASS' if passed else 'FAIL'}"
          + (f" ({report.get('triangle_count')} triangles)" if "triangle_count" in report else ""))
    return passed


def main():
    ids = sys.argv[1:] or sorted(p.stem for p in pipeline.BRIEFS.glob("*.yaml"))
    try:
        with tempfile.TemporaryDirectory() as d:
            results = {aid: validate(aid, Path(d)) for aid in ids}
    except pipeline.PipelineError as e:
        print(f"::error::{e}")
        return 1
    failed = [a for a, ok in results.items() if not ok]
    print(f"validate: {len(results) - len(failed)}/{len(results)} passed" + (f"; failed: {', '.join(failed)}" if failed else ""))
    return 2 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
