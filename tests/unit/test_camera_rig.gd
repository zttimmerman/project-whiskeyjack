extends GdUnitTestSuite

# The over-the-shoulder camera (design bible §2: framing, collision, lock-on; the cam_* targets in §9), on
# the real Player scene in a small arena: a floor, sometimes a kit wall behind him, and a stand-in enemy for
# lock-on. Framing is measured with the replay's screen-space probe (scripts/review/camera_probe.gd).

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const WALL_SCENE := "res://scenes/world/kit/KitWall.tscn"  # 4 m wide along x, 4 m tall, 0.5 m thick
const CameraProbe := preload("res://scripts/review/camera_probe.gd")
const FakeEnemy := preload("res://tests/doubles/fake_enemy.gd")

# Body origins sit at the capsule centre, 0.9 m above the feet
const BODY_Y := 0.9
const FEET_Y := 0.0
const SETTLE_FRAMES := 90


func before_test() -> void:
	# The probe's in-view test needs the game's window shape; a headless root viewport is 64x64
	get_tree().root.size = Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	)


func _floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.5, 0)
	add_child(auto_free(body))


# A kit wall across x at `z` (its faces at z ± 0.25)
func _wall_at(z: float) -> void:
	var wall: Node3D = (load(WALL_SCENE) as PackedScene).instantiate()
	wall.position = Vector3(0, 0, z)
	add_child(auto_free(wall))


# The player at `pos`, facing and looking along -z (yaw 0)
func _player_at(pos: Vector3) -> CharacterBody3D:
	var player: CharacterBody3D = (load(PLAYER_SCENE) as PackedScene).instantiate()
	player.position = pos
	add_child(auto_free(player))
	player.apply_view_state({"facing": 0.0, "camera_yaw": 0.0, "camera_pitch": -0.2})
	return player


# A stand-in enemy: a levy-sized capsule in the "enemy" group with BaseEnemy's is_dead(), that never moves
func _enemy_at(pos: Vector3) -> CharacterBody3D:
	var body: CharacterBody3D = FakeEnemy.new()
	body.position = pos
	add_child(auto_free(body))
	return body


func _physics_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _camera(player: Node) -> Camera3D:
	return player.get_node("CameraRig/Camera3D") as Camera3D


func test_cam_framing_over_the_shoulder() -> void:
	# §2 Framing (user, 2026-10-01, Witcher-like): pivot about 1.6 m above the floor, about 0.9 m to the right,
	# an arm of about 2.5 m, FOV 70–75°
	_floor()
	var player := _player_at(Vector3(0, BODY_Y, 0))
	await _physics_frames(SETTLE_FRAMES)
	var cam := _camera(player)
	var rig: Node3D = player.get_node("CameraRig")
	var pivot: Vector3 = rig.call("get_pivot")
	assert_float(pivot.y - FEET_Y).is_between(1.5, 1.7)
	var local := cam.global_position - pivot
	assert_float(absf(local.x)).override_failure_message("shoulder offset %.2f" % local.x).is_between(0.8, 1.0)
	assert_float(local.z).override_failure_message("behind %.2f" % local.z).is_between(2.2, 2.8)
	assert_float(cam.fov).is_between(70.0, 75.0)


func test_cam_player_in_the_left_third() -> void:
	# The player sits in the left third, with a clear view past his right shoulder
	_floor()
	var player := _player_at(Vector3(0, BODY_Y, 0))
	await _physics_frames(SETTLE_FRAMES)
	var cam := _camera(player)
	var x := cam.unproject_position(player.global_position + Vector3.UP * 0.45).x
	var width := cam.get_viewport().get_visible_rect().size.x
	assert_float(x / width).override_failure_message("player at %.2f of the width" % (x / width)).is_between(0.2, 0.36)


