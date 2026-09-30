#!/usr/bin/env bash
# Run replay scenarios headless, check each is deterministic, and score it against the design bible
# (docs/plans/phase-a/a2b-replay-harness.md):
#   scripts/review/run_scenario.sh tests/scenarios/levy_1v1_sensible.json      one scenario
#   scripts/review/run_scenario.sh tests/scenarios/*.json                      all of them (CI)
#   scripts/review/run_scenario.sh --runs 1 <scenario.json>                    skip the determinism run
# For each scenario it runs scripts/review/replay.tscn --runs times (default 2) on the replay save slot,
# compares every run's event log with the first (scripts/review/replay_metrics.py --compare), then
# writes the metrics. Outputs go to .replay-out/<name>/ (gitignored): run<N>.jsonl, metrics.json.
# Godot comes from $GODOT_BIN, else `godot` on PATH, else /Applications/Godot.app (4.7.2).
# Exit code: 0 when every scenario finished, matched itself and passed its checks; 1 otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 2
test -f "$ROOT/project.godot" || { echo "run_scenario.sh: no project.godot in $ROOT" >&2; exit 2; }

GODOT="${GODOT_BIN:-}"
if [ -z "$GODOT" ]; then
	if command -v godot > /dev/null; then
		GODOT="$(command -v godot)"
	else
		GODOT=/Applications/Godot.app/Contents/MacOS/Godot
	fi
fi
test -x "$GODOT" || { echo "run_scenario.sh: Godot not found at $GODOT (set GODOT_BIN)" >&2; exit 2; }

RUNS=2
if [ "${1:-}" = "--runs" ]; then
	RUNS="$2"
	shift 2
fi
[ $# -gt 0 ] || { echo "usage: run_scenario.sh [--runs N] <scenario.json>..." >&2; exit 2; }

status=0
for scenario in "$@"; do
	scenario_abs="$(cd "$(dirname "$scenario")" && pwd)/$(basename "$scenario")"
	name="$(basename "$scenario" .json)"
	out="$ROOT/.replay-out/$name"
	mkdir -p "$out"
	rm -f "$out"/run*.jsonl "$out"/run*.log "$out/metrics.json"
	echo "== $name"
	for i in $(seq 1 "$RUNS"); do
		# stdin from /dev/null: a script error never waits at the debugger prompt
		"$GODOT" --headless --fixed-fps 60 --path "$ROOT" res://scripts/review/replay.tscn -- \
			--scenario "$scenario_abs" --event-log "$out/run$i.jsonl" --save-slot=replay \
			< /dev/null > "$out/run$i.log" 2>&1
		code=$?
		if [ $code -ne 0 ] || ! grep -q '"event":"scenario_end"' "$out/run$i.jsonl" 2> /dev/null; then
			echo "run $i failed (exit $code); last lines of $out/run$i.log:"
			tail -20 "$out/run$i.log"
			status=1
			continue 2
		fi
		if grep -q "SCRIPT ERROR" "$out/run$i.log"; then
			echo "run $i logged script errors:"
			grep -A3 "SCRIPT ERROR" "$out/run$i.log" | head -30
			status=1
		fi
		if [ "$i" -gt 1 ]; then
			python3 "$ROOT/scripts/review/replay_metrics.py" --compare "$out/run1.jsonl" "$out/run$i.jsonl" || status=1
		fi
	done
	python3 "$ROOT/scripts/review/replay_metrics.py" --scenario "$scenario_abs" --log "$out/run1.jsonl" \
		--out "$out/metrics.json" || status=1
done
exit $status
