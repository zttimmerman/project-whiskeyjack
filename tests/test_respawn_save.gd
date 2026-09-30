extends SceneTree

# Headless test of death/respawn against the save: world state, player position and camera heading,
# and that a save for another scene or an old format is ignored. Uses its own save slot, so the
# player's real user://save.json is never read or written.
#   Godot --headless --path . -s res://tests/test_respawn_save.gd -- --save-slot=respawn_test

const LEVEL := "res://scenes/world/Level1.tscn"
const SLOT := "respawn_test"
const KILLED_BEFORE_SAVE := ["EnemyCorridorA", "ArcherCentral"]
const KILLED_AFTER_SAVE := "EnemyCentral1"
const SAVE_OFFSET := Vector3(-2.0, 0.0, 0.5)  # moves the player off the spawn point before saving
const VIEW := {"facing": 1.1, "camera_yaw": 2.3, "camera_pitch": -0.1}

var _failures: Array[String] = []
var _save_manager: Node
var _game_manager: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_save_manager = root.get_node("/root/SaveManager")
	_game_manager = root.get_node("/root/GameManager")
	# Pin the slot here too, so a run without the command-line arg still can't touch the real save
	_save_manager.set_save_slot(SLOT)
	var path: String = _save_manager.get_save_path()
	if path == _save_manager.SAVE_PATH:
		push_error("test_respawn_save: refusing to run against the real save")
		quit(2)
		return
	var real_save: String = _save_manager.SAVE_PATH
	var real_mtime := FileAccess.get_modified_time(real_save) if FileAccess.file_exists(real_save) else -1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("save slot: ", path)

	change_scene_to_file(LEVEL)
	await _frames(10)
	var level := current_scene
	var player: CharacterBody3D = level.get_node("Player")

	# ── Kill two enemies, move and turn the player, save ──
	for enemy_name in KILLED_BEFORE_SAVE:
		level.get_node(enemy_name).stats.take_damage(99999)
	player.global_position += SAVE_OFFSET
	player.apply_view_state(VIEW)
	await _settle(player)
	_check(player.is_on_floor(), "player is on the floor before saving")
	_save_manager.save_game()
	var saved: Dictionary = _read_json(path)
	var saved_pos := Vector3(saved.player.position[0], saved.player.position[1], saved.player.position[2])
	print("saved: scene=%s version=%s killed=%s pos=%s view=%s" % [saved.scene, saved.version, saved.world.killed_enemies, saved_pos, saved.player.view])
	_check(saved.scene == LEVEL, "save records the scene")
	_check(Array(saved.world.killed_enemies) == KILLED_BEFORE_SAVE, "save lists the pre-save kills")

	# ── Kill one more after the save, then die through the real death flow ──
	level.get_node(KILLED_AFTER_SAVE).stats.take_damage(99999)
	player.stats.take_damage(99999)
	await _await_respawn(level)
	level = current_scene
	player = level.get_node("Player")

	for enemy_name in KILLED_BEFORE_SAVE:
		_check(level.get_node_or_null(enemy_name) == null, "%s (killed before the save) stays dead" % enemy_name)
	var back := level.get_node_or_null(KILLED_AFTER_SAVE)
	_check(back != null and not back.is_dead(), "%s (killed after the save) is back" % KILLED_AFTER_SAVE)
	_check(level.get_node_or_null("EnemyExit1") != null, "untouched enemy is present")
	var d := player.global_position - saved_pos
	print("respawned: pos=%s (delta %s) view=%s rig_yaw=%.4f hp=%d/%d" % [player.global_position, d, player.get_view_state(), player.camera_rig.global_rotation.y, player.stats.current_hp, player.stats.max_hp])
	_check(Vector2(d.x, d.z).length() < 0.05 and absf(d.y) < 0.1, "player is back at the saved position")
	var view: Dictionary = player.get_view_state()
	_check(is_equal_approx(view.facing, VIEW.facing), "player facing restored")
	_check(is_equal_approx(view.camera_yaw, VIEW.camera_yaw), "camera yaw restored")
	_check(is_equal_approx(view.camera_pitch, VIEW.camera_pitch), "camera pitch restored")
	_check(absf(angle_difference(player.camera_rig.global_rotation.y, VIEW.camera_yaw)) < 0.001, "camera rig world heading matches the save")
	_check(player.stats.current_hp == player.stats.max_hp, "respawn at full HP")

	# A later save still carries the kills the loaded save listed
	_save_manager.save_game()
	_check(Array(_read_json(path).world.killed_enemies) == KILLED_BEFORE_SAVE, "re-save keeps the loaded kills")

	# ── A save for another scene, or an old format, is ignored ──
	var foreign: Dictionary = _read_json(path)
	foreign.scene = "res://scenes/world/Level2.tscn"
	_write_json(path, foreign)
	_check(not _save_manager.is_save_compatible(), "save for another scene is incompatible")
	var old_format: Dictionary = _read_json(path)
	old_format.scene = LEVEL
	old_format.erase("version")
	_write_json(path, old_format)
	_check(not _save_manager.is_save_compatible(), "save without a format version is incompatible")

	_write_json(path, foreign)
	await _game_manager.reload_from_save()
	await _frames(3)
	level = current_scene
	player = level.get_node("Player")
	for enemy_name in KILLED_BEFORE_SAVE:
		_check(level.get_node_or_null(enemy_name) != null, "%s present when the foreign save is ignored" % enemy_name)
	var fresh: Node = (load(LEVEL) as PackedScene).instantiate()
	var spawn: Vector3 = fresh.get_node("Player").position
	fresh.free()
	_check(Vector2(player.global_position.x - spawn.x, player.global_position.z - spawn.z).length() < 0.05, "player at the scene's spawn, not the foreign save's position")

	# ── Clean up; the real save must be untouched ──
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var mtime_after := FileAccess.get_modified_time(real_save) if FileAccess.file_exists(real_save) else -1
	_check(mtime_after == real_mtime, "real save.json untouched")

	if _failures.is_empty():
		print("PASS test_respawn_save")
		quit(0)
	else:
		print("FAIL test_respawn_save: %d failure(s)" % _failures.size())
		quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


# Waits for the player to land after being moved
func _settle(player: CharacterBody3D) -> void:
	for i in 60:
		await physics_frame
		if player.is_on_floor() and absf(player.velocity.y) < 0.5 and i > 5:
			break


# Death flow: GameManager waits out the YOU DIED overlay (3.2 s), reloads, then loads the save
func _await_respawn(old_scene: Node) -> void:
	var t0 := Time.get_ticks_msec()
	while current_scene == old_scene or not is_instance_valid(current_scene):
		await process_frame
		if Time.get_ticks_msec() - t0 > 10000:
			_check(false, "scene reloaded after death")
			return
	# reload_from_save applies the save two frames after the swap
	await _frames(4)


func _read_json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
