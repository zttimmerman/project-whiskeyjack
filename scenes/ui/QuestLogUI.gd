extends Control

@onready var quest_list: ItemList = $MainPanel/Margin/VBox/HBox/QuestList
@onready var title_label: Label = $MainPanel/Margin/VBox/HBox/InfoPanel/TitleLabel
@onready var stage_label: Label = $MainPanel/Margin/VBox/HBox/InfoPanel/StageLabel
@onready var completed_label: Label = $MainPanel/Margin/VBox/HBox/InfoPanel/CompletedLabel
@onready var main_panel: Panel = $MainPanel


func _ready() -> void:
	visible = false
	_apply_style()
	quest_list.item_selected.connect(_on_quest_selected)
	QuestManager.quest_started.connect(func(_id: String) -> void: _on_quests_changed())
	QuestManager.quest_updated.connect(func(_id: String, _stage: String) -> void: _on_quests_changed())
	QuestManager.quest_completed.connect(func(_id: String) -> void: _on_quests_changed())


func _apply_style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.12, 0.95)
	panel_style.border_color = Color(0.55, 0.55, 0.8, 1.0)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(0)
	main_panel.add_theme_stylebox_override("panel", panel_style)

	var header := $MainPanel/Margin/VBox/TitleLabel as Label
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.9, 0.78, 0.2))

	var list_bg := StyleBoxFlat.new()
	list_bg.bg_color = Color(0.03, 0.03, 0.08, 1.0)
	list_bg.border_color = Color(0.4, 0.4, 0.65, 1.0)
	list_bg.set_border_width_all(2)
	quest_list.add_theme_stylebox_override("panel", list_bg)
	quest_list.add_theme_font_size_override("font_size", 14)
	quest_list.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))

	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	stage_label.add_theme_font_size_override("font_size", 12)
	stage_label.add_theme_color_override("font_color", Color(0.72, 0.72, 0.78))
	completed_label.add_theme_font_size_override("font_size", 12)
	completed_label.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5))


# ── Toggle ────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("open_quest_log"):
		if visible:
			_close()
		else:
			_open()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _open() -> void:
	_refresh_list()
	_clear_info()
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ── Quest list ────────────────────────────────────────────────────────────────

func _on_quests_changed() -> void:
	if visible:
		_refresh_list()


func _refresh_list() -> void:
	var selected_id := ""
	var sel_items := quest_list.get_selected_items()
	if sel_items.size() > 0:
		selected_id = str(quest_list.get_item_metadata(sel_items[0]))

	quest_list.clear()
	for quest_id in QuestManager._active_quests:
		var data: Dictionary = QuestManager._active_quests[quest_id].get("data", {})
		var display: String = data.get("title", quest_id)
		quest_list.add_item(display)
		var idx: int = quest_list.get_item_count() - 1
		quest_list.set_item_metadata(idx, quest_id)
		# Restore selection after refresh
		if quest_id == selected_id:
			quest_list.select(idx)
			_populate_info(quest_id)


func _on_quest_selected(index: int) -> void:
	var quest_id: String = str(quest_list.get_item_metadata(index))
	_populate_info(quest_id)


func _populate_info(quest_id: String) -> void:
	if not QuestManager.is_quest_active(quest_id):
		_clear_info()
		return

	var entry: Dictionary = QuestManager._active_quests[quest_id]
	var data: Dictionary = entry.get("data", {})
	var stage_id: String = entry.get("stage", "")

	title_label.text = data.get("title", quest_id)

	var stage_desc := ""
	for stage in data.get("stages", []):
		if stage.get("id", "") == stage_id:
			stage_desc = stage.get("description", "")
			break
	stage_label.text = stage_desc if not stage_desc.is_empty() else "(No stage description)"

	_update_completed_section()


func _clear_info() -> void:
	title_label.text = ""
	stage_label.text = ""
	_update_completed_section()


func _update_completed_section() -> void:
	if QuestManager._completed_quests.is_empty():
		completed_label.text = ""
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("-- Completed --")
	for cq in QuestManager._completed_quests:
		lines.append("* " + str(cq))
	completed_label.text = "\n".join(lines)
