extends GdUnitTestSuite

# The motion gates per body size (motion-gates-gait-and-scale, user decision 2026-10-02):
# - the gait check: in a locomotion clip every foot in the limb map lifts above its contact level and swings
#   relative to the root, each by at least a fraction of the body height (art bible motion_gait_lift_bh and
#   motion_gait_swing_bh). Tripo's quadruped walk on the boar passes every other gate with its front legs
#   frozen; the Gobkit walk skates but its legs move.
# - size-relative limits: body height is the rig's bind-pose height (scripts/review/foot_slide.gd
#   body_height()), the slide limit is in body heights per second. Every humanoid is 1.8 m, the reference
#   the metre values were set on, so their results don't change; the 1 m and 4.6 m boars slide alike.
# Measured as the motion review measures it (scripts/review/foot_slide.gd), on the bones, headless.

const FootSlide := preload("res://scripts/review/foot_slide.gd")
const ART_BIBLE := "res://docs/art-bible.md"
const FPS := 30.0
const PLAYER := "res://assets/meshes/player.glb"
const LEVY := "res://assets/meshes/barrow_levy.glb"
const BOAR := "res://assets/meshes/gobkit_Boar.glb"
const BOAR_TRIPO := "res://assets/meshes/gobkit_boar_tripo.glb"
const GOBKIT := "res://data/rigs/gobkit_limbs.tres"
const GOBKIT_TRIPO := "res://data/rigs/gobkit_tripo_limbs.tres"
const TRIPO_WALK := "preset_quadruped_walk"


func _tolerance(key: String) -> float:
	for line in FileAccess.get_file_as_string(ART_BIBLE).split("\n"):
		if line.begins_with("| `%s` |" % key):
			return float(line.split("|")[2].strip_edges())
	fail("no %s in %s → Judge tolerances" % [key, ART_BIBLE])
	return 0.0


# One clip sampled at FPS, as the motion review samples it: the body height, the foot-slide result (contact
# thresholds scaled to the body) and the gait. library: a character library, or "" for the model's own clips.
func _sample(glb: String, library: String, clip: String, limbs_path := "", ground_speed := 0.0) -> Dictionary:
	var model: Node3D = auto_free((load(glb) as PackedScene).instantiate())
	add_child(model)
	var lm: LimbMap = load(limbs_path) if limbs_path != "" else LimbMap.new()
	var ap: AnimationPlayer
	if library != "":
		ap = AnimationPlayer.new()
		model.add_child(ap)
		ap.root_node = NodePath("..")
		ap.add_animation_library("", load(library))
	else:
		ap = model.find_children("*", "AnimationPlayer", true, false)[0]
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var height := FootSlide.body_height(sk, model)
	var anim := ap.get_animation(clip)
	ap.play(clip)
	var t := []
	var samples := []
	var root := []
	for f in int(ceil(anim.length * FPS)) + 1:
		t.append(minf(f / FPS, anim.length))
		ap.seek(t[-1], true)
		samples.append(FootSlide.feet(sk, lm))
		root.append(lm.locate(sk, lm.root, sk.global_transform))
	var looping := anim.loop_mode != Animation.LOOP_NONE
	var fs := FootSlide.measure(t, samples, ground_speed, looping, height / FootSlide.REFERENCE_HEIGHT)
	return {"height": height, "slide": fs, "gait": FootSlide.gait(fs["points"], root)}


# The feet that fail the gait check: [side, "lift" | "swing"] pairs
func _gait_failures(m: Dictionary) -> Array:
	var lift_tol := _tolerance("motion_gait_lift_bh")
	var swing_tol := _tolerance("motion_gait_swing_bh")
	var out := []
	for side: String in m["gait"]:
		if m["gait"][side]["lift_m"] / m["height"] < lift_tol:
			out.append([side, "lift"])
		if m["gait"][side]["swing_m"] / m["height"] < swing_tol:
			out.append([side, "swing"])
	return out


func _slide_bhps(m: Dictionary) -> float:
	return m["slide"]["foot_slide_p90_mps"] / m["height"]


func test_body_height_humanoids_are_the_reference() -> void:
	for glb in [PLAYER, LEVY]:
		var model: Node3D = auto_free((load(glb) as PackedScene).instantiate())
		add_child(model)
		var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		# Exactly the reference, so the contact thresholds scale by exactly 1 and humanoid metrics don't move
		assert_float(FootSlide.body_height(sk, model)).is_equal(FootSlide.REFERENCE_HEIGHT)


