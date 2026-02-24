class_name Item
extends Resource

enum Type { WEAPON, ARMOR, CONSUMABLE, KEY }

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var icon: Texture2D
@export var type: Type = Type.CONSUMABLE
@export var stats_modifier: Dictionary = {}
