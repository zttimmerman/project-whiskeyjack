extends Node

# Review tool: motion evidence for the asset judge, one clip at a time on the imported (retargeted)
# character. For each clip it writes four files into --out:
#   <clip>_strip.png    frame strip: --frames poses at even times, side view (top row) and three-quarter
#                       (bottom row), each cell timestamped, with a red line at the character's origin
#   <clip>_onion.png    onion skin: every strip frame overlaid at partial opacity, blue (start) to red
#                       (end), side and top views, over a 0.25 m floor grid, with the Hips path as dots
#   <clip>_plots.png    Hips offset over time; Hips and foot heights; ground-relative foot and Hips speed
#                       with foot contact shaded; per-frame bind-pose deviation and skin stretch
#   <clip>_stretch.png  the frame with the most skin stretch, close up front and back, worst edges in red
#                       (only when anything stretches)
#   <clip>_metrics.json the numbers scripts/judge.py asserts on (tolerances live in docs/art-bible.md)
# Windowed run (the headless renderer draws nothing):
#   godot --path . res://scripts/review/motion_review.tscn -- --model <res:// glb> --out <dir>
#       [--library <res:// tres>] [--clips a,b]            clips from a character library (default: all)
#       [--raw <PACK>:<Clip>=<name>[,...]]                   a clip straight from a Quaternius pack, before the
#                                                           build tool's options (in_place, trim, speed)
#       [--ground-speed <clip>=<m/s>[,...]]                  gameplay speed for locomotion clips (in-place loops)
#       [--kind <clip>=death|in_place|action[,...]]
#           default: death* death; idle, run, walk in_place; else action
#       [--frames <n>]                                       strip frames (default 14)
#
# Measurements, sampled at FPS on the CPU-skinned mesh (the same linear blend skinning the GPU does):
# - root travel: horizontal Hips offset from the first frame (death and in-place clips must stay put);
# - foot slide: ground-relative horizontal speed of each foot's contact point (the lower of Foot and
#   Toes) while it is planted (within CONTACT_HEIGHT of its lowest point in the clip, and moving
#   vertically slower than CONTACT_VSPEED). The clip plays in
#   place, so the ground moves at --ground-speed toward -Z (the model faces +Z);
# - bind deviation: each vertex's displacement from its bind-pose position, both in the Hips frame;
# - edge stretch: |length / bind length - 1| over the mesh's edges of at least MIN_EDGE.

const FPS := 30.0
const CONTACT_HEIGHT := 0.03
const CONTACT_VSPEED := 0.25  # m/s
const STRETCH_EDGES := 12
const MIN_EDGE := 0.01  # m: shorter edges (crotch and seam slivers) turn millimetre moves into huge ratios
const CELL := Vector2i(170, 250)
const ONION_SIZE := Vector2i(800, 640)
const PLOT_SIZE := Vector2i(1600, 1000)
const PACKS := {
	"UAL1": "res://assets/animations/quaternius/UAL1_Standard.glb",
	"UAL2": "res://assets/animations/quaternius/UAL2_Standard.glb",
}

var args := {}
var model_scene: PackedScene
var out_dir := ""


func _ready() -> void:
	# Vsync off: with another window in front (the human's editor), macOS throttles a covered
	# window's buffer swaps and a vsynced capture crawls (one clip took minutes, not seconds)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var argv := OS.get_cmdline_user_args()
	for i in range(0, argv.size() - 1, 2):
		args[argv[i].trim_prefix("--")] = argv[i + 1]
	get_window().size = Vector2i(320, 240)
	model_scene = load(args["model"])
	out_dir = (
		ProjectSettings.globalize_path(args["out"])
		if String(args["out"]).begins_with("res://")
		else String(args["out"])
	)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var lib := AnimationLibrary.new()
	var sources := {}
	if args.has("library"):
		var src: AnimationLibrary = load(args["library"])
		var names: Array = String(args["clips"]).split(",") if args.has("clips") else Array(src.get_animation_list())
		for n in names:
			lib.add_animation(n, src.get_animation(n))
			sources[n] = "%s:%s" % [args["library"], n]
	if args.has("raw"):
		for spec in String(args["raw"]).split(","):
			var kv := spec.split("=")
			var pc := kv[0].split(":")
			var pack: Node = (load(PACKS[pc[0]]) as PackedScene).instantiate()
			var ap: AnimationPlayer = pack.find_children("*", "AnimationPlayer", true, false)[0]
			var clip_name: String = pc[1] if ap.has_animation(pc[1]) else pc[1].trim_suffix("_Loop")
			lib.add_animation(kv[1], ap.get_animation(clip_name).duplicate())
			sources[kv[1]] = "%s (raw pack clip, no build options)" % kv[0]
			pack.free()
	for n in lib.get_animation_list():
		await _review(String(n), lib, sources[n])
	get_tree().quit()


