extends CharacterBody3D

signal died

# SEARCH is last so the other states keep their values
enum State { IDLE, PATROL, CHASE, ATTACK, STAGGER, DEAD, SEARCH }
enum SearchPhase { GO, LOOK, RETURN }

@export var stats: CharacterStats
@export var xp_reward: int = 10
@export var detection_range: float = 10.0
## Sight (design bible §3): the player is seen within detection_range inside this cone around the facing,
## and heard within hearing_radius in any direction; both need a clear line of sight to the world layer
@export var view_cone_deg: float = 120.0
@export var hearing_radius: float = 4.0
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
## Sight rays run at most this often per enemy (the cheap range and cone tests run every frame)
const SIGHT_INTERVAL: float = 0.1
## Ray ends above the body origin (the capsule centre, 0.9 m above the feet): enemy eyes, player chest
const EYE_HEIGHT: float = 0.7
const CHEST_HEIGHT: float = 0.4
## Melee enemies without an attack token hold this far from the player (design bible §3: 3–5 m)
const HOLD_MIN_DISTANCE: float = 3.0
const HOLD_MAX_DISTANCE: float = 5.0
## Losing sight (decided with the user, 2026-09-30): go to where the player was last seen, turn in place
## looking around for SEARCH_LOOK_TIME, then walk back to the post and idle
const SEARCH_LOOK_TIME: float = 3.5
const SEARCH_TURN_RATE: float = deg_to_rad(90.0)
## Close enough to a search point; and the most time spent walking to one (an unreachable spot)
const SEARCH_ARRIVE_DISTANCE: float = 0.5
const SEARCH_WALK_TIMEOUT: float = 8.0

var state: State = State.IDLE
var _player: CharacterBody3D = null
var _nav_agent: NavigationAgent3D = null
var _hitbox: HitboxComponent = null
const HeldProps := preload("res://scripts/combat/HeldProps.gd")
const WorldRay := preload("res://scripts/combat/WorldRay.gd")
const AttackTokens := preload("res://scripts/combat/AttackTokens.gd")

var _anim_player: AnimationPlayer = null

var _stagger_timer: float = 0.0
var _attack_timer: float = 0.0
var _attack_cooldown_timer: float = 0.0

var _sight_query: PhysicsRayQueryParameters3D = null
var _sight_timer: float = 0.0  # until the next sight ray may run
## The last sight ray's answer while chasing (archers fire only with it)
var _can_see_player: bool = false
var _cone_cos: float = 0.0

## Where the player was last seen, and this enemy's post (its spawn transform), for SEARCH
var _last_seen_position: Vector3 = Vector3.ZERO
var _post: Transform3D = Transform3D.IDENTITY
var _search_phase: SearchPhase = SearchPhase.GO
var _search_timer: float = 0.0


func _ready() -> void:
	add_to_group("enemy")
	# Duplicate the shared stats resource so each instance has its own HP pool
	stats = stats.duplicate()
	$HurtboxComponent.stats = stats
	_nav_agent = $NavigationAgent3D
	_hitbox = $HitboxComponent
	_player = get_tree().get_first_node_in_group("player")
	_sight_query = WorldRay.make_query([get_rid()])
	_cone_cos = cos(deg_to_rad(view_cone_deg * 0.5))
	_post = global_transform
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
		State.SEARCH:
			_tick_search(delta)
		State.DEAD:
			# Collapse in place: no knockback or chase velocity carries through the death clip
			velocity.x = 0.0
			velocity.z = 0.0

	if state != State.DEAD:
		_get_next_action()
	move_and_slide()


