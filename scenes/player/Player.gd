extends CharacterBody3D

signal died
signal inventory_toggled

const HeldProps := preload("res://scripts/combat/HeldProps.gd")
const WorldRay := preload("res://scripts/combat/WorldRay.gd")
const SIGHT_HEIGHT := 0.8  # lock-on sight runs between both bodies at this height, as EventLog.line_of_sight
const CHARACTER_LIGHT_LAYER := 2  # render layer of CameraRig/FillLight's cull mask (value 2 = layer 2)

@export var stats: CharacterStats
## Bone names for this model's rig; the only place socket bones are named
@export var socket_map: SocketMap
## Props to hold, keyed by socket name, e.g. {"hand_r": PackedScene}
@export var held_props: Dictionary = {}
@export var inventory: Inventory
@export var move_speed: float = 5.0
@export var dodge_speed: float = 8.4  # 4.2 m over the dodge, as before
@export var dodge_duration: float = 0.5  # fits the roll clip's core at 1.8x
@export var gravity: float = 20.0
@export var camera_sensitivity: float = 0.003  # radians per pixel (mouse)
@export var camera_pad_speed: float = 2.0  # radians per second (keys/gamepad)
@export var camera_pitch_min: float = -0.4  # ~-23 degrees
@export var camera_pitch_max: float = 0.8  # ~46 degrees
@export var lock_on_range: float = 15.0
@export var lock_lost_sight_time: float = 1.0  # hidden by world geometry this long, the lock ends (user, 2026-10-01)
@export var lock_on_pitch: float = -0.2  # the arm's tilt locked on a target level with him (as free look starts)
@export var combo_window: float = 0.6  # seconds before light combo resets
@export var attack_active_time: float = 0.2  # light hitbox active duration (seconds)
@export var heavy_active_time: float = 0.35  # heavy hitbox active duration (seconds)

# The camera (scenes/player/CameraRig.gd): top level on the head-height pivot, turned to the heading only
@onready var camera_rig: Node3D = $CameraRig
@onready var hurtbox: HurtboxComponent = $HurtboxComponent
@onready var hitbox: HitboxComponent = $HitboxComponent
@onready var _sfx_swing: AudioStreamPlayer3D = $SFXSwing
@onready var _sfx_footstep: AudioStreamPlayer3D = $SFXFootstep
# The model may have no clips yet (animation comes from the shared library)
@onready var _anim_player: AnimationPlayer = get_node_or_null("PlayerModel/AnimationPlayer")

var _is_dodging: bool = false
var _dodge_timer: float = 0.0
var _dodge_dir: Vector3 = Vector3.FORWARD

var _lock_on_target: Node3D = null
var _lock_on_candidates: Array[Node3D] = []
var _lock_on_index: int = 0
var _lock_hidden_time: float = 0.0
var _sight_query := WorldRay.make_query()

# Stored separately so lock-on can drive them independently of input
var _cam_yaw: float = 0.0
var _cam_pitch: float = -0.2

var _combo_index: int = 0
var _combo_timer: float = 0.0
var _attack_timer: float = 0.0

const FOOTSTEP_INTERVAL: float = 0.4
var _footstep_timer: float = 0.0

var _playing_oneshot: bool = false  # True while a non-looping anim plays


func _ready() -> void:
	add_to_group("player")
	# CameraRig/FillLight only lights render layer CHARACTER_LIGHT_LAYER, so it separates the player
	# from dark interiors without lighting walls or enemies
	HeldProps.attach($PlayerModel, socket_map, held_props, name)
	for mesh in $PlayerModel.find_children("*", "VisualInstance3D", true, false):
		(mesh as VisualInstance3D).layers |= 1 << (CHARACTER_LIGHT_LAYER - 1)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_cam_yaw = rotation.y
	_cam_pitch = 0.0
	camera_rig.update_view(0.0, _cam_yaw, _cam_pitch, null)
	if stats:
		stats.died.connect(die)
	if is_instance_valid(hitbox):
		hitbox.hit.connect(_on_hitbox_hit)
	if _anim_player:
		_anim_player.animation_finished.connect(_on_animation_finished)
		_play_anim("idle")
	_populate_starting_items()


