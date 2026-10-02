extends Node3D

## The player's camera (design bible §2), built as modes: over the shoulder, and lock-on framing; first
## person comes later as a third mode. Player.gd owns the inputs, the heading (yaw), pitch and the lock-on
## target, and calls update_view() every physics frame after moving.
##
## The rig is top level and sits on the pivot, turned to the heading only, so camera-relative movement reads
## its basis and shake never turns it. FillLight (CLAUDE.md, lighting) is a child, behind and above the pivot
## on the camera side. The Camera3D is placed each frame:
##   - the arm runs from the pivot out to the shoulder, then back; a sphere probe (cast_motion, so a margin,
##     not a ray) shortens it at once against walls and lets it ease back out;
##   - pitch turns the look; the lens moves only within lens_band of its rest height;
##   - squeezed shorter than squeeze_fraction of the arm, the camera rises;
##   - the look pitch tilts as little as needed to keep his head and torso, then the target, inside the
##     vertical FOV (cam_player_in_frame, cam_lock_both_in_frame);
##   - locked on, the view swings off the heading by an angle that grows as the target closes, so the player
##     stands left of it on screen instead of in front of it (cam_melee_occlusion), and further when his back
##     is to a wall, until the arm has room.

enum Mode { OVER_SHOULDER, LOCK_ON }
## Framing variants for the user to choose between (playtest 2026-10-01); CURRENT keeps the exports as set
enum Framing { CURRENT, A_MEDIUM, B_WIDE, C_TIGHT }

const FRAMINGS := {
	# lens height = 1.6 m pivot + lens_lift; FOV, arm and offset as the orchestrator's brief suggested
	Framing.A_MEDIUM:
	{
		"arm_length": 1.6,
		"lock_arm_length": 2.2,
		"shoulder_offset": 0.7,
		"lens_lift": -0.05,
		"look_down": 0.03,
		"fov": 65.0
	},
	Framing.B_WIDE:
	{
		"arm_length": 2.0,
		"lock_arm_length": 2.6,
		"shoulder_offset": 0.8,
		"lens_lift": 0.05,
		"look_down": 0.12,
		"fov": 68.0
	},
	Framing.C_TIGHT:
	{
		"arm_length": 1.2,
		"lock_arm_length": 1.9,
		"shoulder_offset": 0.6,
		"lens_lift": -0.1,
		"look_down": 0.0,
		"fov": 60.0
	},
}

const BODY_HALF_HEIGHT := 0.9  # the player's and the levy's capsules: origin to top
const BODY_RADIUS := 0.4
const CAST_SKIN := 0.05  # metres every probe move stops short of a hit
const TORSO_HEIGHT := 0.45  # above the body origin: the middle of his head and torso
const FRAME_MARGIN_DEG := 3.0
const LOCK_SWING_STEP := 0.3  # radians
const LOCK_SWING_STEPS := 5
const LOCK_SWING_MAX := 1.5

@export var framing: Framing = Framing.A_MEDIUM
@export var pivot_height: float = 0.7  # above the body origin (0.9 m above the feet): 1.6 m
@export var arm_length: float = 2.5
@export var lock_arm_length: float = 3.0  # locked on, the arm pulls back a little to fit both
@export var shoulder_tuck: float = 0.6  # the most of the shoulder offset a short arm gives up
@export var shoulder_offset: float = 0.9  # to the right
@export var fov: float = 72.0
@export var look_right: float = deg_to_rad(4.0)  # the free look turns this far right, so he sits in the left third
## Lens height at rest relative to the pivot, and how far looking up or down may move it (pitch mostly turns
## the look; see update_view)
@export var lens_lift: float = 0.0
@export var lens_per_radian: float = 0.6
@export var lens_band: float = 0.35
@export var look_down: float = 0.1  # radians the look tilts below the arm, so a wall ahead leaves floor in view
@export var probe_radius: float = 0.3
@export var ease_out_speed: float = 10.0  # 1/s, the arm growing back after a squeeze
@export var squeeze_fraction: float = 0.8  # below this share of the full arm the camera rises
@export var squeeze_rise: float = 1.0  # metres at an arm of zero
@export var lock_separation: float = 1.1  # metres the target should stand off the player's line of sight
@export var lock_angle_min: float = deg_to_rad(8.0)
@export var lock_angle_max: float = deg_to_rad(50.0)
@export var lock_angle_speed: float = 5.0  # 1/s
@export_flags_3d_physics var collision_mask: int = 1

