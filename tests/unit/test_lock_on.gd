extends GdUnitTestSuite

# Lock-on when the locked target dies (design bible §2, lock-on; decided by the user 2026-10-01): the lock
# moves at once to the nearest living enemy within lock-on range, or releases when there's none. Both are
# logged as today (lock_on with the new target, lock_off). Real Player scene, stand-in enemies.

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const NPC_SCENE := "res://scenes/npcs/NPC.tscn"
const WALL_SCENE := "res://scenes/world/kit/KitWall.tscn"  # 4 m wide along x, 4 m tall, 0.5 m thick
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


func _wall_at(z: float) -> Node3D:
	var wall: Node3D = (load(WALL_SCENE) as PackedScene).instantiate()
	wall.position = Vector3(0, 0, z)
	add_child(auto_free(wall))
	return wall


func test_lock_on_ignores_enemies_behind_walls() -> void:
	# Design bible §2: only living enemies in line of sight are candidates (the playtest locked on through walls)
	_arena()
	_wall_at(-3.0)
	_enemy("Hidden", Vector3(0, BODY_Y, -6))
	await _frames(2)
	_player.call("_toggle_lock_on")
	assert_object(_player.get_lock_on_target()).is_null()


func test_lock_on_never_picks_an_npc() -> void:
	# The playtest locked onto the quest giver: only enemies are candidates
	_arena()
	var npc: Node3D = (load(NPC_SCENE) as PackedScene).instantiate()
	npc.position = Vector3(0, BODY_Y, -3)
	add_child(auto_free(npc))
	await _frames(2)
	_player.call("_toggle_lock_on")
	assert_object(_player.get_lock_on_target()).is_null()


func test_lock_survives_a_brief_occlusion() -> void:
	# User's rule (2026-10-01): circling a pillar hides the target for a moment; the lock holds
	_arena()
	var target := _enemy("Target", Vector3(0, BODY_Y, -6))
	await _frames(2)
	_lock(target)
	var wall := _wall_at(-3.0)
	await _frames(30)  # 0.5 s hidden
	wall.free()
	await _frames(2)
	assert_object(_player.get_lock_on_target()).is_same(target)


func test_lock_ends_after_a_second_behind_cover() -> void:
	# User's rule (2026-10-01): hidden by world geometry for more than about 1 s, the lock ends
	_arena()
	var target := _enemy("Target", Vector3(0, BODY_Y, -6))
	await _frames(2)
	_lock(target)
	_wall_at(-3.0)
	await _frames(75)  # 1.25 s hidden
	assert_object(_player.get_lock_on_target()).is_null()


func test_lock_moves_only_to_an_enemy_in_sight() -> void:
	_arena()
	var first := _enemy("First", Vector3(0, BODY_Y, 3))
	_wall_at(-3.0)
	_enemy("Hidden", Vector3(0, BODY_Y, -5))
	var seen := _enemy("Seen", Vector3(8, BODY_Y, 2))
	await _frames(2)
	_lock(first)
	first.dead = true
	await _frames(1)
	assert_object(_player.get_lock_on_target()).is_same(seen)
