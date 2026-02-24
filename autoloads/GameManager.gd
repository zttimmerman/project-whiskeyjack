extends Node

signal scene_changed(scene_path: String)
signal game_over

# Holds a reference to the current player node once the scene is ready
var player: CharacterBody3D = null


func _ready() -> void:
	pass


func change_scene(scene_path: String) -> void:
	emit_signal("scene_changed", scene_path)
	get_tree().change_scene_to_file(scene_path)


func reload_scene() -> void:
	get_tree().reload_current_scene()


# Called by BaseEnemy on death — grants XP to the player
func award_player_xp(amount: int) -> void:
	if not player:
		# Lazy-find the player if we don't have a direct reference yet
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player and player.get("stats"):
		player.stats.gain_experience(amount)


func on_player_died() -> void:
	pass
