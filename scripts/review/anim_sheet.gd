extends Node

# Review tool: a contact sheet of every clip in a character's AnimationLibrary, posed on the imported
# (retargeted) model. One row per clip, one column per point in the clip. Windowed run:
#   godot --path . res://scripts/review/anim_sheet.tscn -- --model <res:// glb> --library <res:// tres> --out <png>
#       [--held <Bone>=<res:// prop scene>[,<Bone>=<scene>]]   props on bones, as held_props would attach them
#       [--yaw <degrees>] [--columns <n>]   view angle (-25 three-quarter, 90 side) and points per clip

var fractions := [0.2, 0.5, 0.8]
const SPACING := Vector2(1.6, 2.1)  # metres between columns, rows


func _ready() -> void:
	# Vsync off: with another window in front (the human's editor), macOS throttles a covered
	# window's buffer swaps and a vsynced capture crawls (one clip took minutes, not seconds)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var args := {}
	var argv := OS.get_cmdline_user_args()
	for i in range(0, argv.size() - 1, 2):
		args[argv[i].trim_prefix("--")] = argv[i + 1]
	if args.has("columns"):
		var n := int(args["columns"])
		fractions = range(n).map(func(i): return (i + 0.5) / n)
	var yaw := float(args.get("yaw", -25))
	get_window().size = Vector2i(400 * fractions.size(), 1600)
	var lib: AnimationLibrary = load(args["library"])
	var names: Array = lib.get_animation_list()
	names.sort()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.42, 0.40)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	for r in names.size():
		for c in fractions.size():
			var model: Node3D = (load(args["model"]) as PackedScene).instantiate()
			add_child(model)
			# Models face +Z in Godot; turn them three-quarters toward the camera
			model.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), Vector3(c * SPACING.x, -r * SPACING.y, 0))
			if args.has("held"):
				var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
				for pair in String(args["held"]).split(","):
					var kv := pair.split("=")
					var att := BoneAttachment3D.new()
					att.bone_name = kv[0]
					sk.add_child(att)
					att.add_child((load(kv[1]) as PackedScene).instantiate())
			var ap := AnimationPlayer.new()
			model.add_child(ap)
			ap.root_node = NodePath("..")
			ap.add_animation_library("", lib)
			ap.play(names[r])
			ap.seek(lib.get_animation(names[r]).length * fractions[c], true)
			ap.pause()
		var label := Label3D.new()
		label.text = "%s (%.2f s)" % [names[r], lib.get_animation(names[r]).length]
		label.position = Vector3(-1.4, -r * SPACING.y + 0.9, 0)
		label.pixel_size = 0.004
		label.modulate = Color.BLACK
		add_child(label)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = names.size() * SPACING.y + 0.4
	cam.position = Vector3((fractions.size() - 1) * SPACING.x / 2 - 0.5, -(names.size() - 1) * SPACING.y / 2 + 0.9, 10)
	add_child(cam)
	cam.current = true
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args["out"])
	print("SAVED ", args["out"])
	get_tree().quit()
