extends GdUnitTestSuite

# A world pickup (scenes/items/ItemPickup.tscn): the payoff in sight after a fight (design bible §4,
# rhythm on a spoke). The player's interact() calls its interact(); it hands its item to the player's
# inventory, tells SaveManager it was taken, and leaves. A full inventory leaves it where it is.

const PICKUP_SCENE := "res://scenes/items/ItemPickup.tscn"
const POTION := "res://data/items/potion_health.tres"
const FakePlayer := preload("res://tests/doubles/fake_player.gd")

var player: CharacterBody3D
var pickup: Node3D


func before_test() -> void:
	player = auto_free(FakePlayer.new())
	player.stats = CharacterStats.new()
	player.inventory = Inventory.new()
	add_child(player)
	var packed: PackedScene = load(PICKUP_SCENE)
	assert_object(packed).override_failure_message("%s doesn't exist" % PICKUP_SCENE).is_not_null()
	if packed == null:
		return
	pickup = auto_free(packed.instantiate())
	pickup.item = load(POTION)
	add_child(pickup)


func test_pickup_gives_its_item_and_leaves() -> void:
	if pickup == null:
		return
	var item: Item = pickup.item
	# A plain connection: the pickup frees itself, so a signal monitor on it can't outlive it
	var emitted: Array[Item] = []
	pickup.picked_up.connect(func(taken: Item) -> void: emitted.append(taken))
	pickup.interact()
	# Taking it twice before it's gone never duplicates the item
	pickup.interact()
	assert_bool(pickup.is_queued_for_deletion()).is_true()
	assert_bool(player.inventory.has_item("potion_health")).is_true()
	assert_int(player.inventory.items.size()).is_equal(1)
	assert_array(emitted).contains_exactly([item])


func test_pickup_stays_when_the_inventory_is_full() -> void:
	if pickup == null:
		return
	var filler: Item = load("res://data/items/sword_iron.tres")
	while not player.inventory.is_full():
		player.inventory.add_item(filler)
	var held: int = player.inventory.items.size()
	pickup.interact()
	assert_int(player.inventory.items.size()).is_equal(held)
	assert_bool(pickup.is_queued_for_deletion()).is_false()


func test_pickup_is_in_the_pickup_group() -> void:
	if pickup == null:
		return
	# SaveManager finds taken pickups by this group when it loads a save
	assert_bool(pickup.is_in_group("pickup")).is_true()