func _tick_idle(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _notices_player(delta):
		_change_state(State.CHASE)


func _tick_patrol(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _notices_player(delta):
		_change_state(State.CHASE)


# Detection (design bible §3): in range and in the view cone, or within hearing; then a sight ray to the
# player's chest. The range and cone tests are cheap and run every frame; a blocked candidate re-casts its
# ray every SIGHT_INTERVAL, and a fresh candidate casts at once, so detection never lags a clear view.
func _notices_player(delta: float) -> bool:
	if not is_instance_valid(_player):
		return false
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var heard := dist <= hearing_radius
	if dist > detection_range or (not heard and not _in_view_cone(to_player, dist)):
		_sight_timer = 0.0
		return false
	_sight_timer -= delta
	if _sight_timer > 0.0:
		return false
	_sight_timer = SIGHT_INTERVAL
	return has_line_of_sight()


func _in_view_cone(to_player: Vector3, dist: float) -> bool:
	if dist < 0.001:
		return true
	var forward := -global_basis.z
	forward.y = 0.0
	return forward.normalized().dot(to_player / dist) >= _cone_cos


## Whether world geometry (not characters) lies between this enemy's eyes and the player's chest
func has_line_of_sight() -> bool:
	if not is_instance_valid(_player) or not is_inside_tree():
		return false
	return WorldRay.is_clear(
		get_world_3d().direct_space_state,
		_sight_query,
		global_position + Vector3.UP * EYE_HEIGHT,
		_player.global_position + Vector3.UP * CHEST_HEIGHT
	)


# While chasing, the sight answer is refreshed every SIGHT_INTERVAL (archers fire only with sight)
func _refresh_sight(delta: float) -> void:
	_sight_timer -= delta
	if _sight_timer > 0.0:
		return
	_sight_timer = SIGHT_INTERVAL
	_can_see_player = has_line_of_sight()
	if _can_see_player:
		_last_seen_position = _player.global_position


func _tick_chase(delta: float) -> void:
	_attack_cooldown_timer = max(0.0, _attack_cooldown_timer - delta)

	if not _player:
		_change_state(State.IDLE)
		return
	_refresh_sight(delta)

	var dist: float = global_position.distance_to(_player.global_position)

	if dist > detection_range * 1.5:
		_change_state(State.IDLE)
		return

	if not _can_see_player:
		_change_state(State.SEARCH)
		return

	if not _may_close_in(dist):
		_hold_off(dist)
		return

	if dist <= attack_range and _attack_cooldown_timer <= 0.0:
		_change_state(State.ATTACK)
		return

	_navigate_toward(_player.global_position)


# Navigate toward a point; falls back to direct movement if no nav mesh is baked
func _navigate_toward(target: Vector3) -> void:
	_nav_agent.target_position = target
	var move_dir: Vector3

	if not _nav_agent.is_navigation_finished():
		var next_pos: Vector3 = _nav_agent.get_next_path_position()
		move_dir = next_pos - global_position
		move_dir.y = 0.0
		# If nav gives us essentially our own position, go direct
		if move_dir.length_squared() < 0.1:
			move_dir = target - global_position
			move_dir.y = 0.0
	else:
		move_dir = target - global_position
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


# Lost sight: walk to the last-seen spot, look around, walk back to the post. Noticing the player again
# (the same rule as from IDLE) resumes the chase at any point.
func _tick_search(delta: float) -> void:
	_attack_cooldown_timer = max(0.0, _attack_cooldown_timer - delta)
	if _notices_player(delta):
		if EventLog.enabled:
			EventLog.log_event("search_end", {"actor": EventLog.label(self), "outcome": "regained"})
		_change_state(State.CHASE)
		return
	_search_timer -= delta
	match _search_phase:
		SearchPhase.GO:
			if _flat_distance_to(_last_seen_position) <= SEARCH_ARRIVE_DISTANCE or _search_timer <= 0.0:
				_search_phase = SearchPhase.LOOK
				_search_timer = SEARCH_LOOK_TIME
				velocity.x = 0.0
				velocity.z = 0.0
				_update_locomotion_anim()
			else:
				_navigate_toward(_last_seen_position)
		SearchPhase.LOOK:
			velocity.x = 0.0
			velocity.z = 0.0
			rotate_y(SEARCH_TURN_RATE * delta)
			if _search_timer <= 0.0:
				if EventLog.enabled:
					EventLog.log_event("search_end", {"actor": EventLog.label(self), "outcome": "gave_up"})
				_search_phase = SearchPhase.RETURN
				_search_timer = SEARCH_WALK_TIMEOUT
		SearchPhase.RETURN:
			if _flat_distance_to(_post.origin) <= SEARCH_ARRIVE_DISTANCE or _search_timer <= 0.0:
				velocity.x = 0.0
				velocity.z = 0.0
				global_basis = _post.basis  # face the way it stood guard
				_change_state(State.IDLE)
			else:
				_navigate_toward(_post.origin)


func _flat_distance_to(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


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


# Attack tokens (design bible §3, enemy_attackers_max): a melee enemy closes inside HOLD_MAX_DISTANCE only
# holding one of the player's melee tokens. Archers (attack_range 0) never need one.
func _may_close_in(dist: float) -> bool:
	if attack_range <= 0.0 or dist > HOLD_MAX_DISTANCE:
		return true
	var tokens := _attack_tokens()
	return tokens == null or tokens.try_acquire_melee(self)


# Without a token: back off inside HOLD_MIN_DISTANCE, otherwise stand and face the player
func _hold_off(dist: float) -> void:
	var away := global_position - _player.global_position
	away.y = 0.0
	if dist < HOLD_MIN_DISTANCE and away.length_squared() > 0.01:
		away = away.normalized()
		velocity.x = away.x * stats.speed
		velocity.z = away.z * stats.speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	_face_player()
	_update_locomotion_anim()


## The player's attack tokens, created by the first enemy to ask; null without a player
func _attack_tokens() -> AttackTokens:
	if not is_instance_valid(_player):
		return null
	if not _player.has_meta(AttackTokens.META):
		_player.set_meta(AttackTokens.META, AttackTokens.new())
	return _player.get_meta(AttackTokens.META) as AttackTokens


func _release_attack_tokens() -> void:
	var tokens := _attack_tokens()
	if tokens:
		tokens.release(self)


# Physics time in seconds, for the ranged token's window (deterministic in replays, unlike wall time)
func _physics_time_s() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)


# Override in subclasses to inject additional per-frame state logic
func _get_next_action() -> void:
	pass


func _change_state(new_state: State) -> void:
	if EventLog.enabled:
		_log_state_change(new_state)
	var old_state := state
	state = new_state
	match new_state:
		State.IDLE:
			_release_attack_tokens()
			_play_anim("idle")
		State.SEARCH:
			_release_attack_tokens()
			_search_phase = SearchPhase.GO
			_search_timer = SEARCH_WALK_TIMEOUT
			_sight_timer = 0.0
			_update_locomotion_anim()
		State.CHASE:
			if is_instance_valid(_player):
				_last_seen_position = _player.global_position
			if old_state == State.IDLE or old_state == State.PATROL or old_state == State.SEARCH:
				# Usually it has just seen the player, but a hit or a script can start a chase too
				_can_see_player = has_line_of_sight()
				_sight_timer = SIGHT_INTERVAL
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
			_release_attack_tokens()
			_hitbox.deactivate()
			velocity = Vector3.ZERO
			_nav_agent.target_position = global_position
			_play_anim("death")


# Event log (scripts/debug/EventLog.gd), called before the state changes so the old state is known
func _log_state_change(new_state: State) -> void:
	var actor := EventLog.label(self)
	var dist := (
		EventLog.round3(global_position.distance_to(_player.global_position)) if is_instance_valid(_player) else -1.0
	)
	match new_state:
		State.ATTACK:
			EventLog.log_event("attack_started", {"actor": actor, "kind": "melee"})
		State.STAGGER:
			EventLog.log_event("stagger", {"actor": actor, "interrupted_attack": state == State.ATTACK})
		State.DEAD:
			EventLog.log_event("death", {"actor": actor})
		State.SEARCH:
			EventLog.log_event("lost_sight", {"actor": actor, "distance": dist})
		State.CHASE:
			if state == State.IDLE or state == State.PATROL or state == State.SEARCH:
				EventLog.log_event(
					"detected",
					{
						"actor": actor,
						"target": EventLog.label(_player),
						"distance": dist,
						"line_of_sight": EventLog.line_of_sight(self, _player)
					}
				)
		State.IDLE:
			if state == State.CHASE:
				EventLog.log_event("disengaged", {"actor": actor, "distance": dist})


# Parents each held prop to a BoneAttachment3D on the bone its socket maps to
func _attach_held_props(model_node: Node) -> void:
	HeldProps.attach(model_node, socket_map, held_props, name)


func _play_anim(anim_name: String) -> void:
	if not _anim_player:
		return
	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)


func _update_locomotion_anim() -> void:
	if not _anim_player or (state != State.CHASE and state != State.SEARCH):
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
	if state == State.CHASE or state == State.SEARCH:
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
	var hp_before := stats.current_hp
	stats.take_damage(amount)
	if EventLog.enabled:
		EventLog.log_event(
			"damage_taken",
			{
				"target": EventLog.label(self),
				"attacker": "scripted",
				"raw": amount,
				"amount": hp_before - stats.current_hp,
				"hp": stats.current_hp,
				"max_hp": stats.max_hp
			}
		)
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
