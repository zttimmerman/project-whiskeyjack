extends CharacterBody3D

signal died

enum State { IDLE, PATROL, CHASE, ATTACK, STAGGER, DEAD }

@export var stats: CharacterStats
@export var xp_reward: int = 10
@export var detection_range: float = 10.0
@export var attack_range: float = 1.5
@export var gravity: float = 20.0
## Bone names for this model's rig; the only place socket bones are named
@export var socket_map: SocketMap
## Props to hold, keyed by socket name, e.g. {"hand_r": PackedScene}
@export var held_props: Dictionary = {}

const STAGGER_DURATION: float = 0.4
const ATTACK_ACTIVE_TIME: float = 0.3
const DEATH_FADE_TIME: float = 0.3
const DEATH_FALLBACK_TIME: float = 2.4  # Death01's length, if the model has no death clip
const ATTACK_COOLDOWN: float = 1.5

var state: State = State.IDLE
var _player: CharacterBody3D = null
var _nav_agent: NavigationAgent3D = null
var _hitbox: HitboxComponent = null
const HeldProps := preload("res://scripts/combat/HeldProps.gd")

var _anim_player: AnimationPlayer = null

var _stagger_timer: float = 0.0
var _attack_timer: float = 0.0
var _attack_cooldown_timer: float = 0.0


func _ready() -> void:
	add_to_group("enemy")
	# Duplicate the shared stats resource so each instance has its own HP pool
	stats = stats.duplicate()
	$HurtboxComponent.stats = stats
	_nav_agent = $NavigationAgent3D
	_hitbox = $HitboxComponent
	_player = get_tree().get_first_node_in_group("player")
	# Grab AnimationPlayer from the model sub-scene (SkeletonModel/AnimationPlayer)
	var model_node: Node = get_node_or_null("SkeletonModel")
	if model_node:
		_anim_player = model_node.get_node_or_null("AnimationPlayer")
	if _anim_player:
		_anim_player.animation_finished.connect(_on_animation_finished)
		_play_anim("idle")
	if model_node:
		_attach_held_props(model_node)
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
			# Collapse in place: no knockback or chase velocity carries through the death clip
			velocity.x = 0.0
			velocity.z = 0.0

	if state != State.DEAD:
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
		_update_locomotion_anim()
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_update_locomotion_anim()


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
		State.IDLE:
			_play_anim("idle")
		State.CHASE:
			_update_locomotion_anim()
		State.ATTACK:
			_face_player()
			_hitbox.activate()
			_attack_timer = ATTACK_ACTIVE_TIME
			_play_anim("attack")
		State.STAGGER:
			_hitbox.deactivate()
			_stagger_timer = STAGGER_DURATION
			_play_anim("stagger")
		State.DEAD:
			_hitbox.deactivate()
			velocity = Vector3.ZERO
			_nav_agent.target_position = global_position
			_play_anim("death")


# Parents each held prop to a BoneAttachment3D on the bone its socket maps to
func _attach_held_props(model_node: Node) -> void:
	HeldProps.attach(model_node, socket_map, held_props, name)


func _play_anim(anim_name: String) -> void:
	if not _anim_player:
		return
	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)


func _update_locomotion_anim() -> void:
	if not _anim_player or state != State.CHASE:
		return
	var dominated: float = Vector2(velocity.x, velocity.z).length()
	if dominated > 0.5:
		if _anim_player.current_animation != "run":
			_play_anim("run")
	else:
		if _anim_player.current_animation != "idle":
			_play_anim("idle")


func _on_animation_finished(_anim_name: StringName) -> void:
	# After a oneshot (attack/stagger) finishes, resume locomotion anim
	if state == State.CHASE:
		_update_locomotion_anim()
	elif state == State.IDLE:
		_play_anim("idle")


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
	GameManager.award_player_xp(xp_reward)
	# Recorded for the save's world state, so this enemy stays dead once a later save loads
	SaveManager.record_enemy_killed(self)
	emit_signal("died")
	# Free once the death clip has played, fading the model out over its last DEATH_FADE_TIME
	var length := DEATH_FALLBACK_TIME
	if _anim_player and _anim_player.has_animation("death"):
		length = _anim_player.get_animation("death").length
	var tween := create_tween()
	tween.tween_interval(maxf(length - DEATH_FADE_TIME, 0.0))
	# Fade through material alpha: the Compatibility renderer doesn't draw GeometryInstance3D.transparency.
	# Each surface gets its own copy, since the material is shared with every other levy.
	var first := true
	for mesh in find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if not mat is BaseMaterial3D:
				continue
			var fading := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			fading.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.set_surface_override_material(s, fading)
			# The first fade follows the wait; the rest run alongside it
			(tween if first else tween.parallel()).tween_property(fading, "albedo_color:a", 0.0, DEATH_FADE_TIME)
			first = false
	tween.tween_callback(queue_free)


func is_dead() -> bool:
	return state == State.DEAD


func _on_stats_died() -> void:
	die()
