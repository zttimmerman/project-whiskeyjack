extends Node

# Readability numbers for a level's lighting, from the gameplay camera (design bible §9:
# lvl_floor_luminance_min, read_char_contrast_min). Review tool, not part of the game; written for
# art-rules-b2 to check the B2 lighting standard before and after. Windowed (headless can't render), as a
# scene so the project's autoloads load:
#   godot --always-on-top --path . res://scripts/review/level_luminance.tscn -- --path <critical path json> \
#       --out <dir> [--shots 1]
# The level is the critical path file's "scene" (tests/critical_paths/*.json). At every waypoint the player
# stands on the floor facing the next waypoint, with his own CameraRig (and its fill light) placed as in play.
# Per waypoint:
#   floor     mean and 10th-percentile linear Rec. 709 luminance of the walkable floor pixels (a grid of
#             camera rays that hit an upward-facing surface near the player's floor, his own pixels excluded)
#   player    his pixels against the same pixels with him hidden: mean linear luminance of each and their
#             contrast ratio (L_hi + 0.05) / (L_lo + 0.05)
# Per enemy in the level: the same contrast from a camera 5 m away at eye height, on the side facing the
# nearest waypoint. Writes <out>/<level>_luminance.json, and with --shots the gameplay frames as PNGs.
# Enemies and the player are frozen (process disabled) in their idle pose, so nothing moves between the paired
# renders.

const SETTLE_FRAMES := 30
const GRID_PX := 8  # floor ray grid spacing, in pixels
const ENEMY_VIEW_M := 5.0
const EYE_HEIGHT_M := 1.7
const FLOOR_NORMAL_Y := 0.8
const FLOOR_BAND_M := 0.3  # floor pixels within this of the player's floor height

var _args := {}
var _level: Node3D
var _player: Node3D
var _cam: Camera3D


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var argv := OS.get_cmdline_user_args()
	for i in range(0, argv.size() - 1, 2):
		_args[argv[i].trim_prefix("--")] = argv[i + 1]
	if not _args.has("path") or not _args.has("out"):
		printerr("level_luminance: usage: -- --path <critical path json> --out <dir> [--shots 1]")
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280, 720)
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_args["path"]))
	_level = (load(spec.scene) as PackedScene).instantiate()
	add_child(_level)
	var ui := _level.get_node_or_null("CanvasLayer")
	if ui:
		ui.visible = false
	_player = _level.get_node("Player")
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	for enemy in get_tree().get_nodes_in_group("enemy"):
		(enemy as Node).process_mode = Node.PROCESS_MODE_DISABLED
	# Characters hold their idle pose: their AnimationPlayers run through the settle, then pause
	var players := _level.find_children("*", "AnimationPlayer", true, false)
	for ap in players:
		(ap as Node).process_mode = Node.PROCESS_MODE_ALWAYS
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	for ap in players:
		(ap as AnimationPlayer).pause()
	_cam = Camera3D.new()
	add_child(_cam)
	var level_name: String = (spec.scene as String).get_file().get_basename()
	var result := {"scene": spec.scene, "waypoints": [], "enemies": []}
	var points: Array[Vector3] = []
	for wp: Dictionary in spec.waypoints:
		points.append(Vector3(wp.position[0], wp.position[1], wp.position[2]))
	for i in points.size():
		var ahead := points[i + 1] - points[i] if i + 1 < points.size() else points[i] - points[i - 1]
		var row := await _measure_waypoint(points[i], atan2(-ahead.x, -ahead.z))
		row["name"] = spec.waypoints[i].name
		result.waypoints.append(row)
		if _args.has("shots"):
			_last_full.save_png(_args["out"].path_join("%s_%s.png" % [level_name, row.name]))
		print(
			(
				"WAYPOINT %s %s floor mean %.4f p10 %.4f (n %d) player %.4f vs %.4f contrast %.2f"
				% [
					level_name,
					row.name,
					row.floor.mean,
					row.floor.p10,
					row.floor.n,
					row.player.lum,
					row.player.bg,
					row.player.contrast
				]
			)
		)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var row := await _measure_enemy(enemy as Node3D, points)
		result.enemies.append(row)
		print(
			(
				"ENEMY %s %s %.4f vs %.4f contrast %.2f (px %d, %.1f m)"
				% [level_name, row.name, row.lum, row.bg, row.contrast, row.px, row.view_m]
			)
		)
	var floors: Array = result.waypoints.map(func(r: Dictionary) -> float: return r.floor.mean)
	var contrasts: Array = result.waypoints.map(func(r: Dictionary) -> float: return r.player.contrast)
	# An enemy with no visible pixels (hidden behind dressing from every view) has no contrast to report
	contrasts.append_array(
		(
			result
			. enemies
			. filter(func(r: Dictionary) -> bool: return r.px > 0)
			. map(func(r: Dictionary) -> float: return r.contrast)
		)
	)
	result["floor_mean_min"] = floors.min()
	result["contrast_min"] = contrasts.min() if not contrasts.is_empty() else 0.0
	print("SUMMARY %s floor_mean_min %.4f contrast_min %.2f" % [level_name, result.floor_mean_min, result.contrast_min])
	var f := FileAccess.open(_args["out"].path_join("%s_luminance.json" % level_name), FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "  "))
	f.close()
	get_tree().quit()


