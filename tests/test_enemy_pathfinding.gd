extends SceneTree

# Headless test that the levels path-find on their edit-time navmeshes (design bible §8):
# - neither level bakes at runtime, and each region uses the committed, non-empty navmesh;
# - in Level 1 a Front-file (BaseEnemy) chases the player around a pillar that blocks the straight
#   line, which the enemy's no-navmesh fallback (walk straight at the player) can't do;
# - in Level 2 the map has a path from the spawn to the end trigger.
#   godot --headless --path . -s res://tests/test_enemy_pathfinding.gd

const SLOT := "pathfinding_test"
const LEVEL1 := "res://scenes/world/Level1.tscn"
const LEVEL2 := "res://scenes/world/Level2.tscn"
const CHASER := "EnemyCentral1"
# Pillar3 is a 1.5 m kit pillar at (24, 0); the enemy and player stand on either side of it on z = 0.
const PILLAR_CENTER := Vector3(24, 0, 0)
const ENEMY_START := Vector3(21.8, 1, 0)
const PLAYER_AT := Vector3(26.2, 1, 0)
const CHASE_TIMEOUT_S := 6.0
const CHASE_STATE := 2  # BaseEnemy.State.CHASE
const LEVEL2_SPAWN := Vector3(0, 0, -4)
const LEVEL2_END := Vector3(0, 0, 72.5)

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("/root/SaveManager").set_save_slot(SLOT)
	var level1 := await _open(LEVEL1)
	await _check_chase(level1)
	var level2 := await _open(LEVEL2)
	_check_level2_path(level2)
	if _failures.is_empty():
		print("test_enemy_pathfinding: PASS")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)


# Checks the level's committed navmesh and script, then opens it the way the game does.
func _open(path: String) -> Node:
	# The committed navmesh, checked before anything could bake into it.
	var probe: Node = load(path).instantiate()
	var navmesh: NavigationMesh = probe.get_node("NavigationRegion3D").navigation_mesh
	var expected := path.get_basename() + "_navmesh.tres"
	_check(navmesh != null and navmesh.resource_path == expected, "%s region uses %s" % [path.get_file(), expected])
	_check(navmesh != null and navmesh.get_polygon_count() > 0, "%s navmesh has polygons" % path.get_file())
	var script_path: String = probe.get_script().resource_path
	probe.free()
	_check(
		not FileAccess.get_file_as_string(script_path).contains("bake_navigation_mesh"),
		"%s doesn't bake its navmesh at runtime" % script_path.get_file()
	)
	change_scene_to_file(path)
	for _i in 30:
		await process_frame
		if current_scene and current_scene.scene_file_path == path:
			break
	if not current_scene or current_scene.scene_file_path != path:
		_check(false, "%s became the current scene" % path.get_file())
		quit(1)
		return null
	await _physics_frames(10)
	return current_scene


func _check_chase(level: Node) -> void:
	# Only the chaser stays, so no other enemy blocks or distracts it.
	for child in level.get_children():
		if child.is_in_group("enemy") and child.name != CHASER:
			child.queue_free()
	var enemy: CharacterBody3D = level.get_node(CHASER)
	var player: CharacterBody3D = get_first_node_in_group("player")
	player.global_position = PLAYER_AT
	enemy.global_position = ENEMY_START
	enemy.velocity = Vector3.ZERO
	# The pillar blocks its sight of the player, so start the chase as if it had seen them earlier:
	# this checks pathfinding, not detection (tests/unit/test_enemy_awareness.gd covers that)
	enemy._change_state(CHASE_STATE)
	await _physics_frames(2)
	var agent: NavigationAgent3D = enemy.get_node("NavigationAgent3D")
	var reach: float = enemy.attack_range + 0.3
	var reached := false
	var max_offset := 0.0  # how far off the straight line (z = 0) the enemy walked
	var bent_path := false
	var frames := int(CHASE_TIMEOUT_S * Engine.physics_ticks_per_second)
	for _i in frames:
		await physics_frame
		max_offset = maxf(max_offset, absf(enemy.global_position.z - PILLAR_CENTER.z))
		bent_path = bent_path or agent.get_current_navigation_path().size() >= 3
		if _flat(enemy.global_position).distance_to(_flat(player.global_position)) <= reach:
			reached = true
			break
	_check(bent_path, "the chaser's navigation path bends around the pillar")
	_check(max_offset > 0.5, "the chaser walked around the pillar (max |dz| %.2f m)" % max_offset)
	_check(
		reached,
		(
			"the chaser reached attack range of the player within %.0f s (at %.2f m)"
			% [CHASE_TIMEOUT_S, _flat(enemy.global_position).distance_to(_flat(player.global_position))]
		)
	)


func _check_level2_path(level: Node) -> void:
	var region: NavigationRegion3D = level.get_node("NavigationRegion3D")
	var path := NavigationServer3D.map_get_path(region.get_navigation_map(), LEVEL2_SPAWN, LEVEL2_END, true)
	_check(
		not path.is_empty() and _flat(path[-1]).distance_to(_flat(LEVEL2_END)) < 0.5,
		"Level2 has a path from the spawn to the end trigger"
	)


func _physics_frames(count: int) -> void:
	for _i in count:
		await physics_frame


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)
