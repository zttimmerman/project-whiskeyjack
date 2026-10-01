#!/usr/bin/env bash
# Rendered evidence for a replay scenario, on the Mac (docs/plans/phase-a/a2b-replay-harness.md):
#   scripts/review/capture_evidence.sh tests/scenarios/levy_1v1_sensible.json [--events hit,dodge_start,stagger] [--keep-frames]
# Runs scripts/review/replay.tscn in a window with Movie Maker (--write-movie, a PNG sequence at a fixed
# 60 fps; the replay turns vsync off), then uses ffmpeg to make, in .replay-out/<name>/capture/ (gitignored):
#   run.mp4             H.264 of the run, with its audio, for humans
#   events/*.png        the frame of every listed event (default: hit, dodge_start, stagger), labelled,
#                       for the playtest critic; events/index.json lists them with the event fields
#   contact_sheet.png   16 evenly spaced frames, 4x4, labelled with their scenario frame
#   capture.jsonl       the run's event log; it is compared with the headless run1.jsonl when that exists
# Hands off the keyboard and mouse while the window runs: the replay ignores real devices. The window is
# kept on top (--always-on-top): covered, macOS throttles it and Movie Maker records stale frames (63 of 542
# rendered once). Rendered capture stays on the Mac (Linux llvmpipe colours differ).
# Godot comes from $GODOT_BIN, else /Applications/Godot.app; ffmpeg from $FFMPEG, else /opt/homebrew/bin/ffmpeg.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 2
test -f "$ROOT/project.godot" || { echo "capture_evidence.sh: no project.godot in $ROOT" >&2; exit 2; }
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
FFMPEG="${FFMPEG:-/opt/homebrew/bin/ffmpeg}"
test -x "$GODOT" || { echo "capture_evidence.sh: Godot not found at $GODOT (set GODOT_BIN)" >&2; exit 2; }
test -x "$FFMPEG" || FFMPEG="$(command -v ffmpeg)" || { echo "capture_evidence.sh: ffmpeg not found (set FFMPEG)" >&2; exit 2; }

scenario=""
events="hit,dodge_start,stagger"
keep_frames=0
while [ $# -gt 0 ]; do
	case "$1" in
		--events) events="$2"; shift 2 ;;
		--keep-frames) keep_frames=1; shift ;;
		*) scenario="$1"; shift ;;
	esac
done
[ -n "$scenario" ] && [ -f "$scenario" ] || { echo "usage: capture_evidence.sh <scenario.json> [--events a,b] [--keep-frames]" >&2; exit 2; }
scenario_abs="$(cd "$(dirname "$scenario")" && pwd)/$(basename "$scenario")"
name="$(basename "$scenario" .json)"
out="$ROOT/.replay-out/$name/capture"
rm -rf "$out"
mkdir -p "$out/frames" "$out/events"

# Labels need a font file for ffmpeg's drawtext; without one the images are unlabelled
font=""
for f in /System/Library/Fonts/Supplemental/Arial.ttf /System/Library/Fonts/Helvetica.ttc /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf; do
	[ -f "$f" ] && { font="$f"; break; }
done

echo "== $name: rendering (Movie Maker)"
"$GODOT" --always-on-top --fixed-fps 60 --write-movie "$out/frames/frame.png" --path "$ROOT" res://scripts/review/replay.tscn -- \
	--scenario "$scenario_abs" --event-log "$out/capture.jsonl" --save-slot=replay < /dev/null > "$out/capture.log" 2>&1
code=$?
if [ $code -ne 0 ] || ! grep -q '"event":"scenario_end"' "$out/capture.jsonl" 2> /dev/null; then
	echo "the rendered run failed (exit $code); see $out/capture.log" >&2
	tail -20 "$out/capture.log" >&2
	exit 1
fi
if [ -f "$ROOT/.replay-out/$name/run1.jsonl" ]; then
	python3 "$ROOT/scripts/review/replay_metrics.py" --compare "$ROOT/.replay-out/$name/run1.jsonl" "$out/capture.jsonl" \
		|| echo "WARNING: the rendered run's events differ from the headless run's"
fi

# Movie frame index = the process frame at scenario frame 0 (logged in scenario_start) + scenario frame;
# each image shows the state after that frame's physics step
offset="$(python3 -c 'import json,sys; print(json.loads(open(sys.argv[1]).readline())["process_frame"])' "$out/capture.jsonl")"
count="$(ls "$out/frames" | grep -c '^frame[0-9]*\.png$')"
echo "   $count frames, scenario frame 0 = movie frame $offset"

echo "== encoding run.mp4"
audio=()
[ -f "$out/frames/frame.wav" ] && audio=(-i "$out/frames/frame.wav" -c:a aac -b:a 128k -shortest)
"$FFMPEG" -hide_banner -loglevel error -y -framerate 60 -i "$out/frames/frame%08d.png" "${audio[@]}" \
	-c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart "$out/run.mp4" || exit 1

echo "== extracting event frames ($events)"
# One line per event: movie_index<TAB>file_stem<TAB>label; index.json keeps the event fields
python3 - "$out/capture.jsonl" "$events" "$offset" "$count" "$out/events/index.json" > "$out/events/list.tsv" <<'PY' || exit 1
import json, re, sys
log, wanted, offset, count, index_path = sys.argv[1], sys.argv[2].split(","), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
index = []
for line in open(log):
    e = json.loads(line)
    if e["event"] not in wanted:
        continue
    movie = offset + e["frame"]
    if movie >= count:
        continue
    who = e.get("actor") or "%s-%s" % (e.get("attacker", ""), e.get("target", ""))
    stem = "f%04d_%s_%s" % (e["frame"], e["event"], re.sub(r"[^A-Za-z0-9-]", "", who))
    stem += "_%d" % sum(1 for i in index if i["file"].startswith(stem))  # two events on one frame
    label = "frame %d  %s  %s" % (e["frame"], e["event"], who)
    index.append(dict(e, file=stem + ".png", movie_frame=movie))
    print("%d\t%s\t%s" % (movie, stem, label))
json.dump(index, open(index_path, "w"), indent=1)
PY
while IFS=$'\t' read -r movie stem label; do
	vf="null"
	[ -n "$font" ] && vf="drawtext=fontfile=$font:text='$label':x=16:y=16:fontsize=28:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=8"
	"$FFMPEG" -hide_banner -loglevel error -y -start_number "$movie" -i "$out/frames/frame%08d.png" -frames:v 1 \
		-vf "$vf" -update 1 "$out/events/$stem.png" || exit 1
done < "$out/events/list.tsv"
rm -f "$out/events/list.tsv"
echo "   $(ls "$out/events" | grep -c '\.png$') event frames"

echo "== contact sheet"
step=$(( count / 16 ))
[ $step -lt 1 ] && step=1
# Labelled before the select, so n is the movie frame
label=""
[ -n "$font" ] && label="drawtext=fontfile=$font:text='f%{eif\:n-$offset\:d}':x=8:y=8:fontsize=40:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=6,"
"$FFMPEG" -hide_banner -loglevel error -y -i "$out/frames/frame%08d.png" \
	-vf "${label}select='not(mod(n\,$step))*lt(n\,$(( step * 16 )))',scale=480:-2,tile=4x4:padding=4" \
	-frames:v 1 -fps_mode vfr "$out/contact_sheet.png" || exit 1

[ $keep_frames -eq 1 ] || rm -rf "$out/frames"
echo "== done: $out"
ls -1 "$out"
