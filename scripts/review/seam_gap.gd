extends RefCounted

# Seam-gap metric for characters built from separate shells (a body plus garment shells, e.g. Tripo
# P2): shells are the mesh's connected pieces after welding coincident vertices (UV-seam splits).
# - seam gap: vertices on different shells that touch at bind (within TOUCH_M) are paired with their
#   nearest such partner, and the largest distance between partners over the clip is the gap;
# - poke-through: a vertex inside another shell at bind (its nearest other-shell vertex within COVER_M
#   has a normal pointing away from it) that comes out through that vertex's tangent plane by more
#   than POKE_M in any frame. An approximation: the plane is the nearest vertex's, not the surface's.
# The motion review (scripts/review/motion_review.gd) creates one per clip, calls sample() each frame
# and adds result() to the clip's metrics. Static helpers take plain arrays so tests can drive them.

const WELD := 1e-5  # m: coincident vertices (UV-seam splits) belong to one shell
const TOUCH_M := 0.005  # m: cross-shell vertices this close at bind touch (garment offsets are 3-5 mm)
const COVER_M := 0.03  # m: a vertex this close under another shell is covered by it
const POKE_M := 0.002  # m: through the covering shell's plane by more than this is poking out
const CELL := 0.03  # m: spatial hash cell, at least COVER_M

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _bones := PackedInt32Array()
var _weights := PackedFloat32Array()
var _surface := PackedInt32Array()  # per vertex: index into _surfaces
var _surfaces := []  # [bind bones, bind poses, first vertex, influences per vertex]
var _pairs := PackedInt32Array()
var _covered := PackedInt32Array()
var _used := PackedInt32Array()  # vertices any pair needs, so only those are skinned
var _gap := [0.0, 0.0, Vector3.ZERO]  # [m, t, bind position of the worst pair]
var _poke_max := [0.0, 0.0, Vector3.ZERO]  # [m, t, bind position of the worst vertex]
var _poked := {}
var _shell_count := 0
var _bind_pos := PackedVector3Array()


func _init(root: Node3D, sk: Skeleton3D) -> void:
	var index := PackedInt32Array()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.mesh == null:
			continue
		var bind_bones := PackedInt32Array()
		var bind_poses: Array[Transform3D] = []
		for b in mi.skin.get_bind_count():
			var bn := mi.skin.get_bind_name(b)
			bind_bones.append(sk.find_bone(bn) if bn != "" else mi.skin.get_bind_bone(b))
			bind_poses.append(mi.skin.get_bind_pose(b))
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var base := _verts.size()
			var stride: int = (arr[Mesh.ARRAY_BONES] as PackedInt32Array).size() / maxi(verts.size(), 1)
			_surfaces.append([bind_bones, bind_poses, base, stride, _bones.size()])
			_verts.append_array(verts)
			_normals.append_array(arr[Mesh.ARRAY_NORMAL])
			_bones.append_array(arr[Mesh.ARRAY_BONES])
			_weights.append_array(arr[Mesh.ARRAY_WEIGHTS])
			for v in verts.size():
				_surface.append(_surfaces.size() - 1)
			if arr[Mesh.ARRAY_INDEX] != null:
				for i: int in arr[Mesh.ARRAY_INDEX]:
					index.append(base + i)
	# Bind positions in world space, the frame the skinned positions come back in
	var skg := sk.global_transform
	var bind_pos := PackedVector3Array()
	var bind_nrm := PackedVector3Array()
	for v in _verts.size():
		bind_pos.append(skg * _verts[v])
		bind_nrm.append((skg.basis * _normals[v]).normalized())
	_bind_pos = bind_pos
	var shell := shells(bind_pos, index)
	for v in shell:
		_shell_count = maxi(_shell_count, v + 1)
	_pairs = touching(bind_pos, shell, TOUCH_M)
	_covered = covered(bind_pos, bind_nrm, shell, COVER_M)
	var used := {}
	for v in _pairs:
		used[v] = true
	for v in _covered:
		used[v] = true
	_used = PackedInt32Array(used.keys())
	_used.sort()


# Skins the paired vertices (positions and normals) at the skeleton's current pose and keeps the worst
func sample(sk: Skeleton3D, t: float) -> void:
	var skg := sk.global_transform
	var xfs := []
	for surf: Array in _surfaces:
		var xf: Array[Transform3D] = []
		for b in surf[0].size():
			xf.append(skg * sk.get_bone_global_pose(surf[0][b]) * surf[1][b])
		xfs.append(xf)
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	pos.resize(_verts.size())
	nrm.resize(_verts.size())
	for v in _used:
		var surf: Array = _surfaces[_surface[v]]
		var xf: Array[Transform3D] = xfs[_surface[v]]
		var stride: int = surf[3]
		var first: int = surf[4] + (v - surf[2]) * stride
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		for k in stride:
			var w := _weights[first + k]
			if w > 0.0:
				var x := xf[_bones[first + k]]
				p += w * (x * _verts[v])
				n += w * (x.basis * _normals[v])
		pos[v] = p
		nrm[v] = n.normalized()
	var g: Array = max_gap(pos, _pairs)
	if g[0] > _gap[0]:
		_gap = [g[0], t, _bind_pos[g[1]]]
	for i in range(0, _covered.size(), 2):
		var s := (pos[_covered[i]] - pos[_covered[i + 1]]).dot(nrm[_covered[i + 1]])
		if s > POKE_M:
			_poked[_covered[i]] = true
		if s > _poke_max[0]:
			_poke_max = [s, t, _bind_pos[_covered[i]]]


