extends Node

# Replay runner (docs/plans/phase-a/a2b-replay-harness.md): plays a scenario's inputs at exact physics
# frames through the real gameplay code and writes the event log (scripts/debug/EventLog.gd).
#   godot --headless --fixed-fps 60 --path . res://scripts/review/replay.tscn -- \
#       --scenario tests/scenarios/<name>.json --event-log <out.jsonl> --save-slot=replay
# Without --headless it renders, and --write-movie <dir>/frame.png records it
# (scripts/review/capture_evidence.sh). scripts/review/run_scenario.sh wraps both runs and the metrics.
#
# Scenario JSON:
#   name, scene           the level to load
#   seed                  seeds the global RNG (camera shake, particles)
#   player: {position: [x, y, z], yaw_deg, pitch}   start; yaw 0 faces -Z, -90 faces +X
#   remove: [node paths]  level nodes freed before the level enters the tree (to isolate a fight)
#   duration_frames       physics frames to run; the run also ends shortly after the player dies
#   steps: [{frame, action, pressed}]   Input Map actions, pressed or released on that frame
#   checks: [...]         read by scripts/review/replay_metrics.py, not here; any cam_* check turns on the
#                         per-frame camera samples (scripts/review/camera_probe.gd, a "camera" event per frame)
# Frame 0 is the second physics frame after the level is ready; EventLog frames count from it, so the
# level's _ready logs at -2 and the warm-up frame at -1 (tests/scenarios/replay_frame_stamps.json).
# Timing: in Godot 4.7 an Input.action_press() during physics frame N reads as just-pressed on N+1,
# while is_action_pressed() changes at once. So this node runs last in every physics frame and, at
# the end of frame N, applies the steps for N+1: presses (just-pressed) and holds (movement) both land
# on the step's own frame, and the input event is logged on that frame.
# Rendered only: --luminance <out.json> [--luminance-every N] samples the readability targets every N
# frames (default 30) through scripts/review/luminance_probe.gd and writes them, with their summary, to
# <out.json> (scripts/review/capture_luminance.sh); --luminance-shots <dir> also saves each sampled frame
# and the player's pixel mask. The extra renders are drawn synchronously inside the
# physics frame (RenderingServer.force_draw), so no physics frame passes and the event log is unchanged.
# Exit code: 0 when the run completed, 1 when the scenario couldn't be loaded.

const END_AFTER_DEATH_FRAMES := 30  # well before GameManager reloads the scene (3.2 s)
const CameraProbe := preload("res://scripts/review/camera_probe.gd")
const LuminanceProbe := preload("res://scripts/review/luminance_probe.gd")

var _scenario: Dictionary = {}
var _steps: Array[Dictionary] = []
var _next_step: int = 0
var _frame: int = -1
var _started: bool = false
var _duration: int = 0
var _end_frame: int = -1
var _held: Dictionary = {}  # action -> true while a step holds it
var _level: Node = null
var _player: CharacterBody3D = null
var _camera_samples: bool = false
var _luminance_out: String = ""
var _luminance_every: int = 30
var _luminance_samples: Array = []
var _luminance_shots: String = ""  # a directory: each sample's frame and its subject mask as PNGs


