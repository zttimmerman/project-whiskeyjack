extends CharacterBody3D

signal died
signal inventory_toggled

@export var stats: CharacterStats
@export var inventory: Inventory
@export var move_speed: float = 5.0
@export var dodge_speed: float = 12.0
@export var dodge_duration: float = 0.35
@export var gravity: float = 20.0
@export var camera_sensitivity: float = 0.003   # radians per pixel (mouse)
@export var camera_pad_speed: float = 2.0        # radians per second (keys/gamepad)
@export var camera_pitch_min: float = -0.4       # ~-23 degrees
@export var camera_pitch_max: float = 0.8        # ~46 degrees
@export var lock_on_range: float = 15.0
@export var combo_window: float = 0.6        # seconds before light combo resets
@export var attack_active_time: float = 0.2  # light hitbox active duration (seconds)
@export var heavy_active_time: float = 0.35  # heavy hitbox active duration (seconds)

@onready var camera_rig: Node3D = $CameraRig
@onready var spring_arm: SpringArm3D = $CameraRig/SpringArm3D
@onready var hurtbox: HurtboxComponent = $HurtboxComponent
@onready var hitbox: HitboxComponent = $HitboxComponent
@onready var _sfx_swing: AudioStreamPlayer3D = $SFXSwing
@onready var _sfx_footstep: AudioStreamPlayer3D = $SFXFootstep
@onready var _anim_player: AnimationPlayer = $PlayerModel/AnimationPlayer

var _is_dodging: bool = false
var _dodge_timer: float = 0.0
var _dodge_dir: Vector3 = Vector3.FORWARD

var _lock_on_target: Node3D = null
var _lock_on_candidates: Array[Node3D] = []
var _lock_on_index: int = 0

# Stored separately so lock-on can drive them independently of input
var _cam_yaw: float = 0.0
var _cam_pitch: float = -0.2

var _combo_index: int = 0
var _combo_timer: float = 0.0
var _attack_timer: float = 0.0

var _shake_timer: float = 0.0
var _shake_duration: float = 0.0
var _shake_intensity: float = 0.0

const FOOTSTEP_INTERVAL: float = 0.4
var _footstep_timer: float = 0.0

var _playing_oneshot: bool = false  # True while a non-looping anim plays


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_cam_yaw = camera_rig.rotation.y + rotation.y
	_cam_pitch = spring_arm.rotation.x
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

	if event.is_action_pressed("lock_on"):
		_toggle_lock_on()

	if event.is_action_pressed("dodge") and not _is_dodging:
		_dodge()

	if event.is_action_pressed("interact"):
		interact()

	if event.is_action_pressed("open_inventory"):
		_toggle_inventory()

	if event.is_action_pressed("attack_light") and not _is_dodging and _attack_timer <= 0.0:
		_attack_light()

	if event.is_action_pressed("attack_heavy") and not _is_dodging and _attack_timer <= 0.0:
		_attack_heavy()


func _physics_process(delta: float) -> void:
	_validate_lock_on()
	_apply_gravity(delta)

	if _is_dodging:
		_tick_dodge(delta)
	else:
		_move(delta)

	_tick_attack(delta)
	_update_camera(delta)
	move_and_slide()
	_update_locomotion_anim()
	_tick_footsteps(delta)


# ── Movement ──────────────────────────────────────────────────────────────────

func _move(delta: float) -> void:
	var input_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_backward")
	)

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
	var input_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_backward")
	)
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


func _tick_dodge(delta: float) -> void:
	velocity.x = _dodge_dir.x * dodge_speed
	velocity.z = _dodge_dir.z * dodge_speed
	_dodge_timer -= delta
	if _dodge_timer <= 0.0:
		_is_dodging = false
		if is_instance_valid(hurtbox):
			hurtbox.invincible = false


# ── Camera ────────────────────────────────────────────────────────────────────

func _update_camera(delta: float) -> void:
	if not _lock_on_target:
		# Gamepad / keyboard camera rotation
		var cam_input := Vector2(
			Input.get_axis("camera_left", "camera_right"),
			Input.get_axis("camera_up", "camera_down")
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
		var desired_pitch: float = clamp(-atan2(to_target.y, flat_dist) * 0.5, camera_pitch_min, camera_pitch_max)
		_cam_pitch = lerp(_cam_pitch, desired_pitch, 5.0 * delta)

	# Subtract player's own rotation so the rig's world-space yaw equals _cam_yaw
	camera_rig.rotation.y = _cam_yaw - rotation.y
	spring_arm.rotation.x = _cam_pitch

	# Camera shake — fades out linearly over the shake duration
	if _shake_timer > 0.0:
		_shake_timer -= delta
		var t: float = _shake_timer / _shake_duration if _shake_duration > 0.0 else 0.0
		camera_rig.rotation.y += randf_range(-_shake_intensity, _shake_intensity) * t
		spring_arm.rotation.x += randf_range(-_shake_intensity, _shake_intensity) * t * 0.5


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


func _release_lock_on() -> void:
	_lock_on_target = null
	_lock_on_index = 0
	_lock_on_candidates.clear()


func _validate_lock_on() -> void:
	if not _lock_on_target:
		return
	# Release if target was freed or moved out of range
	if not is_instance_valid(_lock_on_target) \
			or global_position.distance_to(_lock_on_target.global_position) > lock_on_range * 1.5:
		_release_lock_on()


func _find_lock_on_target() -> Node3D:
	_lock_on_candidates.clear()
	_lock_on_index = 0

	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is Node3D \
				and global_position.distance_to(enemy.global_position) <= lock_on_range:
			_lock_on_candidates.append(enemy as Node3D)

	if _lock_on_candidates.is_empty():
		return null

	# Sort by dot product against camera forward so the most-centered enemy is first
	var cam_forward := -camera_rig.global_transform.basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()

	_lock_on_candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
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
	_shake_intensity = intensity
	_shake_duration = duration
	_shake_timer = duration


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
	hitbox.activate()
	_play_anim("attack_heavy", true)
	if _sfx_swing.stream:
		_sfx_swing.play()
	_attack_timer = heavy_active_time


# ── Footsteps ─────────────────────────────────────────────────────────────────

func _tick_footsteps(delta: float) -> void:
	_footstep_timer -= delta
	if _footstep_timer <= 0.0 \
			and is_on_floor() \
			and Vector2(velocity.x, velocity.z).length() > 0.5:
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
	emit_signal("died")
	set_physics_process(false)
	set_process_input(false)
	velocity = Vector3.ZERO
	_play_anim("death", true)