func _opt(key: String, clip: String, fallback: String) -> String:
	if not args.has(key):
		return fallback
	for pair in String(args[key]).split(","):
		var kv := pair.split("=")
		if kv[0] == clip:
			return kv[1]
	return fallback


func _default_kind(clip: String) -> String:
	if clip.begins_with("death"):
		return "death"
	if clip in ["idle", "run", "walk"]:
		return "in_place"
	return "action"


# ── Character instances ───────────────────────────────────────────────────────


func _spawn(parent: Node, lib: AnimationLibrary, clip: String, t: float) -> Dictionary:
	var root: Node3D = model_scene.instantiate()
	parent.add_child(root)
	var ap := AnimationPlayer.new()
	root.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library("", lib)
	ap.play(clip)
	ap.seek(t, true)
	ap.pause()
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	return {"root": root, "ap": ap, "sk": sk}


func _mesh_data(sk: Skeleton3D, root: Node3D) -> Array:
	var out := []
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.mesh == null:
			continue
		var skin := mi.skin
		var bind_bones := PackedInt32Array()
		var bind_poses: Array[Transform3D] = []
		for b in skin.get_bind_count():
			var bn := skin.get_bind_name(b)
			bind_bones.append(sk.find_bone(bn) if bn != "" else skin.get_bind_bone(b))
			bind_poses.append(skin.get_bind_pose(b))
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			out.append(
				{
					"verts": verts,
					"bones": bones,
					"weights": weights,
					"stride": bones.size() / maxi(verts.size(), 1),
					"index": idx,
					"bind_bones": bind_bones,
					"bind_poses": bind_poses
				}
			)
	return out


