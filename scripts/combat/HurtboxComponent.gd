class_name HurtboxComponent
extends Area3D

# Owner node must have a CharacterStats node or property accessible
@export var stats: CharacterStats

# Invincibility frames — set true during dodge roll, etc.
var invincible: bool = false


func _ready() -> void:
	area_entered.connect(_on_hitbox_entered)


func _on_hitbox_entered(hitbox: Area3D) -> void:
	pass
