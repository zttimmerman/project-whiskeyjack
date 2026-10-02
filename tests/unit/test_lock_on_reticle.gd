extends GdUnitTestSuite

# The lock-on reticle (design bible §2: "A reticle on the target, always visible while locked"):
# scenes/ui/LockOnReticle.tscn, instanced in the HUD. It shows only while a target is locked, centred on the
# target's screen position.

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const RETICLE_SCENE := "res://scenes/ui/LockOnReticle.tscn"
const FakeEnemy := preload("res://tests/doubles/fake_enemy.gd")
const BODY_Y := 0.9

var _player: CharacterBody3D
var _reticle: Control


func before_test() -> void:
	get_tree().root.size = Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	)


func _arena() -> CharacterBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.5, 0)
	add_child(auto_free(body))
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	_player.position = Vector3(0, BODY_Y, 0)
	add_child(auto_free(_player))
	_player.apply_view_state({"facing": 0.0, "camera_yaw": 0.0, "camera_pitch": -0.2})
	var enemy: CharacterBody3D = FakeEnemy.new()
	enemy.position = Vector3(0.5, BODY_Y, -5)
	add_child(auto_free(enemy))
	_reticle = (load(RETICLE_SCENE) as PackedScene).instantiate()
	add_child(auto_free(_reticle))
	return enemy


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame
	await get_tree().process_frame


func test_reticle_hidden_when_not_locked() -> void:
	_arena()
	await _frames(5)
	assert_bool(_reticle.visible).is_false()


func test_reticle_shows_on_the_locked_target() -> void:
	var enemy := _arena()
	await _frames(2)
	_player.call("_toggle_lock_on")
	await _frames(30)
	assert_bool(_reticle.visible).is_true()
	var cam := get_viewport().get_camera_3d()
	var want := cam.unproject_position(enemy.global_position)
	var centre := _reticle.global_position + _reticle.size * 0.5
	assert_float(centre.distance_to(want)).is_less(4.0)


func test_reticle_hides_when_the_lock_releases() -> void:
	_arena()
	await _frames(2)
	_player.call("_toggle_lock_on")
	await _frames(5)
	_player.call("_toggle_lock_on")  # one candidate: pressing again releases
	await _frames(2)
	assert_bool(_reticle.visible).is_false()
