extends Control

@onready var panel: Panel = $MainPanel
@onready var resume_btn: Button = $MainPanel/Margin/VBox/ResumeButton
@onready var save_btn: Button = $MainPanel/Margin/VBox/SaveButton
@onready var load_btn: Button = $MainPanel/Margin/VBox/LoadButton
@onready var quit_btn: Button = $MainPanel/Margin/VBox/QuitButton
@onready var saved_label: Label = $MainPanel/Margin/VBox/SavedLabel


func _ready() -> void:
	hide()
	resume_btn.pressed.connect(_on_resume_pressed)
	save_btn.pressed.connect(_on_save_pressed)
	load_btn.pressed.connect(_on_load_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if visible:
			_do_resume()
		else:
			_do_open()
		get_viewport().set_input_as_handled()


func _do_open() -> void:
	saved_label.hide()
	show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _do_resume() -> void:
	hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_resume_pressed() -> void:
	_do_resume()


func _on_save_pressed() -> void:
	SaveManager.save_game()
	saved_label.text = "Game Saved!"
	saved_label.show()
	# create_timer defaults to process_always=true so it ticks through pause
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(saved_label):
		saved_label.hide()


func _on_load_pressed() -> void:
	_do_resume()
	SaveManager.load_game()


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()
