extends SceneTree

# Writes the two BoneMaps onto SkeletonProfileHumanoid (one per bone-naming scheme):
#   data/rigs/mixamorig_bone_map.tres  - Tripo rig v1.0 characters (player, Barrow-levy)
#   data/rigs/quaternius_bone_map.tres - Quaternius Universal Animation Library 1 and 2
# The GLBs' import settings reference these (retarget/bone_map). Deterministic; re-run after editing:
#   godot --headless --path . -s scripts/tools/make_bone_maps.gd

# Bone names as Godot imports them (its glTF importer turns "mixamorig:Hips" into "mixamorig_Hips").
# The characters have no finger bones.
const MIXAMORIG := {
	"Root": "Root", "Hips": "mixamorig_Hips", "Spine": "mixamorig_Spine", "Chest": "mixamorig_Spine1",
	"UpperChest": "mixamorig_Spine2", "Neck": "mixamorig_Neck", "Head": "mixamorig_Head",
	"LeftShoulder": "mixamorig_LeftShoulder", "LeftUpperArm": "mixamorig_LeftArm",
	"LeftLowerArm": "mixamorig_LeftForeArm", "LeftHand": "mixamorig_LeftHand",
	"RightShoulder": "mixamorig_RightShoulder", "RightUpperArm": "mixamorig_RightArm",
	"RightLowerArm": "mixamorig_RightForeArm", "RightHand": "mixamorig_RightHand",
	"LeftUpperLeg": "mixamorig_LeftUpLeg", "LeftLowerLeg": "mixamorig_LeftLeg",
	"LeftFoot": "mixamorig_LeftFoot", "LeftToes": "mixamorig_LeftToeBase",
	"RightUpperLeg": "mixamorig_RightUpLeg", "RightLowerLeg": "mixamorig_RightLeg",
	"RightFoot": "mixamorig_RightFoot", "RightToes": "mixamorig_RightToeBase",
}

const QUATERNIUS := {
	"Root": "root", "Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_02", "UpperChest": "spine_03",
	"Neck": "neck_01", "Head": "Head",
	"LeftShoulder": "clavicle_l", "LeftUpperArm": "upperarm_l", "LeftLowerArm": "lowerarm_l", "LeftHand": "hand_l",
	"RightShoulder": "clavicle_r", "RightUpperArm": "upperarm_r", "RightLowerArm": "lowerarm_r", "RightHand": "hand_r",
	"LeftUpperLeg": "thigh_l", "LeftLowerLeg": "calf_l", "LeftFoot": "foot_l", "LeftToes": "ball_l",
	"RightUpperLeg": "thigh_r", "RightLowerLeg": "calf_r", "RightFoot": "foot_r", "RightToes": "ball_r",
	"LeftThumbMetacarpal": "thumb_01_l", "LeftThumbProximal": "thumb_02_l", "LeftThumbDistal": "thumb_03_l",
	"LeftIndexProximal": "index_01_l", "LeftIndexIntermediate": "index_02_l", "LeftIndexDistal": "index_03_l",
	"LeftMiddleProximal": "middle_01_l", "LeftMiddleIntermediate": "middle_02_l", "LeftMiddleDistal": "middle_03_l",
	"LeftRingProximal": "ring_01_l", "LeftRingIntermediate": "ring_02_l", "LeftRingDistal": "ring_03_l",
	"LeftLittleProximal": "pinky_01_l", "LeftLittleIntermediate": "pinky_02_l", "LeftLittleDistal": "pinky_03_l",
	"RightThumbMetacarpal": "thumb_01_r", "RightThumbProximal": "thumb_02_r", "RightThumbDistal": "thumb_03_r",
	"RightIndexProximal": "index_01_r", "RightIndexIntermediate": "index_02_r", "RightIndexDistal": "index_03_r",
	"RightMiddleProximal": "middle_01_r", "RightMiddleIntermediate": "middle_02_r", "RightMiddleDistal": "middle_03_r",
	"RightRingProximal": "ring_01_r", "RightRingIntermediate": "ring_02_r", "RightRingDistal": "ring_03_r",
	"RightLittleProximal": "pinky_01_r", "RightLittleIntermediate": "pinky_02_r", "RightLittleDistal": "pinky_03_r",
}


func _init() -> void:
	_save(MIXAMORIG, "res://data/rigs/mixamorig_bone_map.tres")
	_save(QUATERNIUS, "res://data/rigs/quaternius_bone_map.tres")
	quit()


func _save(mapping: Dictionary, path: String) -> void:
	var bm := BoneMap.new()
	bm.profile = SkeletonProfileHumanoid.new()
	for profile_bone in mapping:
		assert(bm.profile.find_bone(profile_bone) != -1, "not a SkeletonProfileHumanoid bone: %s" % profile_bone)
		bm.set_skeleton_bone_name(profile_bone, mapping[profile_bone])
	var err := ResourceSaver.save(bm, path)
	print("BONEMAP ", path, " ", mapping.size(), " bones, err ", err)
