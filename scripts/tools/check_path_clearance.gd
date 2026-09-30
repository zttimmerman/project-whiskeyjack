extends SceneTree

# Checks lvl_path_clearance_min (design bible §7 and §9): the critical path keeps at least 1.0 m of
# clear navmesh width. Report-only by default; --strict exits 1 when a segment fails.
#   godot --headless --path . -s scripts/tools/check_path_clearance.gd [-- --strict] [-- --out=report.json]
#
# For each tests/critical_paths/*.json it bakes the level in memory (never saved) with a 0.5 m agent
# radius, so the navmesh only exists where there is 1.0 m of clearance, and path-finds between
# consecutive waypoints with NavigationServer3D.map_get_path. A segment:
#   PASS   reaches the next waypoint no more than DETOUR_MAX longer than on the reference bake;
#   DETOUR reaches it, but the 1.0 m clearance forces a longer way round (a prop narrowing the path);
#   FAIL   doesn't reach it (a gap narrower than 1.0 m, or a waypoint off the navmesh).
# The reference bake uses a one-cell (0.25 m) agent, close to the raw geometry. The widest column
# re-runs the segment at larger radii and reports the widest clearance that still passes.

const PATHS_DIR := "res://tests/critical_paths"
const Baker := preload("res://scripts/tools/bake_navmeshes.gd")
const CLEARANCE_M := 1.0
const REFERENCE_RADIUS := 0.25
const SWEEP_RADII: Array[float] = [0.75, 1.0, 1.25, 1.5, 1.75]
const DETOUR_MAX := 1.10  # path length over the reference path's
const REACH_TOLERANCE := 0.5  # metres between a path's end and its waypoint, on the floor plane


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var strict := args.has("--strict")
	var out_path := ""
	for arg in args:
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var report := {"target": "lvl_path_clearance_min", "clearance_m": CLEARANCE_M, "levels": []}
	var any_fail := false
	var files := DirAccess.get_files_at(PATHS_DIR)
	files.sort()
	for file in files:
		if not file.ends_with(".json"):
			continue
		var spec: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATHS_DIR.path_join(file)))
		if typeof(spec) != TYPE_DICTIONARY or not spec.has("scene") or not spec.has("waypoints"):
			push_error("check_path_clearance: %s needs scene and waypoints" % file)
			quit(2)
			return
		var level := await _check_level(spec)
		if level.is_empty():
			quit(2)
			return
		report.levels.append(level)
		for seg: Dictionary in level.segments:
			any_fail = any_fail or seg.status != "PASS"
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "  ", false) + "\n")
		f.close()
	quit(1 if strict and any_fail else 0)


func _check_level(spec: Dictionary) -> Dictionary:
	var scene: String = spec.scene
	var points: Array[Vector3] = []
	var names: Array[String] = []
	for wp: Dictionary in spec.waypoints:
		names.append(wp.name)
		points.append(Vector3(wp.position[0], wp.position[1], wp.position[2]))
	var radii: Array[float] = [REFERENCE_RADIUS, CLEARANCE_M / 2.0]
	radii.append_array(SWEEP_RADII)
	# lengths[radius] = per-segment path length, or -1.0 where the path doesn't reach
	var lengths := {}
	for radius in radii:
		var settings: Dictionary = Baker.SETTINGS.duplicate()
		settings.agent_radius = radius
		var navmesh: NavigationMesh = await Baker.bake_region(self, scene, settings)
		if navmesh == null:
			return {}
		lengths[radius] = await _segment_lengths(navmesh, points)
	var level := {"scene": scene, "segments": []}
	print("\n%s  (lvl_path_clearance_min: >= %.1f m)" % [scene, CLEARANCE_M])
	print("  %-30s %-7s %9s %9s %7s %9s" % ["segment", "status", "length", "ref", "detour", "widest"])
	for i in points.size() - 1:
		var ref: float = lengths[REFERENCE_RADIUS][i]
		var got: float = lengths[CLEARANCE_M / 2.0][i]
		var status := _status(got, ref)
		var widest := 0.0
		for radius in [CLEARANCE_M / 2.0] + SWEEP_RADII:
			if _status(lengths[radius][i], ref) == "PASS":
				widest = radius * 2.0
			else:
				break
		var seg := {
			"from": names[i], "to": names[i + 1], "status": status,
			"length_m": snappedf(got, 0.01), "reference_length_m": snappedf(ref, 0.01),
			"detour": snappedf(got / ref, 0.01) if got > 0.0 and ref > 0.0 else -1.0,  # -1: no path
			"widest_clearance_m": widest,
		}
		level.segments.append(seg)
		print("  %-30s %-7s %9s %9s %7s %9s" % [
			"%s -> %s" % [names[i], names[i + 1]], status,
			"%.2f m" % got if got >= 0.0 else "-", "%.2f m" % ref if ref >= 0.0 else "-",
			"%.2f" % (got / ref) if got > 0.0 and ref > 0.0 else "-",
			(">= %.1f m" if widest == (SWEEP_RADII[-1] * 2.0) else "%.1f m") % widest if widest > 0.0 else "< %.1f m" % CLEARANCE_M])
	return level


func _status(length: float, reference: float) -> String:
	if length < 0.0:
		return "FAIL"
	if reference > 0.0 and length > reference * DETOUR_MAX:
		return "DETOUR"
	return "PASS"


# Path length per consecutive waypoint pair on a throwaway map, or -1.0 where the path doesn't
# reach (a start or end more than REACH_TOLERANCE from its waypoint on the floor plane).
func _segment_lengths(navmesh: NavigationMesh, points: Array[Vector3]) -> Array[float]:
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, navmesh.cell_size)
	NavigationServer3D.map_set_cell_height(map, navmesh.cell_height)
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_navigation_mesh(region, navmesh)
	# The server syncs maps on the physics step, and builds region polygons asynchronously, so wait
	# until the map has a polygon under the first waypoint (map_force_update doesn't do it in 4.7).
	var synced := false
	for _i in 120:
		await physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > 0 \
				and NavigationServer3D.map_get_closest_point_owner(map, points[0]).is_valid():
			synced = true
			break
	var out: Array[float] = []
	if not synced:
		push_error("check_path_clearance: the map never had a polygon near %s" % points[0])
		for i in points.size() - 1:
			out.append(-1.0)
	for i in points.size() - 1:
		if out.size() == points.size() - 1:
			break
		var path := NavigationServer3D.map_get_path(map, points[i], points[i + 1], true)
		if path.is_empty() or _flat_distance(path[0], points[i]) > REACH_TOLERANCE \
				or _flat_distance(path[-1], points[i + 1]) > REACH_TOLERANCE:
			out.append(-1.0)
			continue
		var length := 0.0
		for j in range(1, path.size()):
			length += path[j - 1].distance_to(path[j])
		out.append(length)
	NavigationServer3D.free_rid(region)
	NavigationServer3D.free_rid(map)
	return out


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
