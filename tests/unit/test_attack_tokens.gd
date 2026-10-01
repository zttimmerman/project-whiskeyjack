extends GdUnitTestSuite

# `enemy_attackers_max` (design bible §3, §9): at most 2 melee attackers engage the player at once while
# others hold at 3–5 m, and at most 1 archer fires in any 2 s window.

const TOKENS_SCRIPT := "res://scripts/combat/AttackTokens.gd"
const LEVY_SCENE := "res://scenes/enemies/BaseEnemy.tscn"
const FakePlayer := preload("res://tests/doubles/fake_player.gd")

const ATTACK := 3  # BaseEnemy.State.ATTACK
const BODY_Y := 0.9


func _tokens() -> RefCounted:
	var script: GDScript = load(TOKENS_SCRIPT)
	assert_object(script).override_failure_message("%s is missing" % TOKENS_SCRIPT).is_not_null()
	return script.new() if script else null


func _node() -> Node:
	return auto_free(Node.new())


func test_enemy_attackers_max_melee_tokens() -> void:
	var tokens := _tokens()
	if tokens == null:
		return
	var a := _node()
	var b := _node()
	var c := _node()
	assert_bool(tokens.try_acquire_melee(a)).is_true()
	assert_bool(tokens.try_acquire_melee(b)).is_true()
	assert_bool(tokens.try_acquire_melee(c)).override_failure_message("a third melee attacker got a token").is_false()
	assert_bool(tokens.try_acquire_melee(a)).override_failure_message("a holder asking again keeps its token").is_true()
	tokens.release(a)
	assert_bool(tokens.try_acquire_melee(c)).override_failure_message("a released token goes to the next").is_true()
	assert_bool(tokens.holds_melee(a)).is_false()


func test_melee_token_of_freed_enemy_is_reclaimed() -> void:
	var tokens := _tokens()
	if tokens == null:
		return
	var a := Node.new()
	var b := _node()
	assert_bool(tokens.try_acquire_melee(a)).is_true()
	assert_bool(tokens.try_acquire_melee(b)).is_true()
	a.free()
	(
		assert_bool(tokens.try_acquire_melee(_node()))
		. override_failure_message("a freed holder's token stays taken")
		. is_true()
	)


func test_enemy_attackers_max_ranged_window() -> void:
	var tokens := _tokens()
	if tokens == null:
		return
	var a := _node()
	var b := _node()
	assert_bool(tokens.try_fire_ranged(a, 10.0)).is_true()
	assert_bool(tokens.try_fire_ranged(b, 11.0)).override_failure_message("a second archer fired within 2 s").is_false()
	assert_bool(tokens.try_fire_ranged(b, 11.99)).is_false()
	# The same archer isn't limited by its own shots (its cooldown is)
	assert_bool(tokens.try_fire_ranged(a, 11.5)).is_true()
	assert_bool(tokens.try_fire_ranged(b, 13.5)).override_failure_message("2 s after the last shot").is_true()
	# Physics-frame times: 120 frames after a shot is exactly the window, and allowed
	assert_bool(tokens.try_fire_ranged(a, 13.5 + 120.0 / 60.0)).is_true()


# Three levies around the player: two engage and attack, the third holds off at 3–5 m
func test_enemy_attackers_max_melee_in_play() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0, -0.5, 0)
	add_child(auto_free(ground))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var player: CharacterBody3D = FakePlayer.new()
	player.position = Vector3(0, BODY_Y, 0)
	add_child(auto_free(player))
	var levies: Array[CharacterBody3D] = []
	for i in 3:
		var levy: CharacterBody3D = (load(LEVY_SCENE) as PackedScene).instantiate()
		var angle := TAU * i / 3.0
		levy.position = Vector3(sin(angle) * 1.3, BODY_Y, cos(angle) * 1.3)
		add_child(auto_free(levy))
		levies.append(levy)
	var attacked := {}
	for _i in 180:
		await get_tree().physics_frame
		for levy in levies:
			if levy.state == ATTACK:
				attacked[levy.name] = true
	(
		assert_int(attacked.size())
		. override_failure_message("%d levies attacked at once (target: at most 2)" % attacked.size())
		. is_less_equal(2)
	)
	var holding := levies.filter(func(l: CharacterBody3D) -> bool: return not attacked.has(l.name))
	assert_int(holding.size()).is_equal(1)
	if holding.size() == 1:
		var dist: float = Vector2(holding[0].position.x, holding[0].position.z).length()
		(
			assert_float(dist)
			. override_failure_message("the levy without a token holds at %.2f m (target 3–5 m)" % dist)
			. is_between(2.9, 5.1)
		)
