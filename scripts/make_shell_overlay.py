"""Paints a texture overlay over part of a shell (e.g. the tops of P2's leg shells, which Tripo painted
in skin tones where the tunic hides them at bind, so bare skin showed in the tunic slit). Runs inside
headless Blender:

    blender -b --factory-startup --python-exit-code 1 -P scripts/make_shell_overlay.py -- \
        --glb assets/meshes/player_p2parts.glb --uv-source <the clean stage's input GLB> \
        --out assets/overlays/player_p2parts_leg_tops.png --size 256 \
        --ranks 3,4 --above 0.58 --sample 0.45,0.57

Shells are the welded connected pieces ranked by triangles (1 = most), the same ranking as the brief's
`parts`. The faces of the --ranks shells whose centre sits at or above --above (metres, the cleaned
character's height axis) are painted, over their UV footprint plus a 1-texel margin, in one colour: the
median texel colour of the same shells' faces between the two --sample heights (the visible cloth below,
e.g. the trousers under the hem). The clean stage composites the overlay over the albedo after colour
correction (brief: texture_overlays), so the colour is sampled from the cleaned GLB.

Like make_texture_overlay.py, the overlay only fits the UV layout it was drawn on: a sidecar <out>.json
records the SHA-256 of --uv-source, and the clean stage refuses to composite onto anything else.
Deterministic: the same inputs always produce the same PNG.
"""

import argparse
import hashlib
import json
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blender_cleanup import _copy_faces, _shells, uv_footprint  # noqa: E402


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    for name in ("--glb", "--uv-source", "--out", "--ranks", "--sample"):
        ap.add_argument(name, required=True)
    ap.add_argument("--size", type=int, required=True)
    ap.add_argument("--above", type=float, required=True, help="paint faces whose centre is at or above this height (m)")
    return ap.parse_args(argv)


def _dilate(mask):
    out = mask.copy()
    out[1:, :] |= mask[:-1, :]
    out[:-1, :] |= mask[1:, :]
    out[:, 1:] |= mask[:, :-1]
    out[:, :-1] |= mask[:, 1:]
    return out


def main():
    args = parse_args()
    ranks = [int(r) for r in args.ranks.split(",")]
    lo, hi = (float(x) for x in args.sample.split(","))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args.glb)
    for a in (o for o in bpy.context.scene.objects if o.type == "ARMATURE"):
        a.data.pose_position = "REST"
    bpy.context.view_layer.update()
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    shells = [sh for sh in _shells(meshes) if sh["rank"] in ranks]
    if len(shells) != len(ranks):
        raise SystemExit(f"ranks {ranks}: the mesh has only {len(_shells(meshes))} shells")
    tex = next(n.image for o in meshes for s in o.material_slots if s.material and s.material.use_nodes
               for n in s.material.node_tree.nodes if n.type == "TEX_IMAGE" and n.image)
    w, h = tex.size
    px = np.array(tex.pixels[:], dtype=np.float64).reshape(-1, tex.channels)[:, :3]
    n = args.size
    paint = np.zeros(n * n, dtype=bool)
    sample = np.zeros(w * h, dtype=bool)
    faces = 0
    for sh in shells:
        o = sh["mesh"]
        z = {f: (o.matrix_world @ o.data.polygons[f].center).z for f in sh["faces"]}
        top = [f for f in sh["faces"] if z[f] >= args.above]
        cloth = [f for f in sh["faces"] if lo <= z[f] <= hi]
        faces += len(top)
        for fs, mask, size in ((top, paint, (n, n)), (cloth, sample, (w, h))):
            if fs:
                part = _copy_faces(o, fs, "_part")
                mask |= uv_footprint([part], *size)
                bpy.data.objects.remove(part, do_unlink=True)
    if not paint.any() or not sample.any():
        raise SystemExit("nothing to paint, or nothing to sample the colour from")
    rgb = np.median(px[sample], axis=0)
    paint = _dilate(paint.reshape(n, n))
    canvas = np.zeros((n, n, 4))
    canvas[..., :3] = rgb
    canvas[..., 3] = paint.astype(np.float64)
    img = bpy.data.images.new("overlay", n, n, alpha=True)
    img.pixels[:] = canvas.ravel().tolist()  # rows bottom-up, the same as UV v
    img.filepath_raw = args.out
    img.file_format = "PNG"
    img.save()
    color = "#%02X%02X%02X" % tuple(int(round(c * 255)) for c in rgb)
    sha = hashlib.sha256(open(args.uv_source, "rb").read()).hexdigest()
    json.dump({"uv_source_sha256": sha, "uv_source": args.uv_source, "size": n, "ranks": ranks, "above_m": args.above,
               "sample_m": [lo, hi], "color": color, "faces": faces, "covered_pixels": int(paint.sum())},
              open(args.out.rsplit(".", 1)[0] + ".json", "w"), indent=2)
    print(f"OVERLAY {args.out}: {faces} faces, {int(paint.sum())} pixels in {color}")


if __name__ == "__main__":
    main()