var mode: Mode = Mode.OVER_SHOULDER

var _body: Node3D
var _length: float = 0.0
var _mode_length: float = 0.0  # the arm the mode wants, eased between modes so a lock change never jumps
var _lock_angle: float = 0.0
var _shake_timer: float = 0.0
var _shake_duration: float = 0.0
var _shake_intensity: float = 0.0
var _query := PhysicsShapeQueryParameters3D.new()

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	for key: String in FRAMINGS.get(framing, {}):
		set(key, FRAMINGS[framing][key])
	_body = get_parent() as Node3D
	top_level = true
	camera.fov = fov
	_length = arm_length
	_mode_length = arm_length
	var sphere := SphereShape3D.new()
	sphere.radius = probe_radius
	_query.shape = sphere
	_query.collision_mask = collision_mask


func _squeeze_length() -> float:
	return squeeze_fraction * _mode_length


func get_pivot() -> Vector3:
	return _body.global_position + Vector3.UP * pivot_height


## Place the camera for this frame. yaw is the heading (world-space; 0 faces -Z), pitch the look's tilt.
func update_view(delta: float, yaw: float, pitch: float, target: Node3D) -> void:
	mode = Mode.LOCK_ON if is_instance_valid(target) else Mode.OVER_SHOULDER
	if not is_inside_tree():
		return
	var pivot := get_pivot()
	global_transform = Transform3D(Basis(Vector3.UP, yaw), pivot)
	_update_exclusions()

	# Pitch turns the look; the lens only rises or drops within lens_band of its rest height (playtest:
	# swinging the whole arm lifted it to about 3.4 m, behind and above his back)
	var lift := lens_lift + clampf(-pitch * lens_per_radian, -lens_band, lens_band)
	var want_length := lock_arm_length if mode == Mode.LOCK_ON else arm_length
	_mode_length = lerpf(_mode_length, want_length, 1.0 - exp(-ease_out_speed * delta)) if delta > 0.0 else want_length
	var want_angle := 0.0
	if mode == Mode.LOCK_ON:
		var to_target := target.global_position - _body.global_position
		var dist := maxf(Vector2(to_target.x, to_target.z).length(), 0.01)
		want_angle = _roomiest_angle(
			pivot, yaw, lift, clampf(asin(minf(lock_separation / dist, 1.0)), lock_angle_min, lock_angle_max)
		)
	# Swings faster while the arm is squeezed, so a lock with his back to a wall finds room quickly
	var swing_speed := lock_angle_speed
	if want_angle > _lock_angle:  # opening to find room; closing again stays gentle, so unlocking doesn't jump
		swing_speed *= 1.0 + 3.0 * clampf(1.0 - _length / _squeeze_length(), 0.0, 1.0)
	_lock_angle = lerpf(_lock_angle, want_angle, 1.0 - exp(-swing_speed * delta)) if delta > 0.0 else want_angle

	# Positive yaw turns left, so the view looks left of the target and the target sits right of centre
	var view_yaw := yaw + _lock_angle
	var arm := _arm(pivot, Basis(Vector3.UP, view_yaw), lift)
	var reach: float = arm[1]
	if reach < _length or delta <= 0.0:
		_length = reach
	else:
		_length = lerpf(_length, reach, 1.0 - exp(-ease_out_speed * delta))
	var cam_pos: Vector3 = arm[0] + arm[2] * _length
	# A short arm brings the camera in toward his back; the shoulder offset shrinks with it (up to
	# shoulder_tuck of it), or close in his near side leaves the frame sideways
	var tuck: Vector3 = (pivot - arm[0]) * clampf(1.0 - _length / maxf(_mode_length, 0.01), 0.0, shoulder_tuck)
	cam_pos += tuck * _cast(cam_pos, cam_pos + tuck)

	# Squeezed: rise, and turn the look from the heading toward his torso, so he stays whole in view from above
	# his shoulder; the tilt below then keeps his head and torso, and the target, inside the vertical FOV
	var squeeze := clampf(1.0 - _length / _squeeze_length(), 0.0, 1.0)
	var look_yaw := view_yaw - (look_right if mode == Mode.OVER_SHOULDER else 0.0)
	var look_pitch := pitch - look_down
	if squeeze > 0.0:
		var up := Vector3.UP * squeeze_rise * squeeze
		cam_pos += up * _cast(cam_pos, cam_pos + up)
		var ahead := Basis(Vector3.UP, look_yaw) * Basis(Vector3.RIGHT, look_pitch) * Vector3.FORWARD
		var aim := (_body.global_position + Vector3.UP * TORSO_HEIGHT - cam_pos).normalized()
		if mode == Mode.LOCK_ON:
			# Between him and the target by angle, weighted to him: his framing is the stricter target
			aim = (aim * 2.0 + (target.global_position - cam_pos).normalized()).normalized()
		var look := ahead.slerp(aim, minf(squeeze * 2.0, 1.0))
		look_yaw = atan2(-look.x, -look.z)
		look_pitch = asin(clampf(look.y, -1.0, 1.0))
	var spans := [[_body.global_position + Vector3.UP * BODY_HALF_HEIGHT, _body.global_position]]
	if mode == Mode.LOCK_ON:
		spans.append(
			[
				target.global_position + Vector3.UP * BODY_HALF_HEIGHT,
				target.global_position - Vector3.UP * BODY_HALF_HEIGHT
			]
		)
	look_pitch = _framed_pitch(cam_pos, look_yaw, look_pitch, spans)
	look_yaw = _framed_yaw(cam_pos, look_yaw, look_pitch)
	look_pitch = _framed_pitch(cam_pos, look_yaw, look_pitch, spans)
	camera.global_transform = Transform3D(Basis(Vector3.UP, look_yaw) * Basis(Vector3.RIGHT, look_pitch), cam_pos)
	_apply_shake(delta)


