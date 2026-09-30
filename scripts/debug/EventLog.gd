extends Node

## Gameplay event log (autoload EventLog): one JSON object per line, stamped with the physics frame,
## for replays (scripts/review/replay.tscn), their metrics (scripts/review/replay_metrics.py) and
## playtests. Off unless a file is named, and off it opens nothing and writes nothing; every hook in
## gameplay code is guarded by `if EventLog.enabled:`, so an off log costs one bool check.
##   godot ... -- --event-log=<path>      (or `--event-log <path>`; wins over the env var)
##   WHISKEYJACK_EVENT_LOG=<path> godot ...
## Paths are absolute, res://, user://, or relative to the project directory.
##
## Events and their fields (besides "frame" and "event"):
##   attack_started  actor, kind (light | heavy | melee | ranged), combo_index and damage (player)
##   attack_windup   actor                   (reserved: enemy telegraphs don't exist yet)
##   hitbox_open     actor, heavy, damage    (logged when activate() is called; the overlap
##   hitbox_close    actor                    starts on the next physics step)
##   hit             attacker, target, damage, heavy, iframed
##   iframe_block    target, attacker        (a hit ignored by i-frames)
##   damage_taken    target, attacker, raw, amount, hp, max_hp
##   dodge_start     actor, duration_s, invincible
##   dodge_end       actor, invincible
##   stagger         actor, interrupted_attack
##   death           actor
##   lock_on         actor, target
##   lock_off        actor
##   detected        actor, target, distance, line_of_sight   (enemy spotted the player)
##   disengaged      actor, distance          (enemy leashed back to idle)
##   quest           kind (started | updated | completed), quest_id, stage
## The replay runner adds scenario_start, input and scenario_end.

const ARG := "--event-log"
const ENV := "WHISKEYJACK_EVENT_LOG"
## Physics layer the line-of-sight probe collides with (layer 1, "world")
const WORLD_MASK := 1
const EYE_HEIGHT := 0.8

var enabled: bool = false
var path: String = ""
## Subtracted from Engine.get_physics_frames(); a replay sets it at its first frame
var frame_origin: int = 0

var _file: FileAccess = null


func _ready() -> void:
	configure(OS.get_cmdline_user_args(), OS.get_environment(ENV))


## The log path from user args (`--event-log=<p>` or `--event-log <p>`), else the env value; "" is off
func resolve_path(args: PackedStringArray, env_value: String) -> String:
	for i in args.size():
		var arg := args[i]
		if arg.begins_with(ARG + "="):
			return arg.trim_prefix(ARG + "=")
		if arg == ARG and i + 1 < args.size():
			return args[i + 1]
	return env_value


func configure(args: PackedStringArray, env_value: String) -> void:
	var p := resolve_path(args, env_value)
	if not p.is_empty():
		open(p)


func open(log_path: String) -> bool:
	close()
	var dir := log_path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _file == null:
		push_error("EventLog: can't open %s (%s)" % [log_path, error_string(FileAccess.get_open_error())])
		return false
	path = log_path
	enabled = true
	_connect_quests(true)
	return true


func close() -> void:
	if _file:
		_file.close()
		_file = null
	if enabled:
		_connect_quests(false)
	enabled = false


func log_event(event: String, data: Dictionary = {}) -> void:
	log_event_at(Engine.get_physics_frames() - frame_origin, event, data)


## The same, stamped with a given frame (relative to frame_origin): the replay logs an input on the
## frame it lands, one frame after it applies it
func log_event_at(frame: int, event: String, data: Dictionary = {}) -> void:
	if _file == null:
		return
	var entry := {"frame": frame, "event": event}
	entry.merge(data)
	_file.store_line(JSON.stringify(entry, "", false))
	_file.flush()  # a run that crashes or is killed keeps everything up to that frame


## A stable name for a node in the log: its name, or its scene file's name when the engine named it
## (nodes added without a name get @Class@<id>, which changes from run to run)
func label(node: Node) -> String:
	if not is_instance_valid(node):
		return ""
	var n := String(node.name)
	if n.begins_with("@") and not node.scene_file_path.is_empty():
		return node.scene_file_path.get_file().get_basename()
	return n


## Distances and positions in the log are rounded, so physics noise below a millimetre never shows
func round3(value: float) -> float:
	return snappedf(value, 0.001)


## Whether nothing on the world layer lies between two bodies, at eye height
func line_of_sight(from: Node3D, to: Node3D) -> bool:
	if not is_instance_valid(from) or not is_instance_valid(to) or not from.is_inside_tree():
		return false
	var query := PhysicsRayQueryParameters3D.create(
		from.global_position + Vector3.UP * EYE_HEIGHT, to.global_position + Vector3.UP * EYE_HEIGHT, WORLD_MASK)
	var exclude: Array[RID] = []
	for body in [from, to]:
		if body is CollisionObject3D:
			exclude.append((body as CollisionObject3D).get_rid())
	query.exclude = exclude
	return from.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _connect_quests(on: bool) -> void:
	if not is_inside_tree():
		return
	var quests := get_node_or_null("/root/QuestManager")
	if quests == null:
		return
	var handlers := {
		"quest_started": _on_quest_started,
		"quest_updated": _on_quest_updated,
		"quest_completed": _on_quest_completed,
	}
	for sig: String in handlers:
		var handler: Callable = handlers[sig]
		if on and not quests.is_connected(sig, handler):
			quests.connect(sig, handler)
		elif not on and quests.is_connected(sig, handler):
			quests.disconnect(sig, handler)


func _on_quest_started(quest_id: String) -> void:
	log_event("quest", {"kind": "started", "quest_id": quest_id, "stage": ""})


func _on_quest_updated(quest_id: String, stage_id: String) -> void:
	log_event("quest", {"kind": "updated", "quest_id": quest_id, "stage": stage_id})


func _on_quest_completed(quest_id: String) -> void:
	log_event("quest", {"kind": "completed", "quest_id": quest_id, "stage": ""})
