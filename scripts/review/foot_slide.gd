extends RefCounted

# Foot slide and gait, shared by the motion review (scripts/review/motion_review.gd) and the locomotion and
# gait tests (tests/unit/test_locomotion_foot_slide.gd, test_motion_gait.gd): the ground-relative
# horizontal speed of each foot's contact point (the lowest of its candidates: a humanoid's Foot and Toes)
# while it is planted (within CONTACT_HEIGHT of its lowest point in the clip, and moving vertically slower
# than CONTACT_VSPEED). Clips play in place, so the ground moves at the gameplay speed toward -Z (the model
# faces +Z). The tolerances are the art bible's motion_foot_slide_bhps, motion_gait_lift_bh and
# motion_gait_swing_bh, per body height (docs/art-bible.md → Judge tolerances, the only source).
# A contact point's velocity is its own bone's: when the lowest point hops from Foot to Toes as the
# foot rolls, differencing across the hop reads the ~5 cm between the two joints as motion (a false
# 0.8 m/s dip mid-stance on the Back-file walk). A looping clip's last sample is its first instant
# again: velocities difference across the seam, and that instant counts once.
# Which bones are feet comes from the rig's limb map (scripts/review/LimbMap.gd), humanoid by default:
# any number of feet, each with one or more contact candidates (a stub leg's single bone, at its tip).

# Sizes: the contact thresholds and the art bible's motion limits are per body height (the rig's height in
# the bind pose, body_height()), so a 1 m boar and a 4.6 m one are held to the same gait. The metre values
# are a REFERENCE_HEIGHT body's: every humanoid character is 1.8 m tall, so its results don't change.
const REFERENCE_HEIGHT := 1.8  # m
const CONTACT_HEIGHT := 0.03  # m, at REFERENCE_HEIGHT
const CONTACT_VSPEED := 0.25  # m/s, at REFERENCE_HEIGHT


# Every foot's candidate positions this frame, in world space, by side in the limb map's order
# (humanoid: {"left": [foot, toes], "right": [foot, toes]}); a bone the rig lacks reads as the origin
static func feet(sk: Skeleton3D, limbs: LimbMap = null) -> Dictionary:
	var lm := LimbMap.or_default(limbs)
	var out := {}
	for side: String in lm.feet:
		out[side] = []
		for bone: String in lm.feet[side]:
			var p: Variant = lm.locate(sk, bone, sk.global_transform)
			out[side].append(p if p != null else Vector3.ZERO)
	return out


# The sides feet() returned, in order
static func sides(samples: Array) -> Array:
	return samples[0].keys() if not samples.is_empty() else []


# The body's size: the vertical extent of the model's skinned meshes in the bind pose (each vertex under the
# skeleton's transform, as the motion review takes the bind pose), to the millimetre. The skeleton must be in
# the tree. A model with no skinned mesh reads as REFERENCE_HEIGHT.
static func body_height(sk: Skeleton3D, model: Node) -> float:
	var lo := INF
	var hi := -INF
	var xf := sk.global_transform
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var y := (xf * v).y
				lo = minf(lo, y)
				hi = maxf(hi, y)
	return snappedf(hi - lo, 0.001) if hi > lo else REFERENCE_HEIGHT


