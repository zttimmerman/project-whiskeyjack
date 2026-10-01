extends RefCounted

## Screen-space camera checks for replays (design bible §2; the cam_* targets in §9). Headless: nothing
## renders, so points are unprojected through the camera and rays are cast in the physics space against the
## collision shapes (the player's and the levy's capsules, the kit's boxes). scripts/review/replay.gd logs
## one "camera" event per physics frame from sample() when a scenario has cam_* checks, and
## scripts/review/replay_metrics.py turns them into the targets.
##
## A sample:
##   player_in_view     the head and torso (capsule centre to top: a box the capsule's width and depth, turned
##                      to the camera's heading) project fully inside the viewport, in front of the near plane
##   player_visible     fraction of rays to a grid on that region not stopped by world geometry first
##   camera_in_player   the camera is inside the player's capsule (plus the near distance)
##   camera_in_world    the camera is inside world geometry (it would see through a wall)
##   wall_fill          the largest fraction of a grid of screen rays that land on one wall surface (one plane:
##                      coplanar kit pieces merge; floors and ceilings don't count)
##   locked             a lock-on target was given; then also
##   target_in_view, target_visible   the same for the target's whole capsule
##   target_distance    player to target, in metres
##   melee_occlusion    fraction of the rays to the target's grid that meet the player first

const WALL_GRID := Vector2i(32, 18)
const WALL_RAY_LENGTH := 60.0
const WALL_NORMAL_Y_MAX := 0.5  # a surface steeper than this is floor or ceiling, not wall
const NORMAL_SNAP := 8.0  # normals quantised to 1/8 when grouping hits into planes
const PLANE_SNAP := 0.25  # metres: plane offsets within this are one surface
const BODY_COLUMNS := 5
const BODY_ROWS := 7
const BODY_WIDTH := 0.8  # the grid spans this fraction of the capsule's width
const WORLD_MASK := 1
const DEFAULT_RADIUS := 0.4
const DEFAULT_HEIGHT := 1.8


static func sample(camera: Camera3D, player: CollisionObject3D, target: Node3D) -> Dictionary:
	var space := camera.get_world_3d().direct_space_state
	var out := {}
	var pc := capsule(player)
	var p_bottom: float = pc["center"].y
	var p_top: float = pc["center"].y + pc["height"] * 0.5
	out["player_in_view"] = _in_view(camera, pc, p_bottom, p_top)
	out["player_visible"] = _rays_to_body(camera, space, player, pc, p_bottom, p_top, null)["visible"]
	out["camera_in_player"] = _inside_capsule(camera.global_position, pc, camera.near)
	out["camera_in_world"] = _inside_world(space, camera.global_position)
	out["wall_fill"] = wall_fill(camera, space)
	out["locked"] = is_instance_valid(target)
	if out["locked"]:
		var tc := capsule(target)
		var t_bottom: float = tc["center"].y - tc["height"] * 0.5
		var t_top: float = tc["center"].y + tc["height"] * 0.5
		var rays := _rays_to_body(camera, space, target, tc, t_bottom, t_top, player)
		out["target_in_view"] = _in_view(camera, tc, t_bottom, t_top)
		out["target_visible"] = rays["visible"]
		out["melee_occlusion"] = 1.0 if out["camera_in_player"] else rays["covered"]
		out["target_distance"] = player.global_position.distance_to(target.global_position)
	return out


## A body's capsule in world space: {center, radius, height}, from its first capsule CollisionShape3D child
## (or a 0.4 m by 1.8 m capsule on the origin when it has none)
static func capsule(body: Node3D) -> Dictionary:
	for child in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is CapsuleShape3D:
			var shape := (child as CollisionShape3D).shape as CapsuleShape3D
			return {"center": (child as Node3D).global_position, "radius": shape.radius, "height": shape.height}
	return {"center": body.global_position, "radius": DEFAULT_RADIUS, "height": DEFAULT_HEIGHT}


