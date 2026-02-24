class_name Item
extends Resource

enum Type { WEAPON, ARMOR, CONSUMABLE, KEY }

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var icon: Texture2D
@export var type: Type = Type.CONSUMABLE
@export var stats_modifier: Dictionary = {}


# Returns true if the item was consumed (only for CONSUMABLE type).
func use(stats: CharacterStats) -> bool:
	if type != Type.CONSUMABLE:
		return false
	if stats_modifier.has("heal"):
		stats.heal(int(stats_modifier["heal"]))
	return true
