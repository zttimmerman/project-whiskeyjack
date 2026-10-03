"""Look-dev spike (docs/backlog/spike-look-dev.md, look-dev-c.md): the clean stage with the art bible's
shading rule lifted, for variant assets under assets/lookdev/ only. Never used for shipped assets.

    blender -b --factory-startup --python-exit-code 1 -P scripts/lookdev/clean_variant.py -- \
        --input <rigged raw GLB> --output assets/lookdev/player_b1.glb --params <json> --report <json>

Runs scripts/blender_cleanup.py unchanged except for one step: flat_shade_by_angle (custom normals
cleared, every edge over 30 degrees flat) is replaced by keeping the source's own imported normals,
which for Tripo are smooth. Texture size, colour correction and everything else come from --params.

Variant C (scripts/lookdev/build_c.sh) adds two switches, by environment so B1's call is unchanged:
  LOOKDEV_KEEP_PBR=1     keep the source's PBR material as delivered (base colour, metallic-roughness and
                         normal maps at their own size, no colour correction) instead of rebuilding it
                         albedo-only. C-PBR.
  LOOKDEV_DECIMATE=<n>   collapse-decimate every mesh to about n triangles right after import, before any
                         other step (weights and UVs are interpolated by Blender). C-budget. Decimating a
                         rigged mesh is against the pipeline's rules; it's here only to see what survives.
"""

import os
import sys

import bpy

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import blender_cleanup  # noqa: E402


def keep_source_normals(meshes, weld, report):
    report["shading"] = {"mode": "source normals kept (look-dev: no flat shading, no weld)",
                         "custom_normals": [o.name for o in meshes if o.data.has_custom_normals]}


def keep_pbr(meshes, size, report, *args, **kwargs):
    """C-PBR: the source's material stays as imported; record which maps it carries."""
    for o in meshes:
        for slot in o.material_slots:
            mat = slot.material
            if not mat or not mat.use_nodes:
                continue
            imgs = [n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image]
            links = {}
            for n in imgs:
                for out in n.outputs:
                    for link in out.links:
                        links.setdefault(n.image.name, []).append(f"{link.to_node.type}.{link.to_socket.name}")
            report["materials"].append({"name": mat.name, "kept": "PBR as delivered (look-dev C-PBR)",
                                        "maps": links})
            for n in imgs:
                report["textures"].append({"name": n.image.name, "size_before": list(n.image.size),
                                           "size_after": list(n.image.size)})


_import_source = blender_cleanup.import_source


def import_and_decimate(path, report, node_rest=False):
    _import_source(path, report, node_rest)
    target = int(os.environ["LOOKDEV_DECIMATE"])
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    before = sum(sum(p.loop_total - 2 for p in o.data.polygons) for o in meshes)
    for o in meshes:
        bpy.context.view_layer.objects.active = o
        mod = o.modifiers.new("lookdev_decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = min(1.0, target / before)
        mod.use_collapse_triangulate = True
        # The armature modifier sits first; the decimate must apply on its own, so move it to the top
        bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
        bpy.ops.object.modifier_apply(modifier=mod.name)
    after = sum(sum(p.loop_total - 2 for p in o.data.polygons) for o in meshes)
    report["lookdev_decimate"] = {"target": target, "triangles_before": before, "triangles_after": after,
                                  "method": "Blender collapse decimate, weights and UVs interpolated"}


blender_cleanup.flat_shade_by_angle = keep_source_normals
if os.environ.get("LOOKDEV_KEEP_PBR") == "1":
    blender_cleanup.rebuild_materials = keep_pbr
if os.environ.get("LOOKDEV_DECIMATE"):
    blender_cleanup.import_source = import_and_decimate
blender_cleanup.main()
