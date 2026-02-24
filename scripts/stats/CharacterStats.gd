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
	var actual: int = max(0, amount - defense)
	current_hp = max(0, current_hp - actual)
	emit_signal("health_changed", current_hp, max_hp)
	if current_hp == 0:
		emit_signal("died")


func heal(amount: int) -> void:
	current_hp = min(max_hp, current_hp + amount)
	emit_signal("health_changed", current_hp, max_hp)


func gain_experience(amount: int) -> void:
	experience += amount
	if experience >= experience_to_next_level:
		level_up()


func level_up() -> void:
	experience -= experience_to_next_level
	experience_to_next_level = int(experience_to_next_level * 1.5)
	level += 1
	max_hp += 10
	attack += 2
	defense += 1
	current_hp = max_hp  # Full restore on level-up
	emit_signal("health_changed", current_hp, max_hp)
	emit_signal("leveled_up", level)
	# Chain level-ups if carry-over XP already qualifies
	if experience >= experience_to_next_level:
		level_up()
