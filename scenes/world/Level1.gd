extends Node3D


func _ready() -> void:
	AudioManager.play_music(preload("res://assets/audio/music_ambient.ogg"))
	$NavigationRegion3D.bake_navigation_mesh()
	$ExitDoor.body_entered.connect(_on_exit_door_body_entered)


func _on_exit_door_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		GameManager.change_scene("res://scenes/world/Level2.tscn")
