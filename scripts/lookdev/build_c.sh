#!/usr/bin/env bash
# Look-dev variant C (docs/backlog/look-dev-c.md, docs/trials/look-dev.md → Variant C): the PS3-class player
# from Tripo v3.1 (PBR, no face_limit) built from the same approved multiview-1 sheet as the shipped player,
# rigged by the v1.0 humanoid rigger (.tripo-out/player_c/rig-1). Three builds, all under the gitignored
# assets/lookdev/, all through scripts/lookdev/clean_variant.py (the clean stage with source normals kept,
# the shipped player's brief otherwise: facing, 1.8 m, skirt reweight):
#   player_c_pbr.glb     C-PBR: the material as delivered (2048 px base colour, metallic-roughness, normal)
#   player_c.glb         C-albedo: albedo only at 1024 px, colour-corrected toward concept-1 like B1
#   player_c_budget.glb  C-budget: collapse-decimated to about $BUDGET triangles first, then as C-albedo
#   scripts/lookdev/build_c.sh [pbr|albedo|budget ...]      (default: all three)
# Sources are gitignored: this checkout's .tripo-out/player_c and .tripo-out/player (concept-1, clean params),
# else the main checkout's. Nothing shipped changes.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test -f "$ROOT/project.godot" || exit 2
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
BUDGET="${BUDGET:-20000}"
main="$(cd "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)"
pick() { [ -d "$ROOT/.tripo-out/$1" ] && echo "$ROOT/.tripo-out/$1" || echo "$main/.tripo-out/$1"; }
SRC_C="$(pick player_c)"
SRC_P="$(pick player)"
rig="$(ls "$SRC_C"/rig-1/tripo-out/*/model.glb | head -1)"
concept="$(ls "$SRC_P"/concept-1/tripo-out/*/generated_image.png | head -1)"
test -f "$SRC_P/work/clean-params.json" || { echo "build_c.sh: no clean-params.json under $SRC_P/work" >&2; exit 2; }
work="$ROOT/.tripo-out/lookdev"
mkdir -p "$work" "$ROOT/assets/lookdev"
cp "$rig" "$work/player_c_rig1.glb"
cp "$concept" "$work/player_concept1.png"

build() {  # name texture-size [env...]
	local name="$1" size="$2"
	shift 2
	python3 - "$SRC_P/work/clean-params.json" "$work/$name.params.json" "$work/player_concept1.png" "$size" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
# No triangle ceiling in the spike: C is measured against the art bible's budget, not held to it
p.update(texture_size=int(sys.argv[4]), texture_overlays=[], reference_image=sys.argv[3], triangle_budget=10**8)
json.dump(p, open(sys.argv[2], "w"), indent=2)
PY
	echo "== $name"
	env "$@" blender -b --factory-startup --python-exit-code 1 -P "$ROOT/scripts/lookdev/clean_variant.py" -- \
		--input "$work/player_c_rig1.glb" --output "$ROOT/assets/lookdev/$name.glb" \
		--params "$work/$name.params.json" --report "$work/$name.report.json" > "$work/$name.log" 2>&1
	python3 -c "import json,sys; r=json.load(open(sys.argv[1])); print('clean:', r['status'], r['errors'], r['triangle_count'], 'tris', [t['size_after'] for t in r['textures']])
sys.exit(r['status'] != 'pass')" "$work/$name.report.json"
	# The shipped player's import settings (BoneMap, Fix Silhouette), so the shared library retargets the same way
	awk '/^\[params\]/{p=1} p' "$ROOT/assets/meshes/player.glb.import" > "$ROOT/assets/lookdev/$name.glb.import"
}

for v in "${@:-pbr albedo budget}"; do
	for w in $v; do
		case "$w" in
		pbr) build player_c_pbr 2048 LOOKDEV_KEEP_PBR=1 ;;
		albedo) build player_c 1024 LOOKDEV_NONE=1 ;;
		budget) build player_c_budget 1024 LOOKDEV_DECIMATE="$BUDGET" ;;
		*) echo "build_c.sh: unknown variant $w" >&2; exit 2 ;;
		esac
	done
done
"$GODOT" --headless --path "$ROOT" --import > "$work/import_c.log" 2>&1
for f in "$ROOT"/assets/lookdev/player_c*.glb; do
	(cd "$ROOT" && python3 scripts/tools/texture_imports.py --glb "assets/lookdev/$(basename "$f")")
done
