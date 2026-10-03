extends GdUnitTestSuite

# Each character's `run` clip at the speed its scene moves it: planted feet may slide no more than the
# art bible's motion_foot_slide_bhps, in body heights per second (docs/art-bible.md → Judge tolerances, the
# only source; every humanoid is 1.8 m, where it is the old 0.5 m/s). Measured
# as the motion review measures it (scripts/review/foot_slide.gd), on the bones, so it runs headless.
# A gameplay speed and a clip's playback (build_animation_library.gd) that drift apart fail here.
# Locomotion follows the clip (the asset-pipeline skill → Locomotion rule): fix a failure by moving the
# gameplay speed, keeping playback within 0.75–1.5×.

const FootSlide := preload("res://scripts/review/foot_slide.gd")
const ART_BIBLE := "res://docs/art-bible.md"
const FPS := 30.0


func _tolerance(key: String) -> float:
	for line in FileAccess.get_file_as_string(ART_BIBLE).split("\n"):
		if line.begins_with("| `%s` |" % key):
			return float(line.split("|")[2].strip_edges())
	fail("no %s in %s → Judge tolerances" % [key, ART_BIBLE])
	return 0.0


# p90 foot slide of the scene's `run` clip at the scene's own gameplay speed, on a fresh copy of its
# model at the origin (facing +Z, as in the motion review), in body heights per second
func _run_slide(scene_path: String, model_node: String, speed: float) -> float:
	var scene: Node = auto_free((load(scene_path) as PackedScene).instantiate())
	var model_path: String = scene.get_node(model_node).scene_file_path
	var lib: AnimationLibrary = (
		(scene.get_node(model_node + "/AnimationPlayer") as AnimationPlayer).get_animation_library("")
	)
	var model: Node3D = auto_free((load(model_path) as PackedScene).instantiate())
	add_child(model)
	var ap := AnimationPlayer.new()
	model.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library("", lib)
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var clip := lib.get_animation("run")
	ap.play("run")
	var t := []
	var samples := []
	for f in int(ceil(clip.length * FPS)) + 1:
		t.append(minf(f / FPS, clip.length))
		ap.seek(t[-1], true)
		samples.append(FootSlide.feet(sk))
	var looping := clip.loop_mode != Animation.LOOP_NONE
	var height := FootSlide.body_height(sk, model)
	var fs := FootSlide.measure(t, samples, speed, looping, height / FootSlide.REFERENCE_HEIGHT)
	return fs["foot_slide_p90_mps"] / height


func _stats_speed(scene_path: String) -> float:
	var node: Node = auto_free((load(scene_path) as PackedScene).instantiate())
	return (node.get("stats") as CharacterStats).speed


func test_player_run_foot_slide() -> void:
	var player: Node = auto_free((load("res://scenes/player/Player.tscn") as PackedScene).instantiate())
	var slide := _run_slide("res://scenes/player/Player.tscn", "PlayerModel", player.get("move_speed"))
	assert_float(slide).is_less_equal(_tolerance("motion_foot_slide_bhps"))


func test_frontfile_run_foot_slide() -> void:
	var path := "res://scenes/enemies/BaseEnemy.tscn"
	var slide := _run_slide(path, "SkeletonModel", _stats_speed(path))
	assert_float(slide).is_less_equal(_tolerance("motion_foot_slide_bhps"))


func test_backfile_run_foot_slide() -> void:
	var path := "res://scenes/enemies/ArcherEnemy.tscn"
	var slide := _run_slide(path, "SkeletonModel", _stats_speed(path))
	assert_float(slide).is_less_equal(_tolerance("motion_foot_slide_bhps"))
