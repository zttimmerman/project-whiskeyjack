extends SceneTree

# Builds the shared animation set from the Quaternius Universal Animation Library (retargeted onto
# SkeletonProfileHumanoid by the GLBs' import settings), then one AnimationLibrary per character
# that maps the names the code plays onto those clips. Deterministic; re-run after editing:
#   godot --headless --path . -s scripts/tools/build_animation_library.gd
#
# Each clip is resampled at SAMPLE_FPS, so speed and trim are baked into the resource instead of
# distorting playback at runtime, and only tracks for bones the characters have are kept (the
# library's finger tracks are dropped). Identical clip specs are saved once and shared.
# The mapping mirrors the table in .claude/skills/asset-pipeline/SKILL.md → Animation library.

const SAMPLE_FPS := 30.0
const SOURCES := {
	"UAL1": "res://assets/animations/quaternius/UAL1_Standard.glb",
	"UAL2": "res://assets/animations/quaternius/UAL2_Standard.glb",
}
# The characters' bones after retargeting (the mixamorig BoneMap's profile names)
const CHARACTER_BONES := [
	"Root",
	"Hips",
	"Spine",
	"Chest",
	"UpperChest",
	"Neck",
	"Head",
	"LeftShoulder",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightShoulder",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"LeftToes",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
	"RightToes"
]

# code name -> [pack, clip, options]. Options: loop (bool), speed (playback multiplier baked in),
# trim ([start, end] seconds of the source), in_place (bool: hold Hips/Root horizontal position at
# the first frame, so a clip with travel baked in (Death01 falls backward) plays on the spot).
const LIBRARIES := {
	"player":
	{
		"idle": ["UAL1", "Sword_Idle", {"loop": true}],
		"run": ["UAL1", "Jog_Fwd_Loop", {"loop": true, "speed": 0.93}],  # 5.36 m/s native, player moves at 5.0
		"dodge_roll": ["UAL1", "Roll", {"trim": [0.20, 1.10], "speed": 1.8}],  # roll core fitted into the 0.5 s dodge
		"attack_light": ["UAL2", "Sword_Regular_A", {}],
		"attack_heavy": ["UAL2", "Sword_Regular_C", {}],
		"death": ["UAL1", "Death01", {"in_place": true}],
	},
	"levy_frontfile":
	{
		"idle": ["UAL1", "Sword_Idle", {"loop": true}],
		"run": ["UAL1", "Jog_Fwd_Loop", {"loop": true, "speed": 0.75}],  # levy feet at 4.6 m/s: BaseEnemy speed
		# the longest readable lead-in in the Standard packs: the blade rises overhead for 0.32 s
		"attack": ["UAL1", "Sword_Attack", {}],
		"stagger": ["UAL1", "Hit_Chest", {}],
		"death": ["UAL1", "Death01", {"in_place": true}],
	},
	"levy_backfile":
	{
		"idle": ["UAL1", "Idle_Loop", {"loop": true}],
		# levy feet at 1.5 m/s: ArcherEnemy speed matches (Walk_Formal clasps the hands behind the back)
		"run": ["UAL1", "Walk_Loop", {"loop": true, "speed": 1.44}],
		# STAND-IN: no bow-draw clip in either Standard pack; this raises the bow arm to aim
		"attack": ["UAL1", "Spell_Simple_Enter", {}],
		"stagger": ["UAL1", "Hit_Chest", {}],
		"death": ["UAL1", "Death01", {"in_place": true}],
	},
}

# Timing marks on a source clip, in source seconds, added to every clip built from it as Animation
# markers (shifted by its trim, scaled by its speed). "tell" is the anticipation pose an enemy holds
# through its windup (BaseEnemy), "contact" the strike or the release. Measured on the Barrow-levy
# from RightHand speed: the wind-back ends where the hand starts to accelerate, contact is the peak.
# A clip swap re-measures them here; the windup lengths are gameplay constants and don't move with it.
const MARKERS := {
	"Sword_Regular_A": {"tell": 0.17, "contact": 0.25},  # the player's light attack (for atk_hitbox_sync)
	"Sword_Attack": {"tell": 0.32, "contact": 0.38},  # blade overhead, then the downward cut
	"Spell_Simple_Enter": {"tell": 0.47, "contact": 0.53},  # STAND-IN draw: bow arm raised and aimed
}

var _sources := {}
var _built := {}
var _failed := false
var _scenes: Array[Node] = []


func _init() -> void:
	for pack in SOURCES:
		var scene: Node = (load(SOURCES[pack]) as PackedScene).instantiate()
		_scenes.append(scene)
		_sources[pack] = scene.find_children("*", "AnimationPlayer", true, false)[0]
	DirAccess.make_dir_recursive_absolute("res://data/animations/clips")
	for lib_name in LIBRARIES:
		var lib := AnimationLibrary.new()
		for code_name in LIBRARIES[lib_name]:
			var spec: Array = LIBRARIES[lib_name][code_name]
			lib.add_animation(code_name, _clip(spec[0], spec[1], spec[2]))
		var path := "res://data/animations/%s_library.tres" % lib_name
		var err := ResourceSaver.save(lib, path)
		print("LIBRARY ", path, " ", lib.get_animation_list(), " err ", err)
		if err != OK:
			_fail("build_animation_library: couldn't save %s (%s)" % [path, error_string(err)])
		else:
			_check_saved(lib, path)
	for scene: Node in _scenes:
		scene.free()  # the source packs, so nothing leaks at exit
	quit(1 if _failed else 0)


