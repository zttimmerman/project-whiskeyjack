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
	pass


func advance_quest(quest_id: String) -> void:
	pass


func complete_quest(quest_id: String) -> void:
	pass


func is_quest_active(quest_id: String) -> bool:
	return false


func get_quest_stage(quest_id: String) -> String:
	return ""


func _load_quest_data(quest_id: String) -> Dictionary:
	return {}
