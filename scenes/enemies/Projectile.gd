extends Area3D

const SPEED: float = 14.0
const LIFETIME: float = 3.0

const WorldRay := preload("res://scripts/combat/WorldRay.gd")

var direction: Vector3 = Vector3.FORWARD

var _hitbox: HitboxComponent = null
var _age: float = 0.0
var _wall_query: PhysicsRayQueryParameters3D = WorldRay.make_query()


func _ready() -> void:
	_hitbox = $HitboxComponent
	_hitbox.activate()
	_hitbox.hit.connect(_on_hit)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	# Sweep this frame's step against world geometry: at 14 m/s a step is about 0.23 m, enough to pass
	# through a thin wall between two overlap checks
	var step := direction * SPEED * delta
	var hit := WorldRay.first_hit(
		get_world_3d().direct_space_state, _wall_query, global_position, global_position + step
	)
	if not hit.is_empty():
		global_position = hit.position
		queue_free()
		return
	global_position += step


func _on_hit(_target: Node, _damage: int) -> void:
	queue_free()
