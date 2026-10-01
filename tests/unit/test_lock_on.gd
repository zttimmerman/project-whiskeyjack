extends GdUnitTestSuite

# Lock-on when the locked target dies (design bible §2, lock-on; decided by the user 2026-10-01): the lock
# moves at once to the nearest living enemy within lock-on range, or releases when there's none. Both are
# logged as today (lock_on with the new target, lock_off). Real Player scene, stand-in enemies.

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const FakeEnemy := preload("res://tests/doubles/fake_enemy.gd")
const LOG_PATH := "user://test_lock_on.jsonl"
const BODY_Y := 0.9

var _player: CharacterBody3D


func after_test() -> void:
	if EventLog.path == LOG_PATH:
		EventLog.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG_PATH))


func _arena() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.5, 0)
	add_child(auto_free(body))
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	_player.position = Vector3(0, BODY_Y, 0)
	add_child(auto_free(_player))
	_player.apply_view_state({"facing": 0.0, "camera_yaw": 0.0, "camera_pitch": -0.2})


func _enemy(label: String, pos: Vector3) -> CharacterBody3D:
	var enemy: CharacterBody3D = FakeEnemy.new()
	enemy.name = label
	enemy.position = pos
	add_child(auto_free(enemy))
	return enemy


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _lock(expected: Node) -> void:
	_player.call("_toggle_lock_on")
	assert_object(_player.get_lock_on_target()).is_same(expected)


func test_lock_moves_to_the_nearest_living_enemy_when_the_target_dies() -> void:
	_arena()
	var first := _enemy("First", Vector3(0, BODY_Y, -3))
	var near := _enemy("Near", Vector3(4, BODY_Y, 4))
	_enemy("Far", Vector3(-8, BODY_Y, -6))
	await _frames(2)
	_lock(first)
	first.dead = true
	await _frames(1)
	assert_object(_player.get_lock_on_target()).is_same(near)


func test_lock_skips_dead_enemies_when_it_moves() -> void:
	_arena()
	var first := _enemy("First", Vector3(0, BODY_Y, -3))
	var corpse := _enemy("Corpse", Vector3(2, BODY_Y, 2))
	var living := _enemy("Living", Vector3(-7, BODY_Y, 0))
	corpse.dead = true
	await _frames(2)
	_lock(first)
	first.dead = true
	await _frames(1)
	assert_object(_player.get_lock_on_target()).is_same(living)


func test_lock_releases_when_no_living_enemy_is_in_range() -> void:
	_arena()
	var first := _enemy("First", Vector3(0, BODY_Y, -3))
	_enemy("OutOfRange", Vector3(0, BODY_Y, 20))  # lock_on_range is 15 m
	await _frames(2)
	_lock(first)
	first.dead = true
	await _frames(1)
	assert_object(_player.get_lock_on_target()).is_null()


func test_lock_on_never_picks_a_dead_enemy() -> void:
	_arena()
	var corpse := _enemy("Corpse", Vector3(0, BODY_Y, -3))
	corpse.dead = true
	await _frames(2)
	_player.call("_toggle_lock_on")
	assert_object(_player.get_lock_on_target()).is_null()


func test_the_switch_and_the_release_are_logged() -> void:
	_arena()
	var first := _enemy("First", Vector3(0, BODY_Y, -3))
	var second := _enemy("Second", Vector3(4, BODY_Y, 0))
	await _frames(2)
	_lock(first)
	EventLog.open(LOG_PATH)
	first.dead = true
	await _frames(1)
	second.dead = true
	await _frames(1)
	EventLog.close()
	var events: Array[String] = []
	for line in FileAccess.get_file_as_string(LOG_PATH).split("\n", false):
		var e: Dictionary = JSON.parse_string(line)
		if String(e["event"]).begins_with("lock_"):
			events.append("%s %s" % [e["event"], e.get("target", "")])
	assert_array(events).is_equal(["lock_on Second", "lock_off "])
