class_name HitboxComponent
extends Area3D

signal hit(target: Node, damage: int)

@export var damage: int = 10
@export var knockback_force: float = 5.0


func _ready() -> void:
	monitoring = false
	monitorable = false
	area_entered.connect(_on_area_entered)


# Enable the hitbox for one attack swing
func activate() -> void:
	monitoring = true
	monitorable = true


func deactivate() -> void:
	monitoring = false
	monitorable = false


func _on_area_entered(area: Area3D) -> void:
	if area is HurtboxComponent:
		emit_signal("hit", area.get_parent(), damage)
