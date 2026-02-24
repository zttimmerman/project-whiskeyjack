class_name Inventory
extends Resource

signal item_added(item: Item)
signal item_removed(item: Item)
signal equipment_changed(slot: String, item)  # item is Item or null

@export var capacity: int = 20

var items: Array[Item] = []

# Equipment slots: "weapon", "helmet", "chest", "boots"
var equipment: Dictionary = {
	"weapon": null,
	"helmet": null,
	"chest": null,
	"boots": null,
}


func add_item(item: Item) -> bool:
	if is_full():
		return false
	items.append(item)
	emit_signal("item_added", item)
	return true


func remove_item(item: Item) -> bool:
	var idx := items.find(item)
	if idx == -1:
		return false
	items.remove_at(idx)
	emit_signal("item_removed", item)
	return true


# Equip an item, applying its stats_modifier to stats.
# Automatically unequips anything already in the target slot.
func equip_item(item: Item, stats: CharacterStats) -> void:
	var slot := _slot_for_type(item.type)
	if slot.is_empty():
		return
	if equipment[slot] != null:
		unequip_item(slot, stats)
	equipment[slot] = item
	_apply_modifier(item.stats_modifier, stats, 1)
	emit_signal("equipment_changed", slot, item)


# Unequip the item in slot, reversing its stats_modifier.
func unequip_item(slot: String, stats: CharacterStats) -> void:
	var item: Item = equipment.get(slot, null)
	if item == null:
		return
	_apply_modifier(item.stats_modifier, stats, -1)
	equipment[slot] = null
	emit_signal("equipment_changed", slot, null)


func has_item(item_id: String) -> bool:
	for item in items:
		if item.id == item_id:
			return true
	return false


func is_full() -> bool:
	return items.size() >= capacity


# Returns the slot name for a given item type, or "" if not equippable.
func _slot_for_type(t: Item.Type) -> String:
	match t:
		Item.Type.WEAPON:
			return "weapon"
		Item.Type.ARMOR:
			return "chest"
	return ""


func _apply_modifier(mod: Dictionary, stats: CharacterStats, sign: int) -> void:
	if mod.has("attack"):
		stats.attack += int(mod["attack"]) * sign
	if mod.has("defense"):
		stats.defense += int(mod["defense"]) * sign
	if mod.has("speed"):
		stats.speed += float(mod["speed"]) * float(sign)
	if mod.has("max_hp"):
		var delta: int = int(mod["max_hp"]) * sign
		stats.max_hp += delta
		if sign > 0:
			stats.current_hp = mini(stats.current_hp + delta, stats.max_hp)
		stats.emit_signal("health_changed", stats.current_hp, stats.max_hp)
