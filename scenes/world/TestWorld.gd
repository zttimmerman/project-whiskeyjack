extends Node3D

# ── Debug Controls (no input map entries required) ────────────────────────────
# T — take_damage(30)
# H — heal(20)
# X — gain_experience(60)  (press twice to trigger a level-up from default XP)
# ------------------------------------------------------------------------------

var _stats: CharacterStats = null


func _ready() -> void:
	var player := get_node_or_null("Player")
	if not player:
		push_error("TestWorld: Player node not found")
		return

	_stats = player.get("stats") as CharacterStats
	if not _stats:
		push_error("TestWorld: Player has no stats resource assigned")
		return

	_stats.health_changed.connect(_on_health_changed)
	_stats.died.connect(_on_died)
	_stats.leveled_up.connect(_on_leveled_up)

	print("=== CharacterStats debug ready ===")
	_print_stats()


func _input(event: InputEvent) -> void:
	if not _stats:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	match event.keycode:
		KEY_T:
			print("--- [T] take_damage(30) ---")
			_stats.take_damage(30)
		KEY_H:
			print("--- [H] heal(20) ---")
			_stats.heal(20)
		KEY_X:
			print("--- [X] gain_experience(60) ---")
			_stats.gain_experience(60)


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_health_changed(current_hp: int, max_hp: int) -> void:
	print("  health_changed  →  %d / %d" % [current_hp, max_hp])


func _on_died() -> void:
	print("  *** died signal fired ***")


func _on_leveled_up(new_level: int) -> void:
	print("  *** leveled_up → level %d ***" % new_level)
	_print_stats()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _print_stats() -> void:
	print("  HP %d/%d  ATK %d  DEF %d  LVL %d  XP %d/%d" % [
		_stats.current_hp, _stats.max_hp,
		_stats.attack, _stats.defense,
		_stats.level,
		_stats.experience, _stats.experience_to_next_level
	])
