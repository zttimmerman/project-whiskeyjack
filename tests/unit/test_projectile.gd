extends GdUnitTestSuite

# Arrows collide with walls (design bible §3: "Arrows collide with walls"). An arrow flies at 14 m/s,
# 0.23 m per physics frame, so the check must catch a 0.5 m kit wall without tunnelling.

const PROJECTILE_SCENE := "res://scenes/enemies/Projectile.tscn"
const WALL_SCENE := "res://scenes/world/kit/KitWall.tscn"  # 4 m wide along x, 0.5 m thick along z
const FakePlayer := preload("res://tests/doubles/fake_player.gd")

const WALL_Z := -4.0
const WALL_HALF_THICKNESS := 0.25


func _wall() -> void:
	var wall: Node3D = (load(WALL_SCENE) as PackedScene).instantiate()
	wall.position = Vector3(0, 0, WALL_Z)
	add_child(auto_free(wall))
	await get_tree().physics_frame
	await get_tree().physics_frame


func _fire(from: Vector3, direction: Vector3) -> Node3D:
	var arrow: Node3D = (load(PROJECTILE_SCENE) as PackedScene).instantiate()
	add_child(arrow)
	arrow.global_position = from
	arrow.set("direction", direction.normalized())
	return arrow


func test_arrow_stops_at_wall() -> void:
	await _wall()
	var arrow := _fire(Vector3(0, 1.7, 0), Vector3.FORWARD)
	var furthest := 0.0
	for _i in 60:
		await get_tree().physics_frame
		if not is_instance_valid(arrow):
			break
		furthest = minf(furthest, arrow.global_position.z)
	(
		assert_bool(is_instance_valid(arrow))
		. override_failure_message("the arrow was still flying a second after hitting the wall")
		. is_false()
	)
	(
		assert_float(furthest)
		. override_failure_message("the arrow reached z = %.2f, past the wall's face" % furthest)
		. is_greater_equal(WALL_Z + WALL_HALF_THICKNESS - 0.01)
	)
	if is_instance_valid(arrow):
		arrow.free()


func test_arrow_passes_characters_bodies() -> void:
	# A character body on the path (an archer's own capsule, another levy) isn't a wall: the arrow keeps
	# flying, and hurting a character is the HitboxComponent's job
	var body: CharacterBody3D = FakePlayer.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	shape.shape = capsule
	body.add_child(shape)
	body.position = Vector3(0, 1.7, -2)
	add_child(auto_free(body))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var arrow := _fire(Vector3(0, 1.7, 0), Vector3.FORWARD)
	for _i in 30:
		await get_tree().physics_frame
	(
		assert_bool(is_instance_valid(arrow) and arrow.global_position.z < -4.0)
		. override_failure_message("the arrow stopped at a character's body")
		. is_true()
	)
	if is_instance_valid(arrow):
		arrow.free()
