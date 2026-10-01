extends GdUnitTestSuite

# Enemy detection and archer fire need line of sight against world geometry (design bible §3:
# "Detection needs line of sight within a 120° view cone at the detection range, plus a 4 m hearing
# radius"; "archers only shoot with line of sight"; §4: "an encounter never pulls enemies from another
# room"). Each test builds a small arena (a floor, sometimes a kit wall) with a stand-in player and real
# enemy scenes, and steps physics.

const LEVY_SCENE := "res://scenes/enemies/BaseEnemy.tscn"
const ARCHER_SCENE := "res://scenes/enemies/ArcherEnemy.tscn"
const WALL_SCENE := "res://scenes/world/kit/KitWall.tscn"  # 4 m wide along x, 4 m tall, 0.5 m thick
const FakePlayer := preload("res://tests/doubles/fake_player.gd")

# BaseEnemy.State, by value (an enum on a scene script isn't reachable from here)
const IDLE := 0
const CHASE := 2
const ATTACK := 3

# Body origins sit at the capsule centre, 0.9 m above the feet
const BODY_Y := 0.9
const SETTLE_FRAMES := 30


func _floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.5, 0)
	add_child(auto_free(body))


func _wall_at(z: float) -> void:
	var wall: Node3D = (load(WALL_SCENE) as PackedScene).instantiate()
	wall.position = Vector3(0, 0, z)
	add_child(auto_free(wall))


func _player_at(pos: Vector3) -> CharacterBody3D:
	var player: CharacterBody3D = FakePlayer.new()
	player.position = pos
	add_child(auto_free(player))
	return player


# An enemy at `pos` facing -z (the scenes' identity rotation), added after the player so _ready() finds it
func _enemy(scene: String, pos: Vector3) -> CharacterBody3D:
	var enemy: CharacterBody3D = (load(scene) as PackedScene).instantiate()
	enemy.position = pos
	add_child(auto_free(enemy))
	return enemy


func _arena() -> void:
	_floor()
	await _physics_frames(2)


func _physics_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _assert_state(enemy: CharacterBody3D, expected: int, why: String) -> void:
	assert_int(enemy.state).override_failure_message("%s (state %d)" % [why, enemy.state]).is_equal(expected)


# Detected: chasing, or already attacking a player it reached
func _assert_detected(enemy: CharacterBody3D, why: String) -> void:
	assert_int(enemy.state).override_failure_message("%s (state %d)" % [why, enemy.state]).is_not_equal(IDLE)


func test_detects_player_in_view_with_clear_sight() -> void:
	await _arena()
	_player_at(Vector3(0, BODY_Y, -8))
	var levy := _enemy(LEVY_SCENE, Vector3(0, BODY_Y, 0))
	await _physics_frames(SETTLE_FRAMES)
	_assert_detected(levy, "a levy facing the player 8 m away, nothing between, chases")


func test_wall_blocks_detection() -> void:
	await _arena()
	_wall_at(-4)
	await _physics_frames(2)
	_player_at(Vector3(0, BODY_Y, -8))
	var levy := _enemy(LEVY_SCENE, Vector3(0, BODY_Y, 0))
	await _physics_frames(SETTLE_FRAMES)
	_assert_state(levy, IDLE, "a levy doesn't see the player through a wall")


func test_player_beyond_detection_range_is_not_detected() -> void:
	await _arena()
	var levy := _enemy(LEVY_SCENE, Vector3(0, BODY_Y, 0))
	_player_at(Vector3(0, BODY_Y, -(levy.detection_range + 2.0)))
	levy._player = get_tree().get_first_node_in_group("player")
	await _physics_frames(SETTLE_FRAMES)
	_assert_state(levy, IDLE, "a levy doesn't detect the player beyond its detection range")


func test_player_behind_outside_hearing_is_not_detected() -> void:
	await _arena()
	_player_at(Vector3(0, BODY_Y, 8))
	var levy := _enemy(LEVY_SCENE, Vector3(0, BODY_Y, 0))
	await _physics_frames(SETTLE_FRAMES)
	_assert_state(levy, IDLE, "a levy doesn't see a player 8 m behind it (outside the 120° cone and 4 m hearing)")


func test_player_at_cone_edge() -> void:
	await _arena()
	# 50° off the levy's facing is inside the 120° cone (±60°)
	var angle := deg_to_rad(50.0)
	_player_at(Vector3(-sin(angle) * 8.0, BODY_Y, -cos(angle) * 8.0))
	var levy := _enemy(LEVY_SCENE, Vector3(0, BODY_Y, 0))
	await _physics_frames(SETTLE_FRAMES)
	_assert_detected(levy, "a levy sees a player 50° off its facing")


func test_player_just_outside_cone_is_not_detected() -> void:
	await _arena()
	var angle := deg_to_rad(70.0)
	_player_at(Vector3(-sin(angle) * 8.0, BODY_Y, -cos(angle) * 8.0))
	var levy := _enemy(LEVY_SCENE, Vector3(0, BODY_Y, 0))
	await _physics_frames(SETTLE_FRAMES)
	_assert_state(levy, IDLE, "a levy doesn't see a player 70° off its facing at 8 m")


func test_hearing_detects_player_behind_within_4m() -> void:
	await _arena()
	_player_at(Vector3(0, BODY_Y, 3))
	var levy := _enemy(LEVY_SCENE, Vector3(0, BODY_Y, 0))
	await _physics_frames(SETTLE_FRAMES)
	_assert_detected(levy, "a levy hears a player 3 m behind it")


func test_hearing_does_not_pass_walls() -> void:
	await _arena()
	_wall_at(1.5)
	await _physics_frames(2)
	_player_at(Vector3(0, BODY_Y, 3))
	var levy := _enemy(LEVY_SCENE, Vector3(0, BODY_Y, 0))
	await _physics_frames(SETTLE_FRAMES)
	_assert_state(levy, IDLE, "a levy doesn't detect a player 3 m away behind a wall (§4: no pulls between rooms)")


func test_another_enemy_does_not_block_sight() -> void:
	await _arena()
	_player_at(Vector3(0, BODY_Y, -8))
	var levy := _enemy(LEVY_SCENE, Vector3(0, BODY_Y, 0))
	# A second levy stands on the sight line, facing away from the player so it doesn't move first
	var blocker := _enemy(LEVY_SCENE, Vector3(0, BODY_Y, -3))
	blocker.rotation.y = PI
	blocker.detection_range = 0.0
	await _physics_frames(SETTLE_FRAMES)
	_assert_detected(levy, "a levy sees the player past another enemy (characters aren't world geometry)")


func test_archer_does_not_shoot_through_walls() -> void:
	await _arena()
	_wall_at(-4)
	await _physics_frames(2)
	_player_at(Vector3(0, BODY_Y, -8))
	var archer := _enemy(ARCHER_SCENE, Vector3(0, BODY_Y, 0))
	archer.projectile_scene = null  # no arrow is spawned even if it fires; the state says whether it did
	# Already chasing (it saw the player earlier, say), from before its first physics frame: it may close
	# in, but never fires without sight
	archer._change_state(CHASE)
	var fired := false
	for _i in 60:
		await get_tree().physics_frame
		fired = fired or archer.state == ATTACK
	assert_bool(fired).override_failure_message("the archer fired at a player behind a wall").is_false()