# The arm for a view: [shoulder point, reach along the view's back, the back direction]. It runs out to the
# shoulder first, so a wall at his right side shortens the offset instead of the camera passing through it.
func _arm(pivot: Vector3, view: Basis, lift: float) -> Array:
	var side := pivot + view.x * shoulder_offset
	var shoulder := pivot.lerp(side, _cast(pivot, side))
	var back := view.z * _mode_length + Vector3.UP * lift
	return [shoulder, back.length() * _cast(shoulder, shoulder + back), back.normalized()]


# Locked on with his back to a wall, swing the view further off the heading until the arm has room
func _roomiest_angle(pivot: Vector3, yaw: float, lift: float, angle: float) -> float:
	var best := angle
	var best_reach := -1.0
	for i in LOCK_SWING_STEPS:
		var a := minf(angle + LOCK_SWING_STEP * i, LOCK_SWING_MAX)
		var reach: float = _arm(pivot, Basis(Vector3.UP, yaw + a), lift)[1]
		if reach >= _squeeze_length():
			return a
		if reach > best_reach + 0.05:
			best_reach = reach
			best = a
	return best


# The look pitch nearest `pitch` that keeps each span (a body's [top, bottom] on its axis, taken a capsule
# radius nearer and further) inside the vertical FOV, the player's first; a target that can't fit with him is
# left out
func _framed_pitch(cam_pos: Vector3, view_yaw: float, pitch: float, spans: Array) -> float:
	var half := deg_to_rad(fov * 0.5 - FRAME_MARGIN_DEG)
	var forward := Basis(Vector3.UP, view_yaw) * Vector3.FORWARD
	var lo := -PI * 0.5
	var hi := PI * 0.5
	for i in spans.size():
		var top := -PI
		var bottom := PI
		for depth: float in [-BODY_RADIUS, BODY_RADIUS]:
			top = maxf(top, _elevation(cam_pos, spans[i][0] + forward * depth, forward))
			bottom = minf(bottom, _elevation(cam_pos, spans[i][1] + forward * depth, forward))
		if maxf(lo, top - half) > minf(hi, bottom + half):
			if i == 0:
				return (top + bottom) * 0.5
			break
		lo = maxf(lo, top - half)
		hi = minf(hi, bottom + half)
	return clampf(pitch, lo, hi)


