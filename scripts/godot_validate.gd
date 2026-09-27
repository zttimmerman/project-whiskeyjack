extends SceneTree

# Stage 4 (validate) of scripts/pipeline.py:
#   godot --headless --path . -s scripts/godot_validate.gd -- --glb <path> --params <json> --report <json>
# Imports the GLB at runtime with GLTFDocument, so no .import files are written, and reports:
# bone names and their mapping onto SkeletonProfileHumanoid, socket bones, the vertex count,
# textures, extra material maps and animations, all checked against the brief's numbers in --params.
# Exit code: 0 pass, 2 fail.

const EXTRA_MAPS := {
	"normal": BaseMaterial3D.TEXTURE_NORMAL,
	"roughness": BaseMaterial3D.TEXTURE_ROUGHNESS,
	"metallic": BaseMaterial3D.TEXTURE_METALLIC,
	"ambient_occlusion": BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION,
	"emission": BaseMaterial3D.TEXTURE_EMISSION,
}

# Normalized bone-name core -> profile bone base name (side prefix added separately)
const CORE_TO_PROFILE := {
	"hips": "Hips", "hip": "Hips", "pelvis": "Hips",
	"spine": "Spine", "spine0": "Spine", "spine1": "Chest", "chest": "Chest",
	"spine2": "UpperChest", "upperchest": "UpperChest",
	"neck": "Neck", "head": "Head", "jaw": "Jaw",
	"shoulder": "Shoulder", "clavicle": "Shoulder", "collar": "Shoulder",
	"upperarm": "UpperArm", "arm": "UpperArm",
	"forearm": "LowerArm", "lowerarm": "LowerArm",
	"hand": "Hand",
	"thigh": "UpperLeg", "upleg": "UpperLeg", "upperleg": "UpperLeg",
	"shin": "LowerLeg", "calf": "LowerLeg", "leg": "LowerLeg", "lowerleg": "LowerLeg",
	"foot": "Foot",
	"toe": "Toes", "toes": "Toes", "toebase": "Toes",
}
const SIDED := ["Shoulder", "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot", "Toes"]


