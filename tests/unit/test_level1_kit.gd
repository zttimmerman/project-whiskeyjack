extends GdUnitTestSuite

# Level 1 dressed with the KayKit Dungeon Remastered kit (design bible §5, targets in §9):
# - what you see is what you collide with: every mesh on the level's navigation region belongs to a
#   static body whose collision spans the same bounds, and no blockout CSG is left;
# - the kit keeps one scale for the whole pack, set at import (assets/sources.json source_scale), so
#   placed pieces are never scaled;
# - lvl_dressing_density: 1–3 dressing props per 10 m² in each room;
# - lvl_light_spacing: no stretch of the critical path longer than 12 m without a visible light source
#   (the user accepted denser spacing than the band's 8 m, 2026-09-30), and every local light sits on a
#   visible source (art bible → Rendering);
# - the side room off Corridor A (backlog level1-spoke-spacing, design bible §4 rhythm on a spoke): its
#   payoff, a pickup, is in plain sight from the corridor, and the player's interact ray reaches it.
# The level is instanced without entering the tree, so no gameplay script runs; transforms are composed
# up to the level root by hand.

const LEVEL := "res://scenes/world/Level1.tscn"
const CRITICAL_PATH := "res://tests/critical_paths/level1.json"
const REGION := "NavigationRegion3D"
const KIT_PREFIX := "res://assets/meshes/kaykit_dungeon_"
const TORCH_SCENE := "res://assets/meshes/prop_torch.glb"
# Collision may differ from the visible bounds by this much per side (chamfers, raised blocks).
const BOUNDS_TOLERANCE_M := 0.15
# Room floors (x, z, width, depth) inside the walls' faces, as laid out in Level1.tscn.
const ROOMS := {
	"start": Rect2(-6, -6, 12, 12),
	"central": Rect2(16, -8, 16, 16),
	"exit": Rect2(18, 18, 12, 12),
	"side": Rect2(0.5, -30, 16, 16),
}
const DRESSING_PER_10M2 := [1.0, 3.0]
# Wall-mounted props sit in the wall's thickness, just outside the floor rectangle.
const ROOM_MARGIN_M := 1.0
const LIGHT_SPACING_MAX_M := 12.0
# A light counts for the path when it's within this distance of it (lights hang on room walls).
const LIGHT_PATH_REACH_M := 7.0
const LIGHT_SOURCE_REACH_M := 1.0
const POTION := "res://data/items/potion_health.tres"
# Eye height on Corridor A's centreline at the side passage's mouth: where the fight there ends.
const SIDE_ROOM_SIGHT_FROM := Vector3(8.5, 1.6, 0.0)
# Player.interact() casts forward from 0.8 m above the player's origin (0.95 m on the floor).
const INTERACT_RAY_HEIGHT_M := 1.75

var _level: Node3D


func before_test() -> void:
	_level = (load(LEVEL) as PackedScene).instantiate()


func after_test() -> void:
	if is_instance_valid(_level):
		_level.free()


# Every mesh on the navigation region is inside a StaticBody3D whose collision shapes span the same
# box as its meshes (no walk-through walls, no invisible walls), and the CSG blockout is gone.
func test_level1_collision_matches_visible() -> void:
	var region: Node3D = _level.get_node(REGION)
	var csg := region.find_children("*", "CSGShape3D", true, false)
	assert_array(csg.map(func(n: Node) -> String: return str(region.get_path_to(n)))).is_empty()
	for mesh: Node in region.find_children("*", "GeometryInstance3D", true, false):
		(
			assert_object(_static_body_of(mesh, region))
			. override_failure_message("%s has no StaticBody3D, so it can be walked through" % region.get_path_to(mesh))
			. is_not_null()
		)
	var bodies := region.find_children("*", "StaticBody3D", true, false)
	assert_int(bodies.size()).is_greater(0)
	for body: Node in bodies:
		var what := str(region.get_path_to(body))
		var seen := _visible_bounds(body)
		var solid := _collision_bounds(body)
		assert_bool(seen.has_volume()).override_failure_message("%s shows nothing (an invisible wall)" % what).is_true()
		assert_bool(solid.has_volume()).override_failure_message("%s has no box or cylinder collision" % what).is_true()
		for axis in 3:
			var d_min := absf(seen.position[axis] - solid.position[axis])
			var d_max := absf(seen.end[axis] - solid.end[axis])
			(
				assert_float(maxf(d_min, d_max))
				. override_failure_message(
					(
						"%s: collision %s vs visible %s differ by %.2f m on axis %d"
						% [what, solid, seen, maxf(d_min, d_max), axis]
					)
				)
				. is_less_equal(BOUNDS_TOLERANCE_M)
			)


