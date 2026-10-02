extends GdUnitTestSuite

# The motion review's game-path pass (scripts/review/game_path.gd): clips driven through the same
# AnimationPlayer.play() and per-frame advance the game uses (blend times included), not seek(), and a
# derivative gate on hand and foot speed in the character's own frame across each handover. The gate's
# tolerance is the art bible's motion_handover_snap_mps (docs/art-bible.md → Judge tolerances).
# Ideas after htdt/godogen asset-gen/motion.md pitfalls 16 and 18 (MIT; no code copied).

const GamePath := preload("res://scripts/review/game_path.gd")
const BaseEnemy := preload("res://scenes/enemies/BaseEnemy.gd")
const ArcherEnemy := preload("res://scenes/enemies/ArcherEnemy.gd")
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


# idle (looping) holds the left hand at rest; the one-shots (attack, which the game can cut short and
# which has a tell, and attack_light) hold it JUMP metres to the side
func _library() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	for clip_name in ["idle", "attack", "attack_light"]:
		var a := Animation.new()
		var one_shot: bool = clip_name != "idle"
		a.length = 0.5 if one_shot else 1.0
		a.loop_mode = Animation.LOOP_NONE if one_shot else Animation.LOOP_LINEAR
		var t := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(t, NodePath("Skeleton3D:LeftHand"))
		var p := Vector3(0.4 + (JUMP if one_shot else 0.0), 0.5, 0)
		a.position_track_insert_key(t, 0.0, p)
		a.position_track_insert_key(t, a.length, p)
		if clip_name == "attack":
			a.add_marker("tell", 0.2)
			a.add_marker("contact", 0.3)
		lib.add_animation(clip_name, a)
	return lib


func _pair(from: String, to: String, settings: Dictionary, windup := 0.0) -> Dictionary:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)
	return GamePath.measure_pair(holder, _model(), _library(), from, to, settings, FPS, {}, windup)


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
	var r := _pair("attack_light", "idle", {})
	assert_float(r["snap_excess_mps"]).is_between(JUMP * FPS - 1.0, JUMP * FPS + 1.0)
	assert_int(r["wrong_clip_frames"]).is_equal(0)
	assert_int(r["phases"]).is_equal(1)


func test_a_one_shot_the_game_cuts_short_hands_over_mid_clip() -> void:
	# A levy's swing goes back to the chase when its active time ends, before the clip does
	assert_array(GamePath.CUTS).contains([["attack", "idle"]])
	var r := _pair("attack", "idle", {})
	assert_int(r["phases"]).is_equal(GamePath.LOOP_PHASES.size())
	assert_float(r["snap_excess_mps"]).is_between(JUMP * FPS - 1.0, JUMP * FPS + 1.0)
	assert_int(r["wrong_clip_frames"]).is_equal(0)


func test_a_windup_is_posed_as_the_game_poses_it() -> void:
	# Eased into the tell, held, then played on from contact; the crossfade from idle runs meanwhile
	var r := _pair("idle", "attack", {"playback_default_blend_time": 0.2}, 0.6)
	assert_float(r["windup_s"]).is_equal_approx(0.6, 0.001)
	assert_int(r["wrong_clip_frames"]).is_equal(0)
	assert_float(r["snap_excess_mps"]).is_less(2.5)
	assert_float(r["settle_error_m"]).is_less(0.005)


func test_a_scenes_windup_is_its_scripts() -> void:
	assert_float(GamePath.scene_windup("res://scenes/enemies/BaseEnemy.tscn")).is_equal(BaseEnemy.MELEE_WINDUP)
	assert_float(GamePath.scene_windup("res://scenes/enemies/ArcherEnemy.tscn")).is_equal(ArcherEnemy.DRAW_TIME)
	assert_float(GamePath.scene_windup("res://scenes/player/Player.tscn")).is_equal(0.0)


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
	# The pass reads the scene's own blend settings, never assumes them
	var settings := GamePath.game_settings("res://scenes/player/Player.tscn")
	assert_bool(settings.has("libraries")).is_false()
	assert_bool(settings.has("root_node")).is_false()
	assert_bool(settings.has("playback_default_blend_time")).is_true()
	assert_bool(settings.has("blend_times")).is_true()
	assert_str(GamePath.scene_for_library("res://data/animations/levy_backfile_library.tres")).is_equal(
		"res://scenes/enemies/ArcherEnemy.tscn"
	)
