"""Stage 4 (validate) review renders for scripts/pipeline.py. Runs inside headless Blender:

    blender -b --factory-startup --python-exit-code 1 -P scripts/blender_views.py -- \
        --input asset.glb --outdir assets/manifests/<asset-id> --report views.json

Renders four orthographic views (front, right, back, top) with the albedo texture in its true
colors, plus a grey clay front (form only) and a front wireframe, using the Workbench engine
(offline, no API calls). The textured views are the ones to judge: clay exaggerates rounded form
and hides the flat color blocking. It reports how much of
each frame the asset covers and how many separate pieces the welded mesh has. The renders
are for a human to read; nothing here fails or repairs anything.
"""

import argparse
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

SIZE = 512
VIEWS = {
    # name: (camera direction from the asset's center, camera rotation in degrees)
    "front": (Vector((0, -1, 0)), (90, 0, 0)),
    "right": (Vector((1, 0, 0)), (90, 0, 90)),
    "back": (Vector((0, 1, 0)), (90, 0, 180)),
    "top": (Vector((0, 0, 1)), (0, 0, 0)),
}


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--report", required=True)
    ap.add_argument("--closeups", action="store_true",
                    help="also render closeup_front/closeup_back of the top 42%% (head and chest; for the judge)")
    return ap.parse_args(argv)


def pieces(meshes):
    """Connected pieces after welding at 0.01 mm (seam splits merged back)."""
    total = 0
    for o in meshes:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
        seen = set()
        for f in bm.faces:
            if f.index in seen:
                continue
            total += 1
            stack = [f]
            seen.add(f.index)
            while stack:
                cur = stack.pop()
                for e in cur.edges:
                    for nf in e.link_faces:
                        if nf.index not in seen:
                            seen.add(nf.index)
                            stack.append(nf)
        bm.free()
    return total


def coverage(path):
    img = bpy.data.images.load(path)
    alpha = tuple(img.pixels)[3::4]  # bpy arrays don't support stepped slices
    frac = sum(1 for a in alpha if a > 0.5) / len(alpha)
    bpy.data.images.remove(img)
    return round(frac, 4)


def main():
    args = parse_args()
    report = {"status": "ok", "views": {}, "errors": []}
    try:
        render(args, report)
    except Exception as e:  # report every failure to pipeline.py
        report["status"] = "error"
        report["errors"].append(f"{type(e).__name__}: {e}")
    with open(args.report, "w") as f:
        json.dump(report, f, indent=2)


def render(args, report):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args.input)
    shapes = set()  # the importer's bone display shapes, shared between bones
    for o in list(bpy.context.scene.objects):
        if o.type == "ARMATURE":
            o.data.pose_position = "REST"
            for pb in o.pose.bones:
                if pb.custom_shape:
                    shapes.add(pb.custom_shape)
                    pb.custom_shape = None
    for shape in shapes:
        bpy.data.objects.remove(shape, do_unlink=True)
    bpy.context.view_layer.update()
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        report["triangles"] = 0
        return
    report["triangles"] = sum(p.loop_total - 2 for o in meshes for p in o.data.polygons)
    report["pieces_welded"] = pieces(meshes)

    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        ev = o.evaluated_get(dg)
        pts.extend(o.matrix_world @ v.co for v in ev.to_mesh().vertices)
        ev.to_mesh_clear()
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    center, dims = (mn + mx) / 2, mx - mn
    reach = max(dims) * 3 + 1

    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_WORKBENCH"
    except TypeError as e:
        raise RuntimeError(f"Workbench engine unavailable: {e}")
    scene.render.resolution_x = scene.render.resolution_y = SIZE
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    # Standard, not the default AgX: AgX desaturates and darkens the albedo until it reads as clay
    try:
        scene.view_settings.view_transform = "Standard"
    except TypeError as e:
        raise RuntimeError(f"Standard view transform unavailable: {e}")
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.show_specular_highlight = False  # the game material has none either
    shading.color_type = "TEXTURE"

    cam_data = bpy.data.cameras.new("review")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("review", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam_data.clip_end = reach * 2
    os.makedirs(args.outdir, exist_ok=True)

    def shoot(name, direction, rot):
        # Frame the two dimensions visible from this direction, with a 10% margin
        visible = [dims[i] for i in range(3) if abs(direction[i]) < 0.5]
        cam_data.ortho_scale = max(visible) * 1.1
        cam.location = center + direction * reach
        cam.rotation_euler = [math.radians(a) for a in rot]
        path = os.path.join(args.outdir, f"{name}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        report["views"][name] = {"path": path, "coverage": coverage(path)}

    for name, (direction, rot) in VIEWS.items():
        shoot(name, direction, rot)

    if args.closeups:
        # Head and chest at about 3x the full view's scale: face-sized defects (a lost mouth, skin
        # showing through clothing) are a few pixels in the full-height views
        top = mx.z - dims.z * 0.21
        for name in ("front", "back"):
            direction, rot = VIEWS[name]
            cam_data.ortho_scale = dims.z * 0.42
            cam.location = Vector((center.x, center.y, top)) + direction * reach
            cam.rotation_euler = [math.radians(a) for a in rot]
            path = os.path.join(args.outdir, f"closeup_{name}.png")
            scene.render.filepath = path
            bpy.ops.render.render(write_still=True)
            report["views"][f"closeup_{name}"] = {"path": path, "coverage": coverage(path)}

    # Clay: one flat grey front for reading form only
    shading.color_type = "SINGLE"
    shading.single_color = (0.6, 0.6, 0.6)
    direction, rot = VIEWS["front"]
    shoot("clay_front", direction, rot)

    # Wireframe: replace the surfaces with thin edge geometry, drawn in one flat color
    for o in meshes:
        mod = o.modifiers.new("review_wire", "WIREFRAME")
        mod.thickness = max(dims) * 0.0025
        mod.use_replace = True
    shading.color_type = "SINGLE"
    shading.single_color = (0.08, 0.08, 0.1)
    shading.light = "FLAT"
    direction, rot = VIEWS["front"]
    shoot("wireframe_front", direction, rot)


if __name__ == "__main__":
    main()
