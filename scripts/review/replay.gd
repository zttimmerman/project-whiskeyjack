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
# Frame 0 is the second physics frame after the level is ready; EventLog frames count from it.
# Timing: in Godot 4.7 an Input.action_press() during physics frame N reads as just-pressed on N+1,
# while is_action_pressed() changes at once. So this node runs last in every physics frame and, at
# the end of frame N, applies the steps for N+1: presses (just-pressed) and holds (movement) both land
# on the step's own frame, and the input event is logged on that frame.
# Exit code: 0 when the run completed, 1 when the scenario couldn't be loaded.

const END_AFTER_DEATH_FRAMES := 30  # well before GameManager reloads the scene (3.2 s)
const CameraProbe := preload("res://scripts/review/camera_probe.gd")

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
		# A warm-up frame: frame 0 is the next one
		_started = true
		EventLog.frame_origin = Engine.get_physics_frames() + 1
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
	var p := _player.global_position
	data["player_position"] = [EventLog.round3(p.x), EventLog.round3(p.y), EventLog.round3(p.z)]
	EventLog.log_event("camera", data)


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