func _skin(sk: Skeleton3D, meshes: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var skg := sk.global_transform
	for md in meshes:
		var xf: Array[Transform3D] = []
		for b in md["bind_bones"].size():
			xf.append(skg * sk.get_bone_global_pose(md["bind_bones"][b]) * md["bind_poses"][b])
		var verts: PackedVector3Array = md["verts"]
		var bones: PackedInt32Array = md["bones"]
		var weights: PackedFloat32Array = md["weights"]
		var stride: int = md["stride"]
		for v in verts.size():
			var p := Vector3.ZERO
			for k in stride:
				var w := weights[v * stride + k]
				if w > 0.0:
					p += w * (xf[bones[v * stride + k]] * verts[v])
			out.append(p)
	return out


func _dominant_bones(sk: Skeleton3D, meshes: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for md in meshes:
		var stride: int = md["stride"]
		for v in md["verts"].size():
			var best := 0
			for k in stride:
				if md["weights"][v * stride + k] > md["weights"][v * stride + best]:
					best = k
			out.append(sk.get_bone_name(md["bind_bones"][md["bones"][v * stride + best]]))
	return out


func _edges(meshes: Array) -> PackedInt32Array:
	var seen := {}
	var out := PackedInt32Array()
	var base := 0
	for md in meshes:
		var idx: PackedInt32Array = md["index"]
		for i in range(0, idx.size() - 2, 3):
			for e in [[idx[i], idx[i + 1]], [idx[i + 1], idx[i + 2]], [idx[i + 2], idx[i]]]:
				var a: int = base + mini(e[0], e[1])
				var b: int = base + maxi(e[0], e[1])
				var key := a * 1000003 + b
				if not seen.has(key):
					seen[key] = true
					out.append(a)
					out.append(b)
		base += md["verts"].size()
	return out


func _bone_pos(sk: Skeleton3D, bone: String) -> Vector3:
	var i := sk.find_bone(bone)
	return (sk.global_transform * sk.get_bone_global_pose(i)).origin if i >= 0 else Vector3.ZERO


func _percentile(values: Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var s := values.duplicate()
	s.sort()
	return s[clampi(int(round(q * (s.size() - 1))), 0, s.size() - 1)]


# ── Measurement ───────────────────────────────────────────────────────────────


func _measure(lib: AnimationLibrary, clip: String, ground_speed: float) -> Dictionary:
	var holder := Node3D.new()
	add_child(holder)
	var inst := _spawn(holder, lib, clip, 0.0)
	var sk: Skeleton3D = inst["sk"]
	var ap: AnimationPlayer = inst["ap"]
	var meshes := _mesh_data(sk, inst["root"])
	var dom := _dominant_bones(sk, meshes)
	var edges := _edges(meshes)
	# Bind pose: the mesh's own vertices (skin binds map mesh space into each bone's space). Resetting
	# the skeleton to rest doesn't reproduce it on retargeted models: the rest fixer moves the rests
	# (13 cm off on the player). The Hips bind frame is the inverse of the Hips bind pose.
	var rest := PackedVector3Array()
	var hips_rest := sk.global_transform
	for md in meshes:
		for v in md["verts"]:
			rest.append(sk.global_transform * v)
		var hb: int = Array(md["bind_bones"]).find(sk.find_bone("Hips"))
		if hb >= 0:
			hips_rest = sk.global_transform * md["bind_poses"][hb].affine_inverse()
	var rest_local := PackedVector3Array()
	for p in rest:
		rest_local.append(hips_rest.affine_inverse() * p)
	var rest_len := PackedFloat32Array()
	for e in range(0, edges.size(), 2):
		rest_len.append(rest[edges[e]].distance_to(rest[edges[e + 1]]))
	ap.play(clip)
	var length := lib.get_animation(clip).length
	var n := int(ceil(length * FPS)) + 1
	var series := {
		"t": [],
		"hips": [],
		"left_foot": [],
		"right_foot": [],
		"left_contact": [],
		"right_contact": [],
		"bind_deviation_max": [],
		"edge_stretch_max": []
	}
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var dev_all := []
	var stretch_all := []
	var dev_worst := [0.0, ""]
	var stretch_worst := [0.0, ""]
	var stretch_worst_t := 0.0
	for f in n:
		var t: float = minf(f / FPS, length)
		ap.seek(t, true)
		var hips := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips"))
		var pos := _skin(sk, meshes)
		var inv := hips.affine_inverse()
		var fdev := 0.0
		for v in pos.size():
			lo = lo.min(pos[v])
			hi = hi.max(pos[v])
			var d := (inv * pos[v]).distance_to(rest_local[v])
			if d > fdev:
				fdev = d
			if d > dev_worst[0]:
				dev_worst = [d, dom[v]]
			if v % 7 == 0:
				dev_all.append(d)
		var fst := 0.0
		for e in range(0, edges.size(), 2):
			var l0 := rest_len[e / 2]
			if l0 < MIN_EDGE:
				continue
			var s := absf(pos[edges[e]].distance_to(pos[edges[e + 1]]) / l0 - 1.0)
			if s > fst:
				fst = s
			if s > stretch_worst[0]:
				stretch_worst = [s, dom[edges[e]]]
				stretch_worst_t = t
			if e % 14 == 0:
				stretch_all.append(s)
		series["t"].append(t)
		series["hips"].append(hips.origin)
		for side in ["left", "right"]:
			var prefix := "Left" if side == "left" else "Right"
			var foot := _bone_pos(sk, prefix + "Foot")
			var toes := _bone_pos(sk, prefix + "Toes")
			series[side + "_foot"].append(toes if toes.y < foot.y else foot)
		series["bind_deviation_max"].append(fdev)
		series["edge_stretch_max"].append(fst)
	holder.queue_free()
	# Contacts and ground-relative speeds
	var ground := Vector3(0, 0, ground_speed)  # the model faces +Z; an in-place clip's ground moves toward -Z
	var slides := []
	var contact_frames := 0
	var speeds := {"left": [], "right": [], "hips": []}
	for side in ["left", "right"]:
		var ys: Array = series[side + "_foot"].map(func(p): return p.y)
		var floor_y: float = ys.min()
		for f in n:
			var v := _velocity(series[side + "_foot"], f, series["t"]) + ground
			# Planted: near its lowest point and not lifting or striking (heel-strike and toe-off frames
			# are close to the floor but still moving vertically)
			var c: bool = ys[f] <= floor_y + CONTACT_HEIGHT and absf(v.y) < CONTACT_VSPEED
			series[side + "_contact"].append(c)
			var sp := Vector2(v.x, v.z).length()
			speeds[side].append(sp)
			if c:
				contact_frames += 1
				slides.append(sp)
	for f in n:
		var v := _velocity(series["hips"], f, series["t"]) + ground
		speeds["hips"].append(Vector2(v.x, v.z).length())
	var h0: Vector3 = series["hips"][0]
	var travel := []
	for p: Vector3 in series["hips"]:
		travel.append(Vector2(p.x - h0.x, p.z - h0.z).length())
	return {
		"n": n,
		"length": length,
		"series": series,
		"speeds": speeds,
		"bounds": [lo, hi],
		"root_travel_max_m": snappedf(travel.max(), 0.001),
		"root_travel_final_m": snappedf(travel[-1], 0.001),
		"contact_frames": contact_frames,
		"foot_slide_p90_mps": snappedf(_percentile(slides, 0.9), 0.001),
		"foot_slide_max_mps": snappedf(slides.max() if slides else 0.0, 0.001),
		"bind_deviation_max_m": snappedf(dev_worst[0], 0.001),
		"bind_deviation_p99_m": snappedf(_percentile(dev_all, 0.99), 0.001),
		"bind_deviation_worst_bone": dev_worst[1],
		"edge_stretch_max": snappedf(stretch_worst[0], 0.001),
		"edge_stretch_p99": snappedf(_percentile(stretch_all, 0.99), 0.001),
		"edge_stretch_worst_bone": stretch_worst[1],
		"edge_stretch_worst_t": stretch_worst_t,
		"vertices": rest.size(),
		"edges": edges.size() / 2
	}


func _velocity(points: Array, f: int, ts: Array) -> Vector3:
	var a := maxi(f - 1, 0)
	var b := mini(f + 1, points.size() - 1)
	if b == a:
		return Vector3.ZERO
	return (points[b] - points[a]) / (ts[b] - ts[a])


# ── Rendering ─────────────────────────────────────────────────────────────────


func _viewport(size: Vector2i, transparent: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.transparent_bg = transparent
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.42, 0.40)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	vp.add_child(sun)
	return vp


func _capture(vp: SubViewport) -> Image:
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	return img


func _box(parent: Node, size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)


func _ortho(parent: Node, pos: Vector3, look_at_point: Vector3, up: Vector3, size: float) -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	cam.far = 100.0
	parent.add_child(cam)
	cam.look_at_from_position(pos, look_at_point, up)
	cam.current = true


func _tint(root: Node, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat


func _strip(lib: AnimationLibrary, clip: String, m: Dictionary, times: Array) -> Image:
	var lo: Vector3 = m["bounds"][0]
	var hi: Vector3 = m["bounds"][1]
	var span := maxf(maxf(hi.x - lo.x, hi.z - lo.z), 0.6) + 0.3
	var tall := (hi.y - lo.y) + 0.45
	var mpp := maxf(span / CELL.x, tall / CELL.y)  # metres per pixel
	var cw := CELL.x * mpp
	var chh := CELL.y * mpp
	var cols := times.size()
	var vp := _viewport(Vector2i(CELL.x * cols, CELL.y * 2), false)
	var cz := (lo.z + hi.z) / 2
	for r in 2:
		for c in cols:
			var x0 := c * cw + cw / 2
			var y0 := -r * chh
			var inst := _spawn(vp, lib, clip, times[c])
			# Row 0: side view (forward +Z turned to screen right). Row 1: three-quarter.
			var yaw := -PI / 2 if r == 0 else deg_to_rad(-35)
			var root: Node3D = inst["root"]
			root.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(x0, y0 - lo.y - chh / 2 + 0.2, 0))
			if r == 0:
				root.position.x -= cz  # centre the clip's forward range in the cell
				_box(
					vp,
					Vector3(0.01 * mpp * 100 * 0.2, chh * 0.9, 0.01),
					Vector3(x0 - cz, y0, -2),
					Color(0.85, 0.1, 0.1)
				)
			_box(
				vp,
				Vector3(cw * 0.96, 0.012 * mpp * 100 * 0.3, 0.3),
				Vector3(x0, root.position.y, -2.5),
				Color(0.2, 0.2, 0.2)
			)
			var label := Label3D.new()
			label.text = (
				"%s  t=%.2fs  %d/%d" % ["side" if r == 0 else "3/4", times[c], c + 1, cols]
				if c == 0
				else "t=%.2fs  %d/%d" % [times[c], c + 1, cols]
			)
			label.pixel_size = mpp * 0.55
			label.font_size = 24
			label.modulate = Color.BLACK
			label.outline_size = 0
			label.position = Vector3(x0, y0 + chh / 2 - 12 * mpp, 1)
			vp.add_child(label)
	_ortho(vp, Vector3(cols * cw / 2, -chh / 2, 20), Vector3(cols * cw / 2, -chh / 2, 0), Vector3.UP, chh * 2)
	var img: Image = await _capture(vp)
	vp.queue_free()
	return img


# The frame with the most skin stretch, framed on its STRETCH_EDGES worst edges (drawn in red), front
# and back: stretch too small to see in the strip.
func _stretch_detail(lib: AnimationLibrary, clip: String, m: Dictionary) -> Image:
	var vp := _viewport(Vector2i(ONION_SIZE.x * 2, ONION_SIZE.y), false)
	var inst := _spawn(vp, lib, clip, m["edge_stretch_worst_t"])
	var sk: Skeleton3D = inst["sk"]
	var meshes := _mesh_data(sk, inst["root"])
	var edges := _edges(meshes)
	var pos := _skin(sk, meshes)
	var rest := PackedVector3Array()
	for md in meshes:
		for v in md["verts"]:
			rest.append(sk.global_transform * v)
	var ranked := []
	for e in range(0, edges.size(), 2):
		var l0 := rest[edges[e]].distance_to(rest[edges[e + 1]])
		if l0 >= MIN_EDGE:
			ranked.append([absf(pos[edges[e]].distance_to(pos[edges[e + 1]]) / l0 - 1.0), edges[e], edges[e + 1]])
	ranked.sort_custom(func(a, b): return a[0] > b[0])
	var centre := Vector3.ZERO
	var worst: Array = ranked.slice(0, STRETCH_EDGES)
	for w in worst:
		var a: Vector3 = pos[w[1]]
		var b: Vector3 = pos[w[2]]
		centre += (a + b) / 2 / worst.size()
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.006, 0.006, maxf(a.distance_to(b), 0.001))
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 0, 0)
		mat.no_depth_test = true
		bm.material = mat
		mi.mesh = bm
		vp.add_child(mi)
		mi.look_at_from_position(
			(a + b) / 2, b if not (b - a).cross(Vector3.UP).is_zero_approx() else b + Vector3(0.001, 0, 0), Vector3.UP
		)
	# Two cameras can't share one viewport, so render front and back as two captures
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.7
	vp.add_child(cam)
	vp.size = ONION_SIZE
	cam.look_at_from_position(centre + Vector3(0, 0, 5), centre, Vector3.UP)
	cam.current = true
	var front: Image = await _capture(vp)
	cam.look_at_from_position(centre + Vector3(0, 0, -5), centre, Vector3.UP)
	var back: Image = await _capture(vp)
	vp.queue_free()
	var ft := ImageTexture.create_from_image(front)
	var bt := ImageTexture.create_from_image(back)
	var header := 60
	return await _canvas(
		Vector2i(ONION_SIZE.x * 2 + 30, ONION_SIZE.y + header + 10),
		func(ctl: Control):
			_text(
				ctl,
				Vector2(10, 26),
				(
					"%s  most skin stretch at t=%.2f s: the %d worst edges in red (drawn through the mesh), 0.7 m across"
					% [clip, m["edge_stretch_worst_t"], worst.size()]
				),
				20
			)
			_text(
				ctl,
				Vector2(10, 50),
				(
					"Worst edge %.2fx its bind length on %s; ratios of the red edges: %s"
					% [
						1.0 + m["edge_stretch_max"],
						m["edge_stretch_worst_bone"],
						", ".join(worst.map(func(w): return "%.1f" % (1.0 + w[0])))
					]
				),
				15
			)
			ctl.draw_texture(ft, Vector2(10, header))
			ctl.draw_texture(bt, Vector2(ONION_SIZE.x + 20, header))
			_text(ctl, Vector2(18, header + 22), "FRONT", 16, Color.WHITE)
			_text(ctl, Vector2(ONION_SIZE.x + 28, header + 22), "BACK", 16, Color.WHITE)
	)


func _onion_view(lib: AnimationLibrary, clip: String, m: Dictionary, times: Array, top: bool) -> Image:
	var lo: Vector3 = m["bounds"][0]
	var hi: Vector3 = m["bounds"][1]
	var vp := _viewport(ONION_SIZE, false)
	var cx := (lo.x + hi.x) / 2
	var cz := (lo.z + hi.z) / 2
	var cy := (lo.y + hi.y) / 2
	var extent := maxf(maxf(hi.x - lo.x, hi.z - lo.z), hi.y - lo.y) + 0.6
	# Floor grid every 0.25 m, the origin in red
	var g := snappedf(extent, 0.25) + 0.5
	for i in range(-int(g / 0.25), int(g / 0.25) + 1):
		var w := 0.006 if i % 4 else 0.014
		_box(vp, Vector3(w, 0.002, g * 2), Vector3(i * 0.25, 0, cz), Color(0.3, 0.3, 0.3))
		_box(vp, Vector3(g * 2, 0.002, w), Vector3(cx, 0, i * 0.25), Color(0.3, 0.3, 0.3))
	_box(vp, Vector3(0.3, 0.02, 0.02), Vector3(0, 0.01, 0), Color(0.9, 0.05, 0.05))
	_box(vp, Vector3(0.02, 0.02, 0.3), Vector3(0, 0.01, 0), Color(0.9, 0.05, 0.05))
	_box(vp, Vector3(0.02, hi.y + 0.2, 0.02), Vector3(0, (hi.y + 0.2) / 2, 0), Color(0.9, 0.05, 0.05))
	for i in times.size():
		var u := float(i) / maxi(times.size() - 1, 1)
		var inst := _spawn(vp, lib, clip, times[i])
		var edge := i == 0 or i == times.size() - 1
		_tint(inst["root"], Color(u, 0.25, 1.0 - u, 0.55 if edge else 0.16))
	# The Hips path: one dot per sampled frame, blue to red
	var hips: Array = m["series"]["hips"]
	for f in hips.size():
		var u := float(f) / maxi(hips.size() - 1, 1)
		_box(vp, Vector3(0.035, 0.035, 0.035), hips[f], Color(u, 0.25, 1.0 - u))
	if top:
		_ortho(vp, Vector3(cx, 20, cz), Vector3(cx, 0, cz), Vector3(0, 0, -1), extent)
	else:
		_ortho(vp, Vector3(20, cy, cz), Vector3(0, cy, cz), Vector3.UP, extent)
	var img: Image = await _capture(vp)
	vp.queue_free()
	return img


# Two-dimensional compositions (titles, legends, plots) are drawn by a Control in a SubViewport.
func _canvas(size: Vector2i, draw: Callable) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.95, 0.95, 0.93)
	bg.size = size
	vp.add_child(bg)
	var ctl := Control.new()
	ctl.size = size
	vp.add_child(ctl)
	ctl.draw.connect(func(): draw.call(ctl))
	var img: Image = await _capture(vp)
	vp.queue_free()
	return img


