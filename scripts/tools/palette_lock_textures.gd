extends SceneTree

# Palette-lock and downscale step of scripts/tools/make_textures.py (it writes the job file; run that, not this).
#   godot --headless --path . -s scripts/tools/palette_lock_textures.gd -- --job <job.json>
#
# For each job: load Material Maker's albedo export (2048 px, RGBA8), drop alpha, box-filter it down to
# the art-bible size with Image.shrink_x2 (integer 2x2 averages), then snap every texel to the nearest
# entry of the texture's palette ramp: the declared art-bible colours, dark to light, with ramp_steps
# integer-interpolated sRGB steps between neighbours. Squared sRGB distance, ties to the lower entry.
# Everything that decides a pixel is integer arithmetic, so the same input and ramp give the same pixels
# on any machine; the PNG bytes also depend on Godot's encoder, so the job reports a hash of the pixels too.
#
# It also measures colour (CIE76 dE in Lab, as scripts/judge.py does) before and after the lock: each
# texel's distance to the nearest ramp entry, and the art bible's palette groups (each texel joins its
# nearest declared palette colour; the group's per-channel median is compared with that colour).
# The measurements go in the report only; they never feed back into the pixels.


func _init() -> void:
	var argv := OS.get_cmdline_user_args()
	var job_path := ""
	for i in argv.size() - 1:
		if argv[i] == "--job":
			job_path = argv[i + 1]
	if job_path == "":
		printerr("palette_lock_textures: usage: -- --job <job.json>")
		quit(2)
		return
	var job: Variant = JSON.parse_string(FileAccess.get_file_as_string(job_path))
	if not job is Dictionary:
		printerr("palette_lock_textures: cannot read job file %s" % job_path)
		quit(2)
		return
	var results: Array = []
	for t: Dictionary in job["textures"]:
		var r := _lock(t)
		if r.has("error"):
			printerr("palette_lock_textures: %s: %s" % [t["name"], r["error"]])
			quit(1)
			return
		results.append(r)
	var f := FileAccess.open(job["report"], FileAccess.WRITE)
	f.store_string(JSON.stringify({"textures": results}, " ", false))
	f.close()
	quit(0)


