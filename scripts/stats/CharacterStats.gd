class_name CharacterStats
extends Resource

signal health_changed(current_hp: int, max_hp: int)
signal died
signal leveled_up(new_level: int)
signal xp_changed(current_xp: int, xp_to_next: int)

@export var max_hp: int = 100
@export var current_hp: int = 100
@export var attack: int = 10
@export var defense: int = 5
@export var speed: float = 5.0
@export var level: int = 1
@export var experience: int = 0
@export var experience_to_next_level: int = 100

# Design bible §6: enemy stats scale as base × (1 + 0.12 × (level − 1))
const LEVEL_SCALE_PER_LEVEL: float = 0.12


# The level-band multiplier for a stat defined at level 1
static func level_scale(for_level: int) -> float:
	return 1.0 + LEVEL_SCALE_PER_LEVEL * (for_level - 1)


# An integer stat scaled to a level, rounded to nearest (decided 2026-09-30)
static func scaled_stat(base: int, for_level: int) -> int:
	return roundi(base * level_scale(for_level))


# The §6 damage ratio: armour reduces a hit proportionally and never below 1
static func mitigated_damage(amount: int, target_defense: int) -> int:
	return maxi(1, roundi(amount * 100.0 / (100.0 + 10.0 * target_defense)))


func take_damage(amount: int) -> void:
	var actual: int = mitigated_damage(amount, defense)
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
		level_up()  # level_up emits health_changed + leveled_up, which cover XP display
	else:
		emit_signal("xp_changed", experience, experience_to_next_level)


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
