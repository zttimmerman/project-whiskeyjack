---
id: a2b-replay-harness
title: "A2b: replay harness, event log and capture"
status: done
kind: feature
targets: [ttk_player_frontfile, ttk_levy_player, enemy_attackers_max, enc_first_fight_hp_cost, enc_group_max_first_area]
after: []
phase: A
branch: feature/replay-harness
pr: 20
updated: 2026-09-30
---
## Goal

Deterministic, frame-exact gameplay scenarios producing numbers the design-bible targets are checked against, plus reviewable evidence. Brief: `docs/plans/phase-a/a2b-replay-harness.md`.

## Outcome

The `EventLog` autoload (off by default; `WHISKEYJACK_EVENT_LOG` or `--event-log`), `scripts/review/replay.tscn`, `replay_metrics.py`, and the scenarios `levy_1v1_sensible` and `central_room_pull`. Runs are deterministic; same-frame event order may vary (Jolt), which `--compare` accepts. Baselines matched the design bible §9 Current column at the time (`ttk_player_frontfile` 4, `ttk_levy_player` 34, telegraph 0 s, first-fight HP cost 6%, first-area group 4; all since moved by the gameplay batch). The brief's "later" screen-space camera checks shipped with B1 (#33); the render-based luminance checks are `render-luminance-checks`.
