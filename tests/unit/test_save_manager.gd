extends GdUnitTestSuite
# gdUnit4 signal asserts are coroutines behind an abstract interface, so the analyzer flags their
# required await as redundant
@warning_ignore_start("redundant_await")

# Characterization tests for SaveManager on a fresh instance of the autoload's script, writing
# only to its own slot (user://save_gdunit.json). A stand-in world node plays the current scene,
# with a fake player (tests/doubles/fake_player.gd). The QuestManager autoload's state and the
# tree's current scene are restored after every test, and the real user://save.json is checked
# untouched.

const SLOT := "gdunit"
const FakePlayer := preload("res://tests/doubles/fake_player.gd")
const SCENE := "res://scenes/world/Level1.tscn"
const OTHER_SCENE := "res://scenes/world/Level2.tscn"

var saves: Node
var world: Node3D
var player: CharacterBody3D
var enemy: Node3D
var _prev_scene: Node
var _quest_snapshot: Array
var _real_mtime: int


func before_test() -> void:
	_real_mtime = _real_save_mtime()
	_quest_snapshot = [
		QuestManager._active_quests.duplicate(true),
		QuestManager._completed_quests.duplicate(),
		QuestManager._flags.duplicate(true),
	]
	QuestManager._active_quests.clear()
	QuestManager._completed_quests.clear()
	QuestManager._flags.clear()

	saves = auto_free(load("res://autoloads/SaveManager.gd").new())
	add_child(saves)
	saves.set_save_slot(SLOT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saves.get_save_path()))

	world = Node3D.new()
	world.name = "SaveTestWorld"
	world.scene_file_path = SCENE
	player = FakePlayer.new()
	player.name = "Player"
	player.stats = CharacterStats.new()
	player.inventory = Inventory.new()
	world.add_child(player)
	enemy = Node3D.new()
	enemy.name = "EnemyA"
	enemy.add_to_group("enemy")
	world.add_child(enemy)
	enemy.owner = world
	get_tree().root.add_child(world)
	_prev_scene = get_tree().current_scene
	get_tree().current_scene = world
	GameManager.player = null


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saves.get_save_path()))
	if GameManager.player == player:
		GameManager.player = null
	if is_instance_valid(_prev_scene):
		get_tree().current_scene = _prev_scene
	world.free()
	QuestManager._active_quests = _quest_snapshot[0]
	QuestManager._completed_quests.assign(_quest_snapshot[1])
	QuestManager._flags = _quest_snapshot[2]
	assert_int(_real_save_mtime()).override_failure_message("user://save.json was modified").is_equal(_real_mtime)


func test_slot_never_points_at_the_real_save() -> void:
	assert_str(saves.get_save_path()).is_equal("user://save_gdunit.json")
	assert_str(saves.get_save_path()).is_not_equal(saves.SAVE_PATH)


func test_invalid_slot_keeps_the_current_path() -> void:
	await (
		assert_error(func() -> void: saves.set_save_slot("../escape"))
		. is_push_error("SaveManager: invalid save slot '../escape', keeping user://save_gdunit.json")
	)
	assert_str(saves.get_save_path()).is_equal("user://save_gdunit.json")