func _lock(t: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var img := Image.load_from_file(t["in"])
	if img == null:
		return {"error": "cannot load %s" % t["in"]}
	var size := int(t["size"])
	if img.get_width() != img.get_height() or img.get_width() < size:
		return {
			"error": "expected a square export of at least %d px, got %dx%d" % [size, img.get_width(), img.get_height()]
		}
	img.convert(Image.FORMAT_RGB8)
	while img.get_width() > size:
		img.shrink_x2()
	if img.get_width() != size:
		return {"error": "export size %d is not a power-of-two multiple of %d" % [img.get_width(), size]}
	var ramp := _ramp(t["ramp"], int(t["ramp_steps"]))
	var before := img.get_data()
	var after := PackedByteArray()
	after.resize(before.size())
	var cache := {}
	for i in range(0, before.size(), 3):
		var key := (before[i] << 16) | (before[i + 1] << 8) | before[i + 2]
		var e: int = cache.get(key, -1)
		if e < 0:
			e = _nearest(ramp, before[i], before[i + 1], before[i + 2])
			cache[key] = e
		after[i] = ramp[e][0]
		after[i + 1] = ramp[e][1]
		after[i + 2] = ramp[e][2]
	var locked := Image.create_from_data(size, size, false, Image.FORMAT_RGB8, after)
	var err := locked.save_png(t["out"])
	if err != OK:
		return {"error": "cannot write %s (%s)" % [t["out"], error_string(err)]}
	var lock_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(after)
	return {
		"name": t["name"],
		"size": size,
		"ramp_entries": ramp.size(),
		"pixels_sha256": ctx.finish().hex_encode(),
		"distinct_colours": _distinct(after),
		"lock_ms": snappedf(lock_ms, 0.1),
		"before": _measure(before, ramp, t["palette"]),
		"after": _measure(after, ramp, t["palette"]),
	}


# Ramp entries as [r, g, b] ints: each declared colour, plus steps-1 interpolated ones between neighbours.
func _ramp(colours: Array, steps: int) -> Array:
	var out: Array = []
	for c in colours.size() - 1:
		var a: Array = colours[c]
		var b: Array = colours[c + 1]
		for s in steps:
			var entry: Array = []
			for ch in 3:
				# Rounded integer interpolation: (a*(steps-s) + b*s + steps/2) / steps
				@warning_ignore("integer_division")
				entry.append((int(a[ch]) * (steps - s) + int(b[ch]) * s + steps / 2) / steps)
			out.append(entry)
	var last: Array = colours[colours.size() - 1]
	out.append([int(last[0]), int(last[1]), int(last[2])])
	return out


func _nearest(ramp: Array, r: int, g: int, b: int) -> int:
	var best := 0
	var best_d := 1 << 30
	for e in ramp.size():
		var c: Array = ramp[e]
		var d: int = (r - c[0]) * (r - c[0]) + (g - c[1]) * (g - c[1]) + (b - c[2]) * (b - c[2])
		if d < best_d:
			best_d = d
			best = e
	return best


func _distinct(data: PackedByteArray) -> int:
	var seen := {}
	for i in range(0, data.size(), 3):
		seen[(data[i] << 16) | (data[i + 1] << 8) | data[i + 2]] = true
	return seen.size()


func _measure(data: PackedByteArray, ramp: Array, palette: Dictionary) -> Dictionary:
	var ramp_lab: Array = []
	for c: Array in ramp:
		ramp_lab.append(_lab(int(c[0]), int(c[1]), int(c[2])))
	var names: Array = palette.keys()
	var pal_lab: Array = []
	for n: String in names:
		var c: Array = palette[n]
		pal_lab.append(_lab(int(c[0]), int(c[1]), int(c[2])))
	var lab_cache := {}
	var ramp_de := PackedFloat64Array()
	var groups: Array = []
	for n in names:
		groups.append([PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array()])
	for i in range(0, data.size(), 3):
		var key := (data[i] << 16) | (data[i + 1] << 8) | data[i + 2]
		var lab: Vector3 = lab_cache.get(key, Vector3.INF)
		if lab == Vector3.INF:
			lab = _lab(data[i], data[i + 1], data[i + 2])
			lab_cache[key] = lab
		var best := INF
		for rl: Vector3 in ramp_lab:
			best = minf(best, lab.distance_to(rl))
		ramp_de.append(best)
		var gi := 0
		for p in pal_lab.size():
			if lab.distance_to(pal_lab[p]) < lab.distance_to(pal_lab[gi]):
				gi = p
		for ch in 3:
			groups[gi][ch].append(lab[ch])
	@warning_ignore("integer_division")
	var total := data.size() / 3
	var group_rows: Array = []
	for p in names.size():
		var g: Array = groups[p]
		var count: int = g[0].size()
		if count == 0:
			group_rows.append({"palette": names[p], "share": 0.0})
			continue
		var med := Vector3(_median(g[0]), _median(g[1]), _median(g[2]))
		(
			group_rows
			. append(
				{
					"palette": names[p],
					"share": snappedf(float(count) / total, 0.001),
					"median_de": snappedf(med.distance_to(pal_lab[p]), 0.01),
				}
			)
		)
	return {
		"ramp_de_median": snappedf(_median(ramp_de), 0.01),
		"ramp_de_p95": snappedf(_percentile(ramp_de, 0.95), 0.01),
		"ramp_de_max": snappedf(_percentile(ramp_de, 1.0), 0.01),
		"groups": group_rows,
	}


# sRGB 8-bit to CIE Lab (D65), the same constants as scripts/judge.py hex_to_lab.
func _lab(r: int, g: int, b: int) -> Vector3:
	var lin: Array[float] = []
	for v: int in [r, g, b]:
		var c := float(v) / 255.0
		lin.append(c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4))
	var x := (0.4124 * lin[0] + 0.3576 * lin[1] + 0.1805 * lin[2]) / 0.95047
	var y := 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
	var z := (0.0193 * lin[0] + 0.1192 * lin[1] + 0.9505 * lin[2]) / 1.08883
	var f: Array[float] = []
	for v: float in [x, y, z]:
		f.append(pow(v, 1.0 / 3.0) if v > 216.0 / 24389.0 else (24389.0 / 27.0 * v + 16.0) / 116.0)
	return Vector3(116.0 * f[1] - 16.0, 500.0 * (f[0] - f[1]), 200.0 * (f[1] - f[2]))


func _median(values: PackedFloat64Array) -> float:
	return _percentile(values, 0.5)


func _percentile(values: PackedFloat64Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var s := values.duplicate()
	s.sort()
	return s[clampi(int(round(q * (s.size() - 1))), 0, s.size() - 1)]
