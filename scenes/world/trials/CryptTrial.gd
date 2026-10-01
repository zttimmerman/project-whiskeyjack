extends Node3D

# Trial B2 (docs/trials/func-godot.md): a crypt room set built from a Quake .map with func_godot.
# The brushwork and torches are the generated CryptTrial_brushes.tscn (scripts/tools/build_brush_maps.gd);
# this scene adds the lighting environment, the player and a few kit props. Not reachable from the game.


func _ready() -> void:
	AudioManager.play_music(preload("res://assets/audio/music_ambient.ogg"))
