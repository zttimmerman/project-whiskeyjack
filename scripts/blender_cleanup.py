"""Stage 3 (clean) of scripts/pipeline.py. Runs inside headless Blender:

    blender -b --factory-startup --python-exit-code 1 -P scripts/blender_cleanup.py -- \
        --input in.glb --output out.glb --params params.json --report report.json

Imports the GLB and then:
- removes objects the brief lists in exclude_objects;
- fixes facing (characters face -Y), scales to target_size_m, and moves the base or center to the origin;
- rebuilds every material as albedo-only (base color, plus alpha if used), stripping
  normal/roughness/metallic/emission maps and baking non-image albedo;
- downscales the albedo to texture_size;
- aligns props along their principal axis and fails if the residual tilt exceeds PROP_AXIS_TOLERANCE_DEG;
- checks the triangle count against triangle_budget, failing loudly instead of decimating;
- exports the GLB.

Budget numbers come only from --params, which is built from the brief YAML. Every outcome
goes to --report, and on any error nothing is exported.
"""

import argparse
import json
import math
import struct
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

PROP_AXIS_TOLERANCE_DEG = 2.0
STRIP_NOTE = "normal, roughness, metallic, specular, emission and occlusion inputs are not carried over"


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--params", required=True)
    ap.add_argument("--report", required=True)
    return ap.parse_args(argv)


def scene_objects():
    return list(bpy.context.scene.objects)


def world_points(meshes):
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        pts.extend(o.matrix_world @ v.co for v in me.vertices)
        ev.to_mesh_clear()
    return pts


def bbox(points):
    mn = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    mx = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return mn, mx


def is_skinned(mesh_obj):
    return mesh_obj.find_armature() is not None or any(m.type == "ARMATURE" for m in mesh_obj.modifiers)


def bones_with(arm, token):
    return [b for b in arm.data.bones if token in b.name.lower() and "end" not in b.name.lower()]


def detect_forward(arms, meshes, height):
    """Horizontal forward vector from foot bones (heel to toe); falls back to foot geometry vs ankles."""
    feet = [(a, b) for a in arms for b in bones_with(a, "foot")]
    if feet:
        v = sum(((a.matrix_world @ b.tail_local) - (a.matrix_world @ b.head_local) for a, b in feet), Vector())
        v.z = 0
        if v.length > 1e-4:
            return v.normalized(), "foot bones (head to tail)"
        ankles = sum((a.matrix_world @ b.head_local for a, b in feet), Vector()) / len(feet)
        pts = world_points(meshes)
        zmin = min(p.z for p in pts)
        low = [p for p in pts if p.z < zmin + 0.08 * height]
        v = sum(low, Vector()) / len(low) - ankles
        v.z = 0
        if v.length > 1e-4:
            return v.normalized(), "foot geometry forward of the ankles"
    return None, None


def principal_axes(points):
    """Eigenvectors of the point covariance, as Vectors ordered smallest to largest spread."""
    arr = np.array([tuple(p) for p in points])
    vals, vecs = np.linalg.eigh(np.cov((arr - arr.mean(0)).T))
    return [Vector(vecs[:, i]) for i in range(3)], [float(v) for v in vals]


def alignment_matrix(axes):
    """Rotation taking the largest-spread axis to +Z and the second to +X (right-handed)."""
    z = axes[2].normalized()
    x = (axes[1] - axes[1].dot(z) * z).normalized()
    y = z.cross(x)
    return Matrix((x, y, z)).to_4x4()


def tilt_from_z(axis):
    return math.degrees(math.acos(min(1.0, abs(axis.normalized().z))))


def apply_to_roots(matrix):
    for o in scene_objects():
        if o.parent is None:
            o.matrix_world = matrix @ o.matrix_world
    bpy.context.view_layer.update()


def bake_transforms_into_meshes():
    """Unrigged assets only: move every mesh's world transform into its vertex data, drop empties."""
    meshes = [o for o in scene_objects() if o.type == "MESH"]
    world = {o.name: o.matrix_world.copy() for o in meshes}
    for o in meshes:
        if o.data.users > 1:
            o.data = o.data.copy()
        o.data.transform(world[o.name])
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
    for o in scene_objects():
        if o.type not in ("MESH",):
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.context.view_layer.update()