func _text(ctl: Control, pos: Vector2, s: String, size := 16, color := Color.BLACK) -> void:
	ctl.draw_string(ThemeDB.fallback_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _onion(lib: AnimationLibrary, clip: String, m: Dictionary, times: Array, source: String) -> Image:
	var side_img: Image = await _onion_view(lib, clip, m, times, false)
	var top_img: Image = await _onion_view(lib, clip, m, times, true)
	var side_tex := ImageTexture.create_from_image(side_img)
	var top_tex := ImageTexture.create_from_image(top_img)
	var header := 70
	return await _canvas(
		Vector2i(ONION_SIZE.x * 2 + 30, ONION_SIZE.y + header + 10),
		func(ctl: Control):
			_text(
				ctl,
				Vector2(10, 26),
				(
					"%s  (%s)  onion skin: %d frames over %.2f s, blue = first, red = last"
					% [clip, source, times.size(), m["length"]]
				),
				20
			)
			_text(
				ctl,
				Vector2(10, 52),
				(
					(
						"Red cross and post = the character's origin; floor grid 0.25 m (bold every 1 m); dots = Hips path."
						+ " Hips travel max %.2f m, final %.2f m."
					)
					% [m["root_travel_max_m"], m["root_travel_final_m"]]
				),
				15
			)
			ctl.draw_texture(side_tex, Vector2(10, header))
			ctl.draw_texture(top_tex, Vector2(ONION_SIZE.x + 20, header))
			_text(ctl, Vector2(18, header + 22), "SIDE (forward = +Z, to the left)", 16, Color.WHITE)
			_text(ctl, Vector2(ONION_SIZE.x + 28, header + 22), "TOP (forward = +Z, down)", 16, Color.WHITE)
	)


func _plot_panel(ctl: Control, rect: Rect2, title: String, t: Array, lines: Array, bands := []) -> void:
	# lines: [[label, values, color]]; bands: [[label, bools, color]] shaded along the bottom
	ctl.draw_rect(rect, Color.WHITE)
	ctl.draw_rect(rect, Color(0.3, 0.3, 0.3), false, 1.0)
	_text(ctl, rect.position + Vector2(0, -8), title, 17)
	var lo := INF
	var hi := -INF
	for l in lines:
		lo = minf(lo, l[1].min())
		hi = maxf(hi, l[1].max())
	lo = minf(lo, 0.0)
	if hi - lo < 1e-4:
		hi = lo + 1.0
	var pad := (hi - lo) * 0.08
	lo -= pad
	hi += pad
	var t1: float = maxf(t[-1], 1e-3)
	var to_px := func(ti: float, v: float) -> Vector2:
		return Vector2(rect.position.x + ti / t1 * rect.size.x, rect.end.y - (v - lo) / (hi - lo) * rect.size.y)
	for b in bands.size():
		var bools: Array = bands[b][1]
		for f in bools.size():
			if bools[f]:
				var x0: Vector2 = to_px.call(t[maxi(f - 1, 0)] if f > 0 else 0.0, lo)
				var x1: Vector2 = to_px.call(t[f], lo)
				ctl.draw_rect(Rect2(x0.x, rect.end.y - 10 - b * 12, maxf(x1.x - x0.x, 1.0), 10), bands[b][2])
	for k in 5:
		var v := lo + (hi - lo) * k / 4.0
		var p: Vector2 = to_px.call(0.0, v)
		ctl.draw_line(p, Vector2(rect.end.x, p.y), Color(0.88, 0.88, 0.88))
		_text(ctl, Vector2(rect.position.x - 58, p.y + 5), "%.2f" % v, 13)
	var zero: Vector2 = to_px.call(0.0, 0.0)
	ctl.draw_line(zero, Vector2(rect.end.x, zero.y), Color(0.5, 0.5, 0.5), 1.5)
	for k in 6:
		var ti := t1 * k / 5.0
		var p: Vector2 = to_px.call(ti, lo)
		_text(ctl, Vector2(p.x - 14, rect.end.y + 18), "%.2fs" % ti, 13)
	var ly := rect.position.y + 18
	for l in lines:
		var pts := PackedVector2Array()
		for f in t.size():
			pts.append(to_px.call(t[f], l[1][f]))
		ctl.draw_polyline(pts, l[2], 2.0, true)
		ctl.draw_rect(Rect2(rect.end.x - 190, ly - 10, 14, 4), l[2])
		_text(ctl, Vector2(rect.end.x - 170, ly - 3), l[0], 13)
		ly += 17
	for b in bands.size():
		ctl.draw_rect(Rect2(rect.end.x - 190, ly - 10, 14, 8), bands[b][2])
		_text(ctl, Vector2(rect.end.x - 170, ly - 3), bands[b][0], 13)
		ly += 17


func _plots(clip: String, m: Dictionary, ground_speed: float, source: String) -> Image:
	var s: Dictionary = m["series"]
	var t: Array = s["t"]
	var h0: Vector3 = s["hips"][0]
	var dx: Array = s["hips"].map(func(p): return p.x - h0.x)
	var dz: Array = s["hips"].map(func(p): return p.z - h0.z)
	var dxz: Array = s["hips"].map(func(p): return Vector2(p.x - h0.x, p.z - h0.z).length())
	var hy: Array = s["hips"].map(func(p): return p.y)
	var ly: Array = s["left_foot"].map(func(p): return p.y)
	var ry: Array = s["right_foot"].map(func(p): return p.y)
	var lc := Color(0.1, 0.45, 0.85, 0.35)
	var rc := Color(0.85, 0.35, 0.1, 0.35)
	var bands := [["left foot planted", s["left_contact"], lc], ["right foot planted", s["right_contact"], rc]]
	var w := (PLOT_SIZE.x - 200) / 2.0
	var h := (PLOT_SIZE.y - 190) / 2.0
	return await _canvas(
		PLOT_SIZE,
		func(ctl: Control):
			_text(
				ctl,
				Vector2(20, 28),
				"%s  (%s)  %.2f s at %d fps, ground speed %.2f m/s" % [clip, source, m["length"], FPS, ground_speed],
				20
			)
			_text(
				ctl,
				Vector2(20, 52),
				(
					(
						"Hips travel max %.3f m / final %.3f m.  Foot slide p90 %.3f m/s (max %.3f) over %d planted frames."
						+ "  Bind deviation max %.3f m.  Skin stretch max %.3f."
					)
					% [
						m["root_travel_max_m"],
						m["root_travel_final_m"],
						m["foot_slide_p90_mps"],
						m["foot_slide_max_mps"],
						m["contact_frames"],
						m["bind_deviation_max_m"],
						m["edge_stretch_max"]
					]
				),
				15
			)
			_plot_panel(
				ctl,
				Rect2(80, 100, w, h),
				"Root (Hips) horizontal offset from frame 1 (m)",
				t,
				[
					["x", dx, Color(0.2, 0.6, 0.2)],
					["z (forward)", dz, Color(0.1, 0.3, 0.8)],
					["|xz|", dxz, Color(0.8, 0.1, 0.1)]
				]
			)
			_plot_panel(
				ctl,
				Rect2(180 + w, 100, w, h),
				"Heights (m): Hips and each foot's contact point",
				t,
				[
					["hips", hy, Color(0.3, 0.3, 0.3)],
					["left foot", ly, Color(0.1, 0.45, 0.85)],
					["right foot", ry, Color(0.85, 0.35, 0.1)]
				],
				bands
			)
			_plot_panel(
				ctl,
				Rect2(80, 170 + h, w, h),
				"Ground-relative horizontal speed (m/s): feet vs root",
				t,
				[
					["root (hips)", m["speeds"]["hips"], Color(0.3, 0.3, 0.3)],
					["left foot", m["speeds"]["left"], Color(0.1, 0.45, 0.85)],
					["right foot", m["speeds"]["right"], Color(0.85, 0.35, 0.1)]
				],
				bands
			)
			_plot_panel(
				ctl,
				Rect2(180 + w, 170 + h, w, h),
				"Per frame: max vertex deviation from bind pose (m, Hips frame) and max skin stretch",
				t,
				[
					["bind deviation (m)", s["bind_deviation_max"], Color(0.5, 0.2, 0.6)],
					["edge stretch (ratio)", s["edge_stretch_max"], Color(0.1, 0.55, 0.5)]
				]
			)
	)


func _review(clip: String, lib: AnimationLibrary, source: String) -> void:
	var kind := _opt("kind", clip, _default_kind(clip))
	var ground_speed := float(_opt("ground-speed", clip, "0"))
	var m := _measure(lib, clip, ground_speed)
	var frames := int(args.get("frames", 14))
	var times := []
	for i in frames:
		times.append(m["length"] * i / (frames - 1))
	var strip: Image = await _strip(lib, clip, m, times)
	strip.save_png(out_dir.path_join(clip + "_strip.png"))
	var onion: Image = await _onion(lib, clip, m, times, source)
	onion.save_png(out_dir.path_join(clip + "_onion.png"))
	var plots: Image = await _plots(clip, m, ground_speed, source)
	plots.save_png(out_dir.path_join(clip + "_plots.png"))
	if m["edge_stretch_max"] > 0.0:
		var detail: Image = await _stretch_detail(lib, clip, m)
		detail.save_png(out_dir.path_join(clip + "_stretch.png"))
	var s: Dictionary = m["series"]
	var out := {
		"clip": clip,
		"source": source,
		"model": args["model"],
		"kind": kind,
		"length_s": snappedf(m["length"], 0.001),
		"fps": FPS,
		"frames_sampled": m["n"],
		"strip_times_s": times.map(func(x): return snappedf(x, 0.001)),
		"ground_speed_mps": ground_speed,
		"contact_height_m": CONTACT_HEIGHT,
		"vertices": m["vertices"],
		"edges": m["edges"]
	}
	for k in [
		"root_travel_max_m",
		"root_travel_final_m",
		"contact_frames",
		"foot_slide_p90_mps",
		"foot_slide_max_mps",
		"bind_deviation_max_m",
		"bind_deviation_p99_m",
		"bind_deviation_worst_bone",
		"edge_stretch_max",
		"edge_stretch_p99",
		"edge_stretch_worst_bone"
	]:
		out[k] = m[k]
	out["series"] = {
		"t": s["t"],
		"hips": s["hips"].map(func(p): return [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)])
	}
	var f := FileAccess.open(out_dir.path_join(clip + "_metrics.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print(
		(
			"MOTION %s kind=%s travel=%.3f slide_p90=%.3f dev=%.3f stretch=%.3f"
			% [
				clip,
				kind,
				m["root_travel_max_m"],
				m["foot_slide_p90_mps"],
				m["bind_deviation_max_m"],
				m["edge_stretch_max"]
			]
		)
	)
