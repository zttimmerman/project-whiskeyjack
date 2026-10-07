extends GdUnitTestSuite

# A dead enemy's body (design bible §3, death): it stops blocking the player the frame it dies, while the
# death clip plays on and the body stays on the floor until it is freed. Found in two_fight_route, where the
# Corridor A levy's corpse held the player in place for 2.5 s.

const LEVY_SCENE := "res://scenes/enemies/BaseEnemy.tscn"
const DT := 1.0 / 60.0

var _walker: CharacterBody3D  # a player-sized body on the player's physics layers


func before_test() -> void:
	var floor_body: StaticBody3D = auto_free(StaticBody3D.new())
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)

	_walker = auto_free(CharacterBody3D.new())
	var walker_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	walker_shape.shape = capsule
	_walker.add_child(walker_shape)
	add_child(_walker)
	_walker.global_position = Vector3(0, 0.95, 0)


func _spawn_levy(at: Vector3) -> CharacterBody3D:
	var enemy: CharacterBody3D = auto_free((load(LEVY_SCENE) as PackedScene).instantiate())
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = at
	# Let the physics server register the bodies before querying it
	await get_tree().physics_frame
	await get_tree().physics_frame
	return enemy


# Whether the walker, moving 3 m east through the levy standing 1.5 m away, is stopped by the levy
func _blocked_by(enemy: Node) -> bool:
	var hit := KinematicCollision3D.new()
	if not _walker.test_move(_walker.global_transform, Vector3(3, 0, 0), hit):
		return false
	return hit.get_collider() == enemy


func test_living_enemy_blocks_player() -> void:
	var levy: CharacterBody3D = await _spawn_levy(Vector3(1.5, 0.95, 0))
	assert_bool(_blocked_by(levy)).is_true()


func test_dead_enemy_does_not_block_player() -> void:
	var levy: CharacterBody3D = await _spawn_levy(Vector3(1.5, 0.95, 0))
	levy.die()
	# The same frame: no physics step between the death and the move
	assert_bool(_blocked_by(levy)).is_false()
	# The body is still there, playing its death clip, until the fade frees it
	assert_bool(is_instance_valid(levy) and not levy.is_queued_for_deletion()).is_true()
	var anim: AnimationPlayer = levy.get_node("SkeletonModel/AnimationPlayer")
	assert_str(String(anim.current_animation)).is_equal("death")


func test_dead_enemy_stays_on_floor() -> void:
	var levy: CharacterBody3D = await _spawn_levy(Vector3(1.5, 0.95, 0))
	levy.die()
	for _i in 60:
		levy._physics_process(DT)
	# The capsule's centre stays 0.9 m above the floor, so the death clip plays grounded
	assert_float(levy.global_position.y).is_between(0.85, 1.0)
