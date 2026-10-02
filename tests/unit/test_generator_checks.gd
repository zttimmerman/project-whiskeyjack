extends GdUnitTestSuite

# The scene generators' save path (scripts/tools/generator_checks.gd): a node whose owner isn't the
# scene root is silently left out by PackedScene.pack(), so the generators count the nodes before
# packing, instantiate the packed scene and compare; node ids are kept across builds so a regenerated
# scene is byte-identical. Silent-failure checks after htdt/godogen engines/godot.md (MIT; ideas only).

const Checks := preload("res://scripts/tools/generator_checks.gd")
const GLB := "res://assets/meshes/prop_levy_blade.glb"


func _owned_tree() -> Node3D:
	var root: Node3D = auto_free(Node3D.new())
	root.name = "Root"
	var a := Node3D.new()
	a.name = "A"
	root.add_child(a)
	a.owner = root
	var b := MeshInstance3D.new()
	b.name = "B"
	a.add_child(b)
	b.owner = root
	var prop: Node3D = (load(GLB) as PackedScene).instantiate()
	prop.name = "Prop"
	root.add_child(prop)
	prop.owner = root
	return root


func test_saved_nodes_lists_the_root_and_owned_nodes_but_not_an_instance_inside() -> void:
	var nodes := Checks.saved_nodes(_owned_tree())
	assert_array(Array(nodes)).contains_exactly([".:Node3D", "A:Node3D", "A/B:MeshInstance3D", "Prop:Node3D"])


func test_pack_checked_passes_a_fully_owned_tree() -> void:
	var out := Checks.pack_checked(_owned_tree(), "test_gen")
	assert_str(out["error"]).is_empty()
	assert_object(out["scene"]).is_not_null()


func test_pack_checked_fails_loudly_on_a_node_without_an_owner() -> void:
	var root := _owned_tree()
	var orphan := Node3D.new()
	orphan.name = "Unowned"
	root.get_node("A").add_child(orphan)  # owner never set: pack() drops it without a word
	var out := Checks.pack_checked(root, "test_gen")
	assert_object(out["scene"]).is_null()
	assert_str(out["error"]).contains("test_gen").contains("A/Unowned")


func test_pack_checked_fails_on_an_owned_node_under_an_unowned_parent() -> void:
	var root := _owned_tree()
	var mid := Node3D.new()
	mid.name = "Mid"
	root.add_child(mid)  # unowned
	var leaf := Node3D.new()
	leaf.name = "Leaf"
	mid.add_child(leaf)
	leaf.owner = root  # owned, but its parent isn't saved, so it can't be either
	var out := Checks.pack_checked(root, "test_gen")
	assert_object(out["scene"]).is_null()
	assert_str(out["error"]).contains("Mid/Leaf")


func test_keep_node_ids_reuses_the_previous_ids_by_node_path() -> void:
	var previous := (
		'[gd_scene format=3]\n\n[node name="Root" type="Node3D" unique_id=11]\n\n'
		+ '[node name="A" type="Node3D" parent="." unique_id=22]\n'
	)
	var fresh := (
		'[gd_scene format=3]\n\n[node name="Root" type="Node3D" unique_id=987]\n\n'
		+ '[node name="A" type="Node3D" parent="." unique_id=654]\n\n'
		+ '[node name="New" type="Node3D" parent="A" unique_id=321]\n'
	)
	var out := Checks.keep_node_ids(fresh, previous)
	assert_str(out["error"]).is_empty()
	var text: String = out["text"]
	assert_str(text).contains('[node name="Root" type="Node3D" unique_id=11]')
	assert_str(text).contains('[node name="A" type="Node3D" parent="." unique_id=22]')
	# A node the previous build didn't have gets a hash of its path (stable from then on)
	assert_str(text).contains('[node name="New" type="Node3D" parent="A" unique_id=%d]' % ("A/New".hash() & 0x7FFFFFFF))


func test_keep_node_ids_is_stable_over_a_rebuild() -> void:
	var fresh := '[gd_scene format=3]\n\n[node name="Root" type="Node3D" unique_id=987]\n'
	var first: String = Checks.keep_node_ids(fresh, "")["text"]
	var again: String = Checks.keep_node_ids(fresh.replace("987", "5"), first)["text"]
	assert_str(again).is_equal(first)


func test_in_tree_check_names_the_generator() -> void:
	var loose: Node3D = auto_free(Node3D.new())
	assert_str(Checks.in_tree_error(loose, "test_gen")).contains("test_gen")
	var placed: Node3D = auto_free(Node3D.new())
	add_child(placed)
	assert_str(Checks.in_tree_error(placed, "test_gen")).is_empty()
