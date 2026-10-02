extends GdUnitTestSuite

# The replay's screen-space camera checks (scripts/review/camera_probe.gd; design bible §2 and the cam_*
# targets in §9). Each test places a camera, capsule bodies like the player's and the levy's, and sometimes a
# kit wall, then samples once. Nothing renders: the probe unprojects points and casts rays.

const CameraProbe := preload("res://scripts/review/camera_probe.gd")
const WALL_SCENE := "res://scenes/world/kit/KitWall.tscn"  # 4 m wide along x, 4 m tall, 0.5 m thick

# Body origins sit at the capsule centre, 0.9 m above the feet
const BODY_Y := 0.9

var _camera: Camera3D


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


# A character body like the player's and the levy's: a 0.4 m by 1.8 m capsule centred on the origin
func _body_at(pos: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	body.add_child(shape)
	body.position = pos
	add_child(auto_free(body))
	return body


# A camera at `pos` looking at `at`, 75° FOV like the game's
func _camera_at(pos: Vector3, at: Vector3) -> void:
	_camera = Camera3D.new()
	_camera.fov = 75.0
	add_child(auto_free(_camera))
	_camera.look_at_from_position(pos, at)
	_camera.make_current()


func _settle() -> void:
	for _i in 2:
		await get_tree().physics_frame


func test_wall_fill_is_high_with_a_wall_between_camera_and_player() -> void:
	# The camera pushed into a wall: the wall fills the view between it and him
	_floor()
	_wall_at(-1.0)
	_camera_at(Vector3(0, 1.6, 0), Vector3(0, 1.6, -5))
	var player := _body_at(Vector3(0, BODY_Y, -3))
	await _settle()
	var s := CameraProbe.sample(_camera, player, null)
	assert_float(s["wall_fill"]).is_greater(0.9)


func test_wall_fill_is_zero_with_only_floor_in_view() -> void:
	_floor()
	_camera_at(Vector3(0, 1.6, 0), Vector3(0, 0.5, -5))
	var player := _body_at(Vector3(0, BODY_Y, -3))
	await _settle()
	var s := CameraProbe.sample(_camera, player, null)
	assert_float(s["wall_fill"]).is_equal(0.0)


func test_wall_fill_merges_coplanar_wall_pieces() -> void:
	# Two kit walls side by side are one wall surface; each alone covers about half the view
	_floor()
	for x in [-2.0, 2.0]:
		var wall: Node3D = (load(WALL_SCENE) as PackedScene).instantiate()
		wall.position = Vector3(x, 0, -1.2)
		add_child(auto_free(wall))
	_camera_at(Vector3(0, 1.6, 0), Vector3(0, 1.6, -5))
	var player := _body_at(Vector3(0, BODY_Y, -3))
	await _settle()
	var s := CameraProbe.sample(_camera, player, null)
	assert_float(s["wall_fill"]).is_greater(0.9)


func test_wall_fill_ignores_a_wall_he_faces_beyond_him() -> void:
	# The user's rule (2026-10-01): a wall the player deliberately faces close up isn't the camera's
	# fault; only wall between the camera and him, or beside him, counts
	_floor()
	_wall_at(-0.75)  # its near face 0.5 m in front of him
	_camera_at(Vector3(0.6, 1.7, 4), Vector3(0.6, 1.4, -2))
	var player := _body_at(Vector3(0, BODY_Y, 0))
	await _settle()
	var s := CameraProbe.sample(_camera, player, null)
	assert_float(s["wall_fill"]).is_less(0.05)


func test_wall_fill_counts_a_wall_beside_him() -> void:
	# A side wall running past him counts up to his depth
	_floor()
	var wall: Node3D = (load(WALL_SCENE) as PackedScene).instantiate()
	wall.transform = Transform3D(Basis(Vector3.UP, PI / 2), Vector3(-0.9, 0, 2))
	add_child(auto_free(wall))
	_camera_at(Vector3(-0.3, 1.7, 3.5), Vector3(-0.3, 1.4, -2))
	var player := _body_at(Vector3(0.3, BODY_Y, 0))
	await _settle()
	var s := CameraProbe.sample(_camera, player, null)
	assert_float(s["wall_fill"]).is_greater(0.1)


func test_player_ahead_in_open_space_is_in_view_and_visible() -> void:
	_floor()
	_camera_at(Vector3(0, 2.0, 4), Vector3(0, 1.2, 0))
	var player := _body_at(Vector3(0, BODY_Y, 0))
	await _settle()
	var s := CameraProbe.sample(_camera, player, null)
	assert_bool(s["player_in_view"]).is_true()
	assert_float(s["player_visible"]).is_equal(1.0)
	assert_bool(s["camera_in_player"]).is_false()
	assert_bool(s["locked"]).is_false()


func test_player_behind_a_wall_is_not_visible() -> void:
	_floor()
	_wall_at(2.0)
	_camera_at(Vector3(0, 2.0, 4), Vector3(0, 1.2, 0))
	var player := _body_at(Vector3(0, BODY_Y, 0))
	await _settle()
	var s := CameraProbe.sample(_camera, player, null)
	assert_float(s["player_visible"]).is_less(0.5)


func test_player_behind_the_camera_is_out_of_view() -> void:
	_floor()
	_camera_at(Vector3(0, 2.0, 0), Vector3(0, 1.2, -4))
	var player := _body_at(Vector3(0, BODY_Y, 3))
	await _settle()
	var s := CameraProbe.sample(_camera, player, null)
	assert_bool(s["player_in_view"]).is_false()


func test_player_too_close_to_fit_is_out_of_view() -> void:
	# A camera squeezed against the player's back can't show his head and torso whole
	_floor()
	_camera_at(Vector3(0, 1.4, 0.6), Vector3(0, 1.4, -4))
	var player := _body_at(Vector3(0, BODY_Y, 0))
	await _settle()
	var s := CameraProbe.sample(_camera, player, null)
	assert_bool(s["player_in_view"]).is_false()


func test_camera_inside_the_player_is_flagged() -> void:
	_floor()
	_camera_at(Vector3(0, 1.2, 0.1), Vector3(0, 1.2, -4))
	var player := _body_at(Vector3(0, BODY_Y, 0))
	await _settle()
	var s := CameraProbe.sample(_camera, player, null)
	assert_bool(s["camera_in_player"]).is_true()


func test_target_straight_behind_the_player_is_covered() -> void:
	# The dead-centre camera's melee problem (design bible §2): the player hides the enemy he faces
	_floor()
	_camera_at(Vector3(0, 2.4, 4), Vector3(0, 1.4, -2))
	var player := _body_at(Vector3(0, BODY_Y, 0))
	var target := _body_at(Vector3(0, BODY_Y, -2))
	await _settle()
	var s := CameraProbe.sample(_camera, player, target)
	assert_bool(s["locked"]).is_true()
	assert_float(s["target_distance"]).is_equal_approx(2.0, 0.01)
	assert_float(s["melee_occlusion"]).is_greater(0.5)


func test_target_off_the_shoulder_is_not_covered() -> void:
	# An over-the-shoulder offset clears the target
	_floor()
	_camera_at(Vector3(0.6, 1.7, 4), Vector3(0.6, 1.4, -2))
	var player := _body_at(Vector3(-0.6, BODY_Y, 0))
	var target := _body_at(Vector3(0.6, BODY_Y, -2))
	await _settle()
	var s := CameraProbe.sample(_camera, player, target)
	assert_float(s["melee_occlusion"]).is_less(0.25)
	assert_bool(s["target_in_view"]).is_true()
	assert_float(s["target_visible"]).is_equal(1.0)


func test_target_behind_a_wall_is_not_visible() -> void:
	_floor()
	_wall_at(-3.0)
	_camera_at(Vector3(0, 2.0, 4), Vector3(0, 1.2, -4))
	var player := _body_at(Vector3(1.5, BODY_Y, 0))  # aside, so he covers none of the target
	var target := _body_at(Vector3(0, BODY_Y, -5))
	await _settle()
	var s := CameraProbe.sample(_camera, player, target)
	assert_float(s["target_visible"]).is_less(0.5)
