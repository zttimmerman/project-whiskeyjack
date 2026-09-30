extends SceneTree

# Bakes each level's navmesh at edit time (design bible §8) and saves it next to the level.
#   godot --headless --path . -s scripts/tools/bake_navmeshes.gd
#
# GENERATED FILES: scenes/world/*_navmesh.tres are written only by this tool. Never edit them by
# hand or in the editor's Bake button; change the level geometry or SETTINGS here and rerun. CI
# rebakes and fails when the committed files differ (a stale bake).
#
# For each level it takes the NavigationRegion3D subtree out of the instanced scene (so the level
# script never runs), bakes it synchronously from the collision faces of its pieces (CSG shapes with
# use_collision, and StaticBody3D pieces with box or cylinder shapes, such as the KayKit wrappers in
# scenes/world/kit/), and saves the NavigationMesh. Feeding collision faces rather than letting Godot
# parse render meshes avoids the "parse RenderingServer meshes at runtime" warning, which headless
# -s runs hit even at edit time. The first run also
# repoints the scene's region from its inline sub_resource to the saved file; later runs leave the
# .tscn alone. Two runs give identical files.
#
# The clearance check (scripts/tools/check_path_clearance.gd) reuses bake_region() with a wider agent.

const LEVELS := {
	"res://scenes/world/Level1.tscn": "res://scenes/world/Level1_navmesh.tres",
	"res://scenes/world/Level2.tscn": "res://scenes/world/Level2_navmesh.tres",
}
const REGION := "NavigationRegion3D"

# Cell size and height match the navigation map defaults (0.25 m). The agent sizes are whole cells:
# the levels used to ask for 1.8 m and 0.4 m, which Godot ceiled to 2.0 m and 0.5 m (with a warning
# each bake), so these are the values the runtime bake already used.
const SETTINGS := {
	"cell_size": 0.25,
	"cell_height": 0.25,
	"agent_height": 2.0,
	"agent_radius": 0.5,
	"agent_max_climb": 0.25,
	"region_min_size": 2.0,
	"geometry_parsed_geometry_type": NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS,
}


func _initialize() -> void:
	# Deferred so the autoloads exist when the level scenes' scripts compile.
	_run.call_deferred()


func _run() -> void:
	var failed := false
	for scene_path: String in LEVELS:
		var navmesh_path: String = LEVELS[scene_path]
		var navmesh := await bake_region(self, scene_path, SETTINGS)
		if navmesh == null or navmesh.get_polygon_count() == 0:
			push_error("bake_navmeshes: %s baked an empty navmesh" % scene_path)
			failed = true
			continue
		# Bake into the committed resource when there is one, so its uid (and every reference) holds.
		var target: NavigationMesh = navmesh
		if ResourceLoader.exists(navmesh_path):
			target = ResourceLoader.load(navmesh_path, "", ResourceLoader.CACHE_MODE_IGNORE)
			target.clear()
			for key: String in SETTINGS:
				target.set(key, SETTINGS[key])
			target.vertices = navmesh.vertices
			for i in navmesh.get_polygon_count():
				target.add_polygon(navmesh.get_polygon(i))
			target.take_over_path(navmesh_path)
		# Keep the file's uid across bakes (a headless run may not have it in the uid cache); a new
		# file gets a fresh one, so the scene can reference it by uid.
		var uid := _file_uid(navmesh_path)
		if uid == ResourceUID.INVALID_ID:
			uid = ResourceUID.create_id()
		if not ResourceUID.has_id(uid):
			ResourceUID.add_id(uid, navmesh_path)
		var err := ResourceSaver.save(target, navmesh_path)
		if err == OK:
			err = ResourceSaver.set_uid(navmesh_path, uid)
		if err != OK:
			push_error("bake_navmeshes: couldn't save %s (%s)" % [navmesh_path, error_string(err)])
			failed = true
			continue
		if not _point_region_at(scene_path, navmesh_path):
			failed = true
			continue
		print(
			(
				"baked %s -> %s: %d polygons, %d vertices"
				% [scene_path, navmesh_path, target.get_polygon_count(), target.vertices.size()]
			)
		)
	quit(1 if failed else 0)


