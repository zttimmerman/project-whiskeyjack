extends Node

## Runs conversations written as Dialogue Manager `.dialogue` files (data/dialogues/<id>.dialogue)
## and exposes them through the same signals and methods as the old JSON runner, so DialogueUI and
## NPCs don't depend on the addon. Conditions and mutations in the files call the autoloads
## directly (QuestManager.start_quest, QuestManager.set_flag, ...).

signal dialogue_started(dialogue_id: String)
signal line_ready(speaker: String, text: String, choices: Array)
signal dialogue_ended

## Every conversation starts at this cue (`~ start`)
const START_CUE := "start"

## Where start() looks for <dialogue_id>.dialogue (tests point it at their fixtures)
var dialogue_dir: String = "res://data/dialogues/"
## Extra state for dialogue expressions, checked before the autoloads. Tests pass
## [{"QuestManager": <a fresh QuestManager>}] so the real autoload is never touched.
var game_states: Array = []

var _resource: DialogueResource = null
var _line: DialogueLine = null
# The responses the player can pick, in the order line_ready listed them
var _choices: Array[DialogueResponse] = []
var _active: bool = false
# True while Dialogue Manager resolves the next line (mutations take at least a frame)
var _busy: bool = false
# The physics frame the last conversation ended on (see accepts_interact)
var _ended_frame: int = -100


func start(dialogue_id: String) -> void:
	if _active:
		return
	var path := dialogue_dir.path_join("%s.dialogue" % dialogue_id)
	var resource: DialogueResource = load(path) as DialogueResource if ResourceLoader.exists(path) else null
	if resource == null:
		push_error("DialogueRunner: failed to load dialogue '%s'" % dialogue_id)
		return
	_resource = resource
	_active = true
	dialogue_started.emit(dialogue_id)
	await _show(START_CUE)


## Continues the conversation: with choices on screen, picks choice_index; otherwise the next line.
func advance(choice_index: int = 0) -> void:
	if not _active or _busy or _line == null:
		return
	if _choices.is_empty():
		await _show(_line.next_id)
	elif choice_index >= 0 and choice_index < _choices.size():
		await _show(_choices[choice_index].next_id)
	else:
		_end()


func is_active() -> bool:
	return _active


## False while a conversation is open and for two physics frames after it ends. The key that closes
## a conversation is the interact key, which Player polls in the physics step, so without this the
## closing press would reopen the conversation on the frame the tree unpauses.
func accepts_interact() -> bool:
	return not _active and Engine.get_physics_frames() - _ended_frame > 2


# Asks Dialogue Manager for the next spoken line from `key`, running any mutations on the way.
func _show(key: String) -> void:
	_busy = true
	# A copy: Dialogue Manager inserts {"self": resource} into the array it's given
	var states := game_states.duplicate()
	var line: DialogueLine = await DialogueManager.get_next_dialogue_line(_resource, key, states)
	_busy = false
	if not _active:
		return
	if line == null:
		_end()
		return
	_line = line
	_choices.clear()
	var choices: Array = []
	for response: DialogueResponse in line.responses:
		if response.is_allowed:
			_choices.append(response)
			choices.append({"text": response.text})
	line_ready.emit(line.character, line.text, choices)


func _end() -> void:
	_active = false
	_ended_frame = Engine.get_physics_frames()
	_resource = null
	_line = null
	_choices.clear()
	dialogue_ended.emit()