func test_cam_player_in_frame_backed_into_a_wall() -> void:
	# §2 Collision: the arm squeezed short may rise, but the player stays in frame and the camera out of him
	_floor()
	_wall_at(1.0)  # its near face at z = 0.75, so his back is 0.35 m from it
	var player := _player_at(Vector3(0, BODY_Y, 0.0))
	await _physics_frames(SETTLE_FRAMES)
	var cam := _camera(player)
	var s := CameraProbe.sample(cam, player, null)
	assert_bool(s["camera_in_world"]).override_failure_message("camera inside the wall").is_false()
	assert_bool(s["camera_in_player"]).override_failure_message("camera inside the player").is_false()
	assert_bool(s["player_in_view"]).override_failure_message("head and torso out of view").is_true()
	assert_float(cam.global_position.z).is_less_equal(0.75)


func test_cam_sphere_probe_keeps_a_margin_from_walls() -> void:
	# §2 Collision: a sphere probe with a margin, not a ray: the camera never sits on the wall's face
	_floor()
	_wall_at(3.0)  # near face at z = 2.75, inside the 4 m arm
	var player := _player_at(Vector3(0, BODY_Y, 0))
	await _physics_frames(SETTLE_FRAMES)
	var cam := _camera(player)
	assert_float(2.75 - cam.global_position.z).is_greater_equal(cam.near + 0.1)
	var s := CameraProbe.sample(cam, player, null)
	assert_float(s["wall_fill"]).is_less_equal(0.6)
	assert_bool(s["player_in_view"]).is_true()


func test_cam_melee_occlusion_at_melee_range() -> void:
	# §9 cam_melee_occlusion <= 0.25: locked on with the target within 3 m, the player hides little of it
	_floor()
	var player := _player_at(Vector3(0, BODY_Y, 0))
	var enemy := _enemy_at(Vector3(0, BODY_Y, -1.5))
	await _physics_frames(2)
	player.call("_toggle_lock_on")
	await _physics_frames(SETTLE_FRAMES)
	assert_object(player.call("get_lock_on_target")).is_same(enemy)
	var s := CameraProbe.sample(_camera(player), player, enemy)
	assert_float(s["melee_occlusion"]).is_less_equal(0.25)
	assert_bool(s["target_in_view"]).is_true()
	assert_bool(s["player_in_view"]).is_true()


func test_cam_lock_both_in_frame_at_range() -> void:
	# §9 cam_lock_both_in_frame: player and target both framed while locked, near and far
	_floor()
	var player := _player_at(Vector3(0, BODY_Y, 0))
	var near := _enemy_at(Vector3(0.5, BODY_Y, -0.9))
	await _physics_frames(2)
	player.call("_toggle_lock_on")
	await _physics_frames(SETTLE_FRAMES)
	var s := CameraProbe.sample(_camera(player), player, near)
	assert_bool(s["player_in_view"] and s["target_in_view"]).override_failure_message("near: %s" % s).is_true()
	near.global_position = Vector3(-3, BODY_Y, -9)
	await _physics_frames(SETTLE_FRAMES)
	s = CameraProbe.sample(_camera(player), player, near)
	assert_bool(s["player_in_view"] and s["target_in_view"]).override_failure_message("far: %s" % s).is_true()


func test_cam_shake_leaves_the_movement_heading_alone() -> void:
	# Camera shake moves the view, never the heading that camera-relative movement reads
	_floor()
	var player := _player_at(Vector3(0, BODY_Y, 0))
	await _physics_frames(10)
	var rig: Node3D = player.get_node("CameraRig")
	var heading := rig.global_basis.z
	player.camera_shake(0.05, 0.3)
	await _physics_frames(5)
	assert_float(rig.global_basis.z.distance_to(heading)).is_less(1e-4)


func test_fill_light_stays_on_the_camera_side_and_player_only() -> void:
	# CLAUDE.md lighting: CameraRig/FillLight, culled to render layer 2, behind the player on the camera side
	_floor()
	var player := _player_at(Vector3(0, BODY_Y, 0))
	await _physics_frames(SETTLE_FRAMES)
	var light := player.get_node("CameraRig/FillLight") as OmniLight3D
	assert_int(light.light_cull_mask).is_equal(2)
	assert_float(light.global_position.z).is_greater(1.5)  # behind him (he looks along -z)
	var rig: Node3D = player.get_node("CameraRig")
	var pivot: Vector3 = rig.call("get_pivot")
	assert_float(light.global_position.y - pivot.y).is_equal_approx(0.6, 0.05)


