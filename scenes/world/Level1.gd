extends Node3D

const QUEST_ID := "clear_eastern_road"
const TOTAL_ENEMIES := 7

var _enemies_killed: int = 0
var _quest_advanced: bool = false
var _sealed_label: Label = null


func _ready() -> void:
	AudioManager.play_music(preload("res://assets/audio/music_ambient.ogg"))
	$NavigationRegion3D.bake_navigation_mesh()
	$ExitDoor.body_entered.connect(_on_exit_door_body_entered)
	$QuestAdvanceArea.body_entered.connect(_on_quest_advance_area_entered)
	_wire_enemy_deaths()
	_setup_sealed_label()
	# Connect NPC reward
	$VillageElder.quest_reward_given.connect(_on_elder_reward)


func _wire_enemy_deaths() -> void:
	for child in get_children():
		if child.is_in_group("enemy") and child.has_signal("died"):
			child.died.connect(_on_enemy_died)


func _on_enemy_died() -> void:
	_enemies_killed += 1
	if _enemies_killed >= TOTAL_ENEMIES and QuestManager.is_quest_active(QUEST_ID):
		QuestManager.complete_quest(QUEST_ID)


func _on_quest_advance_area_entered(body: Node3D) -> void:
	if _quest_advanced:
		return
	if not body.is_in_group("player"):
		return
	if not QuestManager.is_quest_active(QUEST_ID):
		return
	if QuestManager.get_quest_stage(QUEST_ID) == "find_monsters":
		_quest_advanced = true
		QuestManager.advance_quest(QUEST_ID)


func _on_exit_door_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if QuestManager.is_quest_complete(QUEST_ID):
		GameManager.change_scene("res://scenes/world/Level2.tscn")
	else:
		_show_sealed_message()


func _setup_sealed_label() -> void:
	_sealed_label = Label.new()
	_sealed_label.text = "The way forward is sealed..."
	_sealed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sealed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sealed_label.anchor_left = 0.0
	_sealed_label.anchor_right = 1.0
	_sealed_label.anchor_top = 0.3
	_sealed_label.anchor_bottom = 0.4
	_sealed_label.add_theme_font_size_override("font_size", 28)
	_sealed_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
	_sealed_label.modulate.a = 0.0
	_sealed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$CanvasLayer.add_child(_sealed_label)


func _show_sealed_message() -> void:
	if _sealed_label.modulate.a > 0.0:
		return
	var tween := create_tween()
	tween.tween_property(_sealed_label, "modulate:a", 1.0, 0.3)
	tween.tween_interval(1.5)
	tween.tween_property(_sealed_label, "modulate:a", 0.0, 0.5)


func _on_elder_reward() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return
	# Give XP reward
	if player.stats:
		player.stats.gain_experience(50)
	# Give shield item
	var shield: Item = load("res://data/items/shield_wooden.tres")
	if shield and player.inventory:
		player.inventory.add_item(shield)