func _populate_starting_items() -> void:
	if not inventory or not inventory.items.is_empty():
		return
	var sword: Item = load("res://data/items/sword_iron.tres")
	var potion: Item = load("res://data/items/potion_health.tres")
	if sword:
		inventory.add_item(sword)
	if potion:
		inventory.add_item(potion)


func _input(event: InputEvent) -> void:
	# Mouse look — only when not locked on
	if event is InputEventMouseMotion and not _lock_on_target:
		_cam_yaw -= event.relative.x * camera_sensitivity
		_cam_pitch -= event.relative.y * camera_sensitivity
		_cam_pitch = clamp(_cam_pitch, camera_pitch_min, camera_pitch_max)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event.is_action_pressed("open_inventory"):
		_toggle_inventory()


# Gameplay actions are polled in the physics step rather than read in _input: synthetic action
# input (the Godot MCP's frame-timed input_sequence, used by automated playtests) only reaches
# Input polling, never _input, and polling also lands each press on a known physics frame.
func _poll_gameplay_actions() -> void:
	if Input.is_action_just_pressed("lock_on"):
		_toggle_lock_on()

	if Input.is_action_just_pressed("dodge") and not _is_dodging:
		_dodge()

	if Input.is_action_just_pressed("interact") and DialogueRunner.accepts_interact():
		interact()

	if Input.is_action_just_pressed("attack_light") and not _is_dodging and _attack_timer <= 0.0:
		_attack_light()

	if Input.is_action_just_pressed("attack_heavy") and not _is_dodging and _attack_timer <= 0.0:
		_attack_heavy()


func _physics_process(delta: float) -> void:
	_poll_gameplay_actions()
	_validate_lock_on()
	_apply_gravity(delta)

	if _is_dodging:
		_tick_dodge(delta)
	else:
		_move(delta)

	_tick_attack(delta)
	move_and_slide()
	# After moving, so the camera frames where he is this frame
	_update_camera(delta)
	_update_locomotion_anim()
	_tick_footsteps(delta)


# ── Movement ──────────────────────────────────────────────────────────────────


func _move(delta: float) -> void:
	var input_dir := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_forward", "move_backward"))

	if input_dir.length_squared() > 0.01:
		input_dir = input_dir.normalized()

		# Project onto camera's horizontal plane
		var cam_forward := -camera_rig.global_transform.basis.z
		var cam_right := camera_rig.global_transform.basis.x
		cam_forward.y = 0.0
		cam_right.y = 0.0
		cam_forward = cam_forward.normalized()
		cam_right = cam_right.normalized()

		# move_forward action maps to -Y in get_axis, so negate
		var move_dir := cam_forward * (-input_dir.y) + cam_right * input_dir.x
		velocity.x = move_dir.x * move_speed
		velocity.z = move_dir.z * move_speed

		# Rotate character to face movement direction unless locked on
		if not _lock_on_target:
			rotation.y = lerp_angle(rotation.y, atan2(-move_dir.x, -move_dir.z), 10.0 * delta)
	else:
		# Decelerate
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, move_speed * 10.0 * delta)

	# Always face lock-on target regardless of movement
	if _lock_on_target:
		var to_target := _lock_on_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(-to_target.x, -to_target.z), 12.0 * delta)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta


# ── Dodge ─────────────────────────────────────────────────────────────────────