# t: sample times (s); samples: one feet() result per sample; scale: the body's height over REFERENCE_HEIGHT
# (the contact thresholds scale with it). Returns each side's contact points, planted flags and
# ground-relative horizontal speeds, and the slide over all planted frames.
static func measure(t: Array, samples: Array, ground_speed: float, looping: bool, scale := 1.0) -> Dictionary:
	var ground := Vector3(0, 0, ground_speed)
	var contact_height := CONTACT_HEIGHT * scale
	var contact_vspeed := CONTACT_VSPEED * scale
	var out := {"points": {}, "contact": {}, "speeds": {}}
	var slides := []
	for side in sides(samples):
		var bones := []
		for c in samples[0][side].size():
			bones.append(samples.map(func(s): return s[side][c]))
		var lower := []
		var points := []
		for f in samples.size():
			# The lowest candidate; ties keep the earlier one (a humanoid's ankle over its toes)
			var k := 0
			for c in range(1, bones.size()):
				if bones[c][f].y < bones[k][f].y:
					k = c
			lower.append(k)
			points.append(bones[k][f])
		var ys: Array = points.map(func(p): return p.y)
		var floor_y: float = ys.min()
		var contact := []
		var speeds := []
		var last := points.size() - 1
		for f in points.size():
			if looping and f == last and last > 0:
				contact.append(contact[0])
				speeds.append(speeds[0])
				continue
			var v := velocity(bones[lower[f]], f, t, looping) + ground
			# Planted: near its lowest point and not lifting or striking (heel-strike and toe-off frames
			# are close to the floor but still moving vertically)
			var c: bool = ys[f] <= floor_y + contact_height and absf(v.y) < contact_vspeed
			var sp := Vector2(v.x, v.z).length()
			contact.append(c)
			speeds.append(sp)
			if c:
				slides.append(sp)
		out["points"][side] = points
		out["contact"][side] = contact
		out["speeds"][side] = speeds
	out["contact_frames"] = slides.size()
	out["foot_slide_p90_mps"] = snappedf(percentile(slides, 0.9), 0.001)
	out["foot_slide_max_mps"] = snappedf(slides.max() if slides else 0.0, 0.001)
	return out


# The gait check's evidence: how far each foot's contact point (measure()'s points) lifts above its lowest
# point in the clip, and how far it swings relative to the root (the widest horizontal distance between two of
# its root-relative positions, so a foot frozen under a bobbing body reads near zero). One clip is one cycle.
# points: side -> contact points; root: the root bone's positions on the same frames.
static func gait(points: Dictionary, root: Array) -> Dictionary:
	var out := {}
	for side: String in points:
		var p: Array = points[side]
		var ys: Array = p.map(func(q): return q.y)
		var rel := []
		for f in p.size():
			var d: Vector3 = p[f] - root[f]
			rel.append(Vector2(d.x, d.z))
		var swing := 0.0
		for a in rel.size():
			for b in range(a + 1, rel.size()):
				swing = maxf(swing, (rel[a] as Vector2).distance_to(rel[b]))
		out[side] = {"lift_m": snappedf(ys.max() - ys.min(), 0.001), "swing_m": snappedf(swing, 0.001)}
	return out


# One line of each foot's lift and swing in body heights (metres are in the metrics) (the motion review's plots header);
# whether a foot is under the art bible's gait limits is the judge's assertion, so this only reports
static func gait_line(gait: Dictionary, height: float) -> String:
	var parts := []
	for side: String in gait:
		var g: Dictionary = gait[side]
		parts.append("%s %.3f / %.3f" % [side.replace("_", " "), g["lift_bh"], g["swing_bh"]])
	return "Gait, lift / swing per foot in body heights (%.2f m): %s" % [height, ";  ".join(parts)]


# Central difference at sample f. The last sample is the clip's end (t = length); a looping clip's end
# is its start, so its ends difference across the seam, and a one-shot clip's are one-sided.
static func velocity(points: Array, f: int, t: Array, looping: bool) -> Vector3:
	var last := points.size() - 1
	if looping and last >= 2 and (f == 0 or f == last):
		var dt: float = (t[1] - t[0]) + (t[last] - t[last - 1])
		return (points[1] - points[last - 1]) / dt
	var a := maxi(f - 1, 0)
	var b := mini(f + 1, last)
	if b == a:
		return Vector3.ZERO
	return (points[b] - points[a]) / (t[b] - t[a])


static func percentile(values: Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var s := values.duplicate()
	s.sort()
	return s[clampi(int(round(q * (s.size() - 1))), 0, s.size() - 1)]
