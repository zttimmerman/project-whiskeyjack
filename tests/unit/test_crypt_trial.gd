extends GdUnitTestSuite

# Trial B2 (docs/trials/func-godot.md): the crypt room set built from scenes/world/trials/crypt_trial.map
# by func_godot (scripts/tools/build_brush_maps.gd), against the art bible and the design bible §5:
# - the triangle budget for brush-built interiors, read from docs/art-bible.md (its only source);
# - albedo-only materials (one texture, specular 0, no other maps) at the art bible's texture size;
# - lvl_interior_ceiling: every navmesh polygon has a ceiling over it, at corridor and hall heights;
# - doorways 2.2–3 m;
# - what you see is what you collide with: each brush entity's collision spans its visible bounds;
# - each brush mesh is reached by no more lights than the renderer applies to one mesh.
# The level is instanced without entering the tree; transforms are composed up to its root by hand.

const LEVEL := "res://scenes/world/trials/CryptTrial.tscn"
const BRUSHES := "NavigationRegion3D/Brushes"
const NAVMESH := "res://scenes/world/trials/CryptTrial_navmesh.tres"
const ART_BIBLE := "res://docs/art-bible.md"
# The art bible's brush budget line: "Brush-built interiors ... ≤ N triangles per brush entity ... albedo W×H"
const BUDGET_PATTERN := (
	"Brush-built interiors[^\\n]*?≤ ([0-9,]+) triangles per brush entity" + "[^\\n]*?albedo (\\d+)×(\\d+)"
)
# Design bible §5: corridors 3.5–4.5 m, halls 5–8 m, doorways 2.2–3 m.
const CORRIDOR_CEILING_M := [3.5, 4.5]
const HALL_CEILING_M := [5.0, 8.0]
const DOORWAY_M := [2.2, 3.0]
# Sample floor points (x, z) in the trial's corridor and hall, and the doorway's centre.
const CORRIDOR_POINTS := [Vector2(0, 11), Vector2(0, 7), Vector2(-1.5, 3)]
const HALL_POINTS := [Vector2(0, -1), Vector2(-5, -4), Vector2(5, -10)]
const DOORWAY := Vector3(0, 0, 0.5)
const BOUNDS_TOLERANCE_M := 0.15

var _level: Node3D
var _faces: PackedVector3Array  # every brush collision triangle, in level space


func before_test() -> void:
	_level = (load(LEVEL) as PackedScene).instantiate()
	_faces = PackedVector3Array()
	for body in _brush_bodies():
		for node in body.find_children("*", "CollisionShape3D", true, false):
			var shape := (node as CollisionShape3D).shape as ConcavePolygonShape3D
			if shape == null:
				continue
			var xform := _level_xform(node)
			for p in shape.get_faces():
				_faces.append(xform * p)


func after_test() -> void:
	if is_instance_valid(_level):
		_level.free()


# Art bible → Budgets: brush-built interiors, triangles per brush entity (one room or corridor mesh).
func test_brush_triangle_budget() -> void:
	var budget := _budget()
	assert_int(budget.triangles).override_failure_message("no brush budget in %s" % ART_BIBLE).is_greater(0)
	var bodies := _brush_bodies()
	assert_int(bodies.size()).is_greater(0)
	for body in bodies:
		var count := 0
		for mesh_node in body.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mesh_node as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				var idx: Variant = arrays[Mesh.ARRAY_INDEX]
				var nverts := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				count += floori(((idx as PackedInt32Array).size() if idx != null else nverts) / 3.0)
		(
			assert_int(count)
			. override_failure_message("%s: %d triangles > %d" % [body.name, count, budget.triangles])
			. is_less_equal(budget.triangles)
		)


# Art bible → Textures: albedo only (one texture, no other maps), specular 0, within the texture size.
func test_brush_materials_albedo_only() -> void:
	var budget := _budget()
	var seen := 0
	for body in _brush_bodies():
		for mesh_node in body.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mesh_node as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				seen += 1
				var what := "%s surface %d" % [body.name, s]
				var mat := mesh.surface_get_material(s) as StandardMaterial3D
				assert_object(mat).override_failure_message("%s isn't a StandardMaterial3D" % what).is_not_null()
				if mat == null:
					continue
				assert_object(mat.albedo_texture).override_failure_message("%s has no albedo" % what).is_not_null()
				if mat.albedo_texture:
					var size := mat.albedo_texture.get_size()
					(
						assert_bool(size.x <= budget.texture_px and size.y <= budget.texture_px)
						. override_failure_message("%s: albedo %s over %d px" % [what, size, budget.texture_px])
						. is_true()
					)
				assert_float(mat.metallic_specular).override_failure_message("%s: specular" % what).is_equal(0.0)
				for tex in [
					mat.normal_texture,
					mat.roughness_texture,
					mat.metallic_texture,
					mat.ao_texture,
					mat.emission_texture,
					mat.heightmap_texture
				]:
					assert_object(tex).override_failure_message("%s has a non-albedo map" % what).is_null()
	assert_int(seen).is_greater(0)


# lvl_interior_ceiling: geometry over every navmesh polygon, at the bible's corridor and hall heights.
func test_lvl_interior_ceiling() -> void:
	var navmesh := load(NAVMESH) as NavigationMesh
	assert_int(navmesh.get_polygon_count()).is_greater(0)
	var vertices := navmesh.vertices
	for i in navmesh.get_polygon_count():
		var centre := Vector3.ZERO
		var polygon := navmesh.get_polygon(i)
		for v in polygon:
			centre += vertices[v]
		centre /= polygon.size()
		(
			assert_float(_ray(centre + Vector3.UP * 0.1, Vector3.UP))
			. override_failure_message("navmesh polygon %d at %s has no ceiling" % [i, centre])
			. is_less(INF)
		)
	for p: Vector2 in CORRIDOR_POINTS:
		_assert_clear_height(p, CORRIDOR_CEILING_M, "corridor")
	for p: Vector2 in HALL_POINTS:
		_assert_clear_height(p, HALL_CEILING_M, "hall")


