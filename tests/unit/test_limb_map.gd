extends GdUnitTestSuite

# Per-rig limb maps (scripts/review/LimbMap.gd, data/rigs/*_limbs.tres): which bones the motion review
# (foot slide, scripts/review/foot_slide.gd) and its game-path pass (scripts/review/game_path.gd) treat
# as feet, hands and the root, for any body plan. The humanoid map is the default, so every humanoid
# result stays as it was; a quadruped (the Gobkit boar, spike-agent-animation) gets four feet whose
# contact points are its stub legs' soles.

const FootSlide := preload("res://scripts/review/foot_slide.gd")
const GamePath := preload("res://scripts/review/game_path.gd")
const HUMANOID := "res://data/rigs/humanoid_limbs.tres"
const GOBKIT := "res://data/rigs/gobkit_limbs.tres"
const PLAYER := "res://assets/meshes/player.glb"
const BOAR := "res://assets/meshes/gobkit_Boar.glb"
const SOLE_BAND := 0.01  # m: a sole's vertices are within this of its lowest one


func _spawn(glb: String) -> Dictionary:
	var root: Node3D = auto_free((load(glb) as PackedScene).instantiate())
	add_child(root)
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	return {"root": root, "sk": sk}


func _pos(sk: Skeleton3D, bone: String) -> Vector3:
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))).origin


# The centre of each bone's sole: the bind-pose vertices it dominates that lie within SOLE_BAND of its
# lowest one, in world space
func _soles(root: Node3D, sk: Skeleton3D) -> Dictionary:
	var verts_by_bone := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var arr := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		@warning_ignore("integer_division")
		var stride := bones.size() / verts.size()
		for v in verts.size():
			var best := 0
			for k in stride:
				if weights[v * stride + k] > weights[v * stride + best]:
					best = k
			var bone := mi.skin.get_bind_name(bones[v * stride + best])
			if not verts_by_bone.has(bone):
				verts_by_bone[bone] = []
			verts_by_bone[bone].append(sk.global_transform * verts[v])
	var out := {}
	for bone: String in verts_by_bone:
		var pts: Array = verts_by_bone[bone]
		var low: float = pts.map(func(p): return p.y).min()
		var sole := pts.filter(func(p): return p.y <= low + SOLE_BAND)
		out[bone] = sole.reduce(func(a, p): return a + p, Vector3.ZERO) / sole.size()
	return out


func test_humanoid_limb_map_is_the_default() -> void:
	var file: LimbMap = load(HUMANOID)
	var fallback := LimbMap.new()
	assert_str(file.body_plan).is_equal("humanoid")
	assert_str(file.body_plan).is_equal(fallback.body_plan)
	assert_str(file.root).is_equal(fallback.root)
	assert_dict(file.feet).is_equal(fallback.feet)
	assert_dict(file.hands).is_equal(fallback.hands)
	assert_dict(file.tips).is_equal(fallback.tips)


# The humanoid default reads the same bones, in the same order, as the names the review used to hardcode
func test_humanoid_feet_are_the_named_bones() -> void:
	var inst := _spawn(PLAYER)
	var sk: Skeleton3D = inst["sk"]
	var feet := FootSlide.feet(sk)
	assert_array(feet.keys()).is_equal(["left", "right"])
	assert_array(feet["left"]).is_equal([_pos(sk, "LeftFoot"), _pos(sk, "LeftToes")])
	assert_array(feet["right"]).is_equal([_pos(sk, "RightFoot"), _pos(sk, "RightToes")])
	assert_dict(FootSlide.feet(sk, load(HUMANOID))).is_equal(feet)


func test_humanoid_game_path_limbs() -> void:
	var inst := _spawn(PLAYER)
	var limbs := GamePath.limb_points(inst["root"], inst["sk"])
	assert_array(limbs.keys()).is_equal(["left_hand", "right_hand", "left_foot", "right_foot"])
	assert_dict(LimbMap.new().limbs()).is_equal(
		{"left_hand": "LeftHand", "right_hand": "RightHand", "left_foot": "LeftFoot", "right_foot": "RightFoot"}
	)


func test_quadruped_has_four_feet() -> void:
	var lm: LimbMap = load(GOBKIT)
	assert_str(lm.body_plan).is_equal("quadruped")
	assert_array(lm.feet.keys()).is_equal(["front_left", "front_right", "back_left", "back_right"])
	var inst := _spawn(BOAR)
	var sk: Skeleton3D = inst["sk"]
	for side: String in lm.feet:
		for bone: String in lm.feet[side]:
			assert_int(sk.find_bone(bone)).is_greater_equal(0)
	assert_int(sk.find_bone(lm.root)).is_greater_equal(0)


# A stub leg is one bone with no foot joint: its contact point is the tip recorded in the limb map,
# which must sit at the centre of the leg's sole in the bind pose
func test_quadruped_tips_are_the_soles() -> void:
	var lm: LimbMap = load(GOBKIT)
	var inst := _spawn(BOAR)
	var sk: Skeleton3D = inst["sk"]
	var soles := _soles(inst["root"], sk)
	var feet := FootSlide.feet(sk, lm)
	for side: String in lm.feet:
		var bone: String = lm.feet[side][0]
		assert_bool(lm.tips.has(bone)).is_true()
		var tip: Vector3 = feet[side][0]
		assert_float(tip.distance_to(soles[bone])).is_less(0.02)


func test_quadruped_foot_slide_measures_four_feet() -> void:
	var lm: LimbMap = load(GOBKIT)
	var inst := _spawn(BOAR)
	var sk: Skeleton3D = inst["sk"]
	var t := [0.0, 1.0 / 30.0, 2.0 / 30.0]
	var samples := [FootSlide.feet(sk, lm), FootSlide.feet(sk, lm), FootSlide.feet(sk, lm)]
	var fs := FootSlide.measure(t, samples, 0.0, false)
	assert_array(fs["contact"].keys()).is_equal(lm.feet.keys())
	# A held pose: every foot is planted on every frame, and nothing slides
	assert_int(fs["contact_frames"]).is_equal(12)
	assert_float(fs["foot_slide_max_mps"]).is_equal_approx(0.0, 0.001)


func test_quadruped_game_path_limbs() -> void:
	var lm: LimbMap = load(GOBKIT)
	var inst := _spawn(BOAR)
	var limbs := GamePath.limb_points(inst["root"], inst["sk"], lm)
	assert_array(limbs.keys()).is_equal(lm.limbs().keys())
	assert_array(limbs.keys()).contains(["front_left_foot", "back_right_foot"])
