"""
Blender 5.0 headless script — builds a low-poly PS1-style player character.
Run:  blender --background --python scripts/blender/make_player_model.py
Exports to: assets/meshes/player_character.glb
"""

import bpy
import bmesh
import math
import os
from mathutils import Vector, Euler

# ── Cleanup ──────────────────────────────────────────────────────────────────
bpy.ops.wm.read_factory_settings(use_empty=True)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
OUTPUT_PATH = os.path.join(PROJECT_ROOT, "assets", "meshes", "player_character.glb")

# ── Color palette ────────────────────────────────────────────────────────────
COL_SKIN  = (0.87, 0.72, 0.58, 1.0)
COL_TUNIC = (0.15, 0.40, 0.35, 1.0)
COL_PANTS = (0.45, 0.30, 0.18, 1.0)
COL_BOOTS = (0.28, 0.18, 0.10, 1.0)
COL_HAIR  = (0.12, 0.08, 0.06, 1.0)

# ── Mesh helpers ─────────────────────────────────────────────────────────────

def make_box(name, sx, sy, sz, location=(0,0,0), color=COL_SKIN):
    mesh = bpy.data.meshes.new(name + "_mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x = v.co.x * sx * 2 + location[0]
        v.co.y = v.co.y * sy * 2 + location[1]
        v.co.z = v.co.z * sz * 2 + location[2]
    cl = bm.loops.layers.color.new("Color")
    for f in bm.faces:
        for lp in f.loops:
            lp[cl] = color
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return obj

def make_sphere(name, radius, segs=6, rings=4, location=(0,0,0), color=COL_SKIN):
    mesh = bpy.data.meshes.new(name + "_mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius)
    for v in bm.verts:
        v.co.x += location[0]
        v.co.y += location[1]
        v.co.z += location[2]
    cl = bm.loops.layers.color.new("Color")
    for f in bm.faces:
        for lp in f.loops:
            lp[cl] = color
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return obj

# ── Build body ───────────────────────────────────────────────────────────────
parts = []
# Torso
parts.append(make_box("Torso", 0.22, 0.14, 0.30, (0, 0, 0.95), COL_TUNIC))
# Hips
parts.append(make_box("Hips", 0.20, 0.12, 0.08, (0, 0, 0.60), COL_PANTS))
# Head
parts.append(make_sphere("Head", 0.18, segs=8, rings=5, location=(0, 0, 1.52), color=COL_SKIN))
# Neck
parts.append(make_box("Neck", 0.06, 0.06, 0.06, (0, 0, 1.32), COL_SKIN))
# Hair — multiple spiky tufts instead of a single helmet block
# Base layer covers the top/back of the head
parts.append(make_box("HairBase", 0.17, 0.15, 0.06, (0, -0.03, 1.64), COL_HAIR))
# Spiky tufts pointing outward/upward for a JRPG look
parts.append(make_box("HairSpike1", 0.04, 0.06, 0.10, ( 0.00,  -0.08, 1.72), COL_HAIR))  # back center, tall
parts.append(make_box("HairSpike2", 0.05, 0.05, 0.08, ( 0.10,  -0.05, 1.70), COL_HAIR))  # back right
parts.append(make_box("HairSpike3", 0.05, 0.05, 0.08, (-0.10,  -0.05, 1.70), COL_HAIR))  # back left
parts.append(make_box("HairSpike4", 0.06, 0.04, 0.07, ( 0.08,   0.04, 1.68), COL_HAIR))  # side right
parts.append(make_box("HairSpike5", 0.06, 0.04, 0.07, (-0.08,   0.04, 1.68), COL_HAIR))  # side left
parts.append(make_box("HairFringe", 0.14, 0.04, 0.04, ( 0.00,   0.12, 1.62), COL_HAIR))  # front bangs
# Arms
parts.append(make_box("UpperArm_L", 0.06, 0.06, 0.15, ( 0.30, 0, 1.10), COL_SKIN))
parts.append(make_box("UpperArm_R", 0.06, 0.06, 0.15, (-0.30, 0, 1.10), COL_SKIN))
parts.append(make_box("LowerArm_L", 0.05, 0.05, 0.14, ( 0.30, 0, 0.82), COL_SKIN))
parts.append(make_box("LowerArm_R", 0.05, 0.05, 0.14, (-0.30, 0, 0.82), COL_SKIN))
parts.append(make_box("Hand_L", 0.05, 0.04, 0.06, ( 0.30, 0, 0.66), COL_SKIN))
parts.append(make_box("Hand_R", 0.05, 0.04, 0.06, (-0.30, 0, 0.66), COL_SKIN))
# Legs
parts.append(make_box("UpperLeg_L", 0.08, 0.08, 0.18, ( 0.10, 0, 0.38), COL_PANTS))
parts.append(make_box("UpperLeg_R", 0.08, 0.08, 0.18, (-0.10, 0, 0.38), COL_PANTS))
parts.append(make_box("LowerLeg_L", 0.07, 0.07, 0.16, ( 0.10, 0, 0.16), COL_PANTS))
parts.append(make_box("LowerLeg_R", 0.07, 0.07, 0.16, (-0.10, 0, 0.16), COL_PANTS))
# Boots
parts.append(make_box("Boot_L", 0.08, 0.11, 0.05, ( 0.10, 0.02, 0.05), COL_BOOTS))
parts.append(make_box("Boot_R", 0.08, 0.11, 0.05, (-0.10, 0.02, 0.05), COL_BOOTS))

# Join all into one mesh
bpy.context.view_layer.objects.active = parts[0]
for p in parts:
    p.select_set(True)
bpy.ops.object.join()
player_mesh = bpy.context.active_object
player_mesh.name = "PlayerCharacter"

# Flat shading
for poly in player_mesh.data.polygons:
    poly.use_smooth = False

# ── Material (vertex color) ─────────────────────────────────────────────────
mat = bpy.data.materials.new("PlayerMat")
mat.use_nodes = True
nodes = mat.node_tree.nodes
links = mat.node_tree.links
nodes.clear()
output_node = nodes.new("ShaderNodeOutputMaterial")
bsdf = nodes.new("ShaderNodeBsdfPrincipled")
vcol = nodes.new("ShaderNodeVertexColor")
vcol.layer_name = "Color"
links.new(vcol.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.95
bsdf.inputs["Specular IOR Level"].default_value = 0.0
links.new(bsdf.outputs["BSDF"], output_node.inputs["Surface"])
player_mesh.data.materials.append(mat)

# ── Armature ─────────────────────────────────────────────────────────────────
bpy.ops.object.select_all(action='DESELECT')
bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
armature_obj = bpy.context.active_object
armature_obj.name = "Armature"
armature = armature_obj.data
armature.name = "PlayerArmature"

# Remove default bone
for b in list(armature.edit_bones):
    armature.edit_bones.remove(b)

def add_bone(name, head, tail, parent_name=None):
    bone = armature.edit_bones.new(name)
    bone.head = Vector(head)
    bone.tail = Vector(tail)
    bone.use_connect = False
    if parent_name:
        bone.parent = armature.edit_bones[parent_name]
    return bone

# Spine
add_bone("Root",   (0, 0, 0.55), (0, 0, 0.60))
add_bone("Hips",   (0, 0, 0.60), (0, 0, 0.65), "Root")
add_bone("Spine",  (0, 0, 0.65), (0, 0, 0.85), "Hips")
add_bone("Chest",  (0, 0, 0.85), (0, 0, 1.15), "Spine")
add_bone("Neck",   (0, 0, 1.25), (0, 0, 1.35), "Chest")
add_bone("Head",   (0, 0, 1.35), (0, 0, 1.70), "Neck")
# Left arm
add_bone("Shoulder.L", ( 0.22, 0, 1.20), ( 0.28, 0, 1.20), "Chest")
add_bone("UpperArm.L", ( 0.28, 0, 1.20), ( 0.30, 0, 0.95), "Shoulder.L")
add_bone("LowerArm.L", ( 0.30, 0, 0.95), ( 0.30, 0, 0.72), "UpperArm.L")
add_bone("Hand.L",     ( 0.30, 0, 0.72), ( 0.30, 0, 0.60), "LowerArm.L")
# Right arm
add_bone("Shoulder.R", (-0.22, 0, 1.20), (-0.28, 0, 1.20), "Chest")
add_bone("UpperArm.R", (-0.28, 0, 1.20), (-0.30, 0, 0.95), "Shoulder.R")
add_bone("LowerArm.R", (-0.30, 0, 0.95), (-0.30, 0, 0.72), "UpperArm.R")
add_bone("Hand.R",     (-0.30, 0, 0.72), (-0.30, 0, 0.60), "LowerArm.R")
# Left leg
add_bone("UpperLeg.L", ( 0.10, 0, 0.55), ( 0.10, 0, 0.25), "Hips")
add_bone("LowerLeg.L", ( 0.10, 0, 0.25), ( 0.10, 0, 0.05), "UpperLeg.L")
add_bone("Foot.L",     ( 0.10, 0, 0.05), ( 0.10, 0.10, 0.0), "LowerLeg.L")
# Right leg
add_bone("UpperLeg.R", (-0.10, 0, 0.55), (-0.10, 0, 0.25), "Hips")
add_bone("LowerLeg.R", (-0.10, 0, 0.25), (-0.10, 0, 0.05), "UpperLeg.R")
add_bone("Foot.R",     (-0.10, 0, 0.05), (-0.10, 0.10, 0.0), "LowerLeg.R")

bpy.ops.object.mode_set(mode='OBJECT')

# Parent mesh to armature with automatic weights
bpy.ops.object.select_all(action='DESELECT')
player_mesh.select_set(True)
armature_obj.select_set(True)
bpy.context.view_layer.objects.active = armature_obj
bpy.ops.object.parent_set(type='ARMATURE_AUTO')

# ── Animation helpers ────────────────────────────────────────────────────────
# In Blender 5.0 we use keyframe_insert on pose bones; swap actions via
# animation_data.action with proper slot assignment.

def begin_action(name):
    """Create a new action, assign it to the armature, enter pose mode."""
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    slot = act.slots.new(id_type='OBJECT', name='Slot')
    armature_obj.animation_data_create()
    armature_obj.animation_data.action = act
    armature_obj.animation_data.action_slot = slot
    bpy.ops.object.mode_set(mode='POSE')
    # Reset all pose bones
    for pb in armature_obj.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)
    return act

def end_action():
    bpy.ops.object.mode_set(mode='OBJECT')

def key_rot(bone_name, frame, euler_deg):
    """Insert rotation keyframe from euler degrees (XYZ)."""
    pb = armature_obj.pose.bones[bone_name]
    e = Euler((math.radians(euler_deg[0]), math.radians(euler_deg[1]), math.radians(euler_deg[2])), 'XYZ')
    pb.rotation_quaternion = e.to_quaternion()
    pb.keyframe_insert(data_path='rotation_quaternion', frame=frame)

def key_loc(bone_name, frame, loc):
    pb = armature_obj.pose.bones[bone_name]
    pb.location = loc
    pb.keyframe_insert(data_path='location', frame=frame)

def key_scale(bone_name, frame, scl):
    pb = armature_obj.pose.bones[bone_name]
    pb.scale = scl
    pb.keyframe_insert(data_path='scale', frame=frame)

# ── idle (~1.5s = 36 frames @ 24fps) ────────────────────────────────────────
begin_action("idle")

key_scale("Chest", 1,  (1.0, 1.0, 1.0))
key_scale("Chest", 18, (1.0, 1.02, 1.01))
key_scale("Chest", 36, (1.0, 1.0, 1.0))

key_rot("Head", 1,  (0, 0, 0))
key_rot("Head", 18, (2, 0, 0))
key_rot("Head", 36, (0, 0, 0))

key_rot("UpperArm.L", 1,  (0, 0, 0))
key_rot("UpperArm.L", 18, (3, 0, 2))
key_rot("UpperArm.L", 36, (0, 0, 0))
key_rot("UpperArm.R", 1,  (0, 0, 0))
key_rot("UpperArm.R", 18, (3, 0, -2))
key_rot("UpperArm.R", 36, (0, 0, 0))

end_action()

# ── run (~0.6s = 15 frames) ─────────────────────────────────────────────────
begin_action("run")

for bone, s in [("UpperLeg.L", 1), ("UpperLeg.R", -1)]:
    key_rot(bone, 1,  (35*s, 0, 0))
    key_rot(bone, 8,  (-10*s, 0, 0))
    key_rot(bone, 15, (-35*s, 0, 0))

for bone, s in [("LowerLeg.L", 1), ("LowerLeg.R", -1)]:
    key_rot(bone, 1,  (-20*s, 0, 0))
    key_rot(bone, 5,  (-60, 0, 0))
    key_rot(bone, 8,  (10*s, 0, 0))
    key_rot(bone, 12, (-60, 0, 0))
    key_rot(bone, 15, (-20*s, 0, 0))

for bone, s in [("UpperArm.L", -1), ("UpperArm.R", 1)]:
    key_rot(bone, 1,  (30*s, 0, 0))
    key_rot(bone, 8,  (0, 0, 0))
    key_rot(bone, 15, (-30*s, 0, 0))

for bone, s in [("LowerArm.L", -1), ("LowerArm.R", 1)]:
    key_rot(bone, 1,  (-30*s, 0, 0))
    key_rot(bone, 8,  (-45, 0, 0))
    key_rot(bone, 15, (30*s, 0, 0))

key_rot("Spine", 1, (8, 0, 0))
key_rot("Spine", 8, (8, 0, 0))
key_rot("Spine", 15, (8, 0, 0))

key_loc("Root", 1,  (0, 0, 0.01))
key_loc("Root", 4,  (0, 0, 0.03))
key_loc("Root", 8,  (0, 0, 0.01))
key_loc("Root", 12, (0, 0, 0.03))
key_loc("Root", 15, (0, 0, 0.01))

end_action()

# ── attack_light (~0.4s = 10 frames) ────────────────────────────────────────
begin_action("attack_light")

key_rot("Chest", 1,  (0, 0, 0))
key_rot("Chest", 3,  (0, -20, 0))
key_rot("Chest", 5,  (0, 30, 0))
key_rot("Chest", 10, (0, 0, 0))

key_rot("UpperArm.R", 1,  (0, 0, 0))
key_rot("UpperArm.R", 3,  (-60, 0, -30))
key_rot("UpperArm.R", 5,  (40, 0, 20))
key_rot("UpperArm.R", 10, (0, 0, 0))

key_rot("LowerArm.R", 1,  (0, 0, 0))
key_rot("LowerArm.R", 3,  (-40, 0, 0))
key_rot("LowerArm.R", 5,  (-20, 0, 0))
key_rot("LowerArm.R", 10, (0, 0, 0))

key_loc("Root", 1,  (0, 0, 0))
key_loc("Root", 5,  (0, 0.05, 0))
key_loc("Root", 10, (0, 0, 0))

end_action()

# ── attack_heavy (~0.7s = 17 frames) ────────────────────────────────────────
begin_action("attack_heavy")

key_rot("Chest", 1,  (0, 0, 0))
key_rot("Chest", 5,  (-15, 0, 0))
key_rot("Chest", 9,  (25, 0, 0))
key_rot("Chest", 17, (0, 0, 0))

key_rot("UpperArm.R", 1,  (0, 0, 0))
key_rot("UpperArm.R", 5,  (-140, 0, -10))
key_rot("UpperArm.R", 9,  (30, 0, 10))
key_rot("UpperArm.R", 17, (0, 0, 0))

key_rot("UpperArm.L", 1,  (0, 0, 0))
key_rot("UpperArm.L", 5,  (-120, 0, 10))
key_rot("UpperArm.L", 9,  (20, 0, -10))
key_rot("UpperArm.L", 17, (0, 0, 0))

key_rot("LowerArm.R", 1,  (0, 0, 0))
key_rot("LowerArm.R", 5,  (-60, 0, 0))
key_rot("LowerArm.R", 9,  (-10, 0, 0))
key_rot("LowerArm.R", 17, (0, 0, 0))

key_rot("LowerArm.L", 1,  (0, 0, 0))
key_rot("LowerArm.L", 5,  (-60, 0, 0))
key_rot("LowerArm.L", 9,  (-10, 0, 0))
key_rot("LowerArm.L", 17, (0, 0, 0))

key_loc("Root", 1,  (0, 0, 0))
key_loc("Root", 9,  (0, 0.08, 0))
key_loc("Root", 17, (0, 0, 0))

end_action()

# ── dodge_roll (~0.5s = 12 frames) ──────────────────────────────────────────
# Quick crouching side-step/dash — NOT a full somersault. Spine tucks gently,
# body drops low, arms pull in. The actual movement comes from Player.gd velocity.
begin_action("dodge_roll")

# Spine: gentle forward tuck (like a quick crouch), not a full roll
key_rot("Spine", 1,  (0, 0, 0))
key_rot("Spine", 3,  (25, 0, 0))
key_rot("Spine", 6,  (30, 0, 0))
key_rot("Spine", 9,  (20, 0, 0))
key_rot("Spine", 12, (0, 0, 0))

# Head tucks in slightly
key_rot("Head", 1,  (0, 0, 0))
key_rot("Head", 3,  (15, 0, 0))
key_rot("Head", 9,  (10, 0, 0))
key_rot("Head", 12, (0, 0, 0))

# Legs bend into a crouch
for leg in ["UpperLeg.L", "UpperLeg.R"]:
    key_rot(leg, 1,  (0, 0, 0))
    key_rot(leg, 3,  (-35, 0, 0))
    key_rot(leg, 6,  (-40, 0, 0))
    key_rot(leg, 9,  (-30, 0, 0))
    key_rot(leg, 12, (0, 0, 0))

for leg in ["LowerLeg.L", "LowerLeg.R"]:
    key_rot(leg, 1,  (0, 0, 0))
    key_rot(leg, 3,  (40, 0, 0))
    key_rot(leg, 6,  (45, 0, 0))
    key_rot(leg, 9,  (35, 0, 0))
    key_rot(leg, 12, (0, 0, 0))

# Arms pull close to body
for arm in ["UpperArm.L", "UpperArm.R"]:
    key_rot(arm, 1,  (0, 0, 0))
    key_rot(arm, 3,  (20, 0, 0))
    key_rot(arm, 6,  (25, 0, 0))
    key_rot(arm, 9,  (15, 0, 0))
    key_rot(arm, 12, (0, 0, 0))

for arm in ["LowerArm.L", "LowerArm.R"]:
    key_rot(arm, 1,  (0, 0, 0))
    key_rot(arm, 3,  (-30, 0, 0))
    key_rot(arm, 6,  (-35, 0, 0))
    key_rot(arm, 9,  (-25, 0, 0))
    key_rot(arm, 12, (0, 0, 0))

# Root drops down for the crouch then recovers
key_loc("Root", 1,  (0, 0, 0))
key_loc("Root", 3,  (0, 0, -0.12))
key_loc("Root", 6,  (0, 0, -0.15))
key_loc("Root", 9,  (0, 0, -0.08))
key_loc("Root", 12, (0, 0, 0))

end_action()

# ── death (~1.0s = 24 frames) ───────────────────────────────────────────────
begin_action("death")

key_rot("Spine", 1,  (0, 0, 0))
key_rot("Spine", 8,  (-15, 0, 5))
key_rot("Spine", 16, (-10, 0, 15))
key_rot("Spine", 24, (70, 0, 10))

key_rot("Head", 1,  (0, 0, 0))
key_rot("Head", 12, (-20, 0, 10))
key_rot("Head", 24, (30, 15, 0))

for arm, s in [("UpperArm.L", 1), ("UpperArm.R", -1)]:
    key_rot(arm, 1,  (0, 0, 0))
    key_rot(arm, 12, (20*s, 0, 30*s))
    key_rot(arm, 24, (40*s, 0, 50*s))

for arm in ["LowerArm.L", "LowerArm.R"]:
    key_rot(arm, 1,  (0, 0, 0))
    key_rot(arm, 24, (-30, 0, 0))

key_rot("UpperLeg.L", 1,  (0, 0, 0))
key_rot("UpperLeg.L", 12, (-20, 0, 10))
key_rot("UpperLeg.L", 24, (-40, 0, 15))

key_rot("UpperLeg.R", 1,  (0, 0, 0))
key_rot("UpperLeg.R", 12, (-10, 0, -5))
key_rot("UpperLeg.R", 24, (-30, 0, -10))

key_rot("LowerLeg.L", 1,  (0, 0, 0))
key_rot("LowerLeg.L", 24, (-50, 0, 0))

key_rot("LowerLeg.R", 1,  (0, 0, 0))
key_rot("LowerLeg.R", 24, (-40, 0, 0))

key_loc("Root", 1,  (0, 0, 0))
key_loc("Root", 12, (0, 0, -0.1))
key_loc("Root", 24, (0, 0, -0.4))

end_action()

# ── Push all actions to NLA ──────────────────────────────────────────────────
armature_obj.animation_data.action = None
for action in bpy.data.actions:
    track = armature_obj.animation_data.nla_tracks.new()
    track.name = action.name
    fr = action.curve_frame_range
    strip = track.strips.new(action.name, int(fr[0]), action)
    if len(action.slots) > 0:
        strip.action_slot = action.slots[0]
    track.mute = False

# ── Export ───────────────────────────────────────────────────────────────────
bpy.ops.object.select_all(action='SELECT')
os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)

bpy.ops.export_scene.gltf(
    filepath=OUTPUT_PATH,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
    export_animations=True,
    export_nla_strips=True,
    export_yup=True,
)

print(f"\n=== Exported player model to: {OUTPUT_PATH} ===")
print(f"Vertex count: {len(player_mesh.data.vertices)}")
print(f"Polygon count: {len(player_mesh.data.polygons)}")
print(f"Animations: {[a.name for a in bpy.data.actions]}")