func _dodge() -> void:
	# Snap dodge direction from current input; fallback to character forward
	var input_dir := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_forward", "move_backward"))
	if input_dir.length_squared() > 0.01:
		var cam_forward := -camera_rig.global_transform.basis.z
		var cam_right := camera_rig.global_transform.basis.x
		cam_forward.y = 0.0
		cam_right.y = 0.0
		_dodge_dir = (cam_forward * (-input_dir.y) + cam_right * input_dir.x).normalized()
	else:
		_dodge_dir = -global_transform.basis.z

	_is_dodging = true
	_dodge_timer = dodge_duration
	_play_anim("dodge_roll", true)

	if is_instance_valid(hurtbox):
		hurtbox.invincible = true
	if EventLog.enabled:
		EventLog.log_event(
			"dodge_start",
			{
				"actor": EventLog.label(self),
				"duration_s": dodge_duration,
				"invincible": is_instance_valid(hurtbox) and hurtbox.invincible
			}
		)


func _tick_dodge(delta: float) -> void:
	velocity.x = _dodge_dir.x * dodge_speed
	velocity.z = _dodge_dir.z * dodge_speed
	_dodge_timer -= delta
	if _dodge_timer <= 0.0:
		_is_dodging = false
		if is_instance_valid(hurtbox):
			hurtbox.invincible = false
		if EventLog.enabled:
			EventLog.log_event("dodge_end", {"actor": EventLog.label(self), "invincible": false})


# ── Camera ────────────────────────────────────────────────────────────────────


func _update_camera(delta: float) -> void:
	if not _lock_on_target:
		# Gamepad / keyboard camera rotation
		var cam_input := Vector2(
			Input.get_axis("camera_left", "camera_right"), Input.get_axis("camera_up", "camera_down")
		)
		_cam_yaw -= cam_input.x * camera_pad_speed * delta
		_cam_pitch -= cam_input.y * camera_pad_speed * delta
		_cam_pitch = clamp(_cam_pitch, camera_pitch_min, camera_pitch_max)
	else:
		# Smoothly pivot toward lock-on target
		var to_target := _lock_on_target.global_position - global_position
		_cam_yaw = lerp_angle(_cam_yaw, atan2(-to_target.x, -to_target.z), 5.0 * delta)

		# Tilt camera slightly down to keep target in frame
		var flat_dist := Vector2(to_target.x, to_target.z).length()
		var desired_pitch: float = clamp(
			lock_on_pitch - atan2(to_target.y, flat_dist) * 0.5, camera_pitch_min, camera_pitch_max
		)
		_cam_pitch = lerp(_cam_pitch, desired_pitch, 5.0 * delta)

	camera_rig.update_view(delta, _cam_yaw, _cam_pitch, get_lock_on_target())


# Body facing and camera heading (world-space yaw, pitch) for SaveManager
func get_view_state() -> Dictionary:
	return {"facing": rotation.y, "camera_yaw": _cam_yaw, "camera_pitch": _cam_pitch}


func apply_view_state(view: Dictionary) -> void:
	rotation.y = float(view.get("facing", rotation.y))
	_cam_yaw = wrapf(float(view.get("camera_yaw", _cam_yaw)), -PI, PI)
	_cam_pitch = clampf(float(view.get("camera_pitch", _cam_pitch)), camera_pitch_min, camera_pitch_max)
	_release_lock_on()
	camera_rig.stop_shake()
	# Apply now rather than next physics frame, so input this frame already uses the restored view
	camera_rig.update_view(0.0, _cam_yaw, _cam_pitch, null)


# ── Lock-on ───────────────────────────────────────────────────────────────────


func _toggle_lock_on() -> void:
	if _lock_on_target:
		# Cycle to next candidate; release if only one in range
		if _lock_on_candidates.size() > 1:
			_lock_on_index = (_lock_on_index + 1) % _lock_on_candidates.size()
			_lock_on_target = _lock_on_candidates[_lock_on_index]
		else:
			_release_lock_on()
	else:
		_lock_on_target = _find_lock_on_target()
	if EventLog.enabled and _lock_on_target:
		EventLog.log_event("lock_on", {"actor": EventLog.label(self), "target": EventLog.label(_lock_on_target)})


