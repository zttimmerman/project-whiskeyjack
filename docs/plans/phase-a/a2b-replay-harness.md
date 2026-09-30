# A2b: the replay harness, event log and capture

**Goal:** deterministic, frame-exact gameplay scenarios with no Godot MCP latency, producing numbers the design bible's targets can be checked against, and evidence a human or the playtest critic can review. This is the playtest skill's backbone. The MCP stays for exploratory play and live diagnosis.

**Scope:**
1. **Event log** (`scripts/debug/EventLog.gd`, an autoload that's off unless enabled):
   - Enabled by a user arg `--event-log=<path>` or the env var `WHISKEYJACK_EVENT_LOG`.
   - Writes JSONL, one object per event, stamped with `Engine.get_physics_frames()`: `attack_started` (light or heavy, combo index), `hitbox_open`/`hitbox_close`, `hit` (attacker, target, damage, heavy), `damage_taken`, `dodge_start`/`dodge_end` (i-frame window), `stagger`, `death`, `lock_on`/`lock_off`, `detected` (enemy spotted the player), `attack_windup` (for when telegraphs exist), and `quest` events.
   - Emitted from existing signal points, with minimal hooks in Player, BaseEnemy, HitboxComponent, HurtboxComponent and CharacterStats. Existing signals and methods stay intact.
   - **Off by default:** zero cost and no files when not enabled.
2. **Replay runner** (`scripts/review/replay.tscn` plus `.gd`):
   - Loads a scenario JSON: the scene, the player's start position and heading, an RNG seed, a frame-keyed list of `{frame, action, pressed}` steps, a duration, and checks.
   - Drives `Input.action_press`/`action_release` at exact physics frames.
   - Run with `godot --headless --fixed-fps 60 --path . res://scripts/review/replay.tscn -- --scenario <json> --event-log <out.jsonl> --save-slot=replay`. Always on a separate save slot.
3. **Metrics** (a stdlib Python script, `scripts/review/replay_metrics.py`): reads the event log and computes design-bible numbers:
   - the `ttk_*` targets (hits to kill);
   - `enemy_attackers_max` (simultaneous attackers);
   - `enemy_melee_telegraph` (windup to hitbox open, once windups exist);
   - `atk_hitbox_sync` (hitbox open against the attack start or contact frame);
   - HP lost for `enc_first_fight_hp_cost`;
   - time between fights for `enc_spacing_s`.

   Each scenario has checks; it outputs pass or fail per target ID with values and exits nonzero on failure.
4. **Scenarios** (`tests/scenarios/*.json`), at least:
   - `levy_1v1_sensible`: approach, lock on, light combo, dodge on a fixed schedule, kill the levy in Corridor A;
   - `central_room_pull`: walk into the central room, recording who engages. It shows the current through-walls detection problem as a baseline.

   Run each twice; the event logs must match exactly, or within documented tolerance if physics jitter appears. Seed everything.
5. **Capture** (render mode, Mac):
   - The same runner without `--headless`, adding `--write-movie <dir>/frame.png` (a PNG sequence; Movie Maker implies fixed fps).
   - `scripts/review/capture_evidence.sh` uses ffmpeg (7.1, at `/opt/homebrew/bin/ffmpeg`) to:
     - encode an H.264 MP4 of the run for humans;
     - extract the frames at chosen event-log frames (every `hit`, `dodge_start`, `stagger`) into PNGs for the critic;
     - build a contact sheet (the ffmpeg `tile` filter) of about 16 evenly spaced frames.
   - Outputs go to a gitignored folder. Only the event log, metrics JSON and scenario files are committed as needed.
6. **CI:** run the headless scenarios and metrics (no capture) in the A1 workflow. Rendered capture stays local on the Mac (Linux llvmpipe colours differ), as the tools review notes.

**Acceptance:**
- Both scenarios run headless twice with matching logs.
- The metrics report current values that agree with `docs/design-bible.md` §9's "Current" column (for example `ttk_player_frontfile` = 4 light hits).
- One captured run yields an MP4, event-frame PNGs and a contact sheet.
- CI runs the scenarios.

**Serves:** `ttk_*`, `enemy_*`, `atk_hitbox_sync`, `enc_*`, and the planned playtest critic.

**Later (not this PR):** screen-space camera checks (`cam_melee_occlusion` and the others, via `Camera3D.unproject_position` on character bounds) and render-based luminance checks (`lvl_floor_luminance_min`, `read_char_contrast_min`) in capture mode.
