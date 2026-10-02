class_name LimbMap
extends Resource

## Which bones of one rig the motion review measures (scripts/review/motion_review.gd, its foot slide
## in foot_slide.gd and its game-path pass in game_path.gd), for any body plan. One map per rig in
## data/rigs/<rig>_limbs.tres, passed to the review with --limbs. The defaults are the humanoid map
## (SkeletonProfileHumanoid names, which every retargeted character uses), so a humanoid needs no file.

## A label for people and the metrics: humanoid, quadruped, ...
@export var body_plan := "humanoid"
## The spine root: the bone whose path is the root travel, and whose bind frame the bind deviation is
## measured in
@export var root := "Hips"
## Each foot (keyed by side, in order) and its contact candidates: the lowest of them is the foot's
## contact point on each frame (a humanoid's ankle and toes, as the foot rolls)
@export var feet: Dictionary = {"left": ["LeftFoot", "LeftToes"], "right": ["RightFoot", "RightToes"]}
## Extremities other than the feet that the game-path pass also watches for pose snaps: hands, or a
## creature's striking parts (a snout, a tail)
@export var hands: Dictionary = {"left_hand": "LeftHand", "right_hand": "RightHand"}
## Points on a bone other than its joint, in the bone's own space, keyed by bone name: a leaf bone with
## no child joint to mark its end (a stub leg's sole). A bone without a tip is measured at its joint.
@export var tips: Dictionary = {}


## Every limb the game-path pass watches, by name: the hands, then each foot's first bone as <side>_foot
func limbs() -> Dictionary:
	var out := hands.duplicate()
	for side: String in feet:
		out[side + "_foot"] = feet[side][0]
	return out


## The bone's measured point (its tip, or else its joint) under `base` (the skeleton's global transform,
## or that relative to another frame); null when the rig has no such bone
func locate(sk: Skeleton3D, bone: String, base: Transform3D) -> Variant:
	var i := sk.find_bone(bone)
	if i < 0:
		return null
	var xf := base * sk.get_bone_global_pose(i)
	return xf * (tips[bone] as Vector3) if tips.has(bone) else xf.origin


## `map`, or the humanoid default when it's null
static func or_default(map: LimbMap) -> LimbMap:
	return map if map != null else LimbMap.new()
