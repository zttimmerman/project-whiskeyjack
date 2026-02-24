extends Control

const FLASH_DURATION: float = 0.25
const DEATH_FADE_DURATION: float = 0.6
const DEATH_SHOW_DURATION: float = 2.0

@onready var hp_bar: ProgressBar = $HPPanel/MarginContainer/VBoxContainer/HPBar
@onready var hp_label: Label = $HPPanel/MarginContainer/VBoxContainer/HPLabel
@onready var xp_bar: ProgressBar = $HPPanel/MarginContainer/VBoxContainer/XPBar
@onready var level_label: Label = $HPPanel/MarginContainer/VBoxContainer/LevelLabel
@onready var death_overlay: ColorRect = $DeathOverlay
@onready var you_died_label: Label = $DeathOverlay/YouDiedLabel
@onready var hp_panel: Panel = $HPPanel
@onready var _margin: MarginContainer = $HPPanel/MarginContainer
@onready var _sfx_death: AudioStreamPlayer = $SFXDeath

var _stats: CharacterStats = null
var _flash_tween: Tween = null
var _prev_hp: int = -1


func _ready() -> void:
	_apply_style()
	# Wait one frame so the full scene tree (including Player) finishes _ready()
	await get_tree().process_frame
	_connect_player()
	death_overlay.modulate.a = 0.0
	death_overlay.visible = false
	you_died_label.modulate.a = 0.0


func _apply_style() -> void:
	# Chunky bordered panel — dark navy bg, soft blue border
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.12, 0.88)
	panel_style.border_color = Color(0.55, 0.55, 0.8, 1.0)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(0)  # Sharp corners for the chunky PS1 look
	hp_panel.add_theme_stylebox_override("panel", panel_style)

	# Inner padding via MarginContainer constants
	_margin.add_theme_constant_override("margin_left", 8)
	_margin.add_theme_constant_override("margin_right", 8)
	_margin.add_theme_constant_override("margin_top", 6)
	_margin.add_theme_constant_override("margin_bottom", 6)

	# HP bar: red fill on dark crimson bg
	_apply_bar_style(hp_bar, Color(0.78, 0.12, 0.08), Color(0.15, 0.04, 0.04))

	# XP bar: gold fill on dark olive bg
	_apply_bar_style(xp_bar, Color(0.90, 0.75, 0.10), Color(0.10, 0.08, 0.02))

	# Labels
	hp_label.add_theme_font_size_override("font_size", 12)
	hp_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	level_label.add_theme_font_size_override("font_size", 12)
	level_label.add_theme_color_override("font_color", Color(0.9, 0.78, 0.2))

	# "YOU DIED" — large and red
	you_died_label.add_theme_font_size_override("font_size", 72)
	you_died_label.add_theme_color_override("font_color", Color(0.85, 0.08, 0.08))


func _apply_bar_style(bar: ProgressBar, fill_color: Color, bg_color: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	var bg := StyleBoxFlat.new()
	bg.bg_color = bg_color
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)


func _connect_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		push_warning("HUD: no node in group 'player' found")
		return

	_stats = player.get("stats") as CharacterStats
	if _stats:
		_stats.health_changed.connect(_on_health_changed)
		_stats.leveled_up.connect(_on_leveled_up)
		_stats.xp_changed.connect(_on_xp_changed)
		_prev_hp = _stats.current_hp
		_update_hp(_stats.current_hp, _stats.max_hp)
		_update_xp()

	if player.has_signal("died"):
		player.died.connect(_on_player_died)


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_health_changed(current_hp: int, max_hp: int) -> void:
	var is_damage := (_prev_hp >= 0) and (current_hp < _prev_hp)
	_prev_hp = current_hp
	_update_hp(current_hp, max_hp)
	if is_damage:
		_flash_damage()


func _on_xp_changed(_current_xp: int, _xp_to_next: int) -> void:
	_update_xp()


func _on_leveled_up(_new_level: int) -> void:
	_update_xp()


func _on_player_died() -> void:
	if _sfx_death.stream:
		_sfx_death.play()
	death_overlay.visible = true
	var tween := create_tween()
	tween.set_parallel(false)
	tween.tween_property(death_overlay, "modulate:a", 1.0, DEATH_FADE_DURATION)
	tween.tween_property(you_died_label, "modulate:a", 1.0, 0.35)
	tween.tween_interval(DEATH_SHOW_DURATION)
	# Reload is handled by GameManager.on_player_died() which waits for this tween.


# ── Display helpers ───────────────────────────────────────────────────────────

func _update_hp(current_hp: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = current_hp
	hp_label.text = "HP  %d / %d" % [current_hp, max_hp]


func _update_xp() -> void:
	if not _stats:
		return
	xp_bar.max_value = _stats.experience_to_next_level
	xp_bar.value = _stats.experience
	level_label.text = "LV %d" % _stats.level


func _flash_damage() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	# Briefly bright-red, then restore normal HP bar color
	_apply_bar_style(hp_bar, Color(1.0, 0.25, 0.2), Color(0.15, 0.04, 0.04))
	_flash_tween.tween_interval(FLASH_DURATION)
	_flash_tween.tween_callback(func() -> void:
		_apply_bar_style(hp_bar, Color(0.78, 0.12, 0.08), Color(0.15, 0.04, 0.04))
	)
