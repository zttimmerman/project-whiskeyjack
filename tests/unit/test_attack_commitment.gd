extends GdUnitTestSuite

# Attacks commit (design bible §3, §11 decision 3): movement is locked for the swing, with a short forward
# lunge (0.3–0.5 m) toward a locked target, and a dodge can cancel an attack only after its active frames.
# The swing is the attack's clip (Sword_Regular_A, 0.43 s, for the light attack). Real Player scene on
# flat ground, driven through the Input Map like a replay, with a stand-in enemy to lock on to.

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const FakeEnemy := preload("res://tests/doubles/fake_enemy.gd")
const BODY_Y := 0.9
const HZ := 60.0
const LUNGE_MIN := 0.3
const LUNGE_MAX := 0.5

var _player: CharacterBody3D


func after_test() -> void:
	for action in ["move_forward", "move_backward", "attack_light", "attack_heavy", "dodge"]:
		Input.action_release(action)


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


func _enemy(pos: Vector3) -> CharacterBody3D:
	var enemy: CharacterBody3D = FakeEnemy.new()
	enemy.name = "Target"
	enemy.position = pos
	add_child(auto_free(enemy))
	return enemy


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


# Presses an action for one physics frame, as a replay step does; two frames pass
func _press(action: String) -> void:
	Input.action_press(action)
	await _frames(1)
	Input.action_release(action)
	await _frames(1)


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _dodging() -> bool:
	return bool(_player.get("_is_dodging"))


func test_attack_locks_movement() -> void:
	_arena()
	await _frames(2)
	# Running forward (-z) at full speed, then a light swing with forward still held
	Input.action_press("move_forward")
	await _frames(20)
	await _press("attack_light")
	var start := _flat(_player.global_position)
	# Through the swing (the 0.43 s clip), held input moves him nowhere; no lock, so no lunge
	await _frames(int(0.38 * HZ))
	var moved := _flat(_player.global_position).distance_to(start)
	assert_float(moved).override_failure_message("moved %.3f m during the swing" % moved).is_less(0.05)
	# The swing ends and forward input moves him again
	await _frames(int(0.2 * HZ))
	var after := _flat(_player.global_position).distance_to(start)
	assert_float(after).override_failure_message("still locked after the swing").is_greater(0.3)


func test_attack_lunge_toward_locked_target() -> void:
	_arena()
	var target := _enemy(Vector3(0, BODY_Y, -4))
	await _frames(2)
	_player.call("_toggle_lock_on")
	assert_object(_player.get_lock_on_target()).is_same(target)
	await _frames(10)
	var start := _player.global_position
	# Backing away is ignored: the swing lunges toward the target regardless of input
	Input.action_press("move_backward")
	await _press("attack_light")
	# Measured inside the swing, past the lunge (its active frames), before the input frees him
	await _frames(int(0.35 * HZ))
	Input.action_release("move_backward")
	var step := _flat(_player.global_position - start)
	var toward := _flat(target.global_position - start).normalized()
	var lunge := step.dot(toward)
	(
		assert_float(lunge)
		. override_failure_message("lunged %.3f m, not %.1f–%.1f m" % [lunge, LUNGE_MIN, LUNGE_MAX])
		. is_between(LUNGE_MIN - 0.02, LUNGE_MAX + 0.02)
	)
	assert_float(absf(step.cross(toward))).override_failure_message("the lunge drifted sideways").is_less(0.05)


func test_attack_light_dodge_cancel_after_active_frames() -> void:
	_arena()
	await _frames(2)
	await _press("attack_light")
	# Inside the light attack's active frames (0.2 s), a dodge is refused
	await _press("dodge")
	assert_bool(_dodging()).override_failure_message("a dodge cancelled the swing's active frames").is_false()
	# Past them, still in the swing, a dodge cancels it
	await _frames(int(0.22 * HZ) - 4)
	await _press("dodge")
	assert_bool(_dodging()).override_failure_message("no dodge cancel after the active frames").is_true()


func test_attack_heavy_dodge_cancel_after_active_frames() -> void:
	_arena()
	await _frames(2)
	await _press("attack_heavy")
	# Late in the heavy's active frames (0.35 s), still refused
	await _frames(int(0.28 * HZ) - 2)
	await _press("dodge")
	assert_bool(_dodging()).override_failure_message("a dodge cancelled the heavy's active frames").is_false()
	await _frames(int(0.1 * HZ))
	await _press("dodge")
	assert_bool(_dodging()).override_failure_message("no dodge cancel after the heavy's active frames").is_true()
