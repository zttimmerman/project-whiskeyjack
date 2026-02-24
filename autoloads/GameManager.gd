extends Node

signal scene_changed(scene_path: String)
signal game_over

# Holds a reference to the current player node once the scene is ready
var player: CharacterBody3D = null


func _ready() -> void:
	pass


func change_scene(scene_path: String) -> void:
	pass


func on_player_died() -> void:
	pass
