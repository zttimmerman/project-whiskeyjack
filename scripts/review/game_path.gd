extends RefCounted

# The motion review's game-path pass, shared with its test (tests/unit/test_motion_game_path.gd).
# The review's other measurements scrub each clip with seek(), which never runs a crossfade; the game
# plays clips with AnimationPlayer.play() from whatever was playing (BaseEnemy and Player _play_anim),
# so this pass drives each handover the game makes (HANDOVERS: idle → attack, run → idle, an attack's
# end → locomotion, ...) the same way: play() with the game scene's own AnimationPlayer settings
# (blend times included), advanced one physics frame at a time. Per frame it samples both hands and
# feet in the character's own frame (the model root's: the body's travel and turning don't count) and
# measures:
# - snap_excess_mps: across the handover (from the frame before it to three frames after the blend),
#   how much faster any hand or foot moves than that limb ever moves in either clip played on its own:
#   a pose snap. Gated by the art bible's motion_handover_snap_mps (docs/art-bible.md → Judge
#   tolerances, the only source);
# - wrong_clip_frames: frames after the handover where another clip is current or the clip doesn't
#   advance (a seeked or paused clip freezes a crossfade, and the previous move plays on);
# - settle_error_m: after the blend, the largest hand or foot distance from the clip's own pose at
#   the same time (the previous move must be gone).
# A looping "from" clip is handed over at four phases (a quarter, half, three quarters and all of its
# length), the worst kept; a one-shot hands over when it finishes, from its animation_finished signal,
# as the game does, unless the game cuts it short (CUTS: a stagger, dodge or death mid-attack, a levy's
# swing handed back to the chase when its active time ends), which is measured at the loop phases.
# An enemy's windup (the scene's _windup_time(), BaseEnemy) is driven as BaseEnemy drives it, through
# scripts/combat/AttackWindup.gd: posed by seek() at speed 0 through the tell, then played on from the
# contact marker; the window covers the whole windup.
# Ideas after htdt/godogen asset-gen/motion.md pitfalls 16 and 18 (MIT; no code copied).

const LIMBS := {"left_hand": "LeftHand", "right_hand": "RightHand", "left_foot": "LeftFoot", "right_foot": "RightFoot"}
# [from, to]: the handovers BaseEnemy, ArcherEnemy and Player make, by the clip names they play
const HANDOVERS := [
	["idle", "run"],
	["run", "idle"],
	["idle", "attack"],
	["run", "attack"],
	["attack", "idle"],
	["attack", "run"],
	["idle", "stagger"],
	["run", "stagger"],
	["stagger", "idle"],
	["stagger", "run"],
	["idle", "death"],
	["run", "death"],
	["attack", "death"],
	["stagger", "death"],
	["idle", "attack_light"],
	["run", "attack_light"],
	["attack_light", "idle"],
	["attack_light", "run"],
	["idle", "attack_heavy"],
	["run", "attack_heavy"],
	["attack_heavy", "idle"],
	["attack_heavy", "run"],
	["idle", "dodge_roll"],
	["run", "dodge_roll"],
	["dodge_roll", "idle"],
	["dodge_roll", "run"],
	["dodge_roll", "attack_light"],
	["dodge_roll", "attack_heavy"],
	["attack", "stagger"],
	["attack_light", "dodge_roll"],
	["attack_heavy", "dodge_roll"],
	["attack_light", "attack_heavy"],
	["attack_heavy", "attack_light"],
	["attack_light", "death"],
	["attack_heavy", "death"],
]
# One-shot handovers the game makes before the clip ends (measured at LOOP_PHASES, not at the finish)
const CUTS := [
	["attack", "idle"],
	["attack", "run"],
	["attack", "stagger"],
	["attack", "death"],
	["stagger", "death"],
	["attack_light", "dodge_roll"],
	["attack_heavy", "dodge_roll"],
	["attack_light", "attack_heavy"],
	["attack_heavy", "attack_light"],
	["attack_light", "death"],
	["attack_heavy", "death"],
]
const LOOP_PHASES := [0.25, 0.5, 0.75, 1.0]
const AFTER_BLEND_FRAMES := 3
const SETTLE_FRAMES := 3
const SKIP_SETTINGS := ["libraries", "root_node", "script"]
const AttackWindup := preload("res://scripts/combat/AttackWindup.gd")


