extends GdUnitTestSuite

# The rendered readability checks (scripts/review/luminance_probe.gd; design bible §5 "Lighting and
# readability", lvl_floor_luminance_min and read_char_contrast_min in §9). Nothing renders here: the tests
# hand the probe synthetic images, and the floor test casts its rays against collision shapes.

const LuminanceProbe := preload("res://scripts/review/luminance_probe.gd")


func _gray(srgb: float, size := Vector2i(16, 16)) -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(srgb, srgb, srgb))
	return img


func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	add_child(auto_free(body))
	return body


func _camera_over_floor() -> Camera3D:
	var cam := Camera3D.new()
	add_child(auto_free(cam))
	cam.look_at_from_position(Vector3(0, 2.5, 4), Vector3(0, 0, -2), Vector3.UP)
	cam.current = true
	return cam


func _viewport_image(cam: Camera3D, srgb: float) -> Image:
	return _gray(srgb, Vector2i(cam.get_viewport().get_visible_rect().size))


func test_luminance_is_linear_rec709() -> void:
	assert_float(LuminanceProbe.luminance(Color.WHITE)).is_equal_approx(1.0, 0.001)
	assert_float(LuminanceProbe.luminance(Color.BLACK)).is_equal_approx(0.0, 0.001)
	# sRGB 0.5 is linear 0.214; pure green carries 0.7152 of white
	assert_float(LuminanceProbe.luminance(Color(0.5, 0.5, 0.5))).is_equal_approx(0.214, 0.002)
	assert_float(LuminanceProbe.luminance(Color(0, 1, 0))).is_equal_approx(0.7152, 0.001)


func test_read_char_contrast_min_ratio() -> void:
	# (L_hi + 0.05) / (L_lo + 0.05), whichever side is brighter
	assert_float(LuminanceProbe.contrast(0.10, 0.05)).is_equal_approx(1.5, 0.001)
	assert_float(LuminanceProbe.contrast(0.05, 0.10)).is_equal_approx(1.5, 0.001)
	assert_float(LuminanceProbe.contrast(0.2, 0.2)).is_equal_approx(1.0, 0.001)
	assert_float(LuminanceProbe.CONTRAST_MIN).is_equal(1.3)


func test_read_char_contrast_min_subject_pixels() -> void:
	# A subject 4x4 px at sRGB 0.8 over a 0.2 background: only its pixels count, against what's behind them
	var without := _gray(0.2)
	var full := without.duplicate() as Image
	full.fill_rect(Rect2i(2, 2, 4, 4), Color(0.8, 0.8, 0.8))
	var mask: Dictionary = LuminanceProbe.diff_mask(full, without)
	assert_int(mask.size()).is_equal(16)
	var pair: Dictionary = LuminanceProbe.subject_contrast(full, without, mask)
	assert_int(pair.px).is_equal(16)
	assert_float(pair.lum).is_equal_approx(LuminanceProbe.luminance(Color(0.8, 0.8, 0.8)), 0.001)
	assert_float(pair.bg).is_equal_approx(LuminanceProbe.luminance(Color(0.2, 0.2, 0.2)), 0.001)
	assert_float(pair.contrast).is_equal_approx(LuminanceProbe.contrast(pair.lum, pair.bg), 0.01)
	# A subject that isn't on screen has no pixels and no contrast
	var none: Dictionary = LuminanceProbe.subject_contrast(without, without, LuminanceProbe.diff_mask(without, without))
	assert_int(none.px).is_equal(0)


func test_lvl_floor_luminance_min_floor_pixels() -> void:
	_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0))
	var cam := _camera_over_floor()
	await await_idle_frame()
	var img := _viewport_image(cam, 0.3)
	var space := cam.get_world_3d().direct_space_state
	var open: Dictionary = LuminanceProbe.floor_luminance(img, cam, space, 0.0, [], {})
	assert_int(open.n).is_greater(0)
	assert_float(open.mean).is_equal_approx(LuminanceProbe.luminance(Color(0.3, 0.3, 0.3)), 0.001)
	assert_float(open.p10).is_equal_approx(open.mean, 0.001)
	assert_float(LuminanceProbe.FLOOR_MIN).is_equal(0.05)
	# A wall across the view hides floor pixels; a box top 1 m up isn't the player's floor
	_box(Vector3(40, 6, 0.5), Vector3(0, 3, -3))
	_box(Vector3(2, 1, 2), Vector3(0, 0.5, 0))
	await await_idle_frame()
	var walled: Dictionary = LuminanceProbe.floor_luminance(img, cam, space, 0.0, [], {})
	assert_int(walled.n).is_greater(0)
	assert_int(walled.n).is_less(open.n)
	# The subject's own pixels are skipped
	var all := {}
	for y in img.get_height():
		for x in img.get_width():
			all[Vector2i(x, y)] = true
	assert_int(LuminanceProbe.floor_luminance(img, cam, space, 0.0, [], all).n).is_equal(0)