func _ready() -> void:
	# Last in every physics frame: it applies the next frame's inputs after gameplay has read this one's
	process_physics_priority = 1000
	# macOS throttles a covered vsynced window's swaps and a render run crawls (scripts/review/*)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var path := _arg("--scenario")
	if path.is_empty():
		_fail("no --scenario <json> given")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_fail("can't read scenario %s" % path)
		return
	_scenario = parsed
	_luminance_out = _arg("--luminance")
	if not _luminance_out.is_empty():
		if DisplayServer.get_name() == "headless":
			_fail("--luminance needs a rendered window (drop --headless)")
			return
		var every := _arg("--luminance-every")
		_luminance_every = maxi(int(every), 1) if not every.is_empty() else _luminance_every
		_luminance_shots = _arg("--luminance-shots")
	if DisplayServer.get_name() == "headless":
		# A headless root viewport is 64x64; the camera checks need the game's window shape (16:9)
		get_tree().root.size = Vector2i(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height")
		)
	# Replays never touch the player's save, whatever the command line said
	if SaveManager.get_save_path() == SaveManager.SAVE_PATH:
		SaveManager.set_save_slot("replay")
	if not EventLog.enabled:
		push_warning("replay: no --event-log given; the run leaves no record")
	seed(int(_scenario.get("seed", 0)))
	_duration = int(_scenario.get("duration_frames", 600))
	for step: Dictionary in _scenario.get("steps", []):
		if not InputMap.has_action(String(step.get("action", ""))):
			_fail("unknown action in step %s" % JSON.stringify(step))
			return
		_steps.append(step)
	for check: Dictionary in _scenario.get("checks", []):
		if String(check.get("id", "")).begins_with("cam_"):
			_camera_samples = true
	_steps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["frame"]) < int(b["frame"]))

	var packed := load(String(_scenario.get("scene", ""))) as PackedScene
	if packed == null:
		_fail("can't load scene %s" % _scenario.get("scene", ""))
		return
	# Set before the level enters the tree, so its _ready and the warm-up frame (where gameplay runs
	# before this node) stamp -2 and -1, never frame counts from origin 0 that sort among frames 0 and up
	EventLog.frame_origin = Engine.get_physics_frames() + 2
	_level = packed.instantiate()
	for node_path: String in _scenario.get("remove", []):
		var node := _level.get_node_or_null(node_path)
		if node == null:
			_fail("remove: no node %s in the scene" % node_path)
			return
		node.get_parent().remove_child(node)
		node.free()
	add_child(_level)
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		_fail("the scene has no player")
		return
	_place_player()
	# The replay owns every action: with the Input Map's keys, buttons and pad axes erased, a real
	# device can't reach the game (a rendered run once got a dodge from a modifier key's state as the
	# window opened); Input.action_press() still drives the actions. Mouse look reads raw motion in
	# the player's _input, so that is off too.
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
	_player.set_process_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_player.died.connect(_on_player_died)


func _place_player() -> void:
	var start: Dictionary = _scenario.get("player", {})
	if start.has("position"):
		var p: Array = start["position"]
		_player.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	var yaw := deg_to_rad(float(start.get("yaw_deg", 0.0)))
	_player.apply_view_state({"facing": yaw, "camera_yaw": yaw, "camera_pitch": float(start.get("pitch", -0.2))})


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	if not _started:
		# A warm-up frame (-1): frame 0 is the next one
		_started = true
		if Engine.get_physics_frames() + 1 != EventLog.frame_origin:
			push_error("replay: the warm-up frame isn't frame -1; frame stamps are off")
		EventLog.log_event_at(
			0,
			"scenario_start",
			{
				"scenario": String(_scenario.get("name", "")),
				"seed": int(_scenario.get("seed", 0)),
				"process_frame": Engine.get_process_frames() + 1,
				"duration_frames": _duration
			}
		)
	_frame = Engine.get_physics_frames() - EventLog.frame_origin
	if _frame >= _duration or (_end_frame >= 0 and _frame >= _end_frame):
		_finish()
		return
	if _camera_samples and _frame >= 0:
		_sample_camera()
	while _next_step < _steps.size() and int(_steps[_next_step]["frame"]) <= _frame + 1:
		_apply(_steps[_next_step], _frame + 1)
		_next_step += 1
	if not _luminance_out.is_empty() and _frame >= 0 and _frame % _luminance_every == 0:
		_sample_luminance()


func _apply(step: Dictionary, lands_on: int) -> void:
	var action := String(step["action"])
	var pressed := bool(step.get("pressed", true))
	if pressed:
		Input.action_press(action)
		_held[action] = true
	else:
		Input.action_release(action)
		_held.erase(action)
	EventLog.log_event_at(lands_on, "input", {"action": action, "pressed": pressed})


# Runs last in the physics frame, after the player and his camera rig have moved
func _sample_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var target: Node3D = _player.call("get_lock_on_target") if _player.has_method("get_lock_on_target") else null
	var s := CameraProbe.sample(camera, _player, target)
	var data := {}
	for key: String in s:
		data[key] = EventLog.round3(s[key]) if s[key] is float else s[key]
	if s["locked"]:
		data["target"] = EventLog.label(target)
	var c := camera.global_position
	data["camera_position"] = [EventLog.round3(c.x), EventLog.round3(c.y), EventLog.round3(c.z)]
	data["look_pitch_deg"] = EventLog.round3(rad_to_deg(asin(clampf(-camera.global_basis.z.y, -1.0, 1.0))))
	var look := -camera.global_basis.z
	data["look_yaw_deg"] = EventLog.round3(rad_to_deg(atan2(-look.x, -look.z)))
	var p := _player.global_position
	data["player_position"] = [EventLog.round3(p.x), EventLog.round3(p.y), EventLog.round3(p.z)]
	EventLog.log_event("camera", data)


