extends Node3D

# ── Debug Controls (no input map entries required) ────────────────────────────
# T — take_damage(30)         [player]
# H — heal(20)                [player]
# X — gain_experience(60)     [player, press twice to level up from default XP]
# R — reset dummy HP to full  [dummy]
# ------------------------------------------------------------------------------

var _stats: CharacterStats = null
var _dummy_stats: CharacterStats = null


func _ready() -> void:
	var player := get_node_or_null("Player")
	if not player:
		push_error("TestWorld: Player node not found")
	else:
		_stats = player.get("stats") as CharacterStats
		if not _stats:
			push_error("TestWorld: Player has no stats resource assigned")
		else:
			_stats.health_changed.connect(_on_health_changed)
			_stats.died.connect(_on_died)
			_stats.leveled_up.connect(_on_leveled_up)
			print("=== Player stats debug ready ===")
			_print_stats()

	var dummy_hurtbox := get_node_or_null("DummyTarget/HurtboxComponent")
	if dummy_hurtbox:
		_dummy_stats = dummy_hurtbox.get("stats") as CharacterStats
		if _dummy_stats:
			_dummy_stats.health_changed.connect(_on_dummy_health_changed)
			_dummy_stats.died.connect(_on_dummy_died)
			print("=== Dummy target ready  HP %d/%d ===" % [_dummy_stats.current_hp, _dummy_stats.max_hp])


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	match event.keycode:
		KEY_T:
			if _stats:
				print("--- [T] take_damage(30) ---")
				_stats.take_damage(30)
		KEY_H:
			if _stats:
				print("--- [H] heal(20) ---")
				_stats.heal(20)
		KEY_X:
			if _stats:
				print("--- [X] gain_experience(60) ---")
				_stats.gain_experience(60)
		KEY_R:
			if _dummy_stats:
				print("--- [R] dummy reset ---")
				_dummy_stats.heal(_dummy_stats.max_hp)


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_health_changed(current_hp: int, max_hp: int) -> void:
	print("  health_changed  →  %d / %d" % [current_hp, max_hp])


func _on_died() -> void:
	print("  *** died signal fired ***")


func _on_dummy_health_changed(current_hp: int, max_hp: int) -> void:
	print("  dummy  health_changed  →  %d / %d" % [current_hp, max_hp])


func _on_dummy_died() -> void:
	print("  *** dummy died ***")


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