func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var report := {
		"status": "fail", "errors": [], "warnings": [],
		"godot_version": Engine.get_version_info()["string"],
		"import_method": "GLTFDocument (runtime); editor import settings such as a BoneMap don't apply",
	}
	if args.has("glb") and args.has("params") and args.has("report"):
		_validate(args, report)
	else:
		report["errors"].append("usage: -- --glb <path> --params <path> --report <path>")
	if report["errors"].is_empty():
		report["status"] = "pass"
	if args.has("report"):
		var f := FileAccess.open(args["report"], FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	quit(0 if report["status"] == "pass" else 2)


func _parse_args(argv: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < argv.size() - 1:
		if argv[i].begins_with("--"):
			out[argv[i].substr(2)] = argv[i + 1]
			i += 2
		else:
			i += 1
	return out


func _validate(args: Dictionary, report: Dictionary) -> void:
	var params = JSON.parse_string(FileAccess.get_file_as_string(args["params"]))
	if typeof(params) != TYPE_DICTIONARY:
		report["errors"].append("couldn't read params JSON")
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(args["glb"], state)
	if err != OK:
		report["errors"].append("GLTFDocument couldn't load %s (error %d)" % [args["glb"], err])
		return
	var root := doc.generate_scene(state)
	if root == null:
		report["errors"].append("GLTFDocument produced no scene")
		return
	_check_rig(root, params, report)
	_check_meshes(root, params, report)
	_check_animations(root, params, report)
	root.free()


# ── Rig ──────────────────────────────────────────────────────────────────────

func _check_rig(root: Node, params: Dictionary, report: Dictionary) -> void:
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	var is_character: bool = params.get("type") == "character"
	if skeletons.is_empty():
		report["rig"] = {"skeleton": false}
		if is_character:
			report["errors"].append("character has no Skeleton3D")
		return
	if not is_character:
		report["warnings"].append("prop has a Skeleton3D")
	var skel := skeletons[0] as Skeleton3D
	var bones: Array = []
	for i in skel.get_bone_count():
		bones.append(skel.get_bone_name(i))

	var profile := SkeletonProfileHumanoid.new()
	var profile_names: Array = []
	var required: Array = []
	for i in profile.bone_size:
		var pname := String(profile.get_bone_name(i))
		profile_names.append(pname)
		if profile.is_required(i):
			required.append(pname)

	var exact: Array = bones.filter(func(b): return b in profile_names)
	var mapping := {}  # profile bone -> skeleton bone
	var unmapped: Array = []
	for b in bones:
		var guess := _guess_profile_name(b)
		if guess == "" or not guess in profile_names:
			unmapped.append(b)
		elif mapping.has(guess):
			report["warnings"].append("bones '%s' and '%s' both look like %s" % [mapping[guess], b, guess])
			unmapped.append(b)
		else:
			mapping[guess] = b
	var missing_required: Array = required.filter(func(r): return not mapping.has(r))

	report["rig"] = {
		"skeleton": true,
		"skeleton_path": str(root.get_path_to(skel)),
		"bone_count": bones.size(),
		"bones": bones,
		"profile": "SkeletonProfileHumanoid (%d bones, %d required)" % [profile_names.size(), required.size()],
		"exact_profile_name_matches": exact,
		"proposed_bone_map": mapping,
		"unmapped_bones": unmapped,
		"missing_required": missing_required,
		"humanoid_mappable": missing_required.is_empty(),
		"mapping_method": "name heuristic; confirm in the editor's BoneMap before retargeting",
	}
	if is_character and not missing_required.is_empty():
		report["errors"].append("rig doesn't map onto SkeletonProfileHumanoid; missing required: %s" % [missing_required])

	var socket_path = params.get("socket_map")
	if socket_path:
		var sm = load("res://" + socket_path)
		var sockets := {}
		if sm == null or not "bones" in sm:
			report["errors"].append("socket map %s didn't load as a SocketMap" % socket_path)
		else:
			for socket in sm.bones:
				var bone: String = sm.bones[socket]
				var found := skel.find_bone(bone) != -1
				sockets[socket] = {"bone": bone, "found": found}
				if not found:
					report["errors"].append("socket '%s' maps to bone '%s', which this rig doesn't have" % [socket, bone])
		report["rig"]["sockets"] = sockets


func _guess_profile_name(bone: String) -> String:
	var n := bone.to_lower()
	for prefix in ["mixamorig:", "mixamorig_", "mixamorig1:", "def-", "bip01 ", "bip01_"]:
		if n.begins_with(prefix):
			n = n.substr(prefix.length())
	var re_index := RegEx.create_from_string("_\\d+$")  # exporter suffixes like "_013"
	n = re_index.sub(n, "")
	if n.contains("end") or n.contains("top"):
		return ""  # leaf markers such as hand.L_end, HeadTop_End
	var side := ""
	if n.begins_with("left"):
		side = "Left"
		n = n.substr(4)
	elif n.begins_with("right"):
		side = "Right"
		n = n.substr(5)
	else:
		var re_side := RegEx.create_from_string("(^|[._\\- ])([lr])([._\\- ]|$)")
		var m := re_side.search(n)
		if m:
			side = "Left" if m.get_string(2) == "l" else "Right"
			n = n.substr(0, m.get_start()) + " " + n.substr(m.get_end())
	var core := RegEx.create_from_string("[^a-z0-9]").sub(n, "", true)
	if not CORE_TO_PROFILE.has(core):
		return ""
	var base: String = CORE_TO_PROFILE[core]
	if base in SIDED:
		return side + base if side != "" else ""
	return base if side == "" else ""


# ── Meshes and materials ─────────────────────────────────────────────────────

func _check_meshes(root: Node, params: Dictionary, report: Dictionary) -> void:
	var gpu_verts := 0
	var textures := {}
	var materials: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			gpu_verts += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var mat: Material = mi.get_active_material(s)
			var entry := {"mesh": str(mi.name), "surface": s}
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				entry["transparency"] = ["disabled", "alpha", "alpha_scissor", "alpha_hash", "depth_pre_pass"][bm.transparency]
				entry["unshaded"] = bm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
				if bm.albedo_texture:
					var t := bm.albedo_texture
					textures[t.get_rid()] = [t.get_width(), t.get_height()]
					entry["albedo_texture"] = [t.get_width(), t.get_height()]
				else:
					# Art bible: one albedo texture or vertex colors. Neither means a dropped texture.
					var has_colors: bool = arrays[Mesh.ARRAY_COLOR] != null and (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0
					entry["vertex_colors"] = has_colors
					if not has_colors:
						report["errors"].append("surface %d of '%s' has no albedo texture and no vertex colors" % [s, mi.name])
				var extras: Array = []
				for map_name in EXTRA_MAPS:
					if bm.get_texture(EXTRA_MAPS[map_name]) != null:
						extras.append(map_name)
				entry["extra_maps"] = extras
				if not extras.is_empty():
					report["errors"].append("surface %d of '%s' has extra maps %s (albedo only)" % [s, mi.name, extras])
			elif mat == null:
				entry["material"] = "none"
				report["warnings"].append("surface %d of '%s' has no material" % [s, mi.name])
			else:
				entry["material"] = mat.get_class()
			materials.append(entry)

	var budget: int = params["vertex_budget"]
	var blender_count = params.get("blender_vertex_count")
	report["vertices"] = {
		"gpu_count": gpu_verts,
		"blender_count": blender_count,
		"budget": budget,
		"note": "the budget counts Blender vertices; the GPU count also splits vertices at UV seams and hard edges",
	}
	if blender_count != null:
		if int(blender_count) > budget:
			report["errors"].append("over budget: %d Blender vertices > %d" % [blender_count, budget])
	elif gpu_verts > budget:
		report["errors"].append("over budget: %d GPU vertices > %d (no Blender count to compare)" % [gpu_verts, budget])
	if gpu_verts > budget and blender_count != null and int(blender_count) <= budget:
		report["warnings"].append("GPU vertex count %d exceeds the budget only because of seam splits" % gpu_verts)

	var size: int = params["texture_size"]
	var tex_list: Array = textures.values()
	report["textures"] = {"count": tex_list.size(), "sizes": tex_list, "max_allowed": size}
	for wh in tex_list:
		if wh[0] > size or wh[1] > size:
			report["errors"].append("texture %dx%d exceeds %d" % [wh[0], wh[1], size])
	if tex_list.size() > 1:
		report["errors"].append("%d textures; the art bible allows one per asset" % tex_list.size())
	report["materials"] = materials


func _check_animations(root: Node, params: Dictionary, report: Dictionary) -> void:
	var names: Array = []
	for ap in root.find_children("*", "AnimationPlayer", true, false):
		for a in (ap as AnimationPlayer).get_animation_list():
			names.append(String(a))
	var expected: Array = params.get("animations") if params.get("animations") else []
	var missing: Array = expected.filter(func(e): return not e in names)
	report["animations"] = {"present": names, "expected": expected, "missing": missing}
	if not missing.is_empty():
		report["warnings"].append("animations missing (they'll come from the shared library): %s" % [missing])