# The kit's one scale factor is applied at import; every placed kit piece keeps unit scale.
func test_level1_kit_pieces_unscaled() -> void:
	var pieces := _level.find_children("*", "Node3D", true, false).filter(
		func(n: Node) -> bool: return n.scene_file_path.begins_with(KIT_PREFIX)
	)
	assert_int(pieces.size()).is_greater(0)
	for piece: Node3D in pieces:
		var scale := _level_xform(piece).basis.get_scale()
		(
			assert_vector(scale)
			. override_failure_message("%s is scaled %s" % [_level.get_path_to(piece), scale])
			. is_equal_approx(Vector3.ONE, Vector3.ONE * 0.001)
		)


# lvl_dressing_density: 1–3 dressing props per 10 m² of floor in each room (crates, barrels, pillars,
# torches, racks: the children of the region's Dressing and Pillars groups and of Torches).
func test_lvl_dressing_density() -> void:
	var props: Array[Node3D] = []
	for group in [REGION + "/Dressing", REGION + "/Pillars", "Torches"]:
		var parent := _level.get_node_or_null(group)
		assert_object(parent).override_failure_message("Level1 has no %s" % group).is_not_null()
		if parent == null:
			return
		for child in parent.get_children():
			if child is Node3D and not child is Light3D:
				props.append(child)
	for room: String in ROOMS:
		var rect: Rect2 = ROOMS[room]
		var grown := rect.grow(ROOM_MARGIN_M)
		var count := 0
		for prop in props:
			var at := _level_xform(prop).origin
			if grown.has_point(Vector2(at.x, at.z)):
				count += 1
		var density := count / (rect.get_area() / 10.0)
		(
			assert_float(density)
			. override_failure_message(
				"%s room: %d props on %.0f m² is %.2f per 10 m²" % [room, count, rect.get_area(), density]
			)
			. is_between(DRESSING_PER_10M2[0], DRESSING_PER_10M2[1])
		)


# lvl_light_spacing: along the critical path, no stretch longer than 12 m without a visible light
# source, counting from the spawn and up to the exit.
func test_lvl_light_spacing() -> void:
	var path := _critical_path()
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	var marks: Array[float] = [0.0, total]
	for light in _level_lights():
		var at := _level_xform(light).origin
		var hit := _project(path, Vector2(at.x, at.z))
		if hit.y <= LIGHT_PATH_REACH_M:
			marks.append(hit.x)
	marks.sort()
	for i in range(1, marks.size()):
		(
			assert_float(marks[i] - marks[i - 1])
			. override_failure_message(
				(
					"%.1f m without a light between %.1f and %.1f m along the path"
					% [marks[i] - marks[i - 1], marks[i - 1], marks[i]]
				)
			)
			. is_less_equal(LIGHT_SPACING_MAX_M)
		)


# Art bible → Rendering: local lights only on visible sources. Every OmniLight3D the level places
# sits within 1 m of a torch.
func test_level1_lights_on_visible_sources() -> void:
	var torches := _level.find_children("*", "Node3D", true, false).filter(
		func(n: Node) -> bool: return n.scene_file_path == TORCH_SCENE
	)
	for light in _level_lights():
		var at := _level_xform(light).origin
		var nearest := INF
		for torch: Node3D in torches:
			nearest = minf(nearest, at.distance_to(_level_xform(torch).origin))
		(
			assert_float(nearest)
			. override_failure_message("%s is %.2f m from the nearest torch" % [_level.get_path_to(light), nearest])
			. is_less_equal(LIGHT_SOURCE_REACH_M)
		)