# The locked-on enemy, or null (the replay's camera checks read it)
func get_lock_on_target() -> Node3D:
	return _lock_on_target if is_instance_valid(_lock_on_target) else null


func _release_lock_on() -> void:
	if EventLog.enabled and _lock_on_target != null:
		EventLog.log_event("lock_off", {"actor": EventLog.label(self)})
	_lock_on_target = null
	_lock_hidden_time = 0.0
	_lock_on_index = 0
	_lock_on_candidates.clear()


func _validate_lock_on() -> void:
	# A freed target compares equal to null, so the candidate list tells "never locked" from "target gone"
	if _lock_on_target == null and _lock_on_candidates.is_empty():
		return
	if not is_instance_valid(_lock_on_target) or _is_dead(_lock_on_target):
		_lock_on_next_after_death()
	elif global_position.distance_to(_lock_on_target.global_position) > lock_on_range * 1.5:
		_release_lock_on()
	elif _in_sight(_lock_on_target):
		_lock_hidden_time = 0.0
	else:
		# Circling a pillar hides it for a moment; behind cover for longer, the lock ends
		_lock_hidden_time += get_physics_process_delta_time()
		if _lock_hidden_time > lock_lost_sight_time:
			_release_lock_on()


# The locked target died (or was freed): lock the nearest living enemy in range at once, else release
func _lock_on_next_after_death() -> void:
	var gone := _lock_on_target
	var next: Node3D = null
	var best := INF
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not _lockable(enemy) or enemy == gone:
			continue
		var d := global_position.distance_to((enemy as Node3D).global_position)
		if d <= lock_on_range and d < best:
			best = d
			next = enemy as Node3D
	if next == null:
		_release_lock_on()
		return
	_lock_on_target = next
	_lock_on_candidates = [next]
	_lock_on_index = 0
	if EventLog.enabled:
		EventLog.log_event("lock_on", {"actor": EventLog.label(self), "target": EventLog.label(next)})


static func _is_dead(node: Node) -> bool:
	return node.has_method("is_dead") and bool(node.call("is_dead"))


# Lock-on candidates: living enemies (BaseEnemy and its subclasses, which have is_dead) in line of sight
func _lockable(node: Node) -> bool:
	return node is Node3D and node.has_method("is_dead") and not _is_dead(node) and _in_sight(node as Node3D)


# Nothing on the world layer between him and `target` (characters don't block), as enemy sight
func _in_sight(target: Node3D) -> bool:
	var exclude: Array[RID] = [get_rid()]
	if target is CollisionObject3D:
		exclude.append((target as CollisionObject3D).get_rid())
	_sight_query.exclude = exclude
	return WorldRay.is_clear(
		get_world_3d().direct_space_state,
		_sight_query,
		global_position + Vector3.UP * SIGHT_HEIGHT,
		target.global_position + Vector3.UP * SIGHT_HEIGHT
	)


func _find_lock_on_target() -> Node3D:
	_lock_on_candidates.clear()
	_lock_on_index = 0

	for enemy in get_tree().get_nodes_in_group("enemy"):
		if _lockable(enemy) and global_position.distance_to(enemy.global_position) <= lock_on_range:
			_lock_on_candidates.append(enemy as Node3D)

	if _lock_on_candidates.is_empty():
		return null

	# Sort by dot product against camera forward so the most-centered enemy is first
	var cam_forward := -camera_rig.global_transform.basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()

	_lock_on_candidates.sort_custom(
		func(a: Node3D, b: Node3D) -> bool:
			var da := (a.global_position - global_position).normalized()
			var db := (b.global_position - global_position).normalized()
			da.y = 0.0
			db.y = 0.0
			return cam_forward.dot(da) > cam_forward.dot(db)
	)

	return _lock_on_candidates[0]


# ── Interact ──────────────────────────────────────────────────────────────────


