class_name HurtboxComponent
extends Area3D

# Owner node must have a CharacterStats node or property accessible
@export var stats: CharacterStats

# Invincibility frames — set true during dodge roll, etc.
var invincible: bool = false


func _ready() -> void:
	area_entered.connect(_on_hitbox_entered)


func _on_hitbox_entered(area: Area3D) -> void:
	if invincible:
		return
	var hitbox := area as HitboxComponent
	if not hitbox:
		return
	if not stats:
		return

	stats.take_damage(hitbox.damage)

	# Push the parent CharacterBody3D away from the hitbox source
	var body := get_parent() as CharacterBody3D
	if body:
		var push_dir: Vector3 = body.global_position - hitbox.global_position
		push_dir.y = 0.0
		if push_dir.length_squared() > 0.001:
			push_dir = push_dir.normalized()
		body.velocity += push_dir * hitbox.knockback_force
