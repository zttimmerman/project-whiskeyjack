extends CharacterBody3D

# Test double for SaveManager: the properties and methods it reads from the player, nothing else.

var stats: CharacterStats
var inventory: Inventory
var view := {"facing": 0.0, "camera_yaw": 0.0, "camera_pitch": 0.0}


func _init() -> void:
	add_to_group("player")


func get_view_state() -> Dictionary:
	return view.duplicate()


func apply_view_state(state: Dictionary) -> void:
	view = state.duplicate()