func result() -> Dictionary:
	return {
		"shells": _shell_count,
		"seam_pairs": _pairs.size() / 2,
		"seam_touch_m": TOUCH_M,
		"seam_gap_max_m": snappedf(_gap[0], 0.0001),
		"seam_gap_worst_t": _gap[1],
		"seam_gap_worst_at": [snappedf(_gap[2].x, 0.001), snappedf(_gap[2].y, 0.001), snappedf(_gap[2].z, 0.001)],
		"covered_vertices": _covered.size() / 2,
		"cover_m": COVER_M,
		"poke_through_vertices": _poked.size(),
		"poke_through_max_m": snappedf(_poke_max[0], 0.0001),
		"poke_through_worst_t": _poke_max[1],
		"poke_through_worst_at":
		[snappedf(_poke_max[2].x, 0.001), snappedf(_poke_max[2].y, 0.001), snappedf(_poke_max[2].z, 0.001)],
	}


static func _key(p: Vector3, cell: float) -> Vector3i:
	return Vector3i(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))


static func _find(parent: Array, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x


# Shell id per vertex: connected through the index buffer, with coincident vertices (within WELD) merged
static func shells(verts: PackedVector3Array, index: PackedInt32Array) -> PackedInt32Array:
	var parent := range(verts.size())
	var first := {}
	for v in verts.size():
		var k := _key(verts[v], WELD)
		if first.has(k):
			parent[_find(parent, v)] = _find(parent, first[k])
		else:
			first[k] = v
	for i in range(0, index.size() - 2, 3):
		var r := _find(parent, index[i])
		for j in [index[i + 1], index[i + 2]]:
			var q := _find(parent, j)
			if q != r:
				parent[q] = r
	var ids := {}
	var out := PackedInt32Array()
	out.resize(verts.size())
	for v in verts.size():
		var r := _find(parent, v)
		if not ids.has(r):
			ids[r] = ids.size()
		out[v] = ids[r]
	return out


static func _grid(verts: PackedVector3Array) -> Dictionary:
	var grid := {}
	for v in verts.size():
		var k := _key(verts[v], CELL)
		if not grid.has(k):
			grid[k] = PackedInt32Array()
		grid[k].append(v)
	return grid


# Vertex v's nearest vertex on another shell within radius, or -1
static func _nearest_other(
	v: int, verts: PackedVector3Array, shell: PackedInt32Array, grid: Dictionary, radius: float
) -> int:
	var k := _key(verts[v], CELL)
	var best := -1
	var best_d := radius
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for u: int in grid.get(k + Vector3i(dx, dy, dz), PackedInt32Array()):
					if shell[u] == shell[v]:
						continue
					var d := verts[u].distance_to(verts[v])
					if d <= best_d:
						best_d = d
						best = u
	return best


# Pairs (flat a, b) of vertices on different shells within radius at bind: each vertex with its nearest
# other-shell partner, each unordered pair once
static func touching(verts: PackedVector3Array, shell: PackedInt32Array, radius: float) -> PackedInt32Array:
	var grid := _grid(verts)
	var seen := {}
	var out := PackedInt32Array()
	for v in verts.size():
		var u := _nearest_other(v, verts, shell, grid, radius)
		if u < 0:
			continue
		var key := Vector2i(mini(u, v), maxi(u, v))
		if seen.has(key):
			continue
		seen[key] = true
		out.append(key.x)
		out.append(key.y)
	return out


# Pairs (flat inner, outer): vertices under another shell at bind, each with the nearest vertex of the
# shell covering it (within radius) whose normal points away from it
static func covered(
	verts: PackedVector3Array, normals: PackedVector3Array, shell: PackedInt32Array, radius: float
) -> PackedInt32Array:
	var grid := _grid(verts)
	var out := PackedInt32Array()
	for v in verts.size():
		var u := _nearest_other(v, verts, shell, grid, radius)
		if u >= 0 and (verts[v] - verts[u]).dot(normals[u]) < 0.0:
			out.append(v)
			out.append(u)
	return out


# [largest distance between paired vertices, a, b]
static func max_gap(pos: PackedVector3Array, pairs: PackedInt32Array) -> Array:
	var worst := [0.0, -1, -1]
	for i in range(0, pairs.size(), 2):
		var d := pos[pairs[i]].distance_to(pos[pairs[i + 1]])
		if d > worst[0]:
			worst = [d, pairs[i], pairs[i + 1]]
	return worst


# [covered vertices out through their cover's plane by more than eps, the furthest out (m)]
static func poke(pos: PackedVector3Array, normals: PackedVector3Array, pairs: PackedInt32Array, eps: float) -> Array:
	var count := 0
	var worst := 0.0
	for i in range(0, pairs.size(), 2):
		var s := (pos[pairs[i]] - pos[pairs[i + 1]]).dot(normals[pairs[i + 1]])
		if s > eps:
			count += 1
		worst = maxf(worst, s)
	return [count, worst]