def _bm_stats(bm):
    faces = list(bm.faces)
    sides = [len(f.verts) for f in faces]
    boundary = [e for e in bm.edges if e.is_boundary]
    # Count holes as connected loops of boundary edges (union-find over their vertices).
    parent = {}

    def find(v):
        while parent.setdefault(v, v) != v:
            parent[v] = parent[parent[v]]
            v = parent[v]
        return v
    for e in boundary:
        a, b = find(e.verts[0].index), find(e.verts[1].index)
        if a != b:
            parent[a] = b
    loops = len({find(e.verts[0].index) for e in boundary})
    n = len(faces) or 1
    return {
        "vertices": len(bm.verts), "edges": len(bm.edges), "faces": len(faces),
        "triangles": sides.count(3), "quads": sides.count(4), "ngons": sum(1 for k in sides if k > 4),
        "quad_ratio": round(sides.count(4) / n, 4), "triangle_ratio": round(sides.count(3) / n, 4),
        "non_manifold_edges": sum(1 for e in bm.edges if len(e.link_faces) > 2),
        "boundary_edges": len(boundary), "boundary_loops": loops,
        "wire_edges": sum(1 for e in bm.edges if e.is_wire),
        "loose_vertices": sum(1 for v in bm.verts if not v.link_edges),
        "degenerate_faces": sum(1 for f in faces if f.calc_area() < 1e-12),
        "zero_length_edges": sum(1 for e in bm.edges if e.calc_length() < 1e-9),
    }


def mesh_health(meshes):
    """Baseline topology stats, recorded and never failed on. The glTF importer doesn't merge
    vertices, so every UV seam arrives split and shows up as a boundary. The 'welded' pass
    merges within 0.01 mm to separate real holes from seam splits."""
    per_mesh, totals = [], {"as_imported": {}, "welded": {}}
    for o in meshes:
        entry = {"mesh": o.name}
        for label, weld in (("as_imported", False), ("welded", True)):
            bm = bmesh.new()
            bm.from_mesh(o.data)
            if weld:
                bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
            bm.verts.index_update()
            st = _bm_stats(bm)
            bm.free()
            entry[label] = st
            for k, v in st.items():
                if not k.endswith("_ratio"):
                    totals[label][k] = totals[label].get(k, 0) + v
        per_mesh.append(entry)
    for label in totals:
        f = totals[label].get("faces") or 1
        totals[label]["quad_ratio"] = round(totals[label].get("quads", 0) / f, 4)
        totals[label]["triangle_ratio"] = round(totals[label].get("triangles", 0) / f, 4)
    return {"totals": totals, "per_mesh": per_mesh, "weld_distance_m": 1e-5,
            "note": "baseline only; nothing fails on these yet"}


def albedo_source(nt):
    """(color socket, alpha socket or None, description) feeding the surface's albedo."""
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        col = bsdf.inputs["Base Color"].links
        alp = bsdf.inputs["Alpha"].links
        return (col[0].from_socket if col else None), (alp[0].from_socket if alp else None), "principled"
    emit = next((n for n in nt.nodes if n.type == "EMISSION"), None)
    if emit and emit.inputs["Color"].links:
        src = emit.inputs["Color"].links[0].from_socket
        alpha = None
        if src.node.type == "TEX_IMAGE" and src.node.outputs["Alpha"].links:
            alpha = src.node.outputs["Alpha"]
        return src, alpha, "unlit emission"
    return None, None, "no albedo source found"


def image_has_alpha(img):
    px = img.pixels[:]
    return any(a < 0.99 for a in px[3::4])