func interact() -> void:
	# Short forward raycast; interactables must implement interact()
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 0.8
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * 2.0)
	query.exclude = [get_rid()]
	var result := space.intersect_ray(query)
	if result and result.collider.has_method("interact"):
		result.collider.interact()


func _toggle_inventory() -> void:
	emit_signal("inventory_toggled")


# ── Combat ────────────────────────────────────────────────────────────────────


func _on_hitbox_hit(_target: Node, _damage: int) -> void:
	if hitbox.is_heavy:
		camera_shake(0.05, 0.3)


func camera_shake(intensity: float, duration: float) -> void:
	camera_rig.shake(intensity, duration)


func _tick_attack(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			if is_instance_valid(hitbox):
				hitbox.deactivate()

	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo_index = 0


func _attack_light() -> void:
	if not is_instance_valid(hitbox):
		return
	var base: int = stats.attack if stats else 8
	# Hits 1 & 2 deal base damage; finisher (index 2) deals 1.5× base
	hitbox.damage = base if _combo_index < 2 else base + base / 2
	hitbox.knockback_force = 4.0
	hitbox.is_heavy = false
	if EventLog.enabled:
		EventLog.log_event(
			"attack_started",
			{"actor": EventLog.label(self), "kind": "light", "combo_index": _combo_index, "damage": hitbox.damage}
		)
	hitbox.activate()
	_play_anim("attack_light", true)
	if _sfx_swing.stream:
		_sfx_swing.play()
	_attack_timer = attack_active_time
	_combo_timer = combo_window
	_combo_index = (_combo_index + 1) % 3


func _attack_heavy() -> void:
	if not is_instance_valid(hitbox):
		return
	# Resets any active combo; deals 3× base damage with strong knockback
	_combo_index = 0
	_combo_timer = 0.0
	var base: int = stats.attack if stats else 8
	hitbox.damage = base * 3
	hitbox.knockback_force = 10.0
	hitbox.is_heavy = true
	if EventLog.enabled:
		EventLog.log_event(
			"attack_started",
			{"actor": EventLog.label(self), "kind": "heavy", "combo_index": 0, "damage": hitbox.damage}
		)
	hitbox.activate()
	_play_anim("attack_heavy", true)
	if _sfx_swing.stream:
		_sfx_swing.play()
	_attack_timer = heavy_active_time


# ── Footsteps ─────────────────────────────────────────────────────────────────


func _tick_footsteps(delta: float) -> void:
	_footstep_timer -= delta
	if _footstep_timer <= 0.0 and is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.5:
		_footstep_timer = FOOTSTEP_INTERVAL
		if _sfx_footstep.stream:
			_sfx_footstep.play()


# ── Animation ────────────────────────────────────────────────────────────────


func _play_anim(anim_name: String, oneshot: bool = false) -> void:
	if not _anim_player:
		return
	if _anim_player.has_animation(anim_name):
		_playing_oneshot = oneshot
		_anim_player.play(anim_name)


func _on_animation_finished(_anim_name: StringName) -> void:
	if _playing_oneshot:
		_playing_oneshot = false
		_update_locomotion_anim()


func _update_locomotion_anim() -> void:
	if _playing_oneshot or not _anim_player:
		return
	var lateral := Vector2(velocity.x, velocity.z).length()
	if lateral > 0.5:
		if _anim_player.current_animation != "run":
			_play_anim("run")
	else:
		if _anim_player.current_animation != "idle":
			_play_anim("idle")


# ── Death ─────────────────────────────────────────────────────────────────────


func die() -> void:
	if not is_physics_processing():
		return  # Guard against double-call
	if EventLog.enabled:
		EventLog.log_event("death", {"actor": EventLog.label(self)})
	emit_signal("died")
	set_physics_process(false)
	set_process_input(false)
	velocity = Vector3.ZERO
	_play_anim("death", true)
