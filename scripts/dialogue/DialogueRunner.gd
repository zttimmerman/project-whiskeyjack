extends Node

signal dialogue_started(dialogue_id: String)
signal line_ready(speaker: String, text: String, choices: Array)
signal dialogue_ended

# Currently loaded dialogue nodes keyed by id
var _dialogue_data: Dictionary = {}
var _current_node_id: String = ""
var _active: bool = false


func start(dialogue_id: String) -> void:
	if _active:
		return
	if not _load_dialogue(dialogue_id):
		push_error("DialogueRunner: failed to load dialogue '%s'" % dialogue_id)
		return
	_active = true
	emit_signal("dialogue_started", dialogue_id)
	_show_node("start")


func advance(choice_index: int = 0) -> void:
	if not _active:
		return
	var node: Dictionary = _dialogue_data.get(_current_node_id, {})
	if node.is_empty():
		_end()
		return

	var choices: Array = node.get("choices", [])
	var next_id = null
	if choices.size() > 0:
		if choice_index < choices.size():
			next_id = choices[choice_index].get("next_id", null)
	else:
		next_id = node.get("next_id", null)

	if next_id == null or next_id == "":
		_end()
	else:
		_show_node(next_id)


func _load_dialogue(dialogue_id: String) -> bool:
	var path := "res://data/dialogues/%s.json" % dialogue_id
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var json := JSON.new()
	var parse_result := json.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		push_error("DialogueRunner: JSON parse error in '%s'" % path)
		return false
	var data = json.get_data()
	if not data is Array:
		return false
	_dialogue_data.clear()
	for entry in data:
		if entry is Dictionary and entry.has("id"):
			_dialogue_data[entry["id"]] = entry
	return not _dialogue_data.is_empty()


func _show_node(node_id: String) -> void:
	var node: Dictionary = _dialogue_data.get(node_id, {})
	if node.is_empty():
		_end()
		return
	_current_node_id = node_id
	# Trigger quest before emitting so QuestManager state is updated first
	if node.has("set_quest"):
		var quest_id: String = node["set_quest"]
		if quest_id != "":
			QuestManager.start_quest(quest_id)
	var speaker: String = node.get("speaker", "")
	var text: String = node.get("text", "")
	var choices: Array = node.get("choices", [])
	emit_signal("line_ready", speaker, text, choices)


func _end() -> void:
	_active = false
	_current_node_id = ""
	_dialogue_data.clear()
	emit_signal("dialogue_ended")
