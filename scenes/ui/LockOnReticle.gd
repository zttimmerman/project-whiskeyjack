extends Control

## The lock-on reticle (design bible §2: "A reticle on the target, always visible while locked"). A small
## Signal Red ring with four ticks (art bible accent), centred each frame on the locked target's screen
## position; hidden while nothing is locked or the target is behind the camera. Instanced in the HUD.

const COLOR := Color("#C71F14")  # Signal Red
const RADIUS := 12.0
const TICK := 6.0
const WIDTH := 2.5
const AIM_HEIGHT := 0.0  # metres above the target's origin (its capsule centre)

var _player: Node = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2.ONE * (RADIUS + TICK) * 2.0
	visible = false


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	var target: Node3D = null
	if is_instance_valid(_player) and _player.has_method("get_lock_on_target"):
		target = _player.call("get_lock_on_target")
	var camera := get_viewport().get_camera_3d()
	var aim := target.global_position + Vector3.UP * AIM_HEIGHT if target else Vector3.ZERO
	visible = target != null and camera != null and not camera.is_position_behind(aim)
	if visible:
		global_position = camera.unproject_position(aim) - size * 0.5


func _draw() -> void:
	var c := size * 0.5
	draw_arc(c, RADIUS, 0.0, TAU, 32, COLOR, WIDTH, true)
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + dir * (RADIUS - 2.0), c + dir * (RADIUS + TICK), COLOR, WIDTH, true)
