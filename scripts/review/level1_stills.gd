extends Node

# Review tool: rendered stills of each Level 1 room from fixed cameras, with the level running (so the
# player, the Keeper and the levies stand where they spawn, idling, for scale). Not part of the game.
# Windowed run (headless can't render), as a scene so the project's autoloads load:
#   godot --path . res://scripts/review/level1_stills.tscn -- --out <dir> [--scene <tscn>] [--tag <name>]
#       [--ambient-energy <float>] [--torch-energy <float>]
# --scene renders another copy of the level (e.g. main's, for a before/after); the energy overrides try
# level-side lighting without editing Level1.tscn. Writes <out>/level1_<shot>[_<tag>].png.

const SETTLE_FRAMES := 20

# shot -> [camera position, look-at point]
const SHOTS := {
	"start_spawn": [Vector3(-4.5, 2.4, 0.0), Vector3(6.0, 1.0, 0.0)],
	"start_scale": [Vector3(3.0, 1.7, 3.0), Vector3(-1.5, 1.0, -3.0)],
	"start_overview": [Vector3(-5.0, 3.4, 5.0), Vector3(3.0, 0.5, -3.0)],
	"corridor_a": [Vector3(6.5, 2.2, 0.0), Vector3(16.0, 1.2, 0.0)],
	"central_entry": [Vector3(12.5, 2.4, 0.0), Vector3(24.0, 1.0, 1.0)],
	"central_overview": [Vector3(17.5, 3.4, -7.0), Vector3(27.0, 0.5, 4.0)],
	"central_south": [Vector3(30.5, 3.2, -6.5), Vector3(22.0, 0.5, 7.0)],
	"corridor_b": [Vector3(24.0, 2.4, 5.0), Vector3(24.0, 1.2, 17.0)],
	"exit_entry": [Vector3(24.0, 2.6, 14.0), Vector3(24.0, 1.4, 29.0)],
	"exit_overview": [Vector3(29.0, 3.4, 19.0), Vector3(21.0, 0.5, 28.0)],
}


func _ready() -> void:
	# Vsync off: macOS throttles a covered window's buffer swaps (see level1_compare.gd)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var args := {}
	var argv := OS.get_cmdline_user_args()
	for i in range(0, argv.size() - 1, 2):
		args[argv[i].trim_prefix("--")] = argv[i + 1]
	get_window().size = Vector2i(1280, 720)
	var level: Node = load(args.get("scene", "res://scenes/world/Level1.tscn")).instantiate()
	add_child(level)
	var ui := level.get_node_or_null("CanvasLayer")
	if ui:
		ui.visible = false
	_override_lighting(level, args)
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var tag: String = ("_" + args["tag"]) if args.has("tag") else ""
	for shot: String in SHOTS:
		var spec: Array = SHOTS[shot]
		cam.look_at_from_position(spec[0], spec[1], Vector3.UP)
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path: String = args["out"].path_join("level1_%s%s.png" % [shot, tag])
		get_viewport().get_texture().get_image().save_png(path)
		print("SAVED ", path)
	get_tree().quit()


func _override_lighting(level: Node, args: Dictionary) -> void:
	for node in level.find_children("*", "WorldEnvironment", true, false):
		if args.has("ambient-energy"):
			(node as WorldEnvironment).environment.ambient_light_energy = float(args["ambient-energy"])
	for node in level.find_children("*", "OmniLight3D", true, false):
		if args.has("torch-energy") and node.owner == level:
			(node as OmniLight3D).light_energy = float(args["torch-energy"])
