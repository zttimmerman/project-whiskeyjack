extends GdUnitTestSuite

# Losing sight (decided with the user, 2026-09-30, on PR #26): a chasing enemy that loses sight of the
# player goes to where it last saw them, looks around for a few seconds, then returns to its post and
# idles. Regaining sight at any point resumes the chase.
#
# The arena, seen from above (x right, z down): the levy starts at its post (0, 0) facing -z and sees
# the player at (0, -6). The player then slips to (-6, -6), behind a wall that runs along z at x = -3.
# From the last-seen spot (0, -6) the wall still hides them, and they're beyond the 4 m hearing radius.

const LEVY_SCENE := "res://scenes/enemies/BaseEnemy.tscn"
const WALL_SCENE := "res://scenes/world/kit/KitWall.tscn"  # 4 m wide along its x, 0.5 m thick
const FakePlayer := preload("res://tests/doubles/fake_player.gd")

# BaseEnemy.State, by value
const IDLE := 0
const CHASE := 2
const SEARCH := 6

const BODY_Y := 0.9
const POST := Vector3(0, BODY_Y, 0)
const SEEN_AT := Vector3(0, BODY_Y, -6)
const HIDDEN_AT := Vector3(-6, BODY_Y, -6)


func _arena() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.5, 0)
	add_child(auto_free(body))
	var wall: Node3D = (load(WALL_SCENE) as PackedScene).instantiate()
	wall.position = Vector3(-3, 0, -5)
	wall.rotation.y = PI / 2  # runs along z, from -7 to -3
	add_child(auto_free(wall))
	await _physics_frames(2)


func _physics_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# The levy sees the player and chases; then the player slips behind the wall
func _chase_then_hide() -> Array:
	await _arena()
	var player: CharacterBody3D = FakePlayer.new()
	player.position = SEEN_AT
	add_child(auto_free(player))
	var levy: CharacterBody3D = (load(LEVY_SCENE) as PackedScene).instantiate()
	levy.position = POST
	add_child(auto_free(levy))
	await _physics_frames(10)
	assert_int(levy.state).override_failure_message("the levy didn't start chasing").is_equal(CHASE)
	player.global_position = HIDDEN_AT
	return [levy, player]


func test_lost_sight_searches_last_seen_spot_then_returns_to_post() -> void:
	var pair := await _chase_then_hide()
	var levy: CharacterBody3D = pair[0]
	var searched := false
	var reached_spot := false
	var chased_again := false
	var turned := 0.0  # how far it turned in place while looking around
	var last_yaw := levy.rotation.y
	for _i in 600:
		await get_tree().physics_frame
		searched = searched or levy.state == SEARCH
		chased_again = chased_again or (searched and levy.state == CHASE)
		if levy.state == SEARCH and _flat_dist(levy.global_position, SEEN_AT) < 1.0:
			reached_spot = true
			turned += absf(wrapf(levy.rotation.y - last_yaw, -PI, PI))
		last_yaw = levy.rotation.y
		if searched and levy.state == IDLE:
			break
	assert_bool(searched).override_failure_message("the levy never searched after losing sight").is_true()
	assert_bool(chased_again).override_failure_message("the levy chased again without seeing the player").is_false()
	assert_bool(reached_spot).override_failure_message("the levy didn't go to where it last saw the player").is_true()
	(
		assert_float(rad_to_deg(turned))
		. override_failure_message("the levy turned only %.0f° looking around" % rad_to_deg(turned))
		. is_greater(90.0)
	)
	assert_int(levy.state).override_failure_message("the levy didn't give up within 10 s").is_equal(IDLE)
	(
		assert_float(_flat_dist(levy.global_position, POST))
		. override_failure_message("the levy idles %.2f m from its post" % _flat_dist(levy.global_position, POST))
		. is_less(1.0)
	)


func test_search_lasts_a_few_seconds() -> void:
	var pair := await _chase_then_hide()
	var levy: CharacterBody3D = pair[0]
	var search_frames := 0
	for _i in 600:
		await get_tree().physics_frame
		if levy.state == SEARCH and _flat_dist(levy.global_position, SEEN_AT) < 1.0:
			search_frames += 1
		if search_frames > 0 and levy.state == IDLE:
			break
	var seconds := search_frames / float(Engine.physics_ticks_per_second)
	assert_float(seconds).override_failure_message("looked around for %.2f s (3–4 s)" % seconds).is_between(3.0, 4.2)


func test_regaining_sight_resumes_chase() -> void:
	var pair := await _chase_then_hide()
	var levy: CharacterBody3D = pair[0]
	var player: CharacterBody3D = pair[1]
	for _i in 120:
		await get_tree().physics_frame
		if levy.state == SEARCH:
			break
	assert_int(levy.state).override_failure_message("the levy never searched").is_equal(SEARCH)
	# A few frames into the walk to the last-seen spot it faces -z; the player steps out ahead of it, clear
	# of the wall
	await _physics_frames(10)
	assert_int(levy.state).is_equal(SEARCH)
	player.global_position = Vector3(1, BODY_Y, -8)
	var resumed := false
	for _i in 20:
		await get_tree().physics_frame
		if levy.state == CHASE:
			resumed = true
			break
	assert_bool(resumed).override_failure_message("the levy saw the player again but didn't chase").is_true()
