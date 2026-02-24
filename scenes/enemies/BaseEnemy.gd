class_name BaseEnemy
extends CharacterBody3D

signal died

enum State { IDLE, PATROL, CHASE, ATTACK, STAGGER, DEAD }

@export var stats: CharacterStats
@export var detection_range: float = 10.0
@export var attack_range: float = 1.5
@export var gravity: float = 20.0

var state: State = State.IDLE
var _player: CharacterBody3D = null
var _nav_agent: NavigationAgent3D = null


func _ready() -> void:
	_nav_agent = $NavigationAgent3D
	_player = get_tree().get_first_node_in_group("player")
	stats.died.connect(_on_stats_died)


func _physics_process(delta: float) -> void:
	match state:
		State.IDLE:
			pass
		State.PATROL:
			pass
		State.CHASE:
			pass
		State.ATTACK:
			pass
		State.STAGGER:
			pass
		State.DEAD:
			pass

	_get_next_action()


# Override in subclasses to implement unique enemy behavior
func _get_next_action() -> void:
	pass


func _change_state(new_state: State) -> void:
	state = new_state


func take_damage(amount: int, knockback_direction: Vector3 = Vector3.ZERO) -> void:
	pass


func die() -> void:
	pass


func _on_stats_died() -> void:
	die()
