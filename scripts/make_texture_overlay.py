"""Draws a small texture overlay (e.g. a mouth line) in a mesh's UV space. Runs inside headless Blender:

    blender -b --factory-startup --python-exit-code 1 -P scripts/make_texture_overlay.py -- \
        --glb assets/meshes/player.glb --uv-source <the clean stage's input GLB> \
        --out assets/overlays/player_mouth.png --size 256 \
        --stroke-z 1.48 --half-width 0.02 --thickness 1.5 --color "#4A2A2A" --alpha 0.9

Casts rays at the model's front (it faces -Y after cleanup) along a horizontal stroke at stroke-z,
maps each hit to UV, and paints an anti-aliased line into a transparent PNG of the texture's size.
The clean stage composites it over the albedo after color correction (brief: texture_overlays).

The overlay only fits the UV layout it was drawn on, so a sidecar <out>.json records the SHA-256
of --uv-source (the clean stage's input); the clean stage refuses to composite onto anything else.
Deterministic: the same inputs always produce the same PNG.
"""

import argparse
import hashlib
import json
import math
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

SAMPLES = 64


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    for name in ("--glb", "--uv-source", "--out"):
        ap.add_argument(name, required=True)
    ap.add_argument("--size", type=int, required=True)
    ap.add_argument("--stroke-z", type=float, required=True)
    ap.add_argument("--half-width", type=float, required=True)
    ap.add_argument("--thickness", type=float, default=1.5, help="line thickness in texture pixels")
    ap.add_argument("--color", default="#4A2A2A")
    ap.add_argument("--alpha", type=float, default=0.9)
    return ap.parse_args(argv)


def main():
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args.glb)
    ob = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    me = ob.data
    me.calc_loop_triangles()
    verts = [ob.matrix_world @ v.co for v in me.vertices]
    tris = [tuple(t.vertices) for t in me.loop_triangles]
    bvh = BVHTree.FromPolygons(verts, tris)
    uv = me.uv_layers.active.data
    uvs = []
    for i in range(SAMPLES):
        x = -args.half_width + 2 * args.half_width * i / (SAMPLES - 1)
        hit, _, tri_i, _ = bvh.ray_cast(Vector((x, -5.0, args.stroke_z)), Vector((0, 1, 0)))
        if hit is None:
            raise SystemExit(f"no surface at x={x:.3f}, z={args.stroke_z}")
        t = me.loop_triangles[tri_i]
        a, b, c = (verts[v] for v in t.vertices)
        # Barycentric weights of the hit, then the same blend of the triangle's corner UVs
        v0, v1, v2 = b - a, c - a, hit - a
        d00, d01, d11, d20, d21 = v0.dot(v0), v0.dot(v1), v1.dot(v1), v2.dot(v0), v2.dot(v1)
        den = d00 * d11 - d01 * d01
        wb, wc = (d11 * d20 - d01 * d21) / den, (d00 * d21 - d01 * d20) / den
        wa = 1 - wb - wc
        la, lb, lc = (uv[l].uv for l in t.loops)
        uvs.append((wa * la.x + wb * lb.x + wc * lc.x, wa * la.y + wb * lb.y + wc * lc.y))
    n = args.size
    rgb = [int(args.color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    canvas = np.zeros((n, n, 4))
    yy, xx = np.mgrid[0:n, 0:n] + 0.5
    pts = [(u * n, v * n) for u, v in uvs]
    dist = np.full((n, n), np.inf)
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if math.hypot(x1 - x0, y1 - y0) > n * 0.05:
            continue  # the stroke crossed a UV seam; don't draw across the atlas
        dx, dy = x1 - x0, y1 - y0
        t = np.clip(((xx - x0) * dx + (yy - y0) * dy) / max(dx * dx + dy * dy, 1e-9), 0, 1)
        dist = np.minimum(dist, np.hypot(xx - (x0 + t * dx), yy - (y0 + t * dy)))
    cover = np.clip(args.thickness / 2 + 0.5 - dist, 0, 1)
    canvas[..., :3] = rgb
    canvas[..., 3] = cover * args.alpha
    img = bpy.data.images.new("overlay", n, n, alpha=True)
    img.pixels[:] = canvas.ravel().tolist()  # rows bottom-up, the same as UV v
    img.filepath_raw = args.out
    img.file_format = "PNG"
    img.save()
    sha = hashlib.sha256(open(args.uv_source, "rb").read()).hexdigest()
    span = [[round(min(p[k] for p in uvs), 4), round(max(p[k] for p in uvs), 4)] for k in (0, 1)]
    json.dump({"uv_source_sha256": sha, "uv_source": args.uv_source, "size": n, "stroke_z": args.stroke_z,
               "half_width": args.half_width, "thickness_px": args.thickness, "color": args.color, "alpha": args.alpha,
               "uv_span": span, "covered_pixels": int((cover > 0).sum())},
              open(args.out.rsplit(".", 1)[0] + ".json", "w"), indent=2)
    print(f"OVERLAY {args.out}: uv span {span}, {int((cover > 0).sum())} pixels")


if __name__ == "__main__":
    main()
