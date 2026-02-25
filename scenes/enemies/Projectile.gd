extends Area3D

const SPEED: float = 14.0
const LIFETIME: float = 3.0

var direction: Vector3 = Vector3.FORWARD

var _hitbox: HitboxComponent = null
var _age: float = 0.0


func _ready() -> void:
	_hitbox = $HitboxComponent
	_hitbox.activate()
	_hitbox.hit.connect(_on_hit)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	global_position += direction * SPEED * delta


func _on_hit(_target: Node, _damage: int) -> void:
	queue_free()
