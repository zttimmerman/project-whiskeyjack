extends "res://scenes/enemies/BaseEnemy.gd"

# Preferred engagement distances
const FIRE_RANGE: float = 12.0
const MIN_DISTANCE: float = 4.0
const PREFERRED_DISTANCE: float = 7.0
const SHOOT_COOLDOWN: float = 2.0

@export var projectile_scene: PackedScene


# Override: ATTACK fires a projectile rather than activating the melee hitbox
func _change_state(new_state: State) -> void:
	if new_state == State.ATTACK:
		state = State.ATTACK
		_face_player()
		_attack_timer = 0.4
		_attack_cooldown_timer = SHOOT_COOLDOWN
		_play_anim("attack")
		_fire_projectile()
	else:
		super._change_state(new_state)


# Override: hold still during the brief post-fire pause; don't reset cooldown
func _tick_attack(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_change_state(State.CHASE)


# Override: distance management and fire trigger.
# Base _tick_chase() handles cooldown countdown, navigation toward player, and
# IDLE/leash transitions. attack_range = 0.0 in the .tscn ensures the base
# never fires the melee-attack transition, leaving that control here.
func _get_next_action() -> void:
	if state != State.CHASE or not _player:
		return

	var dist: float = global_position.distance_to(_player.global_position)

	# Fire when in range and cooldown has expired
	if dist <= FIRE_RANGE and _attack_cooldown_timer <= 0.0:
		_change_state(State.ATTACK)
		return

	# Adjust velocity set by base _tick_chase to maintain preferred distance
	var dir_to_player: Vector3 = _player.global_position - global_position
	dir_to_player.y = 0.0

	if dist < MIN_DISTANCE:
		# Retreat — back away while still facing the player
		if dir_to_player.length_squared() > 0.01:
			var retreat: Vector3 = -dir_to_player.normalized()
			velocity.x = retreat.x * stats.speed
			velocity.z = retreat.z * stats.speed
			_face_player()
	elif dist <= PREFERRED_DISTANCE:
		# Hold position and face the player
		velocity.x = 0.0
		velocity.z = 0.0
		_face_player()
	# else: dist > PREFERRED_DISTANCE — base chase velocity already closes the gap


func _fire_projectile() -> void:
	if not projectile_scene or not _player:
		return
	var proj: Node3D = projectile_scene.instantiate() as Node3D
	if not proj:
		return
	get_tree().current_scene.add_child(proj)
	# Spawn at chest height so the projectile doesn't clip the ground
	proj.global_position = global_position + Vector3(0, 0.8, 0)
	var target: Vector3 = _player.global_position + Vector3(0, 0.8, 0)
	var dir: Vector3 = (target - proj.global_position).normalized()
	proj.set("direction", dir)
