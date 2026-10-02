extends RefCounted

## Attack tokens for one target (design bible §3 and §9, `enemy_attackers_max`): at most MELEE_MAX melee
## enemies engage the target at once, and only one archer fires at it in any RANGED_WINDOW_S. The target
## carries its tokens in its metadata (BaseEnemy._attack_tokens()), so they go when its scene is freed.
## Holders are kept by instance ID, so a freed enemy's token is reclaimed rather than read after free.
## A holder that goes (dies, is freed or gives up the chase) keeps its token reserved until MELEE_WINDOW_S
## after its last attack started, so no 2 s window ever counts more than MELEE_MAX melee attackers; one that
## hasn't attacked within the window hands it on at once.

const META := &"attack_tokens"
const MELEE_MAX := 2
const RANGED_WINDOW_S := 2.0
## The window over which melee attackers are counted (the replay's enemy_attackers_max uses the same 2 s)
const MELEE_WINDOW_S := 2.0
## Shot times come from physics frames (frame / ticks per second); this absorbs their float rounding
const TIME_EPSILON := 1e-6

var _melee: Array[int] = []
## Instance ID -> time its last melee attack started
var _last_attack_s: Dictionary[int, float] = {}
## Instance ID of a holder that went -> time its token frees up
var _reserved_until: Dictionary[int, float] = {}
var _last_shot_s: float = -INF
var _last_shooter: int = 0


## True when `enemy` holds, or now takes, one of the melee tokens. `now_s` is physics time; left out, every
## reservation counts as expired.
func try_acquire_melee(enemy: Object, now_s: float = INF) -> bool:
	var id := enemy.get_instance_id()
	if _melee.has(id):
		return true
	_reserved_until.erase(id)  # its own reserved token
	_prune(now_s)
	if _melee.size() + _reserved_until.size() >= MELEE_MAX:
		return false
	_melee.append(id)
	return true


## Records that `enemy` (a holder) started a melee attack at `now_s`
func note_melee_attack(enemy: Object, now_s: float) -> void:
	_last_attack_s[enemy.get_instance_id()] = now_s


func holds_melee(enemy: Object) -> bool:
	return _melee.has(enemy.get_instance_id())


func release(enemy: Object) -> void:
	_vacate(enemy.get_instance_id())


## True (and the shot is recorded) unless another archer fired within the last RANGED_WINDOW_S
func try_fire_ranged(archer: Object, now_s: float) -> bool:
	var id := archer.get_instance_id()
	if id != _last_shooter and now_s - _last_shot_s < RANGED_WINDOW_S - TIME_EPSILON:
		return false
	_last_shot_s = now_s
	_last_shooter = id
	return true


# Gives up `id`'s token, reserved until its last attack's window ends
func _vacate(id: int) -> void:
	if not _melee.has(id):
		return
	_melee.erase(id)
	if _last_attack_s.has(id):
		_reserved_until[id] = _last_attack_s[id] + MELEE_WINDOW_S
		_last_attack_s.erase(id)


# Vacates holders that were freed or died without releasing, and drops reservations whose window has ended
func _prune(now_s: float) -> void:
	for i in range(_melee.size() - 1, -1, -1):
		var holder := instance_from_id(_melee[i])
		if holder == null or (holder.has_method("is_dead") and holder.is_dead()):
			_vacate(_melee[i])
	for id: int in _reserved_until.keys():
		if now_s >= _reserved_until[id] - TIME_EPSILON:
			_reserved_until.erase(id)
