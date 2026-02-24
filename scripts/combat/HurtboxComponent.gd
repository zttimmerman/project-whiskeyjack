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
	_spawn_hit_particles()

	# Push the parent CharacterBody3D away from the hitbox source
	var body := get_parent() as CharacterBody3D
	if body:
		var push_dir: Vector3 = body.global_position - hitbox.global_position
		push_dir.y = 0.0
		if push_dir.length_squared() > 0.001:
			push_dir = push_dir.normalized()
		body.velocity += push_dir * hitbox.knockback_force


func _spawn_hit_particles() -> void:
	var scene_root := get_tree().current_scene
	if not scene_root:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 16
	p.lifetime = 0.55
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.2
	p.direction = Vector3.UP
	p.spread = 140.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0.0, -5.0, 0.0)
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.4
	p.color = Color(1.0, 0.85, 0.2)
	# CPUParticles3D.mesh is null by default — particles are invisible without one
	var quad := QuadMesh.new()
	quad.size = Vector2(0.25, 0.25)
	p.mesh = quad
	scene_root.add_child(p)
	p.global_position = global_position
	p.emitting = true
	p.finished.connect(p.queue_free)