func test_round_trip_restores_player_quests_and_kills() -> void:
	# State to save: position, view, stats, an equipped sword, a quest mid-way, one kill
	player.position = Vector3(3.0, 1.0, -2.0)
	player.apply_view_state({"facing": 1.1, "camera_yaw": 2.3, "camera_pitch": -0.1})
	var sword: Item = load("res://data/items/sword_iron.tres")
	player.inventory.add_item(sword)
	player.inventory.add_item(load("res://data/items/potion_health.tres"))
	player.inventory.equip_item(sword, player.stats)
	player.stats.current_hp = 42
	player.stats.experience = 60
	QuestManager.start_quest("clear_eastern_road")
	QuestManager.advance_quest("clear_eastern_road")
	QuestManager.set_flag("idrenna_turned_down")
	saves.record_enemy_killed(enemy)
	saves.save_game()
	assert_bool(saves.save_exists()).is_true()
	assert_bool(saves.is_save_compatible()).is_true()
	var saved := _read_save()
	assert_int(int(saved.version)).is_equal(saves.SAVE_FORMAT_VERSION)
	assert_str(saved.scene).is_equal(SCENE)
	assert_array(saved.world.killed_enemies).contains_exactly(["EnemyA"])

	# Change everything, then load
	player.position = Vector3.ZERO
	player.apply_view_state({"facing": 0.0, "camera_yaw": 0.0, "camera_pitch": 0.0})
	player.stats.current_hp = 100
	player.stats.experience = 0
	player.inventory.unequip_item("weapon", player.stats)
	player.inventory.items.clear()
	QuestManager._active_quests.clear()
	QuestManager._flags.clear()
	saves.load_game()

	assert_vector(player.global_position).is_equal_approx(Vector3(3.0, 1.0, -2.0), Vector3.ONE * 0.001)
	assert_float(player.get_view_state().camera_yaw).is_equal_approx(2.3, 0.0001)
	assert_int(player.stats.current_hp).is_equal(42)
	assert_int(player.stats.experience).is_equal(60)
	# Saved stats already include the sword; loading must not apply it a second time
	assert_int(player.stats.attack).is_equal(15)
	assert_int(player.inventory.items.size()).is_equal(2)
	assert_str(player.inventory.equipment["weapon"].id).is_equal("sword_iron")
	assert_str(QuestManager.get_quest_stage("clear_eastern_road")).is_equal("defeat_monsters")
	assert_bool(QuestManager.get_flag("idrenna_turned_down")).is_true()
	# The killed enemy leaves the group at once and is freed
	assert_bool(enemy.is_in_group("enemy")).is_false()
	assert_bool(enemy.is_queued_for_deletion()).is_true()


func test_save_for_another_scene_is_ignored() -> void:
	player.stats.current_hp = 42
	player.position = Vector3(3.0, 1.0, -2.0)
	saves.save_game()
	world.scene_file_path = OTHER_SCENE
	assert_bool(saves.save_exists()).is_true()
	assert_bool(saves.is_save_compatible()).is_false()
	player.stats.current_hp = 100
	player.position = Vector3.ZERO
	saves.load_game()
	assert_int(player.stats.current_hp).is_equal(100)
	assert_vector(player.position).is_equal(Vector3.ZERO)


func test_other_format_version_is_ignored() -> void:
	player.stats.current_hp = 42
	saves.save_game()
	var data := _read_save()
	data.version = saves.SAVE_FORMAT_VERSION - 1
	_write_save(data)
	assert_bool(saves.is_save_compatible()).is_false()
	data.erase("version")  # a missing version reads as format 1
	_write_save(data)
	assert_bool(saves.is_save_compatible()).is_false()
	player.stats.current_hp = 100
	saves.load_game()
	assert_int(player.stats.current_hp).is_equal(100)


func test_save_without_flags_loads_with_none() -> void:
	# Saves from before world flags existed have no "flags" key; they load as "no flags set"
	saves.save_game()
	var data := _read_save()
	data.quests.erase("flags")
	_write_save(data)
	QuestManager.set_flag("idrenna_turned_down")
	saves.load_game()
	assert_bool(QuestManager.has_flag("idrenna_turned_down")).is_false()


func test_runtime_spawned_enemy_is_not_recorded() -> void:
	var spawned := Node3D.new()
	world.add_child(spawned)  # no owner: not part of the scene file
	saves.record_enemy_killed(spawned)
	saves.save_game()
	assert_array(_read_save().world.killed_enemies).is_empty()


func _read_save() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(saves.get_save_path()))


func _write_save(data: Dictionary) -> void:
	var f := FileAccess.open(saves.get_save_path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _real_save_mtime() -> int:
	var path := "user://save.json"
	return FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else -1
