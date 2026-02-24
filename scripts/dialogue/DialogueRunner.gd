extends Node

signal dialogue_started(dialogue_id: String)
signal line_ready(speaker: String, text: String, choices: Array)
signal dialogue_ended

# Currently loaded dialogue nodes keyed by id
var _dialogue_data: Dictionary = {}
var _current_node_id: String = ""
var _active: bool = false


func start(dialogue_id: String) -> void:
	pass


func advance(choice_index: int = 0) -> void:
	pass


func _load_dialogue(dialogue_id: String) -> bool:
	return false


func _end() -> void:
	pass
