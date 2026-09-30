class_name HitboxComponent
extends Area3D

signal hit(target: Node, damage: int)

@export var damage: int = 10
@export var knockback_force: float = 5.0
@export var is_heavy: bool = false

var _logged_open: bool = false  # only tracked while EventLog is on, so hitbox_close pairs with an open


func _ready() -> void:
	monitoring = false
	monitorable = false
	area_entered.connect(_on_area_entered)


# Enable the hitbox for one attack swing
func activate() -> void:
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	if EventLog.enabled:
		_logged_open = true
		EventLog.log_event("hitbox_open", {"actor": EventLog.label(get_parent()), "heavy": is_heavy, "damage": damage})


func deactivate() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	if EventLog.enabled and _logged_open:
		_logged_open = false
		EventLog.log_event("hitbox_close", {"actor": EventLog.label(get_parent())})


func _on_area_entered(area: Area3D) -> void:
	if area is HurtboxComponent:
		if EventLog.enabled:
			EventLog.log_event("hit", {"attacker": EventLog.label(get_parent()), "target": EventLog.label(area.get_parent()),
					"damage": damage, "heavy": is_heavy, "iframed": (area as HurtboxComponent).invincible})
		emit_signal("hit", area.get_parent(), damage)
		GameManager.trigger_hit_stop(0.12 if is_heavy else 0.06)