func test_summary_takes_each_minimum_and_its_frame() -> void:
	var samples := [
		{
			"frame": 0,
			"floor": {"mean": 0.20, "p10": 0.10, "n": 100},
			"player": {"contrast": 1.8, "px": 4000},
			"enemies": [{"name": "Levy", "contrast": 1.6, "px": 900}]
		},
		{
			"frame": 60,
			"floor": {"mean": 0.12, "p10": 0.04, "n": 90},
			"player": {"contrast": 1.1, "px": 4100},
			"enemies": [{"name": "Levy", "contrast": 2.0, "px": 50}, {"name": "Archer", "contrast": 1.4, "px": 600}]
		},
		# The camera inside a wall sees no floor and no player: nothing to score
		{"frame": 120, "floor": {"mean": 0.0, "p10": 0.0, "n": 0}, "player": {"contrast": 0.0, "px": 0}, "enemies": []}
	]
	var s: Dictionary = LuminanceProbe.summarize(samples)
	assert_int(s.samples).is_equal(3)
	assert_float(s.floor_mean_min).is_equal_approx(0.12, 0.0001)
	assert_int(s.floor_mean_min_frame).is_equal(60)
	assert_float(s.floor_p10_min).is_equal_approx(0.04, 0.0001)
	assert_float(s.player_contrast_min).is_equal_approx(1.1, 0.001)
	assert_int(s.player_contrast_min_frame).is_equal(60)
	# The 50 px levy is too small to judge (MIN_SUBJECT_PX); the archer is the minimum
	assert_float(s.enemy_contrast_min).is_equal_approx(1.4, 0.001)
	assert_str(s.enemy_contrast_min_name).is_equal("Archer")
	assert_bool(s.floor_ok).is_true()
	assert_bool(s.player_ok).is_false()
	assert_bool(s.enemy_ok).is_true()


func test_read_char_contrast_min_only_inside_subject_rect() -> void:
	# A torch flame flickering elsewhere on screen between the paired renders isn't the subject's
	var without := _gray(0.2, Vector2i(32, 16))
	var full := without.duplicate() as Image
	full.fill_rect(Rect2i(2, 2, 4, 4), Color(0.8, 0.8, 0.8))
	full.fill_rect(Rect2i(24, 2, 4, 4), Color(0.9, 0.6, 0.2))
	assert_int(LuminanceProbe.diff_mask(full, without).size()).is_equal(32)
	assert_int(LuminanceProbe.diff_mask(full, without, Rect2i(0, 0, 16, 16)).size()).is_equal(16)


func test_subject_screen_rect_covers_its_capsule() -> void:
	var cam := Camera3D.new()
	add_child(auto_free(cam))
	cam.look_at_from_position(Vector3(0, 1.7, 5), Vector3(0, 1, 0), Vector3.UP)
	cam.current = true
	await await_idle_frame()
	var size := Vector2i(cam.get_viewport().get_visible_rect().size)
	var rect := LuminanceProbe.screen_rect(cam, Vector3(0, 0.9, 0), 0.4, 1.8, size)
	assert_bool(rect.has_area()).is_true()
	assert_bool(rect.has_point(Vector2i(cam.unproject_position(Vector3(0, 0.9, 0))))).is_true()
	assert_bool(Rect2i(Vector2i.ZERO, size).encloses(rect)).is_true()
	# Behind the camera: nothing to measure
	assert_bool(LuminanceProbe.screen_rect(cam, Vector3(0, 0.9, 10), 0.4, 1.8, size).has_area()).is_false()
