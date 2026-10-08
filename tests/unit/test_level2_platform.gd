extends GdUnitTestSuite

# Level 2's burial platform is walkable (backlog level2-burial-platform, user decision 2026-10-08): it
# stands 0.5 m high, over the navmesh's 0.25 m climb limit, so it gets visible steps on its north and
# south faces with an invisible clip ramp under them, as on the crypt trial's dais. The ramp is what the
# player's capsule and the navmesh bake climb; the steps are what you see.
# - enemies path from the vault floor onto the platform top, and down off the other side, on the
#   committed bake (scenes/world/Level2_navmesh.tres);
# - a player-sized capsule walks up the north ramp onto the platform, and on over the south ramp.

const LEVEL := "res://scenes/world/Level2.tscn"
const NAVMESH := "res://scenes/world/Level2_navmesh.tres"
const PLATFORM_TOP_Y := 0.5
const PLATFORM_TOP := Vector3(0, PLATFORM_TOP_Y, 45)
const VAULT_NORTH := Vector3(0, 0, 40)  # the critical path's burial_vault waypoint
const VAULT_SOUTH := Vector3(0, 0, 50.5)
const REACH_TOLERANCE := 0.3  # metres between a path's end and its target, on the floor plane
const HEIGHT_TOLERANCE := 0.3  # navmesh polygons sit within a cell or so of the surface
const CAPSULE_CENTRE_ABOVE_FLOOR := 0.9
const WALK_SPEED := 4.0
const GRAVITY := 9.8

var _region: NavigationRegion3D
var _nav_rids: Array[RID] = []  # the throwaway map and its region, freed after each test


func before_test() -> void:
	# The level's geometry alone, out of the level, so the level script never runs.
	var level := (load(LEVEL) as PackedScene).instantiate()
	_region = level.get_node("NavigationRegion3D")
	level.remove_child(_region)
	level.free()
	_region.enabled = false  # the test's own nav map below; never the default map
	add_child(_region)
	# CSG shapes build their collision on a deferred update; the physics server needs a step after that.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame


func after_test() -> void:
	if is_instance_valid(_region):
		_region.free()
	for rid in _nav_rids:
		NavigationServer3D.free_rid(rid)
	_nav_rids.clear()


func test_enemies_path_onto_burial_platform() -> void:
	var map := await _nav_map()
	for from: Vector3 in [VAULT_NORTH, VAULT_SOUTH]:
		var path := NavigationServer3D.map_get_path(map, from, PLATFORM_TOP, true)
		assert_bool(path.is_empty()).override_failure_message("no path from %s to the platform" % from).is_false()
		if path.is_empty():
			continue
		var end: Vector3 = path[-1]
		(
			assert_float(Vector2(end.x, end.z).distance_to(Vector2(PLATFORM_TOP.x, PLATFORM_TOP.z)))
			. override_failure_message("path from %s ends at %s, short of the platform top" % [from, end])
			. is_less_equal(REACH_TOLERANCE)
		)
		(
			assert_float(end.y)
			. override_failure_message("path from %s ends at y %.2f, not on the platform top" % [from, end.y])
			. is_between(PLATFORM_TOP_Y - HEIGHT_TOLERANCE, PLATFORM_TOP_Y + HEIGHT_TOLERANCE)
		)


func test_capsule_walks_over_burial_platform() -> void:
	var walker := _walker(VAULT_NORTH)
	var top_y := -INF
	# North to south along x = 0: up the north ramp, across the top, down the south ramp.
	for _i in 180:
		await get_tree().physics_frame
		walker.velocity.z = WALK_SPEED
		walker.velocity.y = 0.0 if walker.is_on_floor() else walker.velocity.y - GRAVITY / 60.0
		walker.move_and_slide()
		if absf(walker.global_position.z - PLATFORM_TOP.z) < 1.0:
			top_y = maxf(top_y, walker.global_position.y)
	(
		assert_float(top_y)
		. override_failure_message("the capsule crossed the platform's middle at y %.2f" % top_y)
		. is_greater(PLATFORM_TOP_Y + CAPSULE_CENTRE_ABOVE_FLOOR - 0.1)
	)
	(
		assert_float(walker.global_position.z)
		. override_failure_message("the capsule stopped at z %.2f" % walker.global_position.z)
		. is_greater(VAULT_SOUTH.z - 1.0)
	)


func _walker(at: Vector3) -> CharacterBody3D:
	var walker: CharacterBody3D = auto_free(CharacterBody3D.new())
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4  # Player.tscn
	capsule.height = 1.8
	shape.shape = capsule
	walker.add_child(shape)
	add_child(walker)
	walker.global_position = at + Vector3.UP * (CAPSULE_CENTRE_ABOVE_FLOOR + 0.05)
	return walker


# A throwaway nav map holding the committed bake, synced (the server builds it on the physics step).
func _nav_map() -> RID:
	var navmesh := load(NAVMESH) as NavigationMesh
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, navmesh.cell_size)
	NavigationServer3D.map_set_cell_height(map, navmesh.cell_height)
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_navigation_mesh(region, navmesh)
	_nav_rids.append_array([region, map])
	for _i in 120:
		await get_tree().physics_frame
		if (
			NavigationServer3D.map_get_iteration_id(map) > 0
			and NavigationServer3D.map_get_closest_point_owner(map, VAULT_NORTH).is_valid()
		):
			break
	return map