# The look yaw nearest `yaw` that keeps the corners of his head-and-torso box inside the horizontal FOV at
# this pitch: close in, the shoulder offset and look_right would otherwise push his near side off the edge.
# Angles are taken in camera space, since a pitched look brings near corners in sideways.
func _framed_yaw(cam_pos: Vector3, yaw: float, pitch: float) -> float:
	var vp := get_viewport().get_visible_rect().size
	var half := atan(tan(deg_to_rad(fov * 0.5)) * vp.x / maxf(vp.y, 1.0)) - deg_to_rad(FRAME_MARGIN_DEG)
	var to_cam := (Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)).inverse()
	var heading := Basis(Vector3.UP, yaw)  # the box turns with the view, as the replay's probe measures it
	var lo := -INF
	var hi := INF
	var c := _body.global_position
	for dy: float in [0.0, BODY_HALF_HEIGHT]:
		for dx: float in [-BODY_RADIUS, BODY_RADIUS]:
			for dz: float in [-BODY_RADIUS, BODY_RADIUS]:
				var local := to_cam * (c + heading * Vector3(dx, dy, dz) - cam_pos)
				if local.z > -0.05:
					continue  # beside or behind the lens: yaw can't bring it in
				var rel := atan2(-local.x, -local.z)  # positive: left of centre
				lo = maxf(lo, rel - half)
				hi = minf(hi, rel + half)
	if lo > hi:
		return yaw
	return yaw + clampf(0.0, lo, hi)


static func _elevation(from: Vector3, p: Vector3, forward: Vector3) -> float:
	var d := p - from
	return atan2(d.y, maxf(d.dot(forward), 0.05))


## Shake the view (not the heading), fading out linearly over duration
func shake(intensity: float, duration: float) -> void:
	_shake_intensity = intensity
	_shake_duration = duration
	_shake_timer = duration


func stop_shake() -> void:
	_shake_timer = 0.0


func _apply_shake(delta: float) -> void:
	if _shake_timer <= 0.0:
		return
	_shake_timer -= delta
	var t: float = _shake_timer / _shake_duration if _shake_duration > 0.0 else 0.0
	camera.rotate_object_local(Vector3.UP, randf_range(-_shake_intensity, _shake_intensity) * t)
	camera.rotate_object_local(Vector3.RIGHT, randf_range(-_shake_intensity, _shake_intensity) * t * 0.5)


# The safe fraction of a sphere's move from `from` to `to` against the world (characters excluded)
# A sphere that starts touching a wall would pass straight through it (cast_motion ignores initial contact),
# so a touching start doesn't move, and every move stops CAST_SKIN short of the hit.
func _cast(from: Vector3, to: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	_query.transform = Transform3D(Basis.IDENTITY, from)
	_query.motion = Vector3.ZERO
	if not space.intersect_shape(_query, 1).is_empty():
		return 0.0
	_query.motion = to - from
	var result := space.cast_motion(_query)
	var length := (to - from).length()
	if result.size() == 0 or result[0] >= 1.0 or length <= 0.0:
		return 1.0
	return maxf(result[0] - CAST_SKIN / length, 0.0)


# Characters share layer 1 with the level; the camera passes through them (the player, enemies)
func _update_exclusions() -> void:
	var rids: Array[RID] = []
	if _body is CollisionObject3D:
		rids.append((_body as CollisionObject3D).get_rid())
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is CollisionObject3D:
			rids.append((enemy as CollisionObject3D).get_rid())
	_query.exclude = rids
