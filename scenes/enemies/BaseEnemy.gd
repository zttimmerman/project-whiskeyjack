extends CharacterBody3D

signal died

enum State { IDLE, PATROL, CHASE, ATTACK, STAGGER, DEAD }

@export var stats: CharacterStats
@export var detection_range: float = 10.0
@export var attack_range: float = 1.5
@export var gravity: float = 20.0

const STAGGER_DURATION: float = 0.4
const ATTACK_ACTIVE_TIME: float = 0.3
const ATTACK_COOLDOWN: float = 1.5

var state: State = State.IDLE
var _player: CharacterBody3D = null
var _nav_agent: NavigationAgent3D = null
var _hitbox: HitboxComponent = null

var _stagger_timer: float = 0.0
var _attack_timer: float = 0.0
var _attack_cooldown_timer: float = 0.0


func _ready() -> void:
	add_to_group("enemy")
	_nav_agent = $NavigationAgent3D
	_hitbox = $HitboxComponent
	_player = get_tree().get_first_node_in_group("player")
	stats.died.connect(_on_stats_died)
	# Connect enemy's own hurtbox to trigger stagger state (HurtboxComponent handles HP)
	$HurtboxComponent.area_entered.connect(_on_hurtbox_hit)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	match state:
		State.IDLE:
			_tick_idle(delta)
		State.PATROL:
			_tick_patrol(delta)
		State.CHASE:
			_tick_chase(delta)
		State.ATTACK:
			_tick_attack(delta)
		State.STAGGER:
			_tick_stagger(delta)
		State.DEAD:
			pass

	_get_next_action()
	move_and_slide()


func _tick_idle(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _player and global_position.distance_to(_player.global_position) <= detection_range:
		_change_state(State.CHASE)


func _tick_patrol(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _player and global_position.distance_to(_player.global_position) <= detection_range:
		_change_state(State.CHASE)


func _tick_chase(delta: float) -> void:
	_attack_cooldown_timer = max(0.0, _attack_cooldown_timer - delta)

	if not _player:
		_change_state(State.IDLE)
		return

	var dist: float = global_position.distance_to(_player.global_position)

	if dist > detection_range * 1.5:
		_change_state(State.IDLE)
		return

	if dist <= attack_range and _attack_cooldown_timer <= 0.0:
		_change_state(State.ATTACK)
		return

	# Navigate toward player; falls back to direct movement if no nav mesh is baked
	_nav_agent.target_position = _player.global_position
	var move_dir: Vector3

	if not _nav_agent.is_navigation_finished():
		var next_pos: Vector3 = _nav_agent.get_next_path_position()
		move_dir = next_pos - global_position
		move_dir.y = 0.0
		# If nav gives us essentially our own position, go direct
		if move_dir.length_squared() < 0.1:
			move_dir = _player.global_position - global_position
			move_dir.y = 0.0
	else:
		move_dir = _player.global_position - global_position
		move_dir.y = 0.0

	if move_dir.length_squared() > 0.01:
		move_dir = move_dir.normalized()
		velocity.x = move_dir.x * stats.speed
		velocity.z = move_dir.z * stats.speed
		look_at(global_position + move_dir, Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0


func _tick_attack(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_hitbox.deactivate()
		_attack_cooldown_timer = ATTACK_COOLDOWN
		_change_state(State.CHASE)


func _tick_stagger(delta: float) -> void:
	# Bleed off knockback velocity from the HurtboxComponent push
	velocity.x = move_toward(velocity.x, 0.0, stats.speed * delta * 10.0)
	velocity.z = move_toward(velocity.z, 0.0, stats.speed * delta * 10.0)
	_stagger_timer -= delta
	if _stagger_timer <= 0.0:
		_change_state(State.CHASE)


# Override in subclasses to inject additional per-frame state logic
func _get_next_action() -> void:
	pass


func _change_state(new_state: State) -> void:
	state = new_state
	match new_state:
		State.ATTACK:
			_face_player()
			_hitbox.activate()
			_attack_timer = ATTACK_ACTIVE_TIME
		State.STAGGER:
			_hitbox.deactivate()
			_stagger_timer = STAGGER_DURATION
		State.DEAD:
			_hitbox.deactivate()


func _face_player() -> void:
	if not _player:
		return
	var look_dir: Vector3 = _player.global_position - global_position
	look_dir.y = 0.0
	if look_dir.length_squared() > 0.01:
		look_at(global_position + look_dir, Vector3.UP)


# Called when the enemy's hurtbox overlaps a hitbox — transitions to STAGGER
# (HP reduction is already handled by HurtboxComponent)
func _on_hurtbox_hit(area: Area3D) -> void:
	if state == State.DEAD:
		return
	if not (area is HitboxComponent):
		return
	_change_state(State.STAGGER)


# Public API for scripted/environmental damage (bypasses the component system)
func take_damage(amount: int, knockback_direction: Vector3 = Vector3.ZERO) -> void:
	if state == State.DEAD:
		return
	stats.take_damage(amount)
	# stats.died may have fired synchronously above, calling die() → state = DEAD
	if state == State.DEAD:
		return
	if knockback_direction != Vector3.ZERO:
		velocity += knockback_direction * 4.0
	_change_state(State.STAGGER)


func die() -> void:
	if state == State.DEAD:
		return
	_change_state(State.DEAD)
	emit_signal("died")
	queue_free()


func _on_stats_died() -> void:
	die()