def bake_albedo(mat, color_socket, users, size, report):
    """Bake an arbitrary color chain to an image by routing it through Emission (single material only)."""
    for o in users:
        if not o.data.uv_layers:
            raise RuntimeError(f"material '{mat.name}' needs a bake but mesh '{o.name}' has no UV map")
    try:
        bpy.context.scene.render.engine = "CYCLES"
    except TypeError as e:
        raise RuntimeError(f"can't switch to Cycles for baking: {e}")
    bpy.context.scene.cycles.samples = 1
    nt = mat.node_tree
    img = bpy.data.images.new(f"{mat.name}_albedo", size, size, alpha=True)
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(color_socket, emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.nodes.active = tex
    bpy.ops.object.select_all(action="DESELECT")
    for o in users:
        o.select_set(True)
    bpy.context.view_layer.objects.active = users[0]
    bpy.ops.object.bake(type="EMIT", margin=4, use_clear=True)
    img.pack()
    report["warnings"].append(f"material '{mat.name}': albedo baked from a node chain (Cycles EMIT bake)")
    return img


def rebuild_materials(meshes, size, report):
    by_mat = {}
    for o in meshes:
        for slot in o.material_slots:
            if slot.material:
                by_mat.setdefault(slot.material, []).append(o)
        if not any(s.material for s in o.material_slots):
            report["warnings"].append(f"mesh '{o.name}' has no material (exports as the default white)")
    needs_bake = [m for m in by_mat if m.use_nodes and (albedo_source(m.node_tree)[0] is not None)
                  and albedo_source(m.node_tree)[0].node.type != "TEX_IMAGE"]
    if len(needs_bake) > 1:
        raise RuntimeError(f"{len(needs_bake)} materials need an albedo bake; baking several into one "
                           "texture needs a shared UV atlas. Regenerate or merge materials first.")
    images = set()
    for mat, users in by_mat.items():
        entry = {"name": mat.name, "stripped": STRIP_NOTE}
        if not mat.use_nodes:
            entry.update(source="viewport color only", alpha=False)
            report["materials"].append(entry)
            continue
        nt = mat.node_tree
        color, alpha, kind = albedo_source(nt)
        entry["converted_from"] = kind
        img = None
        const = None
        if color is None:
            bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
            const = tuple(bsdf.inputs["Base Color"].default_value) if bsdf else tuple(mat.diffuse_color)
        elif color.node.type == "TEX_IMAGE":
            img = color.node.image
        else:
            img = bake_albedo(mat, color, users, size, report)
            alpha = None
        use_alpha = bool(img and alpha is not None and alpha.node.type == "TEX_IMAGE" and image_has_alpha(img))
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
        bsdf.inputs["Metallic"].default_value = 0.0
        bsdf.inputs["Roughness"].default_value = 1.0
        if img:
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = img
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
            if use_alpha:
                # Round makes the glTF exporter write alphaMode MASK (cutout, cutoff 0.5), not BLEND
                cut = nt.nodes.new("ShaderNodeMath")
                cut.operation = "ROUND"
                nt.links.new(tex.outputs["Alpha"], cut.inputs[0])
                nt.links.new(cut.outputs["Value"], bsdf.inputs["Alpha"])
            images.add(img)
            entry["texture"] = img.name
        else:
            bsdf.inputs["Base Color"].default_value = const
            entry["constant_color"] = [round(c, 4) for c in const]
        entry["alpha"] = use_alpha
        report["materials"].append(entry)
    if len(images) > 1:
        raise RuntimeError(f"{len(images)} textures after cleanup ({sorted(i.name for i in images)}); "
                           "the art bible allows one per asset")
    for img in images:
        before = tuple(img.size)
        longest = max(before)
        if longest > size:
            w, h = max(1, round(before[0] * size / longest)), max(1, round(before[1] * size / longest))
            img.scale(w, h)
            # Pack only modified images: pack() on an already-packed, unmodified image unpacks it
            # and leaves the exporter with no image data.
            img.pack()
        report["textures"].append({"name": img.name, "size_before": list(before), "size_after": list(img.size)})


def main():
    args = parse_args()
    params = json.load(open(args.params))
    report = {"status": "fail", "errors": [], "warnings": [], "blender_version": bpy.app.version_string,
              "input": args.input, "output": args.output, "materials": [], "textures": [],
              "removed_objects": []}
    try:
        run(args, params, report)
    except Exception as e:  # report every failure; pipeline.py decides what to do with it
        report["errors"].append(f"{type(e).__name__}: {e}")
    if not report["errors"]:
        report["status"] = "pass"
    with open(args.report, "w") as f:
        json.dump(report, f, indent=2)


def run(args, params, report):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args.input)

    # Blender's glTF importer creates a mesh (e.g. "Icosphere") to draw bones. It isn't in the
    # source file, but it would be exported as real geometry, so drop it.
    shapes = set()
    for a in (o for o in scene_objects() if o.type == "ARMATURE"):
        for pb in a.pose.bones:
            if pb.custom_shape:
                shapes.add(pb.custom_shape)
                pb.custom_shape = None
    for o in shapes:
        report["removed_objects"].append(f"{o.name} (bone display shape created by the importer)")
        bpy.data.objects.remove(o, do_unlink=True)

    # Explicit, auditable removals only: never guess which geometry is junk.
    for name in params.get("exclude_objects") or []:
        o = bpy.data.objects.get(name)
        if o is None:
            raise RuntimeError(f"exclude_objects lists '{name}', which isn't in the file (is the brief stale?)")
        bpy.data.objects.remove(o, do_unlink=True)
        report["removed_objects"].append(name)

    arms = [o for o in scene_objects() if o.type == "ARMATURE"]
    meshes = [o for o in scene_objects() if o.type == "MESH"]
    if not meshes:
        raise RuntimeError("no meshes in the file")
    rigged = bool(arms)
    report["rigged"] = rigged
    if rigged:
        loose = [o.name for o in meshes if not is_skinned(o)]
        if loose:
            raise RuntimeError(f"meshes not attached to the armature: {loose}. If they're junk, list them "
                               "in the brief's exclude_objects; if they belong, skin them in the source.")
        for a in arms:
            a.data.pose_position = "REST"
        bpy.context.view_layer.update()
        report["armatures"] = [{"name": a.name, "bones": [b.name for b in a.data.bones]} for a in arms]

    mn, mx = bbox(world_points(meshes))
    xf = {"pivot": params["pivot"], "size_before_m": [round(v, 4) for v in (mx - mn)]}

    # Facing / orientation
    rot = Matrix.Identity(4)
    if params["type"] == "character":
        fwd, how = detect_forward(arms, meshes, mx.z - mn.z) if rigged else (None, None)
        if fwd is None:
            report["warnings"].append("facing unverified (no usable foot bones); assumed -Y per convention")
            xf["facing"] = "unverified"
        else:
            angle = math.atan2(fwd.x, -fwd.y)  # 0 when already facing -Y
            snapped = round(math.degrees(angle) / 90.0) * 90 % 360
            xf.update(facing_detected_by=how, forward_before=[round(fwd.x, 3), round(fwd.y, 3)],
                      rotation_z_deg=(-snapped + 180) % 360 - 180)
            if snapped:
                rot = Matrix.Rotation(math.radians(-snapped), 4, "Z")
    else:
        # Align the principal axis, not the bounding box: a bbox check misses diagonal props. The first
        # Levy Blade sat 46 degrees off Z and passed every check at 45% over its true length.
        axes, spread = principal_axes(world_points(meshes))
        xf.update(principal_axis_before=[round(c, 3) for c in axes[2]],
                  tilt_from_z_before_deg=round(tilt_from_z(axes[2]), 1))
        if spread[2] < 1.2 * spread[1]:
            report["warnings"].append("prop has no clear long axis (top two spreads within 20%); alignment is arbitrary")
        rot = alignment_matrix(axes)
        report["warnings"].append("prop up-direction (which end is +Z) is unverified; check it in the socket")
    apply_to_roots(rot)
    if params["type"] == "prop":
        residual = tilt_from_z(principal_axes(world_points(meshes))[0][2])
        xf["tilt_from_z_after_deg"] = round(residual, 3)
        if residual > PROP_AXIS_TOLERANCE_DEG:
            raise RuntimeError(f"ORIENTATION: principal axis still {residual:.1f} deg off +Z after alignment "
                               f"(tolerance {PROP_AXIS_TOLERANCE_DEG} deg); not exporting")

    # Scale, then pivot
    mn, mx = bbox(world_points(meshes))
    size_now = (mx.z - mn.z)
    scale = params["target_size_m"] / size_now
    apply_to_roots(Matrix.Scale(scale, 4))
    mn, mx = bbox(world_points(meshes))
    center = (mn + mx) / 2
    offset = Vector((-center.x, -center.y, -mn.z if params["pivot"] == "base" else -center.z))
    apply_to_roots(Matrix.Translation(offset))
    if not rigged:
        bake_transforms_into_meshes()
        meshes = [o for o in scene_objects() if o.type == "MESH"]
    mn, mx = bbox(world_points(meshes))
    # Props are principal-axis aligned by now, so the bounding box gives true dimensions along the part's own axes
    xf.update(scale_factor=round(scale, 5), size_after_m=[round(v, 4) for v in (mx - mn)],
              true_dims_m={"x": round(mx.x - mn.x, 4), "y": round(mx.y - mn.y, 4), "z": round(mx.z - mn.z, 4)},
              true_length_m=round(mx.z - mn.z, 4), min_after=[round(v, 4) for v in mn])
    report["transform"] = xf
    report["mesh_health"] = mesh_health(meshes)

    rebuild_materials(meshes, params["texture_size"], report)

    # Budget is in triangles (n-gon = n-2). Vertex counts are metrics only: they move with UV-seam splits.
    dg = bpy.context.evaluated_depsgraph_get()
    tris = split_verts = 0
    for o in meshes:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        tris += sum(p.loop_total - 2 for p in me.polygons)
        split_verts += len(me.vertices)
        ev.to_mesh_clear()
    report["triangle_count"] = tris
    report["triangle_budget"] = params["triangle_budget"]
    report["vertex_metrics"] = {"split_at_seams": split_verts,
                                "welded": report["mesh_health"]["totals"]["welded"]["vertices"],
                                "note": "metrics only; the budget is in triangles"}
    if tris > params["triangle_budget"]:
        why = ("it's rigged, and decimating a skinned mesh wrecks its weights" if rigged
               else "stage 3 doesn't decimate")
        raise RuntimeError(f"OVER BUDGET: {tris} triangles > {params['triangle_budget']}. Not exporting; {why}. "
                           f"Regenerate with the brief's face_limit ({params['face_limit']}) or reduce the source.")

    for a in arms:
        a.data.pose_position = "POSE"
    report["animations"] = sorted(a.name for a in bpy.data.actions)
    bpy.ops.export_scene.gltf(filepath=args.output, export_format="GLB", export_yup=True,
                              export_animations=True, export_skins=True, export_apply=False)
    verify_export(args.output, report)


