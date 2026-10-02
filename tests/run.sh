#!/usr/bin/env bash
# Run every gdUnit4 test under tests/ headless, locally or in CI:
#   tests/run.sh                  all suites
#   tests/run.sh -a res://tests/unit/test_inventory.gd     one suite (any GdUnitCmdTool args)
# Godot comes from $GODOT_BIN, else `godot` on PATH, else /Applications/Godot.app (4.7.2).
# Reports (HTML and JUnit results.xml) go to reports/report_<n>/ (gitignored). Exit code: 0 all passed,
# 100 failures, 101 warnings only (orphans), 124 a Godot call ran past its limit, anything else a runner error.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2
test -f "$ROOT/project.godot" || { echo "run.sh: no project.godot in $ROOT" >&2; exit 2; }

GODOT="${GODOT_BIN:-}"
if [ -z "$GODOT" ]; then
	if command -v godot > /dev/null; then
		GODOT="$(command -v godot)"
	else
		GODOT=/Applications/Godot.app/Contents/MacOS/Godot
	fi
fi
test -x "$GODOT" || { echo "run.sh: Godot not found at $GODOT (set GODOT_BIN)" >&2; exit 2; }
# Every Godot call runs under a limit (a hung Godot fails with 124); see the helper for the variables
source "$ROOT/scripts/tools/godot_timeout.sh" || exit 2

# Keep the editor and imports from scanning the reports (they include a .png)
mkdir -p "$ROOT/reports" && touch "$ROOT/reports/.gdignore"

ARGS=("$@")
[ ${#ARGS[@]} -eq 0 ] && ARGS=(-a res://tests)

# Tests never share the player's user://save.json (the suites also pin their own slots)
export WHISKEYJACK_SAVE_SLOT="${WHISKEYJACK_SAVE_SLOT:-gdunit}"

# A runtime error in a test stops at the debug> prompt, and with stdin at EOF Godot aborts; pointing
# --remote-debug at a port nothing listens on skips the prompt (as gdUnit4's runtest.sh does; it logs
# two "Remote Debugger" errors). stdin is /dev/null so nothing can wait on input.
with_timeout GODOT_TIMEOUT_TESTS 1500 "tests/run.sh: gdUnit4 run" \
	"$GODOT" --headless --path "$ROOT" -d --remote-debug tcp://127.0.0.1:0 \
	-s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c -rd res://reports \
	"${ARGS[@]}" < /dev/null
code=$?
with_timeout GODOT_TIMEOUT_RUN 600 "tests/run.sh: gdUnit4 log copy" \
	"$GODOT" --headless --path "$ROOT" --quiet -s res://addons/gdUnit4/bin/GdUnitCopyLog.gd \
	-rd res://reports < /dev/null > /dev/null
echo "tests/run.sh: exit $code"
exit $code
