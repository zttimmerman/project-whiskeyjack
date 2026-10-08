#!/usr/bin/env bash
# Rendered readability checks for replay scenarios, on the Mac (design bible §5 and §9:
# lvl_floor_luminance_min, read_char_contrast_min):
#   scripts/review/capture_luminance.sh tests/scenarios/crypt_trial_walk.json [more.json ...] [--every 30]
# Runs scripts/review/replay.tscn in a window with --luminance (scripts/review/luminance_probe.gd has the
# method): every --every frames (default 30) it measures the walkable floor from the gameplay camera and the
# contrast of the player and of each enemy in view against what's behind them. Outputs go to
# .replay-out/<name>/luminance/ (gitignored): luminance.json (every sample and the summary), shots/ (each
# sampled frame and the player's pixel mask, for checking what was measured), capture.jsonl
# (the run's event log, compared with the headless run1.jsonl when that exists) and capture.log.
# Prints one line per scenario with each minimum against its target. Not run in CI: Linux llvmpipe colours
# differ from the Mac's, so the numbers only mean something rendered here.
# Hands off the keyboard and mouse while the window runs; it is kept on top (a covered window is throttled).
# Godot comes from $GODOT_BIN, else /Applications/Godot.app.
# Exit code: 0 when every run completed (a missed target is reported, not failed), 1 when a run failed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 2
test -f "$ROOT/project.godot" || { echo "capture_luminance.sh: no project.godot in $ROOT" >&2; exit 2; }
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
test -x "$GODOT" || { echo "capture_luminance.sh: Godot not found at $GODOT (set GODOT_BIN)" >&2; exit 2; }
# Each windowed run is under GODOT_TIMEOUT_CAPTURE (scripts/tools/godot_timeout.sh): a hung run fails with 124
source "$ROOT/scripts/tools/godot_timeout.sh" || exit 2

every=30
scenarios=()
while [ $# -gt 0 ]; do
	case "$1" in
		--every) every="$2"; shift 2 ;;
		*) scenarios+=("$1"); shift ;;
	esac
done
[ ${#scenarios[@]} -gt 0 ] || { echo "usage: capture_luminance.sh <scenario.json>... [--every N]" >&2; exit 2; }

status=0
for scenario in "${scenarios[@]}"; do
	[ -f "$scenario" ] || { echo "capture_luminance.sh: no scenario $scenario" >&2; status=1; continue; }
	scenario_abs="$(cd "$(dirname "$scenario")" && pwd)/$(basename "$scenario")"
	name="$(basename "$scenario" .json)"
	out="$ROOT/.replay-out/$name/luminance"
	rm -rf "$out"
	mkdir -p "$out/shots"
	echo "== $name: rendering (every $every frames)"
	with_timeout GODOT_TIMEOUT_CAPTURE 1200 "capture_luminance.sh: $name rendered run" \
		"$GODOT" --always-on-top --fixed-fps 60 --path "$ROOT" res://scripts/review/replay.tscn -- \
		--scenario "$scenario_abs" --event-log "$out/capture.jsonl" --save-slot=replay \
		--luminance "$out/luminance.json" --luminance-every "$every" \
		--luminance-shots "$out/shots" < /dev/null > "$out/capture.log" 2>&1
	code=$?
	if [ $code -ne 0 ] || [ ! -f "$out/luminance.json" ]; then
		echo "the rendered run failed (exit $code); see $out/capture.log" >&2
		tail -20 "$out/capture.log" >&2
		status=1
		continue
	fi
	if grep -q "SCRIPT ERROR" "$out/capture.log"; then
		echo "the rendered run logged script errors:" >&2
		grep -A3 "SCRIPT ERROR" "$out/capture.log" | head -30 >&2
		status=1
	fi
	# The paired renders must not change the run: its events match the headless run's
	if [ -f "$ROOT/.replay-out/$name/run1.jsonl" ]; then
		python3 "$ROOT/scripts/review/replay_metrics.py" --compare "$ROOT/.replay-out/$name/run1.jsonl" \
			"$out/capture.jsonl" || echo "WARNING: the rendered run's events differ from the headless run's"
	fi
	python3 - "$out/luminance.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))["summary"]
def row(label, value, target, ok, where):
    shown = "not in view" if value < 0 else "%.4f" % value if "floor" in label else "%.2f" % value
    verdict = "-" if value < 0 else ("ok" if ok else "MISS")
    print("   %-16s %-12s target %-7s %-4s %s" % (label, shown, target, verdict, where if value >= 0 else ""))
print("   %d samples" % s["samples"])
row("floor mean min", s["floor_mean_min"], ">=0.05", s["floor_ok"], "frame %d (p10 %.4f)" % (s["floor_mean_min_frame"], s["floor_p10_min"]))
row("player contrast", s["player_contrast_min"], ">=1.3", s["player_ok"], "frame %d" % s["player_contrast_min_frame"])
row("enemy contrast", s["enemy_contrast_min"], ">=1.3", s["enemy_ok"], "frame %d %s" % (s["enemy_contrast_min_frame"], s["enemy_contrast_min_name"]))
PY
done
exit $status
