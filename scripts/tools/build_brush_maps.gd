extends SceneTree

# Builds each brush-level .map (Quake format, written by hand or in TrenchBroom) into a scene with
# func_godot (addons/func_godot, pinned; trial B2, docs/trials/func-godot.md), headless:
#   godot --headless --path . -s scripts/tools/build_brush_maps.gd
#
# GENERATED FILES: each MAPS value is written only by this tool. Never edit it by hand or with the
# editor's Build Map button; change the .map (or the map settings) and rerun. CI rebuilds and fails
# when a committed scene differs (a stale build). Two runs give identical files.
#
# The build runs func_godot's FuncGodotMap.build() outside the tree, so it needs no editor and no
# enabled plugin: the plugin only adds the editor's .map importer, which this path doesn't use (the
# parser reads the .map text directly). The built nodes are moved under a plain Node3D root, so the
# scene doesn't depend on func_godot at runtime; a point entity with a scene (light_torch) stays an
# instance of that scene.

const MAPS := {
	"res://scenes/world/trials/crypt_trial.map": "res://scenes/world/trials/CryptTrial_brushes.tscn",
}
const MAP_SETTINGS := "res://data/maps/crypt_map_settings.tres"
# Godot 4.7 gives every saved node a random unique_id; Checks.rewrite_node_ids keeps each node's id
# from the previous build (new nodes get a hash of their path), so two builds are identical.
const Checks := preload("res://scripts/tools/generator_checks.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failed := false
	for map_path: String in MAPS:
		var scene_path: String = MAPS[map_path]
		var built := build_map(map_path, scene_path.get_file().get_basename())
		if built == null:
			failed = true
			continue
		# Packed only when every node survives the round trip (scripts/tools/generator_checks.gd)
		var checked := Checks.pack_checked(built, "build_brush_maps")
		built.free()
		if checked["error"] != "":
			push_error(checked["error"])
			failed = true
			continue
		var packed: PackedScene = checked["scene"]
		var previous := FileAccess.get_file_as_string(scene_path) if FileAccess.file_exists(scene_path) else ""
		# Keep the scene's uid across builds, so the level that instances it keeps its reference.
		var uid := _file_uid(scene_path)
		if uid == ResourceUID.INVALID_ID:
			uid = ResourceUID.create_id()
		if not ResourceUID.has_id(uid):
			ResourceUID.add_id(uid, scene_path)
		var err := ResourceSaver.save(packed, scene_path)
		if err == OK:
			err = ResourceSaver.set_uid(scene_path, uid)
		if err != OK:
			push_error("build_brush_maps: couldn't save %s (%s)" % [scene_path, error_string(err)])
			failed = true
			continue
		var ids_err := Checks.rewrite_node_ids(scene_path, previous, "build_brush_maps")
		if ids_err != "":
			push_error(ids_err)
			failed = true
			continue
		print("built %s -> %s" % [map_path, scene_path])
	quit(1 if failed else 0)


# Builds one .map with the project's map settings and returns a Node3D named scene_name that owns
# every generated node (null on failure). The caller frees it.
static func build_map(map_path: String, scene_name: String) -> Node3D:
	var settings := load(MAP_SETTINGS) as FuncGodotMapSettings
	if settings == null:
		push_error("build_brush_maps: can't load %s" % MAP_SETTINGS)
		return null
	var map := FuncGodotMap.new()
	map.local_map_file = map_path
	map.map_settings = settings
	var completed := [false]
	map.build_complete.connect(func() -> void: completed[0] = true)
	map.build()
	if not completed[0] or map.get_child_count() == 0:
		push_error("build_brush_maps: %s didn't build" % map_path)
		map.free()
		return null
	var scene := Node3D.new()
	scene.name = scene_name
	for child in map.get_children():
		map.remove_child(child)
		child.owner = null
		scene.add_child(child)
		_own(child, scene)
	map.free()
	return scene


# Every generated node belongs to the new scene root; an instanced scene's own children stay its own.
static func _own(node: Node, scene: Node) -> void:
	node.owner = scene
	if not node.scene_file_path.is_empty():
		return
	for child in node.get_children():
		_own(child, scene)


static func _file_uid(path: String) -> int:
	if not FileAccess.file_exists(path):
		return ResourceUID.INVALID_ID
	var header := FileAccess.open(path, FileAccess.READ).get_line()
	var found := RegEx.create_from_string('uid="(uid://[a-z0-9]+)"').search(header)
	return ResourceUID.text_to_id(found.get_string(1)) if found else ResourceUID.INVALID_ID