def verify_export(path, report):
    """Read the exported GLB back: the exporter only logs warnings when it drops data."""
    with open(path, "rb") as f:
        data = f.read()
    length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + length])
    images = gltf.get("images", [])
    mats = gltf.get("materials", [])
    report["exported"] = {
        "images": len(images),
        "materials": [{"name": m.get("name"), "alphaMode": m.get("alphaMode", "OPAQUE"),
                       "base_color_texture": "baseColorTexture" in m.get("pbrMetallicRoughness", {})} for m in mats],
        "animations": len(gltf.get("animations", [])),
        "skins": len(gltf.get("skins", [])),
    }
    expected = len(report["textures"])
    if len(images) < expected:
        raise RuntimeError(f"export dropped textures: kept {expected}, but the GLB contains {len(images)} images")
    for m, entry in zip(mats, report["exported"]["materials"]):
        src = next((x for x in report["materials"] if x["name"] == m.get("name")), {})
        if src.get("texture") and not entry["base_color_texture"]:
            raise RuntimeError(f"material '{m.get('name')}' lost its base color texture on export")
        if src.get("alpha") and entry["alphaMode"] != "MASK":
            report["warnings"].append(f"material '{m.get('name')}' exported alphaMode {entry['alphaMode']}, expected MASK")


if __name__ == "__main__":
    main()
