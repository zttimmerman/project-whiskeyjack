extends Node

signal quest_started(quest_id: String)
signal quest_updated(quest_id: String, stage_id: String)
signal quest_completed(quest_id: String)

# { quest_id: { "data": {...}, "stage": stage_id } }
var _active_quests: Dictionary = {}
var _completed_quests: Array[String] = []


func _ready() -> void:
	pass


func start_quest(quest_id: String) -> void:
	if is_quest_active(quest_id) or quest_id in _completed_quests:
		return
	var data := _load_quest_data(quest_id)
	var first_stage := ""
	var stages: Array = data.get("stages", [])
	if stages.size() > 0:
		first_stage = stages[0].get("id", "")
	_active_quests[quest_id] = {"data": data, "stage": first_stage}
	emit_signal("quest_started", quest_id)


func advance_quest(quest_id: String) -> void:
	if not is_quest_active(quest_id):
		return
	var entry: Dictionary = _active_quests[quest_id]
	var stages: Array = entry["data"].get("stages", [])
	var current_stage: String = entry["stage"]
	var current_index := -1
	for i in stages.size():
		if stages[i].get("id", "") == current_stage:
			current_index = i
			break
	if current_index >= 0 and current_index + 1 < stages.size():
		var next_stage: String = stages[current_index + 1].get("id", "")
		_active_quests[quest_id]["stage"] = next_stage
		emit_signal("quest_updated", quest_id, next_stage)
	else:
		complete_quest(quest_id)


func complete_quest(quest_id: String) -> void:
	if not is_quest_active(quest_id):
		return
	_active_quests.erase(quest_id)
	_completed_quests.append(quest_id)
	emit_signal("quest_completed", quest_id)


func is_quest_active(quest_id: String) -> bool:
	return _active_quests.has(quest_id)


func get_quest_stage(quest_id: String) -> String:
	if not is_quest_active(quest_id):
		return ""
	return _active_quests[quest_id].get("stage", "")


func _load_quest_data(quest_id: String) -> Dictionary:
	var path := "res://data/quests/%s.json" % quest_id
	if not FileAccess.file_exists(path):
		# Return a minimal stub so start_quest still works for quests without a data file
		return {"id": quest_id, "stages": []}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	var parse_result := json.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		return {}
	var data = json.get_data()
	if data is Dictionary:
		return data
	return {}
