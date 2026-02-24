extends Control

@onready var item_list: ItemList = $MainPanel/Margin/VBox/HBox/ItemList
@onready var name_label: Label = $MainPanel/Margin/VBox/HBox/InfoPanel/NameLabel
@onready var desc_label: Label = $MainPanel/Margin/VBox/HBox/InfoPanel/DescLabel
@onready var action_hint: Label = $MainPanel/Margin/VBox/HBox/InfoPanel/ActionHint
@onready var main_panel: Panel = $MainPanel

var _inventory: Inventory = null
var _stats: CharacterStats = null


func _ready() -> void:
	visible = false
	_apply_style()
	item_list.item_selected.connect(_on_item_selected)
	# Wait one frame so Player has finished _ready() and populated starting items
	await get_tree().process_frame
	_connect_player()


func _apply_style() -> void:
	# Chunky bordered panel matching the HUD aesthetic
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.12, 0.95)
	panel_style.border_color = Color(0.55, 0.55, 0.8, 1.0)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(0)
	main_panel.add_theme_stylebox_override("panel", panel_style)

	# Title label
	var title_label := $MainPanel/Margin/VBox/TitleLabel as Label
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", Color(0.9, 0.78, 0.2))

	# Item list: dark background with colored selection
	var list_bg := StyleBoxFlat.new()
	list_bg.bg_color = Color(0.03, 0.03, 0.08, 1.0)
	list_bg.border_color = Color(0.4, 0.4, 0.65, 1.0)
	list_bg.set_border_width_all(2)
	item_list.add_theme_stylebox_override("panel", list_bg)
	item_list.add_theme_font_size_override("font_size", 14)
	item_list.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))

	# Info panel labels
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.72, 0.72, 0.78))
	action_hint.add_theme_font_size_override("font_size", 12)
	action_hint.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5))


func _connect_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		push_warning("InventoryUI: no node in group 'player' found")
		return
	_inventory = player.get("inventory") as Inventory
	_stats = player.get("stats") as CharacterStats
	if player.has_signal("inventory_toggled"):
		player.inventory_toggled.connect(_on_toggle)


# ── Toggle ────────────────────────────────────────────────────────────────────

func _on_toggle() -> void:
	if visible:
		_close()
	else:
		_open()


func _open() -> void:
	_refresh_list()
	_clear_info()
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# Handle close keys while inventory is open (PROCESS_MODE_ALWAYS so this
# fires even while tree is paused).
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("open_inventory") or event.is_action_pressed("ui_cancel"):
		_close()


# ── Item list ─────────────────────────────────────────────────────────────────

func _refresh_list() -> void:
	item_list.clear()
	if not _inventory:
		return
	for item in _inventory.items:
		var label: String = item.name
		# Mark currently equipped items
		for slot_name in _inventory.equipment:
			if _inventory.equipment[slot_name] == item:
				label += "  [EQ]"
				break
		item_list.add_item(label)


func _clear_info() -> void:
	name_label.text = ""
	desc_label.text = ""
	action_hint.text = ""


func _on_item_selected(index: int) -> void:
	if not _inventory or not _stats or index >= _inventory.items.size():
		return
	var item: Item = _inventory.items[index]

	# Update info panel
	name_label.text = item.name
	desc_label.text = item.description

	match item.type:
		Item.Type.WEAPON, Item.Type.ARMOR:
			_handle_equip(item)
		Item.Type.CONSUMABLE:
			_handle_use(item)
		_:
			action_hint.text = "(Key item — cannot use)"


func _handle_equip(item: Item) -> void:
	# Toggle equip: unequip if already in a slot, otherwise equip
	var equipped_slot := ""
	for slot_name in _inventory.equipment:
		if _inventory.equipment[slot_name] == item:
			equipped_slot = slot_name
			break

	if not equipped_slot.is_empty():
		_inventory.unequip_item(equipped_slot, _stats)
		action_hint.text = "Unequipped."
	else:
		_inventory.equip_item(item, _stats)
		action_hint.text = "Equipped!"

	_refresh_list()


func _handle_use(item: Item) -> void:
	if item.use(_stats):
		_inventory.remove_item(item)
		action_hint.text = "Used."
	else:
		action_hint.text = "(Cannot use)"
	_refresh_list()
