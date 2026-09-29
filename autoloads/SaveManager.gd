extends Node

const SAVE_PATH := "user://save.json"
## Bump when the save layout changes; saves with another version are ignored, not half-applied
const SAVE_FORMAT_VERSION := 2

# Enemies killed in the current scene instance, as paths relative to the scene root.
# Tied to the scene instance: a reload or scene change starts a fresh list.
var _killed_enemies: Array[String] = []
var _world_scene_id: int = 0


func save_game() -> void:
	var player := _get_player()
	if not player:
		push_warning("SaveManager: no player found, aborting save")
		return
	var scene := get_tree().current_scene
	if not scene:
		push_warning("SaveManager: no current scene, aborting save")
		return
	_sync_world_scene()

	var data := {
		"version": SAVE_FORMAT_VERSION,
		"scene": scene.scene_file_path,
		"player": _serialize_player(player),
		"quests": _serialize_quests(),
		"world": {"killed_enemies": _killed_enemies.duplicate()},
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: could not open save file for writing")
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func load_game() -> void:
	var data := _read_compatible_save(true)
	if data.is_empty():
		return

	if data.has("quests"):
		_deserialize_quests(data["quests"])

	_deserialize_world(data.get("world", {}))

	var player := _get_player()
	if player and data.has("player"):
		_deserialize_player(player, data["player"])


func save_exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## True when a save exists and would be applied to the current scene by load_game()
func is_save_compatible() -> bool:
	return not _read_compatible_save(false).is_empty()


## Called by BaseEnemy.die(). Only enemies placed in the scene file are persisted; ones spawned at
## runtime have no stable path, so they aren't recorded.
func record_enemy_killed(enemy: Node) -> void:
	var scene := get_tree().current_scene
	if not scene or enemy.owner != scene:
		return
	_sync_world_scene()
	var key := str(scene.get_path_to(enemy))
	if key not in _killed_enemies:
		_killed_enemies.append(key)


# ── Helpers ───────────────────────────────────────────────────────────────────

# Reads the save and returns it only if its format version and scene match the current scene;
# otherwise returns {} (with a warning when `warn`), so a stale or foreign save is never applied.
func _read_compatible_save(warn: bool) -> Dictionary:
	if not save_exists():
		if warn:
			push_warning("SaveManager: no save file found at %s" % SAVE_PATH)
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_error("SaveManager: could not open save file for reading")
		return {}
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("SaveManager: failed to parse save file")
		return {}
	var data = json.get_data()
	if not data is Dictionary:
		return {}

	var version := int(data.get("version", 1))
	if version != SAVE_FORMAT_VERSION:
		if warn:
			push_warning("SaveManager: ignoring %s: format version %d, expected %d" % [SAVE_PATH, version, SAVE_FORMAT_VERSION])
		return {}
	var scene := get_tree().current_scene
	var scene_path: String = scene.scene_file_path if scene else ""
	if str(data.get("scene", "")) != scene_path:
		if warn:
			push_warning("SaveManager: ignoring %s: saved in %s, current scene is %s" % [SAVE_PATH, data.get("scene", "?"), scene_path])
		return {}
	return data


# Starts a fresh kill list whenever the current scene instance changes (reload or new level)
func _sync_world_scene() -> void:
	var scene := get_tree().current_scene
	var id := scene.get_instance_id() if scene else 0
	if id != _world_scene_id:
		_world_scene_id = id
		_killed_enemies.clear()


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
	if player.has_method("get_view_state"):
		result["view"] = player.get_view_state()

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

# Removes the enemies the save lists as killed (quietly: no died signal, no XP) and makes the
# save's list the current kill list, so the next save still includes them.
func _deserialize_world(data: Dictionary) -> void:
	_sync_world_scene()
	_killed_enemies.clear()
	var scene := get_tree().current_scene
	for raw_key in data.get("killed_enemies", []):
		var key := str(raw_key)
		_killed_enemies.append(key)
		var enemy := scene.get_node_or_null(NodePath(key))
		if enemy and enemy.is_in_group("enemy"):
			# Leave the group now so lock-on and level kill counts skip it before the free lands
			enemy.remove_from_group("enemy")
			enemy.queue_free()


func _deserialize_player(player: Node, data: Dictionary) -> void:
	# Position
	if data.has("position"):
		var arr: Array = data["position"]
		if arr.size() == 3:
			player.global_position = Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO

	# Facing and camera heading, so the same input moves the same way relative to the view
	if data.has("view") and player.has_method("apply_view_state"):
		player.apply_view_state(data["view"])

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
