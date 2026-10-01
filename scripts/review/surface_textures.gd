extends Node

# Review tool for the Material Maker trial (docs/trials/material-maker.md): the generated level-surface
# textures (assets/textures/surfaces/, made by scripts/tools/make_textures.py) on test walls and floors
# under Level 1's lighting, next to a bay of the shipped KayKit kit for comparison. Not part of the game.
# Windowed run (headless can't render), as a scene so the project's autoloads load:
#   godot --path . res://scripts/review/surface_textures.tscn -- --out <dir>
# Writes <out>/surface_<bay>.png per bay, <out>/surface_overview.png, and <out>/surface_sheet.png (each
# texture at 1x, then tiled 2x2 at 2x with nearest filtering, to show seams).
#
# Lighting copies scenes/world/Level1.tscn: the same DirectionalLight3D, a WorldEnvironment with Wet Slate
# ambient at 0.5, and torch OmniLight3Ds (colour, energy and default range as Level 1's) with the torch prop.

const SURFACES := "res://assets/textures/surfaces/%s.png"
const TILE_M := 2.0  # one texture repeat per 2 m: 64 texels per metre at 128 px
const BAY_W := 4.0
const WALL_H := 4.0  # the kit wall's height
const SETTLE_FRAMES := 20
# bay -> [wall texture, floor texture]; "kit" is the shipped KayKit wall and floor
const BAYS := {
	"stone_on_earth": ["stone_dressed", "packed_earth"],
	"plaster_on_planks": ["plaster", "wood_planks"],
	"planks_on_stone": ["wood_planks", "stone_dressed"],
	"kit": ["", ""],
}
const SHEET := ["stone_dressed", "plaster", "packed_earth", "wood_planks"]


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var args := {}
	var argv := OS.get_cmdline_user_args()
	for i in range(0, argv.size() - 1, 2):
		args[argv[i].trim_prefix("--")] = argv[i + 1]
	var out: String = args.get("out", "")
	if out == "":
		printerr("surface_textures: usage: -- --out <dir>")
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280, 720)
	_save_sheet(out.path_join("surface_sheet.png"))
	_build_lighting()
	var x := 0.0
	var centres := {}
	for bay: String in BAYS:
		_build_bay(bay, x)
		centres[bay] = x
		x += BAY_W + 2.0
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	for bay: String in centres:
		var bx: float = centres[bay]
		# Roughly the gameplay camera: 1.7 m up, 4 m back from the wall's middle
		cam.look_at_from_position(Vector3(bx + 0.8, 1.9, 2.4), Vector3(bx - 0.3, 0.9, -1.5), Vector3.UP)
		await _snap(out.path_join("surface_%s.png" % bay))
	cam.look_at_from_position(Vector3(x * 0.5 - 2.0, 4.5, 9.0), Vector3(x * 0.5 - 4.0, 0.5, -1.0), Vector3.UP)
	await _snap(out.path_join("surface_overview.png"))
	get_tree().quit()


func _snap(path: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SAVED ", path)


func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.transform = Transform3D(
		Basis(Vector3(0.866, 0, -0.5), Vector3(-0.25, 0.866, -0.433), Vector3(0.433, 0.5, 0.75)), Vector3(0, 10, 0)
	)
	add_child(sun)
	var env := Environment.new()
	# Level 1 is enclosed, so nothing shows behind the walls; a near-black background stands in for that
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4509804, 0.41960785, 0.4, 1)
	env.ambient_light_energy = 0.5
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)


func _build_bay(bay: String, x: float) -> void:
	var spec: Array = BAYS[bay]
	if bay == "kit":
		var floor_piece: Node3D = load("res://scenes/world/kit/KitFloorLarge.tscn").instantiate()
		floor_piece.position = Vector3(x, 0, 0)
		add_child(floor_piece)
		var wall_piece: Node3D = load("res://scenes/world/kit/KitWall.tscn").instantiate()
		wall_piece.position = Vector3(x, 0, -2.25)  # 0.5 m thick, so its face is at z = -2
		add_child(wall_piece)
	else:
		_add_plane(_material(spec[1]), Vector2(BAY_W, BAY_W), Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)))
		# A vertical quad facing +Z, its bottom on the floor at the bay's back edge
		var wall_basis := Basis(Vector3.RIGHT, PI / 2.0)
		_add_plane(_material(spec[0]), Vector2(BAY_W, WALL_H), Transform3D(wall_basis, Vector3(x, WALL_H / 2.0, -2.0)))
	var torch: Node3D = load("res://assets/meshes/prop_torch.glb").instantiate()
	torch.transform = Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(x - 1.2, 2.2, -1.95))
	add_child(torch)
	var light := OmniLight3D.new()
	light.position = Vector3(x - 1.2, 2.5, -1.5)
	light.light_color = Color(1, 0.85, 0.6, 1)
	light.light_energy = 0.5
	add_child(light)


func _add_plane(mat: StandardMaterial3D, size: Vector2, xform: Transform3D) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.material = mat
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.transform = xform
	add_child(inst)
	mat.uv1_scale = Vector3(size.x / TILE_M, size.y / TILE_M, 1)


# The art bible's material: albedo texture only, roughness 1, metallic 0, specular 0
func _material(texture_name: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(SURFACES % texture_name)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.metallic_specular = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return mat


func _save_sheet(path: String) -> void:
	var cell := 128 + 16 + 512
	var sheet := Image.create_empty(16 + cell + 16, SHEET.size() * (512 + 16) + 16, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	var y := 16
	for texture_name: String in SHEET:
		var img := Image.load_from_file(ProjectSettings.globalize_path(SURFACES % texture_name))
		img.convert(Image.FORMAT_RGB8)
		var s := img.get_width()
		sheet.blit_rect(img, Rect2i(0, 0, s, s), Vector2i(16, y))
		var big := img.duplicate() as Image
		big.resize(s * 2, s * 2, Image.INTERPOLATE_NEAREST)
		for tx in 2:
			for ty in 2:
				sheet.blit_rect(big, Rect2i(0, 0, s * 2, s * 2), Vector2i(16 + s + 16 + tx * s * 2, y + ty * s * 2))
		y += 512 + 16
	sheet.save_png(path)
	print("SAVED ", path)
