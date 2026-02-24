extends Node

const SAVE_PATH := "user://save.json"


func save_game() -> void:
	var player := _get_player()
	if not player:
		push_warning("SaveManager: no player found, aborting save")
		return

	var data := {
		"player": _serialize_player(player),
		"quests": _serialize_quests(),
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: could not open save file for writing")
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func load_game() -> void:
	if not save_exists():
		push_warning("SaveManager: no save file found")
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_error("SaveManager: could not open save file for reading")
		return
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("SaveManager: failed to parse save file")
		return
	var data = json.get_data()
	if not data is Dictionary:
		return

	if data.has("quests"):
		_deserialize_quests(data["quests"])

	var player := _get_player()
	if player and data.has("player"):
		_deserialize_player(player, data["player"])


func save_exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_player() -> Node:
	if GameManager.player:
		return GameManager.player
	return get_tree().get_first_node_in_group("player")


# ── Serialization ─────────────────────────────────────────────────────────────

func _serialize_player(player: Node) -> Dictionary:
	var pos: Vector3 = player.global_position
	var result: Dictionary = {
		"position": [pos.x, pos.y, pos.z],
	}

	var stats: CharacterStats = player.get("stats")
	if stats:
		result["stats"] = {
			"max_hp": stats.max_hp,
			"current_hp": stats.current_hp,
			"attack": stats.attack,
			"defense": stats.defense,
			"speed": stats.speed,
			"level": stats.level,
			"experience": stats.experience,
			"experience_to_next_level": stats.experience_to_next_level,
		}

	var inventory: Inventory = player.get("inventory")
	if inventory:
		var item_ids: Array = []
		for item in inventory.items:
			item_ids.append(item.id)

		var eq: Dictionary = {}
		for slot in inventory.equipment:
			var equipped: Item = inventory.equipment[slot]
			eq[slot] = equipped.id if equipped else ""

		result["inventory"] = {
			"items": item_ids,
			"equipment": eq,
		}

	return result


func _serialize_quests() -> Dictionary:
	var active: Dictionary = {}
	for quest_id in QuestManager._active_quests:
		active[quest_id] = QuestManager._active_quests[quest_id].get("stage", "")
	return {
		"active": active,
		"completed": QuestManager._completed_quests.duplicate(),
	}


# ── Deserialization ───────────────────────────────────────────────────────────

func _deserialize_player(player: Node, data: Dictionary) -> void:
	# Position
	if data.has("position"):
		var arr: Array = data["position"]
		if arr.size() == 3:
			player.global_position = Vector3(float(arr[0]), float(arr[1]), float(arr[2]))

	# Stats — restore directly; saved values already include any equipment modifiers.
	# Equipment modifiers are NOT re-applied here; the saved numbers are authoritative.
	var stats: CharacterStats = player.get("stats")
	if stats and data.has("stats"):
		var s: Dictionary = data["stats"]
		stats.max_hp = int(s.get("max_hp", stats.max_hp))
		stats.current_hp = int(s.get("current_hp", stats.current_hp))
		stats.attack = int(s.get("attack", stats.attack))
		stats.defense = int(s.get("defense", stats.defense))
		stats.speed = float(s.get("speed", stats.speed))
		stats.level = int(s.get("level", stats.level))
		stats.experience = int(s.get("experience", stats.experience))
		stats.experience_to_next_level = int(s.get("experience_to_next_level", stats.experience_to_next_level))
		# Notify HUD
		stats.emit_signal("health_changed", stats.current_hp, stats.max_hp)
		stats.emit_signal("xp_changed", stats.experience, stats.experience_to_next_level)

	# Inventory — clear and rebuild from saved item IDs.
	# Equipment slots are restored by reference only; modifiers are NOT re-applied
	# because the saved stats already reflect them.
	var inventory: Inventory = player.get("inventory")
	if inventory and data.has("inventory"):
		var inv_data: Dictionary = data["inventory"]

		inventory.items.clear()
		for slot in inventory.equipment:
			inventory.equipment[slot] = null

		var item_ids: Array = inv_data.get("items", [])
		for raw_id in item_ids:
			var item := _load_item(str(raw_id))
			if item:
				inventory.items.append(item)

		# Restore equipment slot references without re-applying modifiers
		var eq_data: Dictionary = inv_data.get("equipment", {})
		for slot in eq_data:
			var item_id: String = str(eq_data[slot])
			if item_id.is_empty():
				continue
			for item in inventory.items:
				if item.id == item_id:
					inventory.equipment[slot] = item
					break


func _deserialize_quests(data: Dictionary) -> void:
	QuestManager._active_quests.clear()
	QuestManager._completed_quests.clear()

	var completed: Array = data.get("completed", [])
	for quest_id in completed:
		QuestManager._completed_quests.append(str(quest_id))

	var active: Dictionary = data.get("active", {})
	for quest_id in active:
		var stage: String = str(active[quest_id])
		var quest_data: Dictionary = QuestManager._load_quest_data(str(quest_id))
		QuestManager._active_quests[str(quest_id)] = {"data": quest_data, "stage": stage}


func _load_item(item_id: String) -> Item:
	var path := "res://data/items/%s.tres" % item_id
	if not ResourceLoader.exists(path):
		push_warning("SaveManager: item resource not found: %s" % path)
		return null
	return load(path) as Item
