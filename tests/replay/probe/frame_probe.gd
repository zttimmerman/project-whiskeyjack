extends Node

# Replay harness self-test (tests/scenarios/replay_frame_stamps.json): logs a "probe" event in _ready and
# in each of its first physics frames, carrying its own count. It runs at the default physics priority,
# before the replay runner (priority 1000), so it logs on the warm-up frame before the runner does.
# The level is ready two physics frames before frame 0, so the stamp of each probe event must be
# tick - 1: tick -1 (ready) is frame -2, tick 0 (the warm-up) is frame -1, tick 1 is frame 0.
# The replay_frame_stamps check (scripts/review/replay_metrics.py) counts the stamps that disagree.

const TICKS := 4

var _tick: int = 0


func _ready() -> void:
	if EventLog.enabled:
		EventLog.log_event("probe", {"tick": -1})


func _physics_process(_delta: float) -> void:
	if _tick >= TICKS:
		set_physics_process(false)
		return
	if EventLog.enabled:
		EventLog.log_event("probe", {"tick": _tick})
	_tick += 1
