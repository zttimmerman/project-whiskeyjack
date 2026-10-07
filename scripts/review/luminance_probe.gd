extends RefCounted

## Rendered readability checks (design bible §5 "Lighting and readability"; lvl_floor_luminance_min and
## read_char_contrast_min in §9). Unlike scripts/review/camera_probe.gd it needs real pixels, so it runs only
## in a rendered window on the Mac (Linux llvmpipe colours differ): scripts/review/capture_luminance.sh during
## a replay, and scripts/review/level_luminance.tscn along a critical path.
##
## Method (the one the player's back was measured with, docs/decisions.md):
##   luminance   linear Rec. 709 luminance of an sRGB-encoded pixel, 0 to 1
##   floor       a grid of camera rays (every GRID_PX pixels); a ray that hits an upward-facing surface
##               (normal y >= FLOOR_NORMAL_Y) within FLOOR_BAND_M of the player's floor height is walkable floor,
##               and its pixel is read. Mean and 10th percentile. Pixels of the subject are skipped
##   subject     two renders of the same frame, with the subject shown and hidden; the pixels that differ are
##               the subject's. Mean luminance of those pixels in each render, and their contrast ratio
##               (L_hi + 0.05) / (L_lo + 0.05), whichever is brighter
## summarize() reduces a run's samples to the minimums the targets read.

const FLOOR_MIN := 0.05  # lvl_floor_luminance_min
const CONTRAST_MIN := 1.3  # read_char_contrast_min
const GRID_PX := 8
const FLOOR_NORMAL_Y := 0.8
const FLOOR_BAND_M := 0.3
const DIFF_MIN := 0.02  # summed RGB difference for a pixel to count as the subject's
const MIN_SUBJECT_PX := 200  # a subject smaller than this on screen (far, or nearly hidden) isn't judged
const RAY_LENGTH := 60.0


## Linear Rec. 709 luminance of an sRGB-encoded colour
static func luminance(c: Color) -> float:
	var lin := c.srgb_to_linear()
	return 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b


static func contrast(a: float, b: float) -> float:
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)


## Pixels that differ between a render with the subject and one without it: {Vector2i: true}
static func diff_mask(full: Image, without: Image) -> Dictionary:
	var mask := {}
	for y in full.get_height():
		for x in full.get_width():
			var c := full.get_pixel(x, y)
			var d := without.get_pixel(x, y)
			if absf(c.r - d.r) + absf(c.g - d.g) + absf(c.b - d.b) >= DIFF_MIN:
				mask[Vector2i(x, y)] = true
	return mask


## {lum, bg, contrast, px} of the masked pixels; px 0 (and contrast 0) when the subject isn't on screen
static func subject_contrast(full: Image, without: Image, mask: Dictionary) -> Dictionary:
	if mask.is_empty():
		return {"lum": 0.0, "bg": 0.0, "contrast": 0.0, "px": 0}
	var lum := 0.0
	var bg := 0.0
	for p: Vector2i in mask:
		lum += luminance(full.get_pixel(p.x, p.y))
		bg += luminance(without.get_pixel(p.x, p.y))
	lum /= mask.size()
	bg /= mask.size()
	return {
		"lum": snappedf(lum, 0.0001),
		"bg": snappedf(bg, 0.0001),
		"contrast": snappedf(contrast(lum, bg), 0.01),
		"px": mask.size()
	}


## {mean, p10, n} of the walkable floor pixels at floor_y; exclude is a list of RIDs the rays pass through
## (the player's body), skip a pixel mask left out (the subject's own pixels)
static func floor_luminance(
	img: Image, cam: Camera3D, space: PhysicsDirectSpaceState3D, floor_y: float, exclude: Array[RID], skip: Dictionary
) -> Dictionary:
	# The image may be the window's framebuffer at a different size from the camera's viewport
	var view := cam.get_viewport().get_visible_rect().size
	var scale := Vector2(view.x / img.get_width(), view.y / img.get_height())
	var values: Array[float] = []
	for y in range(GRID_PX >> 1, img.get_height(), GRID_PX):
		for x in range(GRID_PX >> 1, img.get_width(), GRID_PX):
			if skip.has(Vector2i(x, y)):
				continue
			var px := Vector2(x + 0.5, y + 0.5) * scale
			var from := cam.project_ray_origin(px)
			var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(px) * RAY_LENGTH)
			q.exclude = exclude
			var hit := space.intersect_ray(q)
			if hit.is_empty() or hit.normal.y < FLOOR_NORMAL_Y or absf(hit.position.y - floor_y) > FLOOR_BAND_M:
				continue
			values.append(luminance(img.get_pixel(x, y)))
	if values.is_empty():
		return {"mean": 0.0, "p10": 0.0, "n": 0}
	values.sort()
	var total := 0.0
	for v in values:
		total += v
	return {
		"mean": snappedf(total / values.size(), 0.0001),
		"p10": snappedf(values[int(values.size() * 0.1)], 0.0001),
		"n": values.size()
	}


## A run's samples ({frame, floor, player, enemies: [{name, contrast, px}]}) reduced to the minimums the
## targets read, the frame (or enemy) each came from, and whether each target is met. Samples with no floor
## in view, and subjects under MIN_SUBJECT_PX, don't count.
static func summarize(samples: Array) -> Dictionary:
	var out := {
		"samples": samples.size(),
		"floor_mean_min": -1.0,
		"floor_mean_min_frame": -1,
		"floor_p10_min": -1.0,
		"player_contrast_min": -1.0,
		"player_contrast_min_frame": -1,
		"enemy_contrast_min": -1.0,
		"enemy_contrast_min_frame": -1,
		"enemy_contrast_min_name": ""
	}
	for s: Dictionary in samples:
		var frame := int(s.get("frame", -1))
		var fl: Dictionary = s.get("floor", {})
		if int(fl.get("n", 0)) > 0:
			if out.floor_mean_min < 0.0 or float(fl.mean) < out.floor_mean_min:
				out.floor_mean_min = float(fl.mean)
				out.floor_mean_min_frame = frame
			if out.floor_p10_min < 0.0 or float(fl.p10) < out.floor_p10_min:
				out.floor_p10_min = float(fl.p10)
		var pl: Dictionary = s.get("player", {})
		if int(pl.get("px", 0)) >= MIN_SUBJECT_PX:
			if out.player_contrast_min < 0.0 or float(pl.contrast) < out.player_contrast_min:
				out.player_contrast_min = float(pl.contrast)
				out.player_contrast_min_frame = frame
		for e: Dictionary in s.get("enemies", []):
			if int(e.get("px", 0)) < MIN_SUBJECT_PX:
				continue
			if out.enemy_contrast_min < 0.0 or float(e.contrast) < out.enemy_contrast_min:
				out.enemy_contrast_min = float(e.contrast)
				out.enemy_contrast_min_frame = frame
				out.enemy_contrast_min_name = String(e.get("name", ""))
	# A target with nothing to measure is not met: the run never showed it
	out["floor_ok"] = out.floor_mean_min >= FLOOR_MIN
	out["player_ok"] = out.player_contrast_min >= CONTRAST_MIN
	out["enemy_ok"] = out.enemy_contrast_min < 0.0 or out.enemy_contrast_min >= CONTRAST_MIN
	return out
