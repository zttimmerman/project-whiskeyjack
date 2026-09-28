extends Node

# Renders the player and the Barrow-levy in Level 1 under the level's own torchlight and ambient,
# at gameplay camera framing (Player.tscn: pivot 1.5 m, SpringArm 4 m, pitch -0.2 rad).
# Review tool, not part of the game. Windowed run (headless can't render), as a scene so the
# project's autoloads load:
#   godot --path . res://scripts/review/level1_compare.tscn -- --player <glb> --levy <glb> --out <dir>
#       [--ambient-energy <float>] [--torch-energy <float>] [--tag <name>]
# The energy overrides try level-side lighting changes without editing Level1.tscn.

const SHOTS := {
	# Player's back to the camera at gameplay framing; the levy 5 m ahead, facing the player.
	"gameplay": {"player": [Vector3(9.0, 0.0, 0.0), 90.0], "levy": [Vector3(14.0, 0.0, 0.6), -90.0],
			"pivot": Vector3(9.0, 1.5, 0.0), "yaw": -90.0, "pitch": -0.2, "arm": 4.0},
	# Face-off: both side by side facing the camera, 5 m away, the torch beside them.
	"faceoff": {"player": [Vector3(12.0, 0.0, -0.7), -90.0], "levy": [Vector3(12.0, 0.0, 0.7), -90.0],
			"pivot": Vector3(12.0, 1.1, 0.0), "yaw": -90.0, "pitch": -0.12, "arm": 5.0},
}


func _ready() -> void:
	var args := {}
	var argv := OS.get_cmdline_user_args()
	for i in range(0, argv.size() - 1, 2):
		args[argv[i].trim_prefix("--")] = argv[i + 1]
	GLTFDocument.register_gltf_document_extension(preload("res://addons/stylized_materials/no_specular_gltf.gd").new())
	get_window().size = Vector2i(1280, 720)
	var level: Node3D = load("res://scenes/world/Level1.tscn").instantiate()
	level.set_script(null)  # its _ready wires gameplay (player, quests, music) that isn't here
	for child in level.get_children():
		# Keep the level's geometry, props and lights; drop characters, UI and gameplay nodes
		if child is CharacterBody3D or child is CanvasLayer or child is Control or child is Camera3D:
			level.remove_child(child)
			child.free()
	_override_lighting(level, args)
	add_child(level)
	var player := _load_glb(args["player"])
	var levy := _load_glb(args["levy"])
	level.add_child(player)
	level.add_child(levy)
	var cam := Camera3D.new()
	level.add_child(cam)
	cam.current = true
	for shot in SHOTS:
		var s: Dictionary = SHOTS[shot]
		_place(player, s["player"])
		_place(levy, s["levy"])
		# Same construction as the player's camera rig: yaw at the pivot, pitch on the arm, camera at +Z
		var rig := Transform3D(Basis(Vector3.UP, deg_to_rad(s["yaw"])) * Basis(Vector3.RIGHT, s["pitch"]), s["pivot"])
		cam.global_transform = rig * Transform3D(Basis(), Vector3(0, 0, s["arm"]))
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var tag: String = ("_" + args["tag"]) if args.has("tag") else ""
		var path: String = args["out"].path_join("level1_%s%s.png" % [shot, tag])
		img.save_png(path)
		print("SAVED ", path)
	get_tree().quit()


func _override_lighting(level: Node, args: Dictionary) -> void:
	for node in level.find_children("*", "WorldEnvironment", true, false):
		if args.has("ambient-energy"):
			(node as WorldEnvironment).environment.ambient_light_energy = float(args["ambient-energy"])
	for node in level.find_children("*", "OmniLight3D", true, false):
		if args.has("torch-energy"):
			(node as OmniLight3D).light_energy = float(args["torch-energy"])


func _load_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	assert(err == OK, "couldn't load %s" % path)
	return doc.generate_scene(state)


func _place(node: Node3D, spec: Array) -> void:
	# Cleaned models face -Y in Blender, +Z in Godot; yaw turns +Z toward the wanted direction
	node.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(spec[1])), spec[0])