var _last_full: Image


func _measure_waypoint(at: Vector3, yaw: float) -> Dictionary:
	var floor_y := _floor_height(at)
	_player.global_position = Vector3(at.x, floor_y + 1.0, at.z)
	_player.apply_view_state({"facing": yaw, "camera_yaw": yaw, "camera_pitch": 0.0})
	var cam: Camera3D = _player.camera_rig.camera
	cam.current = true
	var full := await _render()
	_player.visible = false
	var without := await _render()
	_player.visible = true
	_last_full = full
	var mask := _diff_mask(full, without)
	var pair := _pair_luminance(full, without, mask)
	return {"floor": _floor_luminance(full, cam, floor_y, mask), "player": pair}


func _measure_enemy(enemy: Node3D, points: Array[Vector3]) -> Dictionary:
	var at := enemy.global_position
	var nearest := points[0]
	for p in points:
		if Vector2(p.x - at.x, p.z - at.z).length() < Vector2(nearest.x - at.x, nearest.z - at.z).length():
			nearest = p
	var toward := Vector3(nearest.x - at.x, 0.0, nearest.z - at.z)
	toward = toward.normalized() if toward.length() > 0.1 else Vector3.BACK
	var foot := at.y - 0.9
	var chest := Vector3(at.x, foot + EYE_HEIGHT_M, at.z)
	# Pulled in short of any wall between the enemy and the view point, so the camera stays in the room
	var q := PhysicsRayQueryParameters3D.create(chest, chest + toward * ENEMY_VIEW_M)
	q.exclude = [(enemy as CollisionObject3D).get_rid(), (_player as CollisionObject3D).get_rid()]
	var hit := _level.get_world_3d().direct_space_state.intersect_ray(q)
	var reach := maxf(chest.distance_to(hit.position) - 0.3, 1.0) if hit else ENEMY_VIEW_M
	var eye := chest + toward * reach
	_cam.fov = 72.0
	_cam.look_at_from_position(eye, Vector3(at.x, foot + 1.0, at.z), Vector3.UP)
	_cam.current = true
	_player.visible = false
	var full := await _render()
	enemy.visible = false
	var without := await _render()
	enemy.visible = true
	_player.visible = true
	var row := _pair_luminance(full, without, _diff_mask(full, without))
	row["name"] = String(_level.get_path_to(enemy))
	row["view_m"] = snappedf(reach, 0.01)
	return row


func _render() -> Image:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _floor_height(at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 3.0)
	q.exclude = [(_player as CollisionObject3D).get_rid()]
	var hit := _level.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else at.y


func _floor_luminance(img: Image, cam: Camera3D, floor_y: float, player_mask: Dictionary) -> Dictionary:
	var space := _level.get_world_3d().direct_space_state
	var values: Array[float] = []
	for y in range(GRID_PX >> 1, img.get_height(), GRID_PX):
		for x in range(GRID_PX >> 1, img.get_width(), GRID_PX):
			if player_mask.has(Vector2i(x, y)):
				continue
			var px := Vector2(x, y)
			var from := cam.project_ray_origin(px)
			var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(px) * 60.0)
			q.exclude = [(_player as CollisionObject3D).get_rid()]
			var hit := space.intersect_ray(q)
			if not hit or hit.normal.y < FLOOR_NORMAL_Y or absf(hit.position.y - floor_y) > FLOOR_BAND_M:
				continue
			values.append(_lum(img.get_pixel(x, y)))
	values.sort()
	if values.is_empty():
		return {"mean": 0.0, "p10": 0.0, "n": 0}
	var total := 0.0
	for v in values:
		total += v
	return {
		"mean": snappedf(total / values.size(), 0.0001),
		"p10": snappedf(values[int(values.size() * 0.1)], 0.0001),
		"n": values.size()
	}


# Pixels that differ between the two renders (the hidden subject's)
func _diff_mask(a: Image, b: Image) -> Dictionary:
	var mask := {}
	for y in a.get_height():
		for x in a.get_width():
			var c := a.get_pixel(x, y)
			var d := b.get_pixel(x, y)
			if absf(c.r - d.r) + absf(c.g - d.g) + absf(c.b - d.b) >= 0.02:
				mask[Vector2i(x, y)] = true
	return mask


func _pair_luminance(full: Image, without: Image, mask: Dictionary) -> Dictionary:
	if mask.is_empty():
		return {"lum": 0.0, "bg": 0.0, "contrast": 0.0, "px": 0}
	var lum := 0.0
	var bg := 0.0
	for p: Vector2i in mask:
		lum += _lum(full.get_pixel(p.x, p.y))
		bg += _lum(without.get_pixel(p.x, p.y))
	lum /= mask.size()
	bg /= mask.size()
	return {
		"lum": snappedf(lum, 0.0001),
		"bg": snappedf(bg, 0.0001),
		"contrast": snappedf((maxf(lum, bg) + 0.05) / (minf(lum, bg) + 0.05), 0.01),
		"px": mask.size()
	}


# Linear Rec. 709 luminance of an sRGB-encoded pixel
static func _lum(c: Color) -> float:
	var lin := c.srgb_to_linear()
	return 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b
