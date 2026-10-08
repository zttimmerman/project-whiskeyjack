extends StaticBody3D

## A world pickup: an item lying in the level, taken with interact (design bible §4: a payoff in
## sight after a fight). Player.interact() raycasts forward and calls interact() on what it hits, so
## the collision reaches the player's chest height. Taking it adds the item to the player's
## inventory and records it with SaveManager (a loaded save removes it again); a full inventory
## leaves it where it is. Placed outside the level's NavigationRegion3D, so the navmesh never
## depends on it.

signal picked_up(item: Item)

@export var item: Item

var _taken: bool = false


func interact() -> void:
	if _taken or item == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var inventory: Inventory = player.get("inventory")
	if inventory == null or not inventory.add_item(item):
		return
	_taken = true
	EventLog.log_event("item_picked_up", {"actor": EventLog.label(player), "item": item.id})
	SaveManager.record_pickup_taken(self)
	picked_up.emit(item)
	remove_from_group("pickup")
	queue_free()
