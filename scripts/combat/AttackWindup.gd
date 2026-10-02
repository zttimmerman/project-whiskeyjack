extends RefCounted

# An enemy attack's windup on its AnimationPlayer (BaseEnemy), shared with the motion review's game-path
# pass (scripts/review/game_path.gd) so the review drives a windup exactly as the game does. No autoloads
# or scene dependencies, so tool scripts can load it.
# The tell: the attack clip eases into its "tell" marker pose (the wind-back), holds it, then plays on so
# its "contact" marker lands as the windup ends. While posed it plays at speed 0 rather than paused: a
# paused AnimationPlayer freezes its crossfade, and the previous clip would hold through the tell.
# A clip without both markers plays as it is.

## Share of the windup before the strike spent easing into the clip's "tell" pose; it's held after
const TELL_WINDBACK_SHARE: float = 0.6


static func begin(anim_player: AnimationPlayer, clip_name: String) -> void:
	anim_player.play(clip_name, -1.0, 0.0 if has_tell(anim_player.get_animation(clip_name)) else 1.0)


## The clip position `elapsed` seconds into a `windup`-second windup, or -1 when the clip has no tell
static func position(clip: Animation, windup: float, elapsed: float) -> float:
	if not has_tell(clip):
		return -1.0
	var tell := clip.get_marker_time("tell")
	var strike_start := maxf(windup - (clip.get_marker_time("contact") - tell), 0.0)
	var windback := clampf(strike_start * TELL_WINDBACK_SHARE, minf(tell, strike_start), strike_start)
	if elapsed < windback:
		return tell * elapsed / windback
	if elapsed >= strike_start:
		return tell + (elapsed - strike_start)
	return tell


## The windup is over (in the physics step, posed at "contact"): the clip plays on at its own speed,
## with no new blend. The AnimationPlayer advances it by the frame's `delta` after the physics step, so
## it starts one step back and the frame shows the contact pose; posed at contact and then advanced, the
## clip would jump two frames at the swing's fastest moment.
static func release(anim_player: AnimationPlayer, clip_name: String, delta: float) -> void:
	if has_tell(anim_player.get_animation(clip_name)):
		anim_player.seek(maxf(anim_player.current_animation_position - delta, 0.0), true)
		anim_player.play(clip_name, 0.0, 1.0)


static func has_tell(clip: Animation) -> bool:
	return clip != null and clip.has_marker("tell") and clip.has_marker("contact")