# The HANDOVERS whose two clips are both in the library
static func handovers(names: PackedStringArray) -> Array:
	return HANDOVERS.filter(func(p: Array) -> bool: return p[0] in names and p[1] in names)


# The AnimationPlayer properties the game scene sets (blend times, default blend, speed), read from the
# scene file without instancing it (no game script runs)
static func game_settings(scene_path: String) -> Dictionary:
	var out := {}
	var state := (load(scene_path) as PackedScene).get_state()
	for i in state.get_node_count():
		if state.get_node_type(i) != "AnimationPlayer":
			continue
		for p in state.get_node_property_count(i):
			var prop := String(state.get_node_property_name(i, p))
			if not prop in SKIP_SETTINGS:
				out[prop] = state.get_node_property_value(i, p)
		break
	return out


# The game scene's windup in seconds (its root script's _windup_time(): BaseEnemy and ArcherEnemy), 0
# for a scene without one. The script is instanced on its own, outside the tree, so _ready() never runs.
static func scene_windup(scene_path: String) -> float:
	var state := (load(scene_path) as PackedScene).get_state()
	for p in state.get_node_property_count(0):
		if state.get_node_property_name(0, p) != "script":
			continue
		var script: Script = state.get_node_property_value(0, p)
		var inst: Object = script.new()
		var windup: float = inst.call("_windup_time") if inst.has_method("_windup_time") else 0.0
		inst.free()
		return windup
	return 0.0


# The first scene under res://scenes that loads the library (the scene whose AnimationPlayer plays it)
static func scene_for_library(library_path: String) -> String:
	var found := _scenes_with('path="%s"' % library_path, "res://scenes")
	found.sort()
	return found[0] if not found.is_empty() else ""


