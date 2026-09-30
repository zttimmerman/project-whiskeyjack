extends GdUnitTestSuite

# The gameplay event log (scripts/debug/EventLog.gd, autoload EventLog; docs/plans/phase-a/a2b-replay-harness.md)
# on fresh instances of its script, so the autoload's own state is never touched. It is off unless
# `--event-log` or WHISKEYJACK_EVENT_LOG names a file, and off it writes nothing.

const SCRIPT := "res://scripts/debug/EventLog.gd"
const LOG_PATH := "user://test_event_log.jsonl"

var log_node: Node


func before_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG_PATH))
	var script: GDScript = load(SCRIPT)
	assert_object(script).override_failure_message("%s is missing" % SCRIPT).is_not_null()
	log_node = auto_free(script.new())


func after_test() -> void:
	if is_instance_valid(log_node):
		log_node.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG_PATH))


func _read_lines(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var text := FileAccess.get_file_as_string(path)
	for line in text.split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		assert_bool(parsed is Dictionary).override_failure_message("not a JSON object: %s" % line).is_true()
		out.append(parsed)
	return out


func test_event_log_off_by_default_writes_nothing() -> void:
	assert_str(log_node.resolve_path(PackedStringArray(), "")).is_empty()
	log_node.configure(PackedStringArray(["--save-slot=gdunit"]), "")
	assert_bool(log_node.enabled).is_false()
	log_node.log_event("hit", {"attacker": "Player", "target": "Levy", "damage": 10})
	assert_bool(FileAccess.file_exists(LOG_PATH)).is_false()


func test_event_log_path_from_user_arg() -> void:
	assert_str(log_node.resolve_path(PackedStringArray(["--event-log=%s" % LOG_PATH]), "")).is_equal(LOG_PATH)
	# The replay command line passes it as two args
	(
		assert_str(log_node.resolve_path(PackedStringArray(["--scenario", "x.json", "--event-log", LOG_PATH]), ""))
		. is_equal(LOG_PATH)
	)


func test_event_log_path_from_env_and_arg_wins() -> void:
	assert_str(log_node.resolve_path(PackedStringArray(), LOG_PATH)).is_equal(LOG_PATH)
	assert_str(log_node.resolve_path(PackedStringArray(["--event-log=user://from_arg.jsonl"]), LOG_PATH)).is_equal(
		"user://from_arg.jsonl"
	)


func test_event_log_writes_jsonl_stamped_with_physics_frames() -> void:
	log_node.configure(PackedStringArray(["--event-log=%s" % LOG_PATH]), "")
	assert_bool(log_node.enabled).is_true()
	log_node.log_event("attack_started", {"actor": "Player", "kind": "light", "combo_index": 0})
	log_node.log_event("hit", {"attacker": "Player", "target": "Levy", "damage": 10, "heavy": false})
	log_node.close()
	assert_bool(log_node.enabled).is_false()

	var lines := _read_lines(LOG_PATH)
	assert_int(lines.size()).is_equal(2)
	assert_str(lines[0]["event"]).is_equal("attack_started")
	assert_str(lines[0]["kind"]).is_equal("light")
	assert_str(lines[1]["event"]).is_equal("hit")
	assert_int(int(lines[1]["damage"])).is_equal(10)
	for line in lines:
		assert_int(int(line["frame"])).is_equal(Engine.get_physics_frames())


func test_event_log_frames_relative_to_origin() -> void:
	log_node.configure(PackedStringArray(["--event-log=%s" % LOG_PATH]), "")
	log_node.frame_origin = Engine.get_physics_frames() - 7
	log_node.log_event("dodge_start", {"actor": "Player"})
	log_node.close()
	assert_int(int(_read_lines(LOG_PATH)[0]["frame"])).is_equal(7)


func test_event_log_closed_writes_nothing_more() -> void:
	log_node.configure(PackedStringArray(["--event-log=%s" % LOG_PATH]), "")
	log_node.log_event("death", {"actor": "Levy"})
	log_node.close()
	log_node.log_event("death", {"actor": "Other"})
	assert_int(_read_lines(LOG_PATH).size()).is_equal(1)


func test_event_log_label_names_nodes_stably() -> void:
	var named := auto_free(Node3D.new()) as Node3D
	named.name = "EnemyCorridorA"
	assert_str(log_node.label(named)).is_equal("EnemyCorridorA")
	# A node added without a name gets an engine name like @Area3D@123, which changes run to run;
	# the label falls back to its scene file's name
	var parent := auto_free(Node3D.new()) as Node3D
	var spawned := Area3D.new()
	spawned.scene_file_path = "res://scenes/enemies/Projectile.tscn"
	parent.add_child(spawned)  # no name given, so the engine makes one
	assert_str(String(spawned.name)).starts_with("@")
	assert_str(log_node.label(spawned)).is_equal("Projectile")
	assert_str(log_node.label(null)).is_equal("")
