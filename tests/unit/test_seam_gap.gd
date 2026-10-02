extends GdUnitTestSuite

# The motion review's seam-gap metric (scripts/review/seam_gap.gd), for characters built from separate
# shells (a body plus garment shells): vertices on different shells that touch at bind must stay
# together in every frame, and a body vertex covered by a garment at bind must stay under it.
# Shells are the mesh's connected pieces after welding coincident vertices (UV-seam splits).

const SeamGap := preload("res://scripts/review/seam_gap.gd")


# Two triangles: shell A in the z=0 plane, shell B a copy moved by `offset`, as one index buffer.
# A's first vertex is also split in two (a UV seam: same position, its own index), which must not
# make a third shell.
func _two_shells(offset: Vector3) -> Dictionary:
	var verts := PackedVector3Array(
		[
			Vector3(0, 0, 0),
			Vector3(0.1, 0, 0),
			Vector3(0, 0.1, 0),
			Vector3(0, 0, 0),  # seam split of vertex 0
			Vector3(-0.1, 0, 0),
		]
	)
	var index := PackedInt32Array([0, 1, 2, 3, 2, 4])
	for v in [Vector3(0, 0, 0), Vector3(0.1, 0, 0), Vector3(0, 0.1, 0)]:
		verts.append(v + offset)
	index.append_array(PackedInt32Array([5, 6, 7]))
	return {"verts": verts, "index": index}


func test_shells_weld_seam_splits() -> void:
	var m := _two_shells(Vector3(0, 0, 0.5))
	var shell: PackedInt32Array = SeamGap.shells(m["verts"], m["index"])
	assert_int(shell.size()).is_equal(8)
	for v in 5:
		assert_int(shell[v]).is_equal(shell[0])
	for v in [5, 6, 7]:
		assert_int(shell[v]).is_equal(shell[5])
	assert_int(shell[5]).is_not_equal(shell[0])


func test_touching_pairs_cross_shells_only() -> void:
	# B sits 3 mm above A: each B vertex touches the A vertex under it; A's own seam split doesn't count
	var m := _two_shells(Vector3(0, 0, 0.003))
	var shell: PackedInt32Array = SeamGap.shells(m["verts"], m["index"])
	var pairs: PackedInt32Array = SeamGap.touching(m["verts"], shell, SeamGap.TOUCH_M)
	assert_int(pairs.size() % 2).is_equal(0)
	assert_bool(pairs.size() >= 6).is_true()
	for i in range(0, pairs.size(), 2):
		assert_int(shell[pairs[i]]).is_not_equal(shell[pairs[i + 1]])


func test_far_shells_dont_touch() -> void:
	var m := _two_shells(Vector3(0, 0, 0.02))
	var shell: PackedInt32Array = SeamGap.shells(m["verts"], m["index"])
	assert_int(SeamGap.touching(m["verts"], shell, SeamGap.TOUCH_M).size()).is_equal(0)


func test_gap_is_the_largest_pair_distance() -> void:
	var m := _two_shells(Vector3(0, 0, 0.003))
	var shell: PackedInt32Array = SeamGap.shells(m["verts"], m["index"])
	var pairs: PackedInt32Array = SeamGap.touching(m["verts"], shell, SeamGap.TOUCH_M)
	assert_float(SeamGap.max_gap(m["verts"], pairs)[0]).is_equal_approx(0.003, 0.0005)
	# Pose: B's second vertex pulls 2 cm away from A
	var posed: PackedVector3Array = m["verts"].duplicate()
	posed[6] += Vector3(0, 0, 0.02)
	assert_float(SeamGap.max_gap(posed, pairs)[0]).is_equal_approx(0.023, 0.001)


func test_covered_vertex_poking_out() -> void:
	# A body vertex 1 cm under a garment vertex whose normal points out (+Z) is covered at bind
	var verts := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 0.01)])
	var normals := PackedVector3Array([Vector3(0, 0, 1), Vector3(0, 0, 1)])
	var shell := PackedInt32Array([0, 1])
	var cov: PackedInt32Array = SeamGap.covered(verts, normals, shell, SeamGap.COVER_M)
	assert_array(Array(cov)).is_equal([0, 1])
	# Only the body vertex is covered: the garment vertex is outside the body's surface
	assert_int(SeamGap.poke(verts, normals, cov, SeamGap.POKE_M)[0]).is_equal(0)
	# Posed: the body vertex comes 5 mm out through the garment
	var posed := verts.duplicate()
	posed[0] = Vector3(0, 0, 0.015)
	var p: Array = SeamGap.poke(posed, normals, cov, SeamGap.POKE_M)
	assert_int(p[0]).is_equal(1)
	assert_float(p[1]).is_equal_approx(0.005, 0.0005)
