class_name NPC
extends CharacterBody3D

@export var dialogue_id: String = ""
@export var npc_name: String = ""

# True while the player is within interaction range
var _player_in_range: bool = false


func _ready() -> void:
	add_to_group("npc")


func interact() -> void:
	if dialogue_id.is_empty():
		return
	DialogueRunner.start(dialogue_id)


# Called by an Area3D child when the player enters/exits interaction range
func _on_interact_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true


func _on_interact_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
