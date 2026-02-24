class_name HitboxComponent
extends Area3D

signal hit(target: Node, damage: int)

@export var damage: int = 10
@export var knockback_force: float = 5.0

# Call this to activate the hitbox for one attack swing
func activate() -> void:
	pass


func deactivate() -> void:
	pass