# Bakes the level's NavigationRegion3D subtree with the given NavigationMesh settings and returns the
# new NavigationMesh (null on failure). The region is detached from the level, so no level script runs.
static func bake_region(tree: SceneTree, scene_path: String, settings: Dictionary) -> NavigationMesh:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("bake_navmeshes: can't load %s" % scene_path)
		return null
	var level := packed.instantiate()
	var region := level.get_node_or_null(REGION) as NavigationRegion3D
	if region == null:
		push_error("bake_navmeshes: %s has no %s" % [scene_path, REGION])
		level.free()
		return null
	level.remove_child(region)
	level.free()
	var navmesh := NavigationMesh.new()
	for key: String in settings:
		navmesh.set(key, settings[key])
	region.navigation_mesh = null
	region.enabled = false  # never registers on the default map while baking
	tree.root.add_child(region)
	# CSG shapes build their brushes on a deferred update after entering the tree.
	await tree.process_frame
	await tree.process_frame
	var source := NavigationMeshSourceGeometryData3D.new()
	var ok := _add_collision_faces(region, source, scene_path)
	tree.root.remove_child(region)
	region.free()
	if not ok:
		return null
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	return navmesh


# Godot's own parser reads a CSG shape or a mesh through its render mesh, which warns about reading
# RenderingServer meshes outside the editor. Collision faces are what the agent walks on, so each
# collidable CSG shape adds its collision faces, and each StaticBody3D adds the faces of its box and
# cylinder shapes. A mesh inside a StaticBody3D is that body's visual (its collision stands for it);
# anything else that could carry geometry fails the bake, so no floor or wall is silently left out.
static func _add_collision_faces(
	region: Node3D, source: NavigationMeshSourceGeometryData3D, scene_path: String
) -> bool:
	var ok := true
	var nodes: Array[Node] = region.find_children("*", "", true, false)
	nodes.sort_custom(func(a: Node, b: Node) -> bool: return str(region.get_path_to(a)) < str(region.get_path_to(b)))
	for node in nodes:
		if node is CSGShape3D:
			var csg := node as CSGShape3D
			if not csg.is_root_shape() or not csg.use_collision:
				continue  # a CSG child is part of its root's result; no collision means walk-through
			var shape := csg.bake_collision_shape()
			if shape == null or shape.get_faces().is_empty():
				push_error("bake_navmeshes: %s: %s has no collision faces" % [scene_path, region.get_path_to(csg)])
				ok = false
				continue
			source.add_faces(shape.get_faces(), csg.global_transform)
		elif node is CollisionShape3D and node.get_parent() is StaticBody3D:
			var col := node as CollisionShape3D
			if col.disabled:
				continue
			var faces := shape_faces(col.shape)
			if faces.is_empty():
				push_error(
					(
						"bake_navmeshes: %s: %s has a %s; teach shape_faces about it"
						% [scene_path, region.get_path_to(col), col.shape.get_class() if col.shape else "null shape"]
					)
				)
				ok = false
				continue
			source.add_faces(faces, col.global_transform)
		elif node is StaticBody3D or _in_static_body(node, region):
			continue  # the body's shapes carry it
		elif node is GeometryInstance3D or node is CollisionObject3D or node is CollisionShape3D:
			push_error(
				(
					"bake_navmeshes: %s: %s (%s) isn't a CSG shape or in a StaticBody3D; teach _add_collision_faces about it"
					% [scene_path, region.get_path_to(node), node.get_class()]
				)
			)
			ok = false
	return ok


static func _in_static_body(node: Node, region: Node) -> bool:
	var at := node.get_parent()
	while at != null and at != region:
		if at is StaticBody3D:
			return true
		at = at.get_parent()
	return false


