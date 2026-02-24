extends Node

const SAVE_PATH := "user://save.json"

# Serializes: player position, CharacterStats, Inventory, equipment,
# QuestManager state, world flags (doors, killed enemies, etc.)


func save_game() -> void:
	pass


func load_game() -> void:
	pass


func save_exists() -> bool:
	return false
