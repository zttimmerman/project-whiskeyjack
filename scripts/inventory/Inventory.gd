class_name Inventory
extends Resource

signal item_added(item: Item)
signal item_removed(item: Item)
signal equipment_changed(slot: String, item: Item)

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
	return false


func remove_item(item: Item) -> bool:
	return false


func equip_item(item: Item, stats: CharacterStats) -> void:
	pass


func unequip_item(slot: String, stats: CharacterStats) -> void:
	pass


func has_item(item_id: String) -> bool:
	return false


func is_full() -> bool:
	return items.size() >= capacity
