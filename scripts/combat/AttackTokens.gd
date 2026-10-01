extends RefCounted

## Attack tokens for one target (design bible §3 and §9, `enemy_attackers_max`): at most MELEE_MAX melee
## enemies engage the target at once, and only one archer fires at it in any RANGED_WINDOW_S. The target
## carries its tokens in its metadata (BaseEnemy._attack_tokens()), so they go when its scene is freed.
## Holders are kept by instance ID, so a freed enemy's token is reclaimed rather than read after free.

const META := &"attack_tokens"
const MELEE_MAX := 2
const RANGED_WINDOW_S := 2.0
## Shot times come from physics frames (frame / ticks per second); this absorbs their float rounding
const TIME_EPSILON := 1e-6

var _melee: Array[int] = []
var _last_shot_s: float = -INF
var _last_shooter: int = 0


## True when `enemy` holds, or now takes, one of the melee tokens
func try_acquire_melee(enemy: Object) -> bool:
	var id := enemy.get_instance_id()
	if _melee.has(id):
		return true
	_prune()
	if _melee.size() >= MELEE_MAX:
		return false
	_melee.append(id)
	return true


func holds_melee(enemy: Object) -> bool:
	return _melee.has(enemy.get_instance_id())


func release(enemy: Object) -> void:
	_melee.erase(enemy.get_instance_id())


## True (and the shot is recorded) unless another archer fired within the last RANGED_WINDOW_S
func try_fire_ranged(archer: Object, now_s: float) -> bool:
	var id := archer.get_instance_id()
	if id != _last_shooter and now_s - _last_shot_s < RANGED_WINDOW_S - TIME_EPSILON:
		return false
	_last_shot_s = now_s
	_last_shooter = id
	return true


# Drops holders that were freed or died without releasing
func _prune() -> void:
	for i in range(_melee.size() - 1, -1, -1):
		var holder := instance_from_id(_melee[i])
		if holder == null or (holder.has_method("is_dead") and holder.is_dead()):
			_melee.remove_at(i)