# Paired renders of this frame (the subject shown, then hidden) for the floor and each character's contrast,
# with the HUD hidden so it covers neither. Runs last in the physics frame, like the camera sample
func _sample_luminance() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var layers: Array[CanvasLayer] = []
	for node in _level.find_children("*", "CanvasLayer", true, false):
		if (node as CanvasLayer).visible:
			layers.append(node)
			(node as CanvasLayer).visible = false
	# The first draw of a frame can still show the previous frame's state; the second is the reference
	_draw()
	var full := _draw()
	_player.visible = false
	var no_player := _draw()
	_player.visible = true
	var mask := LuminanceProbe.diff_mask(full, no_player, _subject_rect(camera, _player, full.get_size()))
	var space := camera.get_world_3d().direct_space_state
	var exclude: Array[RID] = [_player.get_rid()]
	var sample := {
		"frame": _frame,
		"floor": LuminanceProbe.floor_luminance(full, camera, space, _floor_height(space), exclude, mask),
		"player": LuminanceProbe.subject_contrast(full, no_player, mask),
		"enemies": []
	}
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var body := enemy as Node3D
		if body == null or not body.visible or (enemy.has_method("is_dead") and enemy.call("is_dead")):
			continue
		var rect := _subject_rect(camera, body, full.get_size())
		if not rect.has_area():
			continue
		# A fresh reference per subject: a mesh shown again after a hidden draw can differ for a draw
		var shown := _draw()
		body.visible = false
		var without := _draw()
		body.visible = true
		var row := LuminanceProbe.subject_contrast(shown, without, LuminanceProbe.diff_mask(shown, without, rect))
		row["name"] = EventLog.label(enemy)
		row["distance_m"] = snappedf(camera.global_position.distance_to(body.global_position), 0.01)
		sample.enemies.append(row)
	for layer in layers:
		layer.visible = true
	_luminance_samples.append(sample)
	if not _luminance_shots.is_empty():
		full.save_png(_luminance_shots.path_join("f%04d.png" % _frame))
		var shown := Image.create(full.get_width(), full.get_height(), false, Image.FORMAT_L8)
		for p: Vector2i in mask:
			shown.set_pixel(p.x, p.y, Color.WHITE)
		shown.save_png(_luminance_shots.path_join("f%04d_player_mask.png" % _frame))


func _subject_rect(camera: Camera3D, body: Node3D, size: Vector2i) -> Rect2i:
	var c := CameraProbe.capsule(body)
	return LuminanceProbe.screen_rect(camera, c.center, c.radius, c.height, size)


# Draws the frame now, without a main-loop iteration (so no physics frame passes), and reads it back
func _draw() -> Image:
	RenderingServer.force_draw(false, 0.0)
	return get_viewport().get_texture().get_image()


# Height of the floor under the player: the walkable floor band the probe reads
func _floor_height(space: PhysicsDirectSpaceState3D) -> float:
	var at := _player.global_position
	var q := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 4.0)
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else at.y - 0.9


func _write_luminance() -> void:
	var summary := LuminanceProbe.summarize(_luminance_samples)
	var f := FileAccess.open(_luminance_out, FileAccess.WRITE)
	if f == null:
		push_error("replay: can't write %s" % _luminance_out)
		return
	f.store_string(
		JSON.stringify(
			{
				"scenario": String(_scenario.get("name", "")),
				"scene": String(_scenario.get("scene", "")),
				"every_frames": _luminance_every,
				"summary": summary,
				"samples": _luminance_samples
			},
			"  "
		)
	)
	f.close()


func _on_player_died() -> void:
	_end_frame = _frame + END_AFTER_DEATH_FRAMES


func _finish() -> void:
	set_physics_process(false)
	for action: String in _held:
		Input.action_release(action)
	var alive: Array[String] = []
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy.has_method("is_dead") and not enemy.call("is_dead"):
			alive.append(EventLog.label(enemy))
	alive.sort()
	var stats: CharacterStats = _player.get("stats")
	var pos := _player.global_position
	EventLog.log_event(
		"scenario_end",
		{
			"player_hp": stats.current_hp if stats else -1,
			"player_max_hp": stats.max_hp if stats else -1,
			"player_position": [EventLog.round3(pos.x), EventLog.round3(pos.y), EventLog.round3(pos.z)],
			"enemies_alive": alive
		}
	)
	EventLog.close()
	if not _luminance_out.is_empty():
		_write_luminance()
	print("replay: %s finished at frame %d" % [_scenario.get("name", ""), _frame])
	get_tree().quit(0)


func _arg(key: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i].begins_with(key + "="):
			return args[i].trim_prefix(key + "=")
		if args[i] == key and i + 1 < args.size():
			return args[i + 1]
	return ""


func _fail(message: String) -> void:
	push_error("replay: " + message)
	EventLog.close()
	get_tree().quit(1)
