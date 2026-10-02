#!/usr/bin/env bash
# A time limit on every Godot (and Blender) call from a shell script, the bash half of the one helper
# (scripts/tools/godot_timeout.py is the Python half). On macOS a fatal Godot error opens a modal alert
# that --headless can't dismiss, so the process idles at 0% CPU forever instead of exiting (the idea is
# from htdt/godogen, engines/godot.md, "Quirks worth knowing"; MIT). A limit turns that hang into a failure.
#
# Source it and call with_timeout, or run it as a command (CI steps, OS.execute):
#   source scripts/tools/godot_timeout.sh
#   with_timeout <ENV_VAR> <default seconds> <label> <command> [args...]
#   scripts/tools/godot_timeout.sh <ENV_VAR> <default seconds> <label> <command> [args...]
# The limit is $ENV_VAR when it is set, else the default. The variables in use (seconds):
#   GODOT_TIMEOUT_IMPORT   900   headless --import (a cold import of every asset takes minutes)
#   GODOT_TIMEOUT_RUN      600   one headless script or scene run: load_all, a generator, a bake, a replay run
#   GODOT_TIMEOUT_TESTS    1500  the whole gdUnit4 run (tests/run.sh)
#   GODOT_TIMEOUT_CAPTURE  1200  a windowed Movie Maker capture (scripts/review/capture_evidence.sh)
#   BLENDER_TIMEOUT        1800  one headless Blender run (scripts/pipeline.py, scripts/judge.py)
# Exit status: the command's own, or 124 when the limit expired (the command is sent TERM, then KILL 15 s
# later), with "<label>: timed out after <n>s ..." on stderr. Needs coreutils' timeout (Linux) or gtimeout
# / timeout from Homebrew coreutils (macOS: brew install coreutils).

with_timeout() {
	if [ $# -lt 4 ]; then
		echo "with_timeout: usage: with_timeout <ENV_VAR> <default seconds> <label> <command> [args...]" >&2
		return 2
	fi
	local var=$1 default=$2 label=$3
	shift 3
	local limit=${!var:-$default}
	if ! [[ "$limit" =~ ^[0-9]+$ ]] || [ "$limit" -eq 0 ]; then
		echo "with_timeout: $var=$limit is not a positive whole number of seconds" >&2
		return 2
	fi
	local bin=""
	for c in timeout gtimeout /opt/homebrew/bin/gtimeout /opt/homebrew/bin/timeout /usr/local/bin/gtimeout; do
		if command -v "$c" > /dev/null 2>&1; then
			bin=$(command -v "$c")
			break
		fi
	done
	if [ -z "$bin" ]; then
		echo "with_timeout: no timeout command for $label (macOS: brew install coreutils)" >&2
		return 2
	fi
	local start=$SECONDS code
	# --foreground keeps the command in the caller's process group, so Ctrl-C still reaches it
	"$bin" --foreground -k 15 "$limit" "$@"
	code=$?
	# 124: TERM after the limit. 137: it ignored TERM and was killed (a child killed by anything else
	# also reads 137, hence the elapsed-time check).
	if [ $code -eq 124 ] || { [ $code -eq 137 ] && [ $((SECONDS - start)) -ge "$limit" ]; }; then
		echo "$label: timed out after ${limit}s and was stopped (exit $code); a hung Godot or Blender, or raise the limit with $var=<seconds>" >&2
		return 124
	fi
	return $code
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	with_timeout "$@"
	exit $?
fi
