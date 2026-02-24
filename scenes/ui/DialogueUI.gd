extends Control

const TYPEWRITER_SPEED: float = 45.0  # characters per second

@onready var _speaker_label: Label = $DialoguePanel/Margin/VBox/SpeakerLabel
@onready var _dialogue_text: RichTextLabel = $DialoguePanel/Margin/VBox/DialogueText
@onready var _choices_box: VBoxContainer = $DialoguePanel/Margin/VBox/ChoicesBox
@onready var _advance_hint: Label = $DialoguePanel/Margin/VBox/AdvanceHint

var _chars_revealed: float = 0.0
var _full_char_count: int = 0
var _typing_done: bool = true
var _has_choices: bool = false


func _ready() -> void:
	hide()
	DialogueRunner.dialogue_started.connect(_on_dialogue_started)
	DialogueRunner.line_ready.connect(_on_line_ready)
	DialogueRunner.dialogue_ended.connect(_on_dialogue_ended)


func _process(delta: float) -> void:
	if _typing_done:
		return
	_chars_revealed += TYPEWRITER_SPEED * delta
	var to_show := int(_chars_revealed)
	if to_show >= _full_char_count:
		_dialogue_text.visible_characters = -1
		_typing_done = true
		_advance_hint.visible = not _has_choices
		_choices_box.visible = _has_choices
		return
	_dialogue_text.visible_characters = to_show


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact"):
		if not _typing_done:
			# Skip typewriter animation
			_typing_done = true
			_dialogue_text.visible_characters = -1
			_advance_hint.visible = not _has_choices
			_choices_box.visible = _has_choices
		elif not _has_choices:
			DialogueRunner.advance()
		get_viewport().set_input_as_handled()


func _on_dialogue_started(_dialogue_id: String) -> void:
	show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_line_ready(speaker: String, text: String, choices: Array) -> void:
	_speaker_label.text = speaker.to_upper()
	_dialogue_text.text = text
	_dialogue_text.visible_characters = 0
	_chars_revealed = 0.0
	_typing_done = false
	_full_char_count = _dialogue_text.get_total_character_count()
	_has_choices = choices.size() > 0
	_clear_choices()
	_choices_box.visible = false
	_advance_hint.visible = false
	# Build choice buttons (hidden until typing finishes)
	if _has_choices:
		for i in choices.size():
			var btn := Button.new()
			btn.text = choices[i].get("text", "")
			var idx := i
			btn.pressed.connect(func(): _on_choice_pressed(idx))
			_choices_box.add_child(btn)


func _on_dialogue_ended() -> void:
	get_tree().paused = false
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _clear_choices() -> void:
	for child in _choices_box.get_children():
		child.queue_free()


func _on_choice_pressed(choice_index: int) -> void:
	DialogueRunner.advance(choice_index)
