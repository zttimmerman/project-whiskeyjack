#!/usr/bin/env bash
# Look-dev spike (docs/trials/look-dev.md): renders every variant's stills and frame times, then the
# labelled side-by-side sheets. On the Mac, windowed (headless can't render); hands off while it runs.
#   scripts/lookdev/run_lookdev.sh [out-dir]     (default .tripo-out/lookdev, gitignored)
# Sheets: <out>/sheets/<room>_<shot>.jpg (A | B1 | B2 | B3 | B3plus), turntable_<variant>.mp4,
# timing.json (every variant's frame times, at 1280x720 and 2560x1440; the viewport's GPU timer reads 0
# on this Mac, so frame time is the wall-clock frame delta with vsync off). B3/B3plus run with --rendering-method forward_plus; the
# project setting stays gl_compatibility.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 2
test -f "$ROOT/project.godot" || exit 2
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${1:-$ROOT/.tripo-out/lookdev}"
SHOTS="$OUT/shots"
mkdir -p "$SHOTS" "$OUT/sheets"
VARIANTS="${VARIANTS:-A B1 B2 B3 B3plus}"  # variant C: VARIANTS="A B2 C-albedo C-PBR C-budget"
font=/System/Library/Fonts/Supplemental/Arial.ttf

run() {  # variant room mode [extra godot args]
	local v="$1" room="$2" mode="$3"; shift 3
	local extra=()
	case "$v" in B3* | C-PBR) extra=(--rendering-method forward_plus) ;; esac
	[ "$mode" = stills ] && extra+=(--fixed-fps 30)
	echo "== $v $room $mode"
	timeout 600 "$GODOT" --always-on-top ${extra[@]+"${extra[@]}"} --path "$ROOT" res://scenes/lookdev/LookDev.tscn -- \
		--variant "$v" --room "$room" --mode "$mode" --out "$SHOTS" "$@" < /dev/null > "$SHOTS/${v}_${room}_${mode}${2:+_$2}.log" 2>&1 \
		|| { echo "failed: see $SHOTS/${v}_${room}_${mode}${2:+_$2}.log" >&2; return 1; }
}

for v in $VARIANTS; do
	for room in level1 crypt; do
		run "$v" "$room" stills || exit 1
		run "$v" "$room" timing || exit 1
		run "$v" "$room" timing --size 2560x1440 || exit 1
	done
	ffmpeg -loglevel error -y -framerate 30 -i "$SHOTS/turntable_$v/f%03d.png" -vf scale=640:-2 -c:v libx264 -pix_fmt yuv420p \
		"$OUT/sheets/turntable_$v.mp4"
done

# Sheets: one row per shot, a labelled tile per variant
for room in level1 crypt; do
	for shot in gameplay face body34 room; do
		tiles=()
		for v in $VARIANTS; do
			tiles+=("(" "$SHOTS/${room}_${shot}_${v}.png" -resize 640x -gravity north -background black -splice 0x34 \
				-font "$font" -pointsize 24 -fill white -annotate +0+4 "$v" ")")
		done
		magick "${tiles[@]}" +append -quality 85 "$OUT/sheets/${room}_${shot}.jpg"
	done
done
python3 - "$SHOTS" "$OUT/sheets/timing.json" <<'PY'
import glob, json, sys
rows = [json.load(open(p)) for p in sorted(glob.glob(sys.argv[1] + "/timing_*.json"))]
json.dump(rows, open(sys.argv[2], "w"), indent=2)
for r in rows:
    print(f"{r['room']:7} {r['variant']:7} {r['renderer']:16} {r['viewport_px'][0]}x{r['viewport_px'][1]} " + "  ".join(
        f"{v}: frame {r[v]['frame_ms']['median']:.2f} ms (p95 {r[v]['frame_ms']['p95']:.2f})" for v in ("gameplay", "overview")))
PY
