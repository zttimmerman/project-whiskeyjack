extends CharacterBody3D

# Test double for lock-on: a levy-sized capsule in the "enemy" group that never moves, with BaseEnemy's
# is_dead(). Set `dead` to kill it without its death clip or free.

var dead := false


func _init() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	add_child(shape)
	add_to_group("enemy")


func is_dead() -> bool:
	return dead
