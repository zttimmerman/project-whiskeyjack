extends Node

signal scene_changed(scene_path: String)
signal game_over

# Holds a reference to the current player node once the scene is ready
var player: CharacterBody3D = null


func _ready() -> void:
	# Watch for any new node entering the tree so we can (re-)connect to the
	# player after a scene reload.  call_deferred ensures the node's _ready()
	# has run (and add_to_group("player") has been called) before we search.
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_try_connect_player")


func _on_node_added(_node: Node) -> void:
	# Only attempt reconnect when we don't already hold a valid player ref.
	if not is_instance_valid(player):
		call_deferred("_try_connect_player")


func _try_connect_player() -> void:
	var p := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if p == null or p == player:
		return
	player = p
	if p.has_signal("died") and not p.died.is_connected(on_player_died):
		p.died.connect(on_player_died)


func change_scene(scene_path: String) -> void:
	emit_signal("scene_changed", scene_path)
	get_tree().change_scene_to_file(scene_path)


func reload_scene() -> void:
	get_tree().reload_current_scene()


# Called by BaseEnemy on death — grants XP to the player
func award_player_xp(amount: int) -> void:
	if not player:
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player and player.get("stats"):
		player.stats.gain_experience(amount)


func on_player_died() -> void:
	# HUD owns the YOU DIED visual tween:
	#   DEATH_FADE_DURATION (0.6 s) + label fade (0.35 s) + DEATH_SHOW_DURATION (2.0 s) ≈ 3 s
	# We wait slightly longer so the overlay is fully visible before we reload.
	await get_tree().create_timer(3.2).timeout

	player = null  # clear stale ref; _try_connect_player will re-populate after reload
	get_tree().reload_current_scene()

	# reload_current_scene() is deferred — the actual scene swap happens at idle
	# time between frames.  Two process_frame awaits guarantee _ready() calls on
	# all new nodes (including Player) have finished before we apply saved data.
	await get_tree().process_frame
	await get_tree().process_frame

	if SaveManager.save_exists():
		SaveManager.load_game()

	# Respawn always at full HP regardless of what HP value was saved
	var p := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if p:
		var s := p.get("stats") as CharacterStats
		if s:
			s.current_hp = s.max_hp
			s.emit_signal("health_changed", s.current_hp, s.max_hp)
