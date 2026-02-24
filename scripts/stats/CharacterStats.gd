class_name CharacterStats
extends Resource

signal health_changed(current_hp: int, max_hp: int)
signal died
signal leveled_up(new_level: int)

@export var max_hp: int = 100
@export var current_hp: int = 100
@export var attack: int = 10
@export var defense: int = 5
@export var speed: float = 5.0
@export var level: int = 1
@export var experience: int = 0
@export var experience_to_next_level: int = 100


func take_damage(amount: int) -> void:
	pass


func heal(amount: int) -> void:
	pass


func gain_experience(amount: int) -> void:
	pass


func level_up() -> void:
	pass