# Design bible §5: doorways 2.2–3 m wide, and at least as tall as the narrowest doorway is wide.
func test_doorway_clearance() -> void:
	var at := DOORWAY + Vector3.UP
	var width := _ray(at, Vector3.LEFT) + _ray(at, Vector3.RIGHT)
	assert_float(width).override_failure_message("doorway %.2f m wide" % width).is_between(DOORWAY_M[0], DOORWAY_M[1])
	var height := _ray(DOORWAY + Vector3.UP * 0.05, Vector3.UP) + 0.05
	assert_float(height).override_failure_message("doorway %.2f m tall" % height).is_greater_equal(DOORWAY_M[0])


# Each brush entity's collision spans the same box as its mesh (no walk-through walls, no invisible
# walls); a clip brush's collision sits inside the visible geometry, so it doesn't move the bounds.
func test_brush_collision_matches_visible() -> void:
	for body in _brush_bodies():
		var seen := AABB()
		for mesh_node in body.find_children("*", "MeshInstance3D", true, false):
			seen = _merge(seen, _level_xform(mesh_node) * (mesh_node as MeshInstance3D).get_aabb())
		var solid := AABB()
		for node in body.find_children("*", "CollisionShape3D", true, false):
			var shape := (node as CollisionShape3D).shape as ConcavePolygonShape3D
			assert_object(shape).override_failure_message("%s: not a concave shape" % body.name).is_not_null()
			if shape == null:
				continue
			var xform := _level_xform(node)
			for p in shape.get_faces():
				solid = _merge(solid, AABB(xform * p, Vector3.ZERO))
		assert_bool(seen.has_volume() and solid.has_volume()).override_failure_message("%s" % body.name).is_true()
		for axis in 3:
			var d := maxf(absf(seen.position[axis] - solid.position[axis]), absf(seen.end[axis] - solid.end[axis]))
			(
				assert_float(d)
				. override_failure_message("%s: collision %s vs visible %s on axis %d" % [body.name, solid, seen, axis])
				. is_less_equal(BOUNDS_TOLERANCE_M)
			)


# The Compatibility renderer lights one mesh with at most max_lights_per_object lights, and a brush
# entity is one mesh: rooms must be split so each mesh stays under the cap (lights beyond it drop out).
func test_brush_lights_per_mesh() -> void:
	var cap: int = ProjectSettings.get_setting("rendering/limits/opengl/max_lights_per_object", 8)
	var lights: Array[OmniLight3D] = []
	for light in _level.find_children("*", "OmniLight3D", true, false):
		lights.append(light)
	assert_int(lights.size()).is_greater(0)
	for body in _brush_bodies():
		for mesh_node in body.find_children("*", "MeshInstance3D", true, false):
			var box := _level_xform(mesh_node) * (mesh_node as MeshInstance3D).get_aabb()
			var reaching := 0
			for light in lights:
				var at := _level_xform(light).origin
				var nearest := Vector3(
					clampf(at.x, box.position.x, box.end.x),
					clampf(at.y, box.position.y, box.end.y),
					clampf(at.z, box.position.z, box.end.z)
				)
				if at.distance_to(nearest) < light.omni_range:
					reaching += 1
			(
				assert_int(reaching)
				. override_failure_message("%s is lit by %d lights; the cap is %d" % [body.name, reaching, cap])
				. is_less_equal(cap)
			)


func _assert_clear_height(p: Vector2, band: Array, what: String) -> void:
	var floor_at := Vector3(p.x, 0.05, p.y)
	var height := _ray(floor_at, Vector3.UP) + 0.05
	assert_float(height).override_failure_message("%s ceiling at %s is %.2f m" % [what, p, height]).is_between(
		band[0], band[1]
	)


# Distance along dir to the nearest brush collision triangle (INF when nothing is hit).
func _ray(from: Vector3, dir: Vector3) -> float:
	var best := INF
	for i in range(0, _faces.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, _faces[i], _faces[i + 1], _faces[i + 2])
		if hit != null:
			best = minf(best, from.distance_to(hit))
	return best


func _budget() -> Dictionary:
	var text := FileAccess.get_file_as_string(ART_BIBLE)
	var found := RegEx.create_from_string(BUDGET_PATTERN).search(text)
	if found == null:
		return {"triangles": 0, "texture_px": 0}
	return {
		"triangles": int(found.get_string(1).replace(",", "")),
		"texture_px": maxi(int(found.get_string(2)), int(found.get_string(3)))
	}


func _brush_bodies() -> Array[StaticBody3D]:
	var bodies: Array[StaticBody3D] = []
	var brushes := _level.get_node_or_null(BRUSHES)
	if brushes == null:
		return bodies
	for child in brushes.get_children():
		if child is StaticBody3D:
			bodies.append(child)
	return bodies


func _level_xform(node: Node) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var at := node
	while at != null and at != _level:
		if at is Node3D:
			xform = (at as Node3D).transform * xform
		at = at.get_parent()
	return xform


func _merge(a: AABB, b: AABB) -> AABB:
	return b if a.size == Vector3.ZERO and a.position == Vector3.ZERO else a.merge(b)