# Triangles of a box or cylinder collision shape in its own space (empty for any other shape).
static func shape_faces(shape: Shape3D) -> PackedVector3Array:
	var faces := PackedVector3Array()
	if shape is BoxShape3D:
		var h: Vector3 = (shape as BoxShape3D).size / 2.0
		var c := func(x: float, y: float, z: float) -> Vector3: return Vector3(x * h.x, y * h.y, z * h.z)
		# Each face as two triangles; winding doesn't matter to the navmesh voxelizer.
		for quad in [
			[c.call(-1, -1, -1), c.call(1, -1, -1), c.call(1, -1, 1), c.call(-1, -1, 1)],
			[c.call(-1, 1, -1), c.call(-1, 1, 1), c.call(1, 1, 1), c.call(1, 1, -1)],
			[c.call(-1, -1, -1), c.call(-1, 1, -1), c.call(1, 1, -1), c.call(1, -1, -1)],
			[c.call(-1, -1, 1), c.call(1, -1, 1), c.call(1, 1, 1), c.call(-1, 1, 1)],
			[c.call(-1, -1, -1), c.call(-1, -1, 1), c.call(-1, 1, 1), c.call(-1, 1, -1)],
			[c.call(1, -1, -1), c.call(1, 1, -1), c.call(1, 1, 1), c.call(1, -1, 1)],
		]:
			faces.append_array([quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]])
	elif shape is CylinderShape3D:
		var r: float = (shape as CylinderShape3D).radius
		var y: float = (shape as CylinderShape3D).height / 2.0
		var sides := 16
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var p0 := Vector3(cos(a0) * r, 0.0, sin(a0) * r)
			var p1 := Vector3(cos(a1) * r, 0.0, sin(a1) * r)
			var up := Vector3(0.0, y, 0.0)
			faces.append_array([p0 - up, p1 - up, p1 + up, p0 - up, p1 + up, p0 + up])
			faces.append_array([up, p1 + up, p0 + up, -up, p0 - up, p1 - up])
	return faces


static func _file_uid(path: String) -> int:
	if not FileAccess.file_exists(path):
		return ResourceUID.INVALID_ID
	var header := FileAccess.open(path, FileAccess.READ).get_line()
	var found := RegEx.create_from_string('uid="(uid://[a-z0-9]+)"').search(header)
	return ResourceUID.text_to_id(found.get_string(1)) if found else ResourceUID.INVALID_ID


# One-time migration: replace the region's inline NavigationMesh sub_resource with an ext_resource
# to the baked file. Returns true when the scene already points at it or now does.
func _point_region_at(scene_path: String, navmesh_path: String) -> bool:
	var file_path := ProjectSettings.globalize_path(scene_path)
	var text := FileAccess.get_file_as_string(file_path)
	if text.contains('path="%s"' % navmesh_path):
		return true
	var uid := ResourceUID.id_to_text(_file_uid(navmesh_path))
	var sub := RegEx.create_from_string(
		'\\[sub_resource type="NavigationMesh" id="([^"]+)"\\]\\n(?:[^\\[\\n][^\\n]*\\n)*\\n'
	)
	var found := sub.search(text)
	if found == null:
		push_error("bake_navmeshes: %s has no inline NavigationMesh to repoint" % scene_path)
		return false
	var sub_id := found.get_string(1)
	var ext_id := "navmesh_baked"
	var ext_line := '[ext_resource type="NavigationMesh" uid="%s" path="%s" id="%s"]\n' % [uid, navmesh_path, ext_id]
	text = text.replace(found.get_string(0), "")
	var last_ext := text.rfind("\n[ext_resource ")
	if last_ext < 0:
		push_error("bake_navmeshes: %s has no ext_resource block" % scene_path)
		return false
	var insert_at := text.find("\n", last_ext + 1) + 1
	text = text.insert(insert_at, ext_line)
	var old_ref := 'navigation_mesh = SubResource("%s")' % sub_id
	if not text.contains(old_ref):
		push_error("bake_navmeshes: %s doesn't assign %s to a region" % [scene_path, sub_id])
		return false
	text = text.replace(old_ref, 'navigation_mesh = ExtResource("%s")' % ext_id)
	var out := FileAccess.open(file_path, FileAccess.WRITE)
	out.store_string(text)
	out.close()
	print("repointed %s at %s" % [scene_path, navmesh_path])
	return true
