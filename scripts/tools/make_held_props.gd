extends SceneTree

# Writes the held-prop wrapper scenes: each instances a prop GLB under a Node3D with the child
# Transform3D that seats it in the hand. The art bible keeps alignment here, never in the mesh.
#   godot --headless --path . -s scripts/tools/make_held_props.gd
# The save is checked (scripts/tools/generator_checks.gd): a node lost in packing fails the run, and
# node ids are kept across runs, so two runs give identical files.
#
# Offsets are in the hand bone's local frame after retargeting, which is the same on every
# SkeletonProfileHumanoid character: +Y runs along the hand to the fingers, +X is the thumb side
# (forward with the palm down), +Z is the palm side. Props are cleaned with their long axis on +Y:
# the blade's pommel is at its origin, the bow's grip at its origin.

const PROPS := {
	"res://scenes/props/HeldLevyBlade.tscn":
	{
		"glb": "res://assets/meshes/prop_levy_blade.glb",
		"rotation_deg": Vector3(0, 0, -90),  # blade (+Y) along the thumb (+X)
		"offset": Vector3(-0.075, 0.08, 0.02),  # grip centre (7.5 cm from the pommel) in the fist
	},
	"res://scenes/props/HeldLevyBow.tscn":
	{
		"glb": "res://assets/meshes/prop_levy_bow.glb",
		# Left hand: the thumb side is local -X. Limbs (+Y) along the thumb, so the bow stands upright
		# in a fist; the string (+X, 10 cm off the limbs) faces back along the arm (-Y), toward the archer.
		"basis": [Vector3(0, -1, 0), Vector3(-1, 0, 0), Vector3(0, 0, -1)],
		"offset": Vector3(0, 0.08, 0.02),  # the grip (the bow's origin) in the fist
	},
}

const Checks := preload("res://scripts/tools/generator_checks.gd")


func _init() -> void:
	var failed := false
	for path in PROPS:
		var spec: Dictionary = PROPS[path]
		var root := Node3D.new()
		root.name = path.get_file().get_basename()
		var prop: Node3D = (load(spec["glb"]) as PackedScene).instantiate()
		prop.name = "Prop"
		root.add_child(prop)
		prop.owner = root
		var basis: Basis
		if spec.has("basis"):  # explicit images of the prop's X, Y and Z axes in the hand frame
			basis = Basis(spec["basis"][0], spec["basis"][1], spec["basis"][2])
		else:
			var r: Vector3 = spec["rotation_deg"]
			basis = Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)))
		prop.transform = Transform3D(basis, spec["offset"])
		# Packed only when every node survives the round trip; node ids are kept, so a rebuild is identical
		var checked := Checks.pack_checked(root, "make_held_props")
		root.free()
		var err: String = checked["error"]
		if err == "":
			err = Checks.save_scene(checked["scene"], path, "make_held_props")
		if err != "":
			push_error(err)
			failed = true
			continue
		print("PROP ", path, " saved")
	quit(1 if failed else 0)