# The two boars are the same mesh at 4.6 m and 1.0 m long: their heights keep that ratio
func test_body_height_scales_with_the_creature() -> void:
	var heights := []
	for glb in [BOAR, BOAR_TRIPO]:
		var model: Node3D = auto_free((load(glb) as PackedScene).instantiate())
		add_child(model)
		var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		heights.append(FootSlide.body_height(sk, model))
	assert_float(heights[0]).is_between(3.4, 3.6)
	assert_float(heights[1]).is_between(0.74, 0.8)
	assert_float(heights[0] / heights[1]).is_between(4.4, 4.8)


func test_gait_of_a_frozen_foot_is_zero() -> void:
	var root := [Vector3(0, 1, 0), Vector3(0, 1.05, 0.02), Vector3(0, 1, 0)]
	var frozen := [Vector3(0.2, 0, 0.3), Vector3(0.2, 0, 0.3), Vector3(0.2, 0, 0.3)]
	# Carried along with the root, never relative to it: no swing
	var carried := [Vector3(0.2, 0, 0.3), Vector3(0.2, 0.1, 0.32), Vector3(0.2, 0, 0.3)]
	var stepping := [Vector3(0.2, 0, 0.6), Vector3(0.2, 0.1, 0.3), Vector3(0.2, 0, 0.0)]
	var g := FootSlide.gait({"frozen": frozen, "carried": carried, "stepping": stepping}, root)
	assert_float(g["frozen"]["lift_m"]).is_equal(0.0)
	assert_float(g["frozen"]["swing_m"]).is_equal_approx(0.02, 0.001)
	assert_float(g["carried"]["lift_m"]).is_equal_approx(0.1, 0.001)
	assert_float(g["carried"]["swing_m"]).is_equal(0.0)
	assert_float(g["stepping"]["swing_m"]).is_equal_approx(0.6, 0.001)


# Tripo's preset drove only the back legs: the front feet never lift or swing, so the walk fails the gait
# check on exactly those two feet
func test_motion_gait_tripo_walk_fails() -> void:
	var m := _sample(BOAR_TRIPO, "", TRIPO_WALK, GOBKIT_TRIPO)
	var failures := _gait_failures(m)
	assert_array(failures).contains_exactly_in_any_order(
		[["front_left", "lift"], ["front_left", "swing"], ["front_right", "lift"], ["front_right", "swing"]]
	)


# The Gobkit walk skates (it fails foot slide) but every leg moves
func test_motion_gait_gobkit_walk_passes() -> void:
	var m := _sample(BOAR, "", "walk", GOBKIT)
	assert_array(_gait_failures(m)).is_empty()


func test_motion_gait_humanoid_locomotion_passes() -> void:
	var player := _sample(PLAYER, "res://data/animations/player_library.tres", "run", "", 5.0)
	var front := _sample(LEVY, "res://data/animations/levy_frontfile_library.tres", "run", "", 4.6)
	var back := _sample(LEVY, "res://data/animations/levy_backfile_library.tres", "run", "", 1.5)
	for m in [player, front, back]:
		assert_array(_gait_failures(m)).is_empty()


# Per body height both boars' walks slide alike and both fail; in metres the 1 m Tripo boar used to pass
func test_size_relative_slide_fails_both_boar_walks() -> void:
	var limit := _tolerance("motion_foot_slide_bhps")
	var gobkit := _sample(BOAR, "", "walk", GOBKIT)
	var tripo := _sample(BOAR_TRIPO, "", TRIPO_WALK, GOBKIT_TRIPO)
	assert_float(_slide_bhps(gobkit)).is_greater(limit)
	assert_float(_slide_bhps(tripo)).is_greater(limit)


# The humanoid equivalents of the relative limits are the metre limits they replaced (0.15 m root travel,
# 0.5 m/s slide, 1.8 m bind deviation), rounded up, so no humanoid clip that passed can fail
func test_relative_limits_keep_the_humanoid_metre_values() -> void:
	var h := FootSlide.REFERENCE_HEIGHT
	assert_float(_tolerance("motion_root_travel_bh") * h).is_between(0.15, 0.1502)
	assert_float(_tolerance("motion_foot_slide_bhps") * h).is_between(0.5, 0.5002)
	assert_float(_tolerance("motion_bind_deviation_bh") * h).is_equal_approx(1.8, 0.0001)