func _fail(message: String) -> void:
	push_error(message)
	_failed = true


# The saved library, read back from disk, must hold the clips that were built: same names, lengths,
# loop modes, track paths and markers (a silently dropped clip or track would otherwise ship).
func _check_saved(lib: AnimationLibrary, path: String) -> void:
	var back := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as AnimationLibrary
	if back == null:
		_fail("build_animation_library: %s doesn't load back" % path)
		return
	if back.get_animation_list() != lib.get_animation_list():
		_fail(
			(
				"build_animation_library: %s holds %s, built %s"
				% [path, back.get_animation_list(), lib.get_animation_list()]
			)
		)
		return
	for clip_name in lib.get_animation_list():
		if _clip_signature(back.get_animation(clip_name)) != _clip_signature(lib.get_animation(clip_name)):
			_fail("build_animation_library: %s: clip %s differs after saving" % [path, clip_name])


static func _clip_signature(clip: Animation) -> String:
	var tracks := []
	for t in clip.get_track_count():
		tracks.append("%s:%d:%d" % [clip.track_get_path(t), clip.track_get_type(t), clip.track_get_key_count(t)])
	return "%.4f|%d|%s|%s" % [clip.length, clip.loop_mode, ",".join(tracks), ",".join(clip.get_marker_names())]


func _clip(pack: String, clip: String, opts: Dictionary) -> Animation:
	var speed: float = opts.get("speed", 1.0)
	var trim: Array = opts.get("trim", [])
	var key := (
		"%s%s%s%s"
		% [
			clip,
			("_x%.2f" % speed) if speed != 1.0 else "",
			("_%.2f-%.2f" % [trim[0], trim[1]]) if trim else "",
			"_loop" if opts.get("loop", false) else ""
		]
	)
	if opts.get("in_place", false):
		key += "_inplace"
	if _built.has(key):
		return _built[key]
	# Godot's glTF importer strips a "_Loop" suffix from clip names (and marks the clip looping)
	var player: AnimationPlayer = _sources[pack]
	var src_name := clip if player.has_animation(clip) else clip.trim_suffix("_Loop")
	if not player.has_animation(src_name):
		push_error("no clip %s in %s" % [clip, pack])
		quit(1)
		return null
	var src: Animation = player.get_animation(src_name)
	var t0: float = trim[0] if trim else 0.0
	var t1: float = trim[1] if trim else src.length
	var out := Animation.new()
	out.length = (t1 - t0) / speed
	out.loop_mode = Animation.LOOP_LINEAR if opts.get("loop", false) else Animation.LOOP_NONE
	var frames := int(ceil(out.length * SAMPLE_FPS))
	for i in src.get_track_count():
		var type := src.track_get_type(i)
		var path := src.track_get_path(i)
		if path.get_subname_count() == 0 or not String(path.get_concatenated_subnames()) in CHARACTER_BONES:
			continue
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var t := out.add_track(type)
		out.track_set_path(t, path)
		var hold_xz: bool = (
			opts.get("in_place", false)
			and type == Animation.TYPE_POSITION_3D
			and String(path.get_concatenated_subnames()) in ["Hips", "Root"]
		)
		var first := Vector3.ZERO
		var travel := 0.0
		for f in frames + 1:
			var u: float = minf(f / SAMPLE_FPS, out.length)
			var s: float = t0 + u * speed
			match type:
				Animation.TYPE_POSITION_3D:
					var pos := src.position_track_interpolate(i, s)
					if hold_xz:
						if f == 0:
							first = pos
						travel = maxf(travel, Vector2(pos.x - first.x, pos.z - first.z).length())
						pos = Vector3(first.x, pos.y, first.z)
					out.position_track_insert_key(t, u, pos)
				Animation.TYPE_ROTATION_3D:
					out.rotation_track_insert_key(t, u, src.rotation_track_interpolate(i, s))
				Animation.TYPE_SCALE_3D:
					out.scale_track_insert_key(t, u, src.scale_track_interpolate(i, s))
		if hold_xz:
			print(
				(
					"IN_PLACE %s %s: removed up to %.2f (track units) of horizontal travel"
					% [clip, path.get_concatenated_subnames(), travel]
				)
			)
	var marks: Dictionary = MARKERS.get(clip, {})
	for mark: String in marks:
		var at: float = (float(marks[mark]) - t0) / speed
		if at >= 0.0 and at <= out.length:
			out.add_marker(mark, at)
	var file := "res://data/animations/clips/%s.res" % key
	var err := ResourceSaver.save(out, file)
	print("CLIP ", file, " length %.2f s, %d tracks, err %d" % [out.length, out.get_track_count(), err])
	if err != OK:
		_fail("build_animation_library: couldn't save %s (%s)" % [file, error_string(err)])
	out.take_over_path(file)
	_built[key] = out
	return out
