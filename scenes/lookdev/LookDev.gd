extends Node

# Look-dev spike (docs/backlog/spike-look-dev.md, docs/trials/look-dev.md): the same player in the same room
# under each look variant, from fixed shots, plus frame times. Review tool only: it changes nothing in the
# shipped game; every variant is applied at runtime to an instanced copy of the level.
# Windowed (headless can't render), as a scene so the project's autoloads load:
#   godot --always-on-top --fixed-fps 30 --path . res://scenes/lookdev/LookDev.tscn -- \
#       --variant A|B1|B2|B3|B3plus --room level1|crypt --mode stills|timing --out <dir> [--size WxH]
#       [--model res://assets/lookdev/player_b1_1024.glb]  (another B1 build, e.g. SIZE=1024 build_b1.sh)
# B3 and B3plus need `--rendering-method forward_plus` on the command line (the project stays on
# Compatibility); scripts/lookdev/run_lookdev.sh passes it.
#   A       as shipped: assets/meshes/player.glb, the level's own lighting
#   B1      the player re-cleaned with smooth (source) normals and the 2048 px source texture
#           (assets/lookdev/player_b1.glb, scripts/lookdev/build_b1.sh), the level's own lighting
#   B2      B1 + lighting: brighter warm ambient, filmic tonemap, depth fog, warmer and stronger torches
#           with a steeper falloff, a dimmer cool key
#   B3      B2 under Forward+
#   B3plus  B3 + what only Forward+ draws: SSAO, volumetric fog, torch shadows
# stills writes <out>/<room>_<shot>_<variant>.png and, for level1, a turntable's frames to
# <out>/turntable_<variant>/; timing writes <out>/timing_<room>_<variant>.json.

const SETTLE_FRAMES := 30
const B1_MODEL := "res://assets/lookdev/player_b1.glb"
const TIMING_WARMUP := 120
const TIMING_FRAMES := 600
const TURNTABLE_FRAMES := 90

# Room overview shots (positions from scripts/review/level1_stills.gd)
const ROOM_SHOTS := {
	"level1": {"room": [Vector3(17.5, 3.4, -7.0), Vector3(27.0, 0.5, 4.0)]},
	"crypt": {"room": [Vector3(0.0, 5.0, -0.6), Vector3(0.0, 0.5, -9.0)]},
}
const ROOM_SCENES := {
	"level1": "res://scenes/world/Level1.tscn",
	"crypt": "res://scenes/world/trials/CryptTrial.tscn",
}

var _args := {}
var _level: Node
var _player: Node3D
var _cam: Camera3D


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var argv := OS.get_cmdline_user_args()
	for i in range(0, argv.size() - 1, 2):
		_args[argv[i].trim_prefix("--")] = argv[i + 1]
	var size: PackedStringArray = _args.get("size", "1280x720").split("x")
	get_window().size = Vector2i(int(size[0]), int(size[1]))
	var variant: String = _args.get("variant", "A")
	var room: String = _args.get("room", "level1")
	_level = load(ROOM_SCENES[room]).instantiate()
	_player = _level.get_node("Player")
	if variant != "A":
		_swap_player_model()
	add_child(_level)
	var ui := _level.get_node_or_null("CanvasLayer")
	if ui:
		ui.visible = false
	if variant in ["B2", "B3", "B3plus"]:
		_apply_lighting(variant == "B3plus")
	print("LOOKDEV variant=%s room=%s renderer=%s" % [variant, room, RenderingServer.get_current_rendering_method()])
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	_cam = Camera3D.new()
	add_child(_cam)
	if _args.get("mode", "stills") == "timing":
		await _timing(room, variant)
	else:
		await _stills(room, variant)
	get_tree().quit()


## B1+: the variant player mesh in place of the shipped one, keeping Player.tscn's AnimationPlayer
## (it holds the shared animation library), so Player.gd drives it exactly as it drives the shipped model.
func _swap_player_model() -> void:
	var old: Node3D = _player.get_node("PlayerModel")
	var path: String = _args.get("model", B1_MODEL)
	var model: Node3D = (load(path) as PackedScene).instantiate()
	model.transform = old.transform
	var anim := old.get_node("AnimationPlayer")
	old.remove_child(anim)
	var index := old.get_index()
	_player.remove_child(old)
	old.free()
	model.name = "PlayerModel"
	_player.add_child(model)
	_player.move_child(model, index)
	model.add_child(anim)


