extends GdUnitTestSuite

# The motion review's game-path pass (scripts/review/game_path.gd): clips driven through the same
# AnimationPlayer.play() and per-frame advance the game uses (blend times included), not seek(), and a
# derivative gate on hand and foot speed in the character's own frame across each handover. The gate's
# tolerance is the art bible's motion_handover_snap_mps (docs/art-bible.md → Judge tolerances).
# Ideas after htdt/godogen asset-gen/motion.md pitfalls 16 and 18 (MIT; no code copied).

const GamePath := preload("res://scripts/review/game_path.gd")
const FPS := 60.0
const JUMP := 0.3  # m: the left hand's offset between the two test clips


# A five-bone stand-in character: Hips with both hands and feet, packed like a model GLB
func _model() -> PackedScene:
	var root := Node3D.new()
	root.name = "Model"
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	sk.owner = root
	sk.add_bone("Hips")
	sk.set_bone_rest(0, Transform3D(Basis(), Vector3(0, 1, 0)))
	var rests := {
		"LeftHand": Vector3(0.4, 0.5, 0),
		"RightHand": Vector3(-0.4, 0.5, 0),
		"LeftFoot": Vector3(0.1, -0.9, 0),
		"RightFoot": Vector3(-0.1, -0.9, 0)
	}
	for bone: String in rests:
		var i := sk.get_bone_count()
		sk.add_bone(bone)
		sk.set_bone_parent(i, 0)
		sk.set_bone_rest(i, Transform3D(Basis(), rests[bone]))
	sk.reset_bone_poses()
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


# idle (looping) holds the left hand at rest; attack (one-shot) holds it JUMP metres to the side
func _library() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	for clip_name in ["idle", "attack"]:
		var a := Animation.new()
		a.length = 0.5 if clip_name == "attack" else 1.0
		a.loop_mode = Animation.LOOP_NONE if clip_name == "attack" else Animation.LOOP_LINEAR
		var t := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(t, NodePath("Skeleton3D:LeftHand"))
		var p := Vector3(0.4 + (JUMP if clip_name == "attack" else 0.0), 0.5, 0)
		a.position_track_insert_key(t, 0.0, p)
		a.position_track_insert_key(t, a.length, p)
		lib.add_animation(clip_name, a)
	return lib


func _pair(from: String, to: String, settings: Dictionary) -> Dictionary:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)
	return GamePath.measure_pair(holder, _model(), _library(), from, to, settings, FPS)


func test_a_hard_cut_reads_as_a_snap_at_the_handover() -> void:
	var r := _pair("idle", "attack", {})
	# The hand crosses JUMP metres in one frame; neither clip moves it on its own
	assert_float(r["snap_excess_mps"]).is_between(JUMP * FPS - 1.0, JUMP * FPS + 1.0)
	assert_str(r["peak_limb"]).is_equal("left_hand")
	assert_float(r["blend_s"]).is_equal(0.0)


func test_a_crossfade_spreads_the_handover() -> void:
	var r := _pair("idle", "attack", {"playback_default_blend_time": 0.3})
	assert_float(r["blend_s"]).is_equal_approx(0.3, 0.001)
	# JUMP over 0.3 s is about 1 m/s; well under the hard cut's 18
	assert_float(r["snap_excess_mps"]).is_less(2.5)


func test_the_expected_clip_plays_and_settles_on_its_own_pose() -> void:
	var r := _pair("idle", "attack", {"playback_default_blend_time": 0.1})
	assert_int(r["wrong_clip_frames"]).is_equal(0)
	assert_float(r["settle_error_m"]).is_less(0.005)


func test_a_one_shot_hands_over_when_it_finishes() -> void:
	var r := _pair("attack", "idle", {})
	assert_float(r["snap_excess_mps"]).is_between(JUMP * FPS - 1.0, JUMP * FPS + 1.0)
	assert_int(r["wrong_clip_frames"]).is_equal(0)


func test_check_frames_counts_the_wrong_clip_and_a_frozen_clip() -> void:
	var dt := 1.0 / FPS
	var samples := [
		{"clip": "attack", "position": dt},
		{"clip": "attack", "position": 2 * dt},
		{"clip": "idle", "position": 0.5},  # the previous move still playing
		{"clip": "attack", "position": 2 * dt},  # frozen: a seeked clip doesn't advance
		{"clip": "attack", "position": 3 * dt},
	]
	assert_int(GamePath.check_frames(samples, "attack", 0.5)).is_equal(2)


func test_handovers_follow_the_game_and_the_library() -> void:
	var pairs := GamePath.handovers(PackedStringArray(["idle", "run", "attack", "death"]))
	assert_array(pairs).contains([["idle", "run"], ["run", "idle"], ["idle", "attack"], ["attack", "run"]])
	assert_array(pairs).not_contains([["idle", "stagger"]])


func test_the_game_scenes_animation_player_settings_are_read() -> void:
	# Player.tscn's AnimationPlayer sets no blend times today; the pass must read them, not assume them
	var settings := GamePath.game_settings("res://scenes/player/Player.tscn")
	assert_bool(settings.has("libraries")).is_false()
	assert_bool(settings.has("root_node")).is_false()
	assert_str(GamePath.scene_for_library("res://data/animations/levy_backfile_library.tres")).is_equal(
		"res://scenes/enemies/ArcherEnemy.tscn"
	)
