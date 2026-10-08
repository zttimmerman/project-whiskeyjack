extends GdUnitTestSuite

# The settled dodge (design bible §3, §11 decision 2): 4.2 m over 0.5 s, i-frames for the first 0.30 s
# only (late dodges are punished a little), then a 0.15 s recovery after the roll before the next dodge
# or attack. Real Player scene on flat ground, driven through the Input Map like a replay.

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const BODY_Y := 0.9
const HZ := 60.0

var _player: CharacterBody3D


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


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


# Presses an action for one physics frame, as a replay step does
func _press(action: String) -> void:
	Input.action_press(action)
	await _frames(1)
	Input.action_release(action)
	await _frames(1)


func _dodging() -> bool:
	return bool(_player.get("_is_dodging"))


func _invincible() -> bool:
	return (_player.get_node("HurtboxComponent") as HurtboxComponent).invincible


# Starts a dodge and returns how many physics frames of it have run
func _start_dodge() -> int:
	await _frames(2)
	Input.action_press("dodge")
	var ran := 0
	for _i in 4:
		await _frames(1)
		if _dodging():
			ran = 1
			break
	Input.action_release("dodge")
	assert_bool(_dodging()).override_failure_message("the dodge didn't start").is_true()
	return ran


func _run_until(ran: int, seconds: float) -> int:
	var target := int(round(seconds * HZ))
	if target > ran:
		await _frames(target - ran)
	return max(ran, target)


func test_dodge_iframe_window() -> void:
	_arena()
	var ran := await _start_dodge()
	assert_bool(_invincible()).override_failure_message("no i-frames at the start of the roll").is_true()
	# Still invincible just inside 0.30 s (one frame of tolerance either side)
	ran = await _run_until(ran, 0.30 - 1.0 / HZ)
	assert_bool(_invincible()).override_failure_message("i-frames ended before 0.30 s").is_true()
	# Past 0.30 s the roll goes on, but a hit lands
	ran = await _run_until(ran, 0.30 + 2.0 / HZ)
	assert_bool(_dodging()).override_failure_message("the roll ended before 0.5 s").is_true()
	assert_bool(_invincible()).override_failure_message("i-frames last past 0.30 s").is_false()
	ran = await _run_until(ran, 0.45)
	assert_bool(_invincible()).override_failure_message("i-frames came back late in the roll").is_false()
	# The roll itself is still 0.5 s
	ran = await _run_until(ran, 0.5 + 2.0 / HZ)
	assert_bool(_dodging()).override_failure_message("the roll lasts past 0.5 s").is_false()
	assert_bool(_invincible()).is_false()


func test_dodge_recovery_blocks_the_next_dodge() -> void:
	_arena()
	var ran := await _start_dodge()
	# The roll has ended; inside the 0.15 s recovery a press is dropped
	ran = await _run_until(ran, 0.5 + 2.0 / HZ)
	assert_bool(_dodging()).is_false()
	await _press("dodge")
	ran += 2
	assert_bool(_dodging()).override_failure_message("a dodge started inside the 0.15 s recovery").is_false()
	# After the recovery the next dodge goes
	ran = await _run_until(ran, 0.65 + 2.0 / HZ)
	await _press("dodge")
	assert_bool(_dodging()).override_failure_message("no dodge after the recovery").is_true()


func test_dodge_recovery_blocks_attacks() -> void:
	_arena()
	var ran := await _start_dodge()
	var hitbox := _player.get_node("HitboxComponent") as HitboxComponent
	ran = await _run_until(ran, 0.5 + 2.0 / HZ)
	await _press("attack_light")
	ran += 2
	(
		assert_float(float(_player.get("_attack_timer")))
		. override_failure_message("a light attack started inside the recovery")
		. is_less_equal(0.0)
	)
	await _press("attack_heavy")
	ran += 2
	(
		assert_float(float(_player.get("_attack_timer")))
		. override_failure_message("a heavy attack started inside the recovery")
		. is_less_equal(0.0)
	)
	ran = await _run_until(ran, 0.65 + 2.0 / HZ)
	await _press("attack_light")
	(
		assert_float(float(_player.get("_attack_timer")))
		. override_failure_message("no attack after the recovery")
		. is_greater(0.0)
	)
	assert_object(hitbox).is_not_null()
