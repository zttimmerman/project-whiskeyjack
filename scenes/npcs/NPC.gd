class_name NPC
extends CharacterBody3D

signal quest_reward_given

@export var dialogue_id: String = ""
@export var npc_name: String = ""
## If this quest is complete, use completion_dialogue_id instead of dialogue_id
@export var completion_quest_id: String = ""
@export var completion_dialogue_id: String = ""

var _player_in_range: bool = false
var _reward_given: bool = false


func _ready() -> void:
	add_to_group("npc")


func interact() -> void:
	var active_dialogue := dialogue_id
	if not completion_quest_id.is_empty() and QuestManager.is_quest_complete(completion_quest_id):
		if not completion_dialogue_id.is_empty():
			active_dialogue = completion_dialogue_id
		if not _reward_given:
			_reward_given = true
			quest_reward_given.emit()

	if active_dialogue.is_empty():
		return
	DialogueRunner.start(active_dialogue)


func _on_interact_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true


func _on_interact_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
