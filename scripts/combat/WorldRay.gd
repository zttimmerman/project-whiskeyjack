extends RefCounted

## Rays against world geometry, for enemy sight and arrows (design bible §3). The player and enemy bodies
## share physics layer 1 ("world") with the level, so a ray that meets a character is cast again past it:
## characters never block sight or stop an arrow (an arrow hurts through its HitboxComponent instead).
## Callers keep one PhysicsRayQueryParameters3D each and pass it in, so a clear ray allocates nothing new.

const WORLD_MASK := 1
const MAX_CHARACTER_SKIPS := 4


## A query set up for world rays, excluding `exclude` (the caller's own body, say)
static func make_query(exclude: Array[RID] = []) -> PhysicsRayQueryParameters3D:
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = WORLD_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = exclude
	return query


## The first world hit from `from` to `to` (intersect_ray's dictionary), or {} when the way is clear.
## Character bodies met on the way are skipped; the query's exclude list is restored afterwards.
static func first_hit(
	space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D, from: Vector3, to: Vector3
) -> Dictionary:
	query.from = from
	query.to = to
	var hit := space.intersect_ray(query)
	if hit.is_empty() or not hit.collider is CharacterBody3D:
		return hit
	var base := query.exclude
	var skipped := base.duplicate()
	for _i in MAX_CHARACTER_SKIPS:
		skipped.append(hit.rid)
		query.exclude = skipped
		hit = space.intersect_ray(query)
		if hit.is_empty() or not hit.collider is CharacterBody3D:
			break
	query.exclude = base
	if not hit.is_empty() and hit.collider is CharacterBody3D:
		return {}  # a crowd of characters, no wall found behind them
	return hit


static func is_clear(
	space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D, from: Vector3, to: Vector3
) -> bool:
	return first_hit(space, query, from, to).is_empty()
