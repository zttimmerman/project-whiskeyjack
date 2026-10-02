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


# A holder that dies (or is freed) keeps its token until 2 s after its last attack started, so the metric's
# 2 s window never counts a third melee attacker
func test_enemy_attackers_max_handoff_waits_for_window() -> void:
	var tokens := _tokens()
	if tokens == null:
		return
	var a := _node()
	var b := _node()
	var c := _node()
	assert_bool(tokens.try_acquire_melee(a, 9.0)).is_true()
	assert_bool(tokens.try_acquire_melee(b, 9.0)).is_true()
	tokens.note_melee_attack(a, 10.0)
	tokens.release(a)  # a dies at 10.5
	assert_bool(tokens.holds_melee(a)).is_false()
	(
		assert_bool(tokens.try_acquire_melee(c, 10.5))
		. override_failure_message("the dead holder's token went on within 2 s of its last attack")
		. is_false()
	)
	assert_bool(tokens.try_acquire_melee(c, 11.99)).is_false()
	# Physics-frame times: 120 frames after the attack is exactly the window, and allowed
	assert_bool(tokens.try_acquire_melee(c, 10.0 + 120.0 / 60.0)).override_failure_message("2 s after").is_true()


func test_enemy_attackers_max_handoff_immediate_without_recent_attack() -> void:
	var tokens := _tokens()
	if tokens == null:
		return
	var a := _node()
	var b := _node()
	var c := _node()
	assert_bool(tokens.try_acquire_melee(a, 0.0)).is_true()
	assert_bool(tokens.try_acquire_melee(b, 0.0)).is_true()
	tokens.note_melee_attack(a, 10.0)
	tokens.release(a)
	(
		assert_bool(tokens.try_acquire_melee(c, 12.5))
		. override_failure_message("a holder that last attacked over 2 s ago still blocks its token")
		. is_true()
	)
	# A holder that never attacked hands its token on at once
	tokens.release(b)
	assert_bool(tokens.try_acquire_melee(_node(), 12.5)).is_true()


func test_enemy_attackers_max_freed_holder_waits_for_window() -> void:
	var tokens := _tokens()
	if tokens == null:
		return
	var a := Node.new()
	var b := _node()
	var c := _node()
	assert_bool(tokens.try_acquire_melee(a, 9.0)).is_true()
	assert_bool(tokens.try_acquire_melee(b, 9.0)).is_true()
	tokens.note_melee_attack(a, 10.0)
	a.free()
	assert_bool(tokens.try_acquire_melee(c, 11.0)).override_failure_message("freed holder's token handed on").is_false()
	assert_bool(tokens.try_acquire_melee(c, 12.0)).is_true()


func test_enemy_attackers_max_holder_reclaims_its_own_token() -> void:
	var tokens := _tokens()
	if tokens == null:
		return
	var a := _node()
	var b := _node()
	assert_bool(tokens.try_acquire_melee(a, 9.0)).is_true()
	assert_bool(tokens.try_acquire_melee(b, 9.0)).is_true()
	tokens.note_melee_attack(a, 10.0)
	tokens.release(a)  # lost sight of the player
	assert_bool(tokens.try_acquire_melee(a, 10.5)).override_failure_message("its own reserved token").is_true()
	assert_bool(tokens.try_acquire_melee(_node(), 12.5)).is_false()


# Three levies around the player; one holder dies right after attacking. No 2 s window counts three distinct
# melee attack starts, and the third levy still gets the token and attacks.
func test_enemy_attackers_max_melee_when_holder_dies() -> void:
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
	var starts: Array[Dictionary] = []  # {frame, actor}
	var was_attacking := {}
	var killed: CharacterBody3D = null
	var kill_at := -1
	for frame in 480:
		await get_tree().physics_frame
		for levy in levies:
			if not is_instance_valid(levy):
				continue
			var attacking: bool = levy.state == ATTACK
			if attacking and not was_attacking.get(levy.name, false):
				starts.append({"frame": frame, "actor": levy.name})
				if killed == null:
					killed = levy
					kill_at = frame + 50  # dies 50 frames into its attack
			was_attacking[levy.name] = attacking
		if frame == kill_at and is_instance_valid(killed):
			killed.take_damage(9999)
	var best := 0
	for s in starts:
		var actors := {}
		for e in starts:
			if s.frame - 120 < e.frame and e.frame <= s.frame:
				actors[e.actor] = true
		best = maxi(best, actors.size())
	(
		assert_int(best)
		. override_failure_message("%d melee attackers started within 2 s (target: at most 2)" % best)
		. is_less_equal(2)
	)
	var actors := {}
	for s in starts:
		actors[s.actor] = true
	assert_int(actors.size()).override_failure_message("the third levy never got the token").is_equal(3)