static func _scenes_with(needle: String, dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tscn") and FileAccess.get_file_as_string(dir.path_join(f)).contains(needle):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scenes_with(needle, dir.path_join(d)))
	return out


# Every handover in the library, each its worst phase
static func measure_all(
	holder: Node, model: PackedScene, lib: AnimationLibrary, settings: Dictionary, fps: float, windup := 0.0
) -> Array:
	var steady := {}
	var out := []
	for pair in handovers(lib.get_animation_list()):
		out.append(measure_pair(holder, model, lib, pair[0], pair[1], settings, fps, steady, windup))
	return out


# One handover, from `from` to `to`; `steady` caches each clip's own limb speeds between calls, and
# `windup` (seconds) drives a `to` clip with tell and contact markers through an enemy's windup
static func measure_pair(
	holder: Node,
	model: PackedScene,
	lib: AnimationLibrary,
	from: String,
	to: String,
	settings: Dictionary,
	fps: float,
	steady := {},
	windup := 0.0
) -> Dictionary:
	for clip in [from, to]:
		if not steady.has(clip):
			steady[clip] = _steady_peaks(holder, model, lib, clip, settings, fps)
	var own := {}
	for limb in LIMBS:
		own[limb] = maxf(steady[from].get(limb, 0.0), steady[to].get(limb, 0.0))
	var phased := lib.get_animation(from).loop_mode != Animation.LOOP_NONE or [from, to] in CUTS
	var worst := {}
	for phase in LOOP_PHASES if phased else [-1.0]:
		var r := _handover(holder, model, lib, from, to, phase, settings, fps, own, windup)
		if worst.is_empty() or r["snap_excess_mps"] > worst["snap_excess_mps"]:
			worst = r
	worst["phases"] = LOOP_PHASES.size() if phased else 1
	return worst


# Hands and feet in the model root's frame
static func limb_points(root: Node3D, sk: Skeleton3D) -> Dictionary:
	var out := {}
	var to_root := root.global_transform.affine_inverse() * sk.global_transform
	for limb: String in LIMBS:
		var i := sk.find_bone(LIMBS[limb])
		if i >= 0:
			out[limb] = (to_root * sk.get_bone_global_pose(i)).origin
	return out


# Frames where the clip isn't `to` or doesn't advance (a one-shot held at its end, and a loop wrapping,
# are fine). A sample with an "expected" position (a windup's posed frames) must be at it instead.
static func check_frames(samples: Array, to: String, to_length: float) -> int:
	var wrong := 0
	var prev := -1.0
	for s: Dictionary in samples:
		var pos: float = s["position"]
		var advancing: bool = prev < 0.0 or pos > prev or pos >= to_length - 0.0001 or pos < prev - to_length * 0.5
		if s.has("expected"):
			advancing = absf(pos - float(s["expected"])) < 0.001
		if s["clip"] != to:
			wrong += 1
			continue  # advancing is judged between frames of `to` itself
		if not advancing:
			wrong += 1
		prev = pos
	return wrong


static func _spawn(holder: Node, model: PackedScene, lib: AnimationLibrary, settings: Dictionary) -> Dictionary:
	var root: Node3D = model.instantiate()
	holder.add_child(root)
	var ap := AnimationPlayer.new()
	root.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library("", lib)
	for prop: String in settings:
		ap.set(prop, settings[prop])
	# Advanced by hand, one physics frame per step, so the run is deterministic
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	return {"root": root, "ap": ap, "sk": sk}


static func _sample(inst: Dictionary) -> Dictionary:
	var ap: AnimationPlayer = inst["ap"]
	var clip := String(ap.current_animation)
	return {
		"clip": clip,
		"position": ap.current_animation_position if clip != "" else 0.0,
		"limbs": limb_points(inst["root"], inst["sk"])
	}


static func _speeds(a: Dictionary, b: Dictionary, fps: float) -> Dictionary:
	var out := {}
	for limb in b["limbs"]:
		if a["limbs"].has(limb):
			out[limb] = (b["limbs"][limb] as Vector3).distance_to(a["limbs"][limb]) * fps
	return out


# Each limb's top speed over the clip played on its own (a loop includes its wrap)
static func _steady_peaks(
	holder: Node, model: PackedScene, lib: AnimationLibrary, clip: String, settings: Dictionary, fps: float
) -> Dictionary:
	var inst := _spawn(holder, model, lib, settings)
	var ap: AnimationPlayer = inst["ap"]
	ap.play(clip)
	var peaks := {}
	var prev := {}
	for f in int(ceil(lib.get_animation(clip).length * fps)) + 2:
		ap.advance(1.0 / fps)
		var s := _sample(inst)
		if f > 0:
			var sp := _speeds(prev, s, fps)
			for limb in sp:
				peaks[limb] = maxf(peaks.get(limb, 0.0), sp[limb])
		prev = s
	inst["root"].free()
	return peaks


static func _blend_time(ap: AnimationPlayer, from: String, to: String) -> float:
	var pair := ap.get_blend_time(from, to)
	return pair if pair > 0.0 else ap.playback_default_blend_time


# phase < 0: `from` is a one-shot and hands over when it finishes. With a windup, `to` (when it has
# tell and contact markers) is posed through it as BaseEnemy does (AttackWindup), from a phased handover.
static func _handover(
	holder: Node,
	model: PackedScene,
	lib: AnimationLibrary,
	from: String,
	to: String,
	phase: float,
	settings: Dictionary,
	fps: float,
	own: Dictionary,
	windup := 0.0
) -> Dictionary:
	var inst := _spawn(holder, model, lib, settings)
	var ap: AnimationPlayer = inst["ap"]
	var blend := _blend_time(ap, from, to)
	var from_len := lib.get_animation(from).length
	var to_clip := lib.get_animation(to)
	var to_len := to_clip.length
	var winding := phase >= 0.0 and windup > 0.0 and AttackWindup.position(to_clip, windup, 0.0) >= 0.0
	var elapsed := 0.0
	var handed := [false]
	if phase < 0.0:
		# As Player/BaseEnemy _on_animation_finished: the next clip starts from the finished signal
		ap.animation_finished.connect(
			func(n: StringName) -> void:
				if n == from and not handed[0]:
					handed[0] = true
					ap.play(to)
		)
	ap.play(from)
	var samples := []
	var h := -1  # index of the first sample taken after play(to)
	var lead := maxi(1, roundi(phase * from_len * fps)) if phase >= 0.0 else int(ceil(from_len * fps)) + 5
	for f in lead:
		ap.advance(1.0 / fps)
		samples.append(_sample(inst))
		if handed[0]:
			h = samples.size() - 1
			break
	if h < 0:
		if phase < 0.0:
			inst["root"].free()
			return {"from": from, "to": to, "error": "%s never finished" % from, "snap_excess_mps": -1.0}
		h = samples.size()
		# The game's state change, in its physics step
		if winding:
			AttackWindup.begin(ap, to)
			ap.seek(AttackWindup.position(to_clip, windup, 0.0), true)
		else:
			ap.play(to)
	var span := blend
	var to_frames := int(ceil(to_len * fps)) - 1
	if winding:
		span = maxf(blend, windup)
		to_frames = int(ceil((windup + to_len - to_clip.get_marker_time("contact")) * fps)) - 1
	var window_end := h + int(ceil(span * fps)) + AFTER_BLEND_FRAMES
	var stop := mini(window_end + SETTLE_FRAMES, h + maxi(to_frames, 1))
	var posed := -1.0
	while samples.size() <= maxi(stop, h):
		if winding and samples.size() > h:
			# BaseEnemy._tick_attack: the windup's clock, its pose, and the release at its end
			elapsed = minf(elapsed + 1.0 / fps, windup)
			posed = AttackWindup.position(to_clip, windup, elapsed)
			ap.seek(posed, true)
			if elapsed >= windup - 0.0001:
				winding = false
				AttackWindup.release(ap, to, 1.0 / fps)  # the next advance lands on contact itself
		elif winding:
			posed = AttackWindup.position(to_clip, windup, 0.0)
		ap.advance(1.0 / fps)
		var s := _sample(inst)
		if posed >= 0.0:
			s["expected"] = posed
		posed = -1.0
		samples.append(s)
	# The snap: limb speed above either clip's own top speed, across the handover
	var best := {"excess": 0.0, "speed": 0.0, "limb": "", "frame": -1}
	for i in range(maxi(h - 1, 1), mini(window_end, samples.size() - 1) + 1):
		var sp := _speeds(samples[i - 1], samples[i], fps)
		for limb in sp:
			var excess: float = sp[limb] - own.get(limb, 0.0)
			if best["limb"] == "" or excess > best["excess"]:
				best = {"excess": excess, "speed": sp[limb], "limb": limb, "frame": i - h}
	var wrong := check_frames(samples.slice(h), to, to_len)
	# After the blend the pose must be the clip's own at the same time
	var last: Dictionary = samples[-1]
	var ref := _spawn(holder, model, lib, settings)
	(ref["ap"] as AnimationPlayer).play(to)
	(ref["ap"] as AnimationPlayer).seek(last["position"], true)
	var own_pose := limb_points(ref["root"], ref["sk"])
	ref["root"].free()
	var settle := 0.0
	for limb in own_pose:
		settle = maxf(settle, (own_pose[limb] as Vector3).distance_to(last["limbs"].get(limb, own_pose[limb])))
	inst["root"].free()
	return {
		"from": from,
		"to": to,
		"handover_at_s": snappedf((h if phase >= 0.0 else h + 1) / fps, 0.001),
		"blend_s": snappedf(blend, 0.001),
		"windup_s": snappedf(windup, 0.001) if span > blend else 0.0,
		"snap_excess_mps": snappedf(maxf(best["excess"], 0.0), 0.01),
		"peak_mps": snappedf(best["speed"], 0.01),
		"peak_limb": best["limb"],
		"peak_frame_after_handover": best["frame"],
		"own_peak_mps": snappedf(own.get(best["limb"], 0.0), 0.01),
		"wrong_clip_frames": wrong,
		"settle_error_m": snappedf(settle, 0.001),
		"settle_frames_after_handover": samples.size() - 1 - h
	}