## The largest fraction of the screen covered by one wall plane
static func wall_fill(camera: Camera3D, space: PhysicsDirectSpaceState3D) -> float:
	var rect := camera.get_viewport().get_visible_rect()
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = WORLD_MASK
	var counts := {}
	var best := 0
	for i in WALL_GRID.x:
		for j in WALL_GRID.y:
			var screen := (
				rect.position + Vector2((i + 0.5) / WALL_GRID.x * rect.size.x, (j + 0.5) / WALL_GRID.y * rect.size.y)
			)
			var from := camera.project_ray_origin(screen)
			var hit := _first_world_hit(space, query, from, from + camera.project_ray_normal(screen) * WALL_RAY_LENGTH)
			if hit.is_empty():
				continue
			var n: Vector3 = hit["normal"]
			if absf(n.y) > WALL_NORMAL_Y_MAX:
				continue
			var key := (
				"%d,%d,%d,%d"
				% [
					roundi(n.x * NORMAL_SNAP),
					roundi(n.y * NORMAL_SNAP),
					roundi(n.z * NORMAL_SNAP),
					roundi(n.dot(hit["position"]) / PLANE_SNAP)
				]
			)
			counts[key] = int(counts.get(key, 0)) + 1
			best = maxi(best, counts[key])
	return float(best) / float(WALL_GRID.x * WALL_GRID.y)


# The eight corners of a body's region (a box the capsule's width and depth around its axis, upright and turned
# to the camera's heading) all project inside the viewport, in front of the near plane
static func _in_view(camera: Camera3D, cap: Dictionary, bottom: float, top: float) -> bool:
	var rect := camera.get_viewport().get_visible_rect()
	var r := float(cap["radius"])
	var right := _flat_right(camera) * r
	var ahead := Vector3.UP.cross(right)
	var c: Vector3 = cap["center"]
	for y: float in [bottom, top]:
		for side: float in [-1.0, 1.0]:
			for depth: float in [-1.0, 1.0]:
				var p := Vector3(c.x, y, c.z) + right * side + ahead * depth
				if camera.is_position_behind(p) or not rect.has_point(camera.unproject_position(p)):
					return false
	return true


# Rays from the camera to a grid on a body's region: "visible" is the fraction not stopped by world geometry
# first; "covered" the fraction that meet `cover` (the player, for a target) first
static func _rays_to_body(
	camera: Camera3D,
	space: PhysicsDirectSpaceState3D,
	body: Node3D,
	cap: Dictionary,
	bottom: float,
	top: float,
	cover: Node3D
) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = WORLD_MASK
	var right := _flat_right(camera) * float(cap["radius"]) * BODY_WIDTH
	var c: Vector3 = cap["center"]
	var from := camera.global_position
	var hidden := 0
	var covered := 0
	for i in BODY_COLUMNS:
		var u := lerpf(-1.0, 1.0, float(i) / (BODY_COLUMNS - 1))
		for j in BODY_ROWS:
			var y := lerpf(bottom, top, (j + 0.5) / BODY_ROWS)
			var p := Vector3(c.x, y, c.z) + right * u
			query.from = from
			query.to = p
			var hit := space.intersect_ray(query)
			if hit.is_empty() or hit["collider"] == body:
				continue
			if cover != null and hit["collider"] == cover:
				covered += 1
			elif not hit["collider"] is CharacterBody3D:
				hidden += 1
	var total := float(BODY_COLUMNS * BODY_ROWS)
	return {"visible": 1.0 - hidden / total, "covered": covered / total}


# The first hit that isn't a character body (the player and enemies share layer 1 with the level)
static func _first_world_hit(
	space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D, from: Vector3, to: Vector3
) -> Dictionary:
	query.from = from
	query.to = to
	query.exclude = []
	var skipped: Array[RID] = []
	for _i in 4:
		var hit := space.intersect_ray(query)
		if hit.is_empty() or not hit["collider"] is CharacterBody3D:
			return hit
		skipped.append(hit["rid"])
		query.exclude = skipped
	return {}


static func _inside_capsule(p: Vector3, cap: Dictionary, margin: float) -> bool:
	var c: Vector3 = cap["center"]
	var r: float = cap["radius"]
	var half: float = maxf(float(cap["height"]) * 0.5 - r, 0.0)
	var axis_y := clampf(p.y, c.y - half, c.y + half)
	return p.distance_to(Vector3(c.x, axis_y, c.z)) < r + margin


static func _inside_world(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = p
	query.collision_mask = WORLD_MASK
	for hit in space.intersect_point(query, 8):
		if not hit["collider"] is CharacterBody3D:
			return true
	return false


# The camera's right, flattened to horizontal: body regions stay upright when the camera pitches or rolls
static func _flat_right(camera: Camera3D) -> Vector3:
	var right := camera.global_basis.x
	right.y = 0.0
	return right.normalized() if right.length_squared() > 1e-6 else Vector3.RIGHT