func _apply_lighting(forward_extras: bool) -> void:
	for node in _level.find_children("*", "WorldEnvironment", true, false):
		var we := node as WorldEnvironment
		var env: Environment = we.environment.duplicate()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.03, 0.025, 0.02)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.56, 0.5, 0.45)
		env.ambient_light_energy = 0.8
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure = 1.15
		env.fog_enabled = true
		env.fog_light_color = Color(0.12, 0.09, 0.07)
		env.fog_density = 0.03
		env.fog_sky_affect = 0.0
		if forward_extras:
			env.ssao_enabled = true
			env.ssao_radius = 1.2
			env.ssao_intensity = 1.6
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.01
			env.volumetric_fog_albedo = Color(0.9, 0.8, 0.7)
		we.environment = env
	for node in _level.find_children("*", "DirectionalLight3D", true, false):
		var key := node as DirectionalLight3D
		key.light_energy = 0.55
		key.light_color = Color(0.78, 0.84, 1.0)
	for node in _level.find_children("*", "OmniLight3D", true, false):
		var torch := node as OmniLight3D
		if _player.is_ancestor_of(torch):
			continue  # the player's own CameraRig/FillLight stays as shipped
		torch.light_color = Color(1.0, 0.7, 0.4)
		torch.light_energy = 1.6
		torch.omni_range = 7.0
		torch.omni_attenuation = 1.6
		if forward_extras:
			torch.shadow_enabled = true


func _model() -> Node3D:
	return _player.get_node("PlayerModel")


func _head() -> Vector3:
	var skel := _model().find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	return skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Head")).origin


func _character_shots() -> Dictionary:
	var model := _model()
	var front := model.global_basis.z.normalized()  # the model faces its own +Z (the 180 deg node turn)
	var right := front.cross(Vector3.UP).normalized()
	var face := _head() + Vector3.UP * 0.09
	var body := model.global_position + Vector3.UP * 0.9
	return {
		"face": [face + front * 0.8 - Vector3.UP * 0.12, face, 32.0],
		"body34": [body + (front + right).normalized() * 3.0 + Vector3.UP * 0.25, body, 45.0],
	}


func _shoot(path: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SAVED ", path)


func _stills(room: String, variant: String) -> void:
	var out: String = _args["out"]
	# The gameplay camera as it spawns: the player's own CameraRig camera
	await _shoot(out.path_join("%s_gameplay_%s.png" % [room, variant]))
	var shots := _character_shots()
	shots["room"] = ROOM_SHOTS[room]["room"] + [75.0]
	_cam.current = true
	for shot: String in shots:
		var spec: Array = shots[shot]
		_cam.fov = spec[2]
		_cam.look_at_from_position(spec[0], spec[1], Vector3.UP)
		await _shoot(out.path_join("%s_%s_%s.png" % [room, shot, variant]))
	if room == "level1":
		await _turntable(out.path_join("turntable_" + variant))


## One turn around the idling player at the 3/4 framing (the idle keeps playing, so shading moves with it)
func _turntable(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var body := _model().global_position + Vector3.UP * 0.9
	_cam.fov = 45.0
	for i in TURNTABLE_FRAMES:
		var a := TAU * i / TURNTABLE_FRAMES
		var dir_v := Vector3(sin(a), 0.0, cos(a))
		_cam.look_at_from_position(body + dir_v * 3.0 + Vector3.UP * 0.25, body, Vector3.UP)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("f%03d.png" % i))


## Frame time from the gameplay camera and the room overview: wall-clock frame delta plus the viewport's
## measured CPU and GPU render time, median and p95 over TIMING_FRAMES after a warm-up (vsync off).
func _timing(room: String, variant: String) -> void:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var result := {
		"variant": variant,
		"room": room,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"window": [get_window().size.x, get_window().size.y],
		"viewport_px": [get_viewport().get_texture().get_width(), get_viewport().get_texture().get_height()],
		"frames": TIMING_FRAMES,
	}
	for view: String in ["gameplay", "overview"]:
		if view == "overview":
			var spec: Array = ROOM_SHOTS[room]["room"]
			_cam.fov = 75.0
			_cam.look_at_from_position(spec[0], spec[1], Vector3.UP)
			_cam.current = true
		for i in TIMING_WARMUP:
			await get_tree().process_frame
		var wall: Array[float] = []
		var cpu: Array[float] = []
		var gpu: Array[float] = []
		var last := Time.get_ticks_usec()
		for i in TIMING_FRAMES:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			wall.append((now - last) / 1000.0)
			last = now
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		result[view] = {"frame_ms": _stats(wall), "render_cpu_ms": _stats(cpu), "render_gpu_ms": _stats(gpu)}
	var tag: String = ("_" + _args["size"]) if _args.has("size") else ""
	var path: String = _args["out"].path_join("timing_%s_%s%s.json" % [room, variant, tag])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "  "))
	f.close()
	print("SAVED ", path)


func _stats(values: Array[float]) -> Dictionary:
	var s := values.duplicate()
	s.sort()
	return {"median": snappedf(s[int(s.size() / 2.0)], 0.001), "p95": snappedf(s[int(s.size() * 0.95)], 0.001)}
