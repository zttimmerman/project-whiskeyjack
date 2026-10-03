#!/usr/bin/env bash
# Look-dev spike (docs/trials/look-dev.md): builds variant B1's player, assets/lookdev/player_b1.glb, from the
# shipped player's own sources (P1 attempt-1, rigged as rig-1): the clean stage with smooth (source) normals
# instead of flat shading > 30 deg, and the source's 2048 px texture instead of 256 px. Colour correction
# toward concept-1 is kept; the mouth overlay is left out (it's drawn at 256 px). Nothing shipped changes.
#   scripts/lookdev/build_b1.sh [tripo-out/player dir]
# SIZE=1024 (or 512) builds the same at that texture size, as assets/lookdev/player_b1_<size>.glb.
# The sources are gitignored Tripo downloads: the default is this checkout's .tripo-out/player, else the main
# checkout's. assets/lookdev/ is gitignored too (3.4 MB GLB + 3.0 MB PNG); rerun this to get it back.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test -f "$ROOT/project.godot" || exit 2
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
SRC="${1:-$ROOT/.tripo-out/player}"
SIZE="${SIZE:-2048}"
NAME="player_b1"
[ "$SIZE" = 2048 ] || NAME="player_b1_$SIZE"
if [ ! -d "$SRC/rig-1" ]; then
	main="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)/.."
	SRC="$(cd "$main" && pwd)/.tripo-out/player"
fi
test -f "$SRC/work/clean-params.json" || { echo "build_b1.sh: no clean-params.json under $SRC/work" >&2; exit 2; }
rig="$(ls "$SRC"/rig-1/tripo-out/*/model.glb | head -1)"
concept="$(ls "$SRC"/concept-1/tripo-out/*/generated_image.png | head -1)"
work="$ROOT/.tripo-out/lookdev"
mkdir -p "$work" "$ROOT/assets/lookdev"
cp "$rig" "$work/player_rig1.glb"
cp "$concept" "$work/player_concept1.png"
python3 - "$SRC/work/clean-params.json" "$work/$NAME.params.json" "$work/player_concept1.png" "$SIZE" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
p.update(texture_size=int(sys.argv[4]), texture_overlays=[], reference_image=sys.argv[3])
json.dump(p, open(sys.argv[2], "w"), indent=2)
PY
blender -b --factory-startup --python-exit-code 1 -P "$ROOT/scripts/lookdev/clean_variant.py" -- \
	--input "$work/player_rig1.glb" --output "$ROOT/assets/lookdev/$NAME.glb" \
	--params "$work/$NAME.params.json" --report "$work/$NAME.report.json" > "$work/$NAME.log" 2>&1
python3 -c "import json,sys; r=json.load(open(sys.argv[1])); print('clean:', r['status'], r['errors'], r['triangle_count'], 'tris', r['textures'][0]['size_after']); sys.exit(r['status'] != 'pass')" "$work/$NAME.report.json"
# The shipped player's import settings (BoneMap, Fix Silhouette), so the shared library retargets the same way
awk '/^\[params\]/{p=1} p' "$ROOT/assets/meshes/player.glb.import" > "$ROOT/assets/lookdev/$NAME.glb.import"
"$GODOT" --headless --path "$ROOT" --import > "$work/import.log" 2>&1
(cd "$ROOT" && python3 scripts/tools/texture_imports.py --glb "assets/lookdev/$NAME.glb")
