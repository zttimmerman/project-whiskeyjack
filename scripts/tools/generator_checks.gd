extends RefCounted

# Silent-failure checks for the scene generators (make_held_props.gd, build_brush_maps.gd), whose
# output is committed and checked for staleness, so a bad build must fail loudly, never save:
# - pack_checked(): PackedScene.pack() quietly leaves out any node whose owner isn't the scene root
#   (and everything under it). Count what should be saved, pack, instantiate the packed scene and
#   compare node by node.
# - keep_node_ids(): Godot 4.7 gives every saved node a random unique_id, so a rebuild differs from
#   the committed file. Each node keeps the id it had in the previous build (by node path); a new node
#   gets a hash of its path.
# - in_tree_error(): global_transform, look_at and friends are wrong on a node outside the tree
#   (Godot warns once, then answers with the local transform).
# The first and third follow htdt/godogen engines/godot.md, "Scenes are generated at build time"
# (MIT; ideas only, no code copied).

const NODE_HEADER := '\\[node name="([^"]+)"(?: type="[^"]+")?(?: parent="([^"]*)")? unique_id=(\\d+)'


# "path:Class" for the root (".") and every node it owns, in tree order: what pack() should keep.
# An instanced scene's own nodes belong to that instance and come back from its file, so they're out.
static func saved_nodes(root: Node) -> PackedStringArray:
	var out := PackedStringArray([".:%s" % root.get_class()])
	for node in root.find_children("*", "", true, false):
		if node.owner == root:
			out.append("%s:%s" % [root.get_path_to(node), node.get_class()])
	return out


# Packs root and proves the packed scene instantiates to the same nodes. Returns
# {"scene": PackedScene or null, "error": ""} ; the error names the generator and each lost node.
static func pack_checked(root: Node, generator: String) -> Dictionary:
	var expected := saved_nodes(root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		return {"scene": null, "error": "%s: couldn't pack %s (%s)" % [generator, root.name, error_string(err)]}
	var copy := packed.instantiate()
	if copy == null:
		return {"scene": null, "error": "%s: the packed %s doesn't instantiate" % [generator, root.name]}
	var got := saved_nodes(copy)
	copy.free()
	var problems := PackedStringArray()
	if got != expected:
		for n in expected:
			if not n in got:
				problems.append("lost " + n)
		for n in got:
			if not n in expected:
				problems.append("gained " + n)
	# Unowned nodes aren't in `expected` either; they're dropped all the same, so they fail too
	for node in root.find_children("*", "", true, false):
		if node.owner == null:
			problems.append("unowned %s (pack() drops it)" % root.get_path_to(node))
	if not problems.is_empty():
		return {
			"scene": null,
			"error":
			(
				"%s: %s packs %d nodes, %d expected: %s"
				% [generator, root.name, got.size(), expected.size(), ", ".join(problems)]
			)
		}
	return {"scene": packed, "error": ""}


# Rewrites the unique_id of each [node] in a freshly saved scene's text: the id the same node path had
# in `previous` (the file before this build, "" if none), else a hash of the path. Returns
# {"text": String, "error": ""}.
static func keep_node_ids(text: String, previous: String) -> Dictionary:
	var header := RegEx.create_from_string(NODE_HEADER)
	var before := {}
	for found in header.search_all(previous):
		before[_node_path(found)] = int(found.get_string(3))
	var out := ""
	var at := 0
	var seen := {}
	for found in header.search_all(text):
		var path := _node_path(found)
		var id: int = before.get(path, path.hash() & 0x7FFFFFFF)
		if seen.has(id):
			return {"text": "", "error": "node id clash (%s, %s)" % [seen[id], path]}
		seen[id] = path
		out += text.substr(at, found.get_start(3) - at) + str(id)
		at = found.get_end(3)
	return {"text": out + text.substr(at), "error": ""}


static func _node_path(found: RegExMatch) -> String:
	return found.get_string(2).path_join(found.get_string(1)) if found.get_start(2) >= 0 else "."


# Saves a checked scene and gives its nodes their kept ids. Returns an error message ("" on success).
static func save_scene(packed: PackedScene, scene_path: String, generator: String) -> String:
	var file_path := ProjectSettings.globalize_path(scene_path)
	var previous := FileAccess.get_file_as_string(file_path) if FileAccess.file_exists(file_path) else ""
	var err := ResourceSaver.save(packed, scene_path)
	if err != OK:
		return "%s: couldn't save %s (%s)" % [generator, scene_path, error_string(err)]
	return rewrite_node_ids(scene_path, previous, generator)


# The keep_node_ids() pass on a saved file. Returns an error message ("" on success).
static func rewrite_node_ids(scene_path: String, previous: String, generator: String) -> String:
	var file_path := ProjectSettings.globalize_path(scene_path)
	var kept := keep_node_ids(FileAccess.get_file_as_string(file_path), previous)
	if kept["error"] != "":
		return "%s: %s in %s" % [generator, kept["error"], scene_path]
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		return "%s: can't write %s (%s)" % [generator, scene_path, error_string(FileAccess.get_open_error())]
	f.store_string(kept["text"])
	f.close()
	return ""


# "" when node is in the scene tree (its global_* values mean something), else an error naming generator
static func in_tree_error(node: Node, generator: String) -> String:
	if node.is_inside_tree():
		return ""
	return "%s: %s isn't in the scene tree, so its global transforms would be its local ones" % [generator, node.name]