# Level 1's start-room north-west corner: two kit walls and the corner crate the player can stand on
func _corner() -> void:
	var north: Node3D = (load(WALL_SCENE) as PackedScene).instantiate()
	north.position = Vector3(-4, 0, -6.25)
	add_child(auto_free(north))
	var west: Node3D = (load(WALL_SCENE) as PackedScene).instantiate()
	west.transform = Transform3D(Basis(Vector3.UP, PI / 2), Vector3(-6.25, 0, -4))
	add_child(auto_free(west))
	var crate: Node3D = (load("res://scenes/world/kit/KitBoxSmall.tscn") as PackedScene).instantiate()
	crate.position = Vector3(-5.2, 0, -5.2)
	add_child(auto_free(crate))


func _inside_world(cam: Camera3D, player: Node) -> bool:
	var space := cam.get_world_3d().direct_space_state
	var shape := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 0.1
	shape.shape = ball
	shape.transform = Transform3D(Basis(), cam.global_position)
	shape.exclude = [(player as CollisionObject3D).get_rid()]
	if not space.intersect_shape(shape, 1).is_empty():
		return true
	var point := PhysicsPointQueryParameters3D.new()
	var vp := cam.get_viewport().get_visible_rect().size
	for corner: Vector2 in [Vector2.ZERO, Vector2(vp.x, 0), Vector2(0, vp.y), vp]:
		point.position = cam.project_position(corner, cam.near)
		for hit in space.intersect_point(point, 4):
			if not hit["collider"] is CharacterBody3D:
				return true
	return false


func test_cam_never_clips_into_walls_in_a_corner() -> void:
	# The user saw the camera clip into walls (2026-10-01): a sphere cast that starts touching a wall passes
	# through it. Tucked into a corner and turned all the way round at every pitch, the lens keeps clear.
	_floor()
	_corner()
	var player := _player_at(Vector3(-5.5, BODY_Y + 1.2, -5.5))  # dropped onto the corner crate
	await _physics_frames(30)
	var cam := _camera(player)
	var clipped: Array[String] = []
	for i in 16:
		for pitch: float in [-0.4, 0.0, 0.8]:
			player.apply_view_state({"facing": i * TAU / 16, "camera_yaw": i * TAU / 16, "camera_pitch": pitch})
			await _physics_frames(3)
			if _inside_world(cam, player):
				clipped.append("yaw %.2f pitch %.1f at %s" % [i * TAU / 16, pitch, cam.global_position])
	assert_array(clipped).is_empty()


func test_cam_pitch_turns_the_look_not_the_arm() -> void:
	# The user's playtest (2026-10-01): mouse pitch swung the whole arm, lifting the lens to about 3.4 m.
	# Looking from full down to full up, the lens stays within 0.4 m of its resting height and he stays in frame.
	_floor()
	var player := _player_at(Vector3(0, BODY_Y, 0))
	player.apply_view_state({"facing": 0.0, "camera_yaw": 0.0, "camera_pitch": 0.0})
	await _physics_frames(SETTLE_FRAMES)
	var cam := _camera(player)
	var rest := cam.global_position.y
	var lows: Array[float] = []
	for pitch: float in [player.camera_pitch_min, -0.2, 0.2, 0.5, player.camera_pitch_max]:
		player.apply_view_state({"facing": 0.0, "camera_yaw": 0.0, "camera_pitch": pitch})
		await _physics_frames(30)
		var s := CameraProbe.sample(cam, player, null)
		(
			assert_float(absf(cam.global_position.y - rest))
			. override_failure_message("pitch %.1f: lens at %.2f m, rest %.2f m" % [pitch, cam.global_position.y, rest])
			. is_less_equal(0.4)
		)
		assert_bool(s["player_in_view"]).override_failure_message("pitch %.1f: out of view" % pitch).is_true()
		lows.append(cam.global_basis.z.y)
	# and the look does turn: full up and full down look different ways
	assert_float(lows[0] - lows[-1]).is_greater(0.3)