# The side room's payoff is a pickup holding a potion, inside the side room, in plain sight from
# Corridor A (no wall, pillar or prop on the line from the corridor to it), and the player's interact
# ray, cast at chest height, reaches its collision.
func test_level1_side_room_payoff_in_sight() -> void:
	var pickups := _level.find_children("*", "", true, false).filter(
		func(n: Node) -> bool: return n.is_in_group("pickup")
	)
	assert_int(pickups.size()).override_failure_message("Level1 has %d pickups" % pickups.size()).is_equal(1)
	if pickups.size() != 1:
		return
	var pickup: Node3D = pickups[0]
	assert_str((pickup.get("item") as Item).resource_path if pickup.get("item") else "").is_equal(POTION)
	var at := _level_xform(pickup).origin
	assert_bool(ROOMS.side.has_point(Vector2(at.x, at.z))).override_failure_message("pickup at %s" % at).is_true()
	var target := at + Vector3.UP * 0.15
	var region: Node3D = _level.get_node(REGION)
	for body: Node in region.find_children("*", "StaticBody3D", true, false):
		var solid := _collision_bounds(body)
		(
			assert_bool(solid.intersects_segment(SIDE_ROOM_SIGHT_FROM, target) != null)
			. override_failure_message("%s blocks the view of the pickup" % region.get_path_to(body))
			. is_false()
		)
	var reach := _collision_bounds(pickup)
	(
		assert_bool(reach.position.y <= INTERACT_RAY_HEIGHT_M and reach.end.y >= INTERACT_RAY_HEIGHT_M)
		. override_failure_message(
			"pickup collision %s misses the interact ray at %.2f m" % [reach, INTERACT_RAY_HEIGHT_M]
		)
		. is_true()
	)


# The level's own local lights (not those inside instanced scenes, such as the player's fill light).
func _level_lights() -> Array[Node3D]:
	var lights: Array[Node3D] = []
	for light in _level.find_children("*", "OmniLight3D", true, false):
		if light.owner == _level:
			lights.append(light)
	return lights


func _critical_path() -> Array[Vector2]:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CRITICAL_PATH))
	var points: Array[Vector2] = []
	for waypoint: Dictionary in spec.waypoints:
		points.append(Vector2(waypoint.position[0], waypoint.position[2]))
	return points


# (distance along the path, distance from it) of the path point nearest to `p`
func _project(path: Array[Vector2], p: Vector2) -> Vector2:
	var best := Vector2(0.0, INF)
	var along := 0.0
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_to(q)
		if d < best.y:
			best = Vector2(along + a.distance_to(q), d)
		along += a.distance_to(b)
	return best


func _static_body_of(node: Node, stop: Node) -> StaticBody3D:
	var at := node.get_parent()
	while at != null and at != stop:
		if at is StaticBody3D:
			return at
		at = at.get_parent()
	return null


func _level_xform(node: Node) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var at := node
	while at != null and at != _level:
		if at is Node3D:
			xform = (at as Node3D).transform * xform
		at = at.get_parent()
	return xform


func _visible_bounds(body: Node) -> AABB:
	var bounds := AABB()
	for mesh in body.find_children("*", "MeshInstance3D", true, false):
		bounds = _merge(bounds, _level_xform(mesh) * (mesh as MeshInstance3D).get_aabb())
	return bounds


func _collision_bounds(body: Node) -> AABB:
	var bounds := AABB()
	for node in body.find_children("*", "CollisionShape3D", true, false):
		var shape := (node as CollisionShape3D).shape
		var local := AABB()
		if shape is BoxShape3D:
			var size: Vector3 = (shape as BoxShape3D).size
			local = AABB(-size / 2.0, size)
		elif shape is CylinderShape3D:
			var r: float = (shape as CylinderShape3D).radius
			var h: float = (shape as CylinderShape3D).height
			local = AABB(Vector3(-r, -h / 2.0, -r), Vector3(2.0 * r, h, 2.0 * r))
		else:
			continue
		bounds = _merge(bounds, _level_xform(node) * local)
	return bounds


func _merge(a: AABB, b: AABB) -> AABB:
	return b if not a.has_volume() else a.merge(b)
