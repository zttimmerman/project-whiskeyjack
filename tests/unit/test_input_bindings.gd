extends GdUnitTestSuite

# Design bible §2 Bindings: one action per key. Reads the input map from project.godot and fails
# when a physical key, mouse button or joypad button drives more than one gameplay action. Godot's
# built-in ui_* actions are left out: they share keys with gameplay by design and are read only by
# Controls.


func _gameplay_actions() -> Dictionary:
	var actions := {}
	for prop in ProjectSettings.get_property_list():
		var setting: String = prop.name
		if not setting.begins_with("input/"):
			continue
		var action := setting.trim_prefix("input/")
		if action.begins_with("ui_"):
			continue
		actions[action] = ProjectSettings.get_setting(setting).get("events", [])
	return actions


func _binding_key(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return "key %s" % OS.get_keycode_string(code)
	if event is InputEventMouseButton:
		return "mouse button %d" % (event as InputEventMouseButton).button_index
	if event is InputEventJoypadButton:
		return "joypad button %d" % (event as InputEventJoypadButton).button_index
	return ""


func test_one_action_per_key() -> void:
	var actions := _gameplay_actions()
	assert_bool(actions.has("interact")).is_true()
	var owners := {}
	for action: String in actions:
		for event: InputEvent in actions[action]:
			var binding := _binding_key(event)
			if binding.is_empty():
				continue
			if not owners.has(binding):
				owners[binding] = []
			if not owners[binding].has(action):
				owners[binding].append(action)
	var shared: Array[String] = []
	for binding: String in owners:
		if owners[binding].size() > 1:
			shared.append("%s -> %s" % [binding, ", ".join(owners[binding])])
	assert_array(shared).override_failure_message("Bound to several actions: %s" % "; ".join(shared)).is_empty()


func test_interact_keyboard_is_f_only() -> void:
	var keys: Array[String] = []
	var pads := 0
	for event: InputEvent in _gameplay_actions()["interact"]:
		if event is InputEventKey:
			keys.append(_binding_key(event))
		elif event is InputEventJoypadButton:
			pads += 1
	assert_array(keys).contains_exactly(["key F"])
	assert_int(pads).is_equal(1)


func test_e_rotates_camera_right() -> void:
	var keys: Array[String] = []
	for event: InputEvent in _gameplay_actions()["camera_right"]:
		keys.append(_binding_key(event))
	assert_array(keys).contains(["key E"])
