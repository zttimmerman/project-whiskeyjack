extends GdUnitTestSuite
# gdUnit4 signal asserts are coroutines behind an abstract interface, so the analyzer flags their
# required await as redundant
@warning_ignore_start("redundant_await")

# Characterization tests for Inventory: add and remove, capacity, and equipment modifiers applied
# exactly once (equipping, swapping, re-equipping and unequipping).

const SWORD := "res://data/items/sword_iron.tres"  # weapon, attack +5
const SHIELD := "res://data/items/shield_wooden.tres"  # armor (chest), defense +4
const POTION := "res://data/items/potion_health.tres"  # consumable, heal 30

var inventory: Inventory
var stats: CharacterStats


func before_test() -> void:
	inventory = Inventory.new()
	inventory.capacity = 3
	stats = CharacterStats.new()
	stats.max_hp = 100
	stats.current_hp = 100
	stats.attack = 10
	stats.defense = 5
	stats.speed = 5.0


func _item(id: String, type: Item.Type, modifier: Dictionary) -> Item:
	var item := Item.new()
	item.id = id
	item.type = type
	item.stats_modifier = modifier
	return item


func test_add_and_remove_emit_signals() -> void:
	var sword: Item = load(SWORD)
	var monitor := monitor_signals(inventory)
	assert_bool(inventory.add_item(sword)).is_true()
	assert_bool(inventory.has_item("sword_iron")).is_true()
	await assert_signal(monitor).is_emitted("item_added", sword)
	assert_bool(inventory.remove_item(sword)).is_true()
	assert_bool(inventory.has_item("sword_iron")).is_false()
	await assert_signal(monitor).is_emitted("item_removed", sword)


func test_remove_missing_item_returns_false() -> void:
	assert_bool(inventory.remove_item(load(SWORD))).is_false()


func test_add_refused_when_full() -> void:
	for i in inventory.capacity:
		assert_bool(inventory.add_item(load(POTION))).is_true()
	assert_bool(inventory.is_full()).is_true()
	assert_bool(inventory.add_item(load(SWORD))).is_false()
	assert_int(inventory.items.size()).is_equal(3)


func test_equip_applies_modifier_once() -> void:
	var sword: Item = load(SWORD)
	var monitor := monitor_signals(inventory)
	inventory.equip_item(sword, stats)
	assert_int(stats.attack).is_equal(15)
	assert_object(inventory.equipment["weapon"]).is_same(sword)
	await assert_signal(monitor).is_emitted("equipment_changed", "weapon", sword)
	# Equipping the same item again swaps it out and back in: still +5, not +10
	inventory.equip_item(sword, stats)
	assert_int(stats.attack).is_equal(15)


func test_equip_replaces_the_item_in_the_slot() -> void:
	inventory.equip_item(load(SWORD), stats)
	var axe := _item("axe_test", Item.Type.WEAPON, {"attack": 8})
	inventory.equip_item(axe, stats)
	assert_int(stats.attack).is_equal(18)
	assert_object(inventory.equipment["weapon"]).is_same(axe)


func test_armor_goes_to_the_chest_slot() -> void:
	inventory.equip_item(load(SHIELD), stats)
	assert_int(stats.defense).is_equal(9)
	assert_object(inventory.equipment["chest"]).is_not_null()


func test_unequip_reverses_every_modifier() -> void:
	var gear := _item("gear_test", Item.Type.ARMOR, {"attack": 1, "defense": 2, "speed": 0.5, "max_hp": 20})
	inventory.equip_item(gear, stats)
	assert_int(stats.attack).is_equal(11)
	assert_int(stats.defense).is_equal(7)
	assert_float(stats.speed).is_equal_approx(5.5, 0.0001)
	assert_int(stats.max_hp).is_equal(120)
	assert_int(stats.current_hp).is_equal(120)
	var monitor := monitor_signals(inventory)
	inventory.unequip_item("chest", stats)
	assert_int(stats.attack).is_equal(10)
	assert_int(stats.defense).is_equal(5)
	assert_float(stats.speed).is_equal_approx(5.0, 0.0001)
	assert_int(stats.max_hp).is_equal(100)
	# Current HP isn't reduced by unequipping (kept as is, above the new max)
	assert_int(stats.current_hp).is_equal(120)
	assert_object(inventory.equipment["chest"]).is_null()
	await assert_signal(monitor).is_emitted("equipment_changed", "chest", null)


func test_unequip_empty_slot_changes_nothing() -> void:
	inventory.unequip_item("weapon", stats)
	assert_int(stats.attack).is_equal(10)


func test_consumables_and_keys_are_not_equippable() -> void:
	inventory.equip_item(load(POTION), stats)
	inventory.equip_item(_item("key_test", Item.Type.KEY, {"attack": 99}), stats)
	assert_int(stats.attack).is_equal(10)
	for slot in inventory.equipment:
		assert_object(inventory.equipment[slot]).is_null()


func test_potion_use_heals_and_is_consumed() -> void:
	stats.current_hp = 50
	assert_bool((load(POTION) as Item).use(stats)).is_true()
	assert_int(stats.current_hp).is_equal(80)
	assert_bool((load(SWORD) as Item).use(stats)).is_false()
