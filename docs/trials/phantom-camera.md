# Trial B1: Phantom Camera against our own camera rig (2026-10-01)

This is Phase B trial 5 in `docs/tools-review-2026-09.md`. The question: should the over-the-shoulder camera, built as modes (design bible §2), be built on Phantom Camera v0.11.0.3 (MIT) or on our own rig of about 150 lines? It's evidence for a decision, not the decision.

**Recommendation: keep A, our own rig, and drop Phantom Camera.** This PR switches the game to A (`scenes/player/CameraRig.tscn`) and leaves Phantom Camera out of the repo. A meets every `cam_*` target in every scenario. B, Phantom Camera configured to do the same, misses `cam_player_in_frame` in four of six scenarios and `cam_lock_both_in_frame` in one. It does nothing when the arm is squeezed, starts every scene with the camera inside the player for 6 to 12 frames, and shows a runtime error and a self-updater in the code paths read for the audit. Matching A would mean writing A's framing code on top of it anyway.

## How the camera is measured (new in this PR)

The replay harness now scores the camera headless. There's no rendering: points are unprojected through the camera, and rays are cast against the collision shapes (`scripts/review/camera_probe.gd`).
- `replay.gd` logs one `camera` event per physics frame whenever a scenario has a `cam_*` check, and sizes the headless root viewport to the game's 1152×648 (headless, it's 64×64).
- `replay_metrics.py` turns those events into the four targets:
  - **`cam_player_in_frame`**: the share of frames in which the player's head and torso are fully in frame. That means all eight corners of a box, from the capsule's centre to its top and as wide and deep as the capsule, project inside the viewport. The camera must also be outside the capsule, and at least 75% of a 5×7 ray grid on the body must reach it before any world geometry does.
  - **`cam_wall_fill`**: the worst frame's largest share of a 32×18 grid of screen rays that land on one wall plane. Coplanar kit pieces merge, and floors don't count. Since the user's ruling (2026-10-01), a hit counts only when it's no deeper along the view than the player's axis: wall between the camera and him, or beside him, not a wall he faces beyond him.
  - **`cam_melee_occlusion`**: over locked frames with the target within 3 m, the mean share of the target's ray grid that hits the player first. The detail also gives p90 and the maximum.
  - **`cam_lock_both_in_frame`**: the share of locked frames in which both the player and the target are framed, by the same test as the player.
- `tests/scenarios/camera_stress.json` is a new stress scenario in Level 1, with the other enemies removed:
  - the player backs into the start room's west wall;
  - he locks onto the central levy and fights it beside Corridor A's north pillar, where a dodge to the left pins the camera against the pillar;
  - he turns about in the 4 m corridor.
- Every scenario now carries `cam_*` checks with baselines (tolerance 0.05 for cross-machine physics).
- The rendered capture of each candidate logged the same events as its headless run (`--compare`: identical), so the headless numbers describe what's on screen.

## The candidates

**A: our rig** (`scenes/player/CameraRig.gd`, 218 lines with comments).
- **Placement:** the rig is top level on a 1.7 m pivot and turned to the heading only, so camera-relative movement and `FillLight` read it as before. The shoulder offset is 0.6 m, the arm 4 m and the FOV 72°.
- **Collision:** a 0.3 m sphere probe (`cast_motion`) runs from the pivot out to the shoulder, then back along the arm. It snaps in at once and eases back out.
- **Squeezed under 1.5 m:** the camera rises, and the look turns from the heading toward his torso. When locked, it turns toward the angle between him and the target, weighted to him.
- **Framing tilt:** the look pitch tilts only as far as it must to keep his box, then the target's, inside the vertical FOV.
- **Lock-on mode:** the view swings 8 to 50° off the heading as the target closes (`asin(1.1 m / distance)`), so the target stands to the right of him. When his back is to a wall, it swings up to 86°, in steps, until the arm has room.
- **Shake:** it moves the view, never the heading.
- **Player.gd changes:**
  - it updates the camera after `move_and_slide`;
  - it passes the lock target only while that target is valid (a freed target used to reach the camera);
  - it rests the locked arm at −0.2 rad (`lock_on_pitch`) instead of level.
  - Public methods and signals are unchanged, and `get_lock_on_target()` is new.

**B: Phantom Camera v0.11.0.3**, configured to do the same (`docs/trials/phantom-camera/CameraRig.{gd,tscn}.txt`, a 107-line wrapper with A's interface, so Player.gd is the same).
- **OverShoulder:** a `PhantomCamera3D` in THIRD_PERSON follow (its `SpringArm3D` with a 0.3 m sphere shape) on a shoulder node 0.6 m right of the 1.7 m pivot. The shoulder has to be a node because `follow_offset` is world-space.
- **LockOn:** a second `PhantomCamera3D` with the same arm plus LookAt GROUP on the player's torso and the target. It takes over by priority, with a 0.3 s tween.
- **Shake:** a `PhantomCameraNoiseEmitter3D` with a fixed noise seed.
- **Parity with A:** the wrapper adds what Phantom Camera has no setting for: the arm's rotation (the heading, plus A's lock-on swing, so the comparison stays fair) and the character exclusions. A's squeeze handling and framing tilt aren't ported, because they're rig code, not configuration.
- `FillLight` stays on the wrapper node and needed no re-wiring.

## Results

All three runs use the same inputs, the same seed and the same probe. Wall-fill values for today and A use the user's final definition (wall beyond him doesn't count); ¹ B's were measured under the earlier one, which counted it. Lock-on numbers for A include the dead-target retarget (below). Each run was replayed twice and compared: identical, or `same_per_frame`. The gameplay checks didn't move in any scenario (`ttk_*`, the telegraphs, attackers and detection). The pass marks are against the design-bible targets.

| Scenario | Target | Today | A, our rig | B, Phantom Camera |
|---|---|---|---|---|
| levy_1v1_passive | `cam_player_in_frame` (1.0) | 1.000 | **1.000** | 0.985 (start-up) |
| | `cam_wall_fill` (≤ 0.6) | 0.014 | **0.038** | 0.149¹ |
| | `cam_melee_occlusion` (≤ 0.25) | 0.873 | **0.116** (max 0.17) | 0.118 |
| | `cam_lock_both_in_frame` (≥ 0.95) | 1.000 | **1.000** | 0.996 |
| levy_1v1_sensible | `cam_player_in_frame` | 0.667 | **1.000** | 0.674 |
| | `cam_wall_fill` | 0.014 | **0.408** | 0.231¹ |
| | `cam_melee_occlusion` | 0.681 | **0.033** | 0.090 |
| | `cam_lock_both_in_frame` | 0.664 | **0.974** | 0.680 |
| central_room_pull | `cam_player_in_frame` | 1.000 | **1.000** | 1.000 |
| | `cam_wall_fill` | 0.368 | **0.392** | 0.417¹ |
| tomb_hall_group | `cam_player_in_frame` | 1.000 | **1.000** | 0.978 (start-up) |
| | `cam_wall_fill` | 0.441 | **0.415** | 0.465¹ |
| crypt_trial_walk (from main) | `cam_player_in_frame` | 1.000 | **1.000** | not run (B's branch predates it) |
| | `cam_wall_fill` | 0.573 | **0.361** | not run |
| camera_stress (new) | `cam_player_in_frame` | 0.577 | **1.000** | 0.897 |
| | `cam_wall_fill` | 0.462 | **0.406** | 0.564¹ |
| | `cam_melee_occlusion` | 0.595 | **0.021** | 0.025 |
| | `cam_lock_both_in_frame` | 0.355 | **1.000** | 1.000 |

Where each candidate loses frames:
- **Today:** the player is covered by himself at melee range (the levy is 0.87 hidden behind him when locked on). With his back to a wall, the ray arm parks the camera on the wall face 0.4 m behind him, so his head and torso can't fit.
- **A:**
  - It loses no frames on the player.
  - **Lock-on, `levy_1v1_sensible`:** for 14 frames (0.23 s) after the dodge back against the west wall, the camera swings along the wall and is briefly too close to fit the levy beside him (0.974, which passes).
  - **Wall fill, `camera_stress`, under the earlier definition:** frames 917 to 929 of the corridor about-turn read 0.604. He faces the corridor's far wall from about 3.5 m, with the camera pinned to the near wall, and that wall was 0.60 to 0.62 of the frame at every look-down tilt tried (0 to 0.25 rad). The user's ruling excludes that case.
- **B:**
  - Frames 0 to 6 (up to 12) of every scene: Phantom Camera creates its spring arm deferred, so the camera starts at the pivot, inside the player.
  - Backed into a wall (`camera_stress` 52–145, `levy_1v1_sensible` 371–end): the spring arm shortens to the wall and the camera sits against his back. The rendered frames show an arm and a shoulder.
- **Rendered contact sheets** of `camera_stress` (16 frames each): `phantom-camera/camera_stress_today.jpg`, `…_A-own-rig.jpg`, `…_B-phantom-camera.jpg`. In frames 62 and 125, A shows him whole from above his shoulder against the wall, while B shows only his arm.

## Phantom Camera: pin and audit

| | |
|---|---|
| Release | v0.11.0.3 (2026-07-19), https://github.com/ramokz/phantom-camera |
| Commit | `cb6e0966ac305202c47f1d1a81c105966e29da96` (tag `v0.11.0.3`) |
| Tarball | `archive/cb6e0966….tar.gz`, SHA-256 `a410435c47a5785fb466de151e8c3dd6e92a2f123196462693f4b51c0652f3eb` |
| Licence | MIT (`addons/phantom_camera/LICENSE`, © 2022 Marcus Skov) |
| Size | 2.0 MB, 201 files, 34 scripts (9,664 lines), including `examples/` |
| Runtime | It ran headless on 4.7.2 with only the `PhantomCameraManager` autoload registered, and the editor plugin not enabled. The import added no new errors or warnings |

Code paths read for the audit: `plugin.gd`, the updater (`scripts/panel/updater/*`), the manager, the host, `phantom_camera_3d.gd` and the noise emitter. What they do:
- **Network (editor only):** while the editor plugin is enabled, the bottom-panel `UpdateButton` calls `check_for_update()` on every editor start. That's an `HTTPRequest` to `https://api.github.com/repos/ramokz/phantom-camera/releases`, unless the project setting `phantom_camera/updater/updater_mode` is 0.
  - Accepting its prompt downloads the release zip to `user://temp.zip` and **rewrites `res://addons/phantom_camera/` in place**.
  - It can also `OS.shell_open` the release page.
  - Nothing goes online at runtime, and there's no telemetry.
- **Writes:** `plugin.gd` `_enter_tree` writes project settings: `phantom_camera/updater/updater_mode`, which defaults to 2, the updater window, and `phantom_camera/tips/show_jitter_tips`. The editor saves both into `project.godot`. `_enable_plugin` adds the autoload and restarts the editor.
- **Runtime noise:**
  - It prints a rich-text warning whenever a camera has both Follow and Look At set ("not fully tested yet").
  - It `printerr`s a physics-interpolation tip when it follows a physics body and `physics/common/physics_interpolation` is off, which ours is.
- **Bugs met:**
  - Freeing a look-at target while the host is leaving the tree raises a runtime error (`phantom_camera_host.gd:822`, `get_tree()` is null). That happens in teardown, and it would on a respawn reload while locked on.
  - A hand-written `.tscn` must list node exports in `node_paths=`, or `follow_target` silently stays null and the camera never moves. That's the first thing that broke here.
  - Its arm excludes only the follow target, and passes the Node to `SpringArm3D.add_excluded_object()`, which takes a RID. With a plain shoulder node as the target, nothing is excluded, so the wrapper excludes the player and enemies itself.
- **Pre-1.0:** the tools review notes it broke once on 4.7.1.

## What adopting it would cost

- **A** (this PR): 218 lines in one file, with no dependency. It's covered by `tests/unit/test_camera_rig.gd` (7 tests) and the replay checks. First person comes later as a third mode in the same rig.
- **B:**
  - A pre-1.0 addon to pin and re-verify on every Godot upgrade.
  - An updater to switch off and keep off (`updater_mode = 0` in `project.godot`), or a patch to it, as Dialogue Manager needed.
  - Two printed warnings to silence.
  - A runtime error to patch or work around.
  - **And A's framing code anyway:** squeeze, framing tilt and the lock swing, about 60 lines in the wrapper, because Phantom Camera's third-person arm doesn't keep the player in frame against walls.
  - What it would add on top: priority tweens between modes, noise resources, and an editor viewfinder.

**If it's adopted later**, pin it the way godot-ai and gdUnit4 are pinned:
- vendor `addons/phantom_camera/` from the tag on a `chore/phantom-camera-<version>` branch, and record the tag, commit and tarball SHA-256 here;
- set `phantom_camera/updater/updater_mode=0` and `phantom_camera/tips/show_jitter_tips=false` in `project.godot` before the editor plugin is ever enabled;
- never press its Update button or update it in place;
- re-run the camera scenarios on every bump.

**Reproducing B:**
1. Branch from this PR's head.
2. Untar the release into `addons/phantom_camera/`.
3. Add `PhantomCameraManager="*res://addons/phantom_camera/scripts/managers/phantom_camera_manager.gd"` under `[autoload]` (the editor plugin stays off).
4. Copy `docs/trials/phantom-camera/CameraRig.{gd,tscn}.txt` over `scenes/player/CameraRig.{gd,tscn}`.
5. Run two headless imports, then `scripts/review/run_scenario.sh tests/scenarios/*.json` (B misses its baselines, which are A's).

## Open questions (for the user)

1. **`cam_wall_fill` in a 4 m corridor (answered by the user, 2026-10-01):** wall the player deliberately faces close up doesn't count, only wall between the camera and him or beside him. Under that rule, `camera_stress` reads 0.406 (it was 0.604 and pending), and the check is no longer pending.
2. **How `cam_melee_occlusion` aggregates frames:** the mean over locked frames within 3 m (here 0.02 to 0.12, max 0.17). The bible doesn't say which: mean, p90 or worst frame. All three meet ≤ 0.25 with A.
3. **Lock-on on a dead target (answered by the user, 2026-10-01):** the lock now moves at once to the nearest living enemy in range, or releases (`tests/unit/test_lock_on.gd`). After the change, `levy_1v1_sensible` reads wall fill 0.432, melee occlusion 0.044 and both-in-frame 0.969, and `camera_stress` reads melee occlusion 0.038.
4. The pivot is now 1.7 m (the bible's 1.6 to 1.8), so `FillLight` sits 0.7 m lower than before, still 0.6 m above and 2.5 m behind the pivot. The back-luminance figure in the art bible (0.133) was measured with the old pivot and may want a re-measure.

## FillLight back luminance with the new pivot (2026-10-01)

`scripts/review/level1_compare.tscn -- … --fill 3.5,5,0.6,2.5 --measure 1` renders the gameplay shot twice, with and without the player. It takes his pixels as the ones that changed, and averages their Rec. 709 luminance.

| Framing | linear | of the sRGB values |
|---|---|---|
| old dead-centre framing (`gameplay`) | 0.0301 | 0.146 |
| A's framing (`rig`: pivot 1.7 m, 0.6 m right, look 0.1 rad lower) | 0.0303 | 0.146 |
| A's framing, fill light off | 0.0088 | 0.054 |

- His whole visible body is unchanged by the new pivot, since the fill light keeps its place relative to the pivot.
- The 0.133 in `docs/decisions.md` came from a different region of his back that isn't in the repo. This method gives 0.146 for the same old setup, so the two aren't directly comparable, but the change between framings is about 0.
- The art bible doesn't quote the 0.133, so it isn't edited.

## Retune after the user's playtest (2026-10-01): Witcher-like framing

The playtest read A as a zoomed-out third person. The user chose Witcher-like framing: pivot about 1.6 m, about 0.9 m right, a 2.5 m arm. A now uses pivot 1.6 m, shoulder 0.9 m, arm 2.5 m (3.0 m locked on, eased between modes) and 72° FOV, with the free look turned 4° right so he sits in the left third (`test_cam_player_in_the_left_third`).
- **New:** a horizontal framing constraint. Close in, the wide shoulder offset pushed his near side off the left edge, so the look yaw now turns only as far as it must to keep his box in view.
- **New:** a lock swing that only speeds up while opening to find room, so unlocking doesn't jump.
- **New:** the lock-on reticle (`scenes/ui/LockOnReticle.tscn`, in the HUD), which design bible §2 already specified.

| Scenario | in frame | wall fill | melee occlusion | both locked |
|---|---|---|---|---|
| levy_1v1_passive | 1.0 | 0.003 | 0.112 | 1.0 |
| levy_1v1_sensible | 1.0 | 0.413 | 0.021 | 1.0 |
| central_room_pull | 1.0 | 0.370 | – | – |
| tomb_hall_group | 1.0 | 0.368 | – | – |
| crypt_trial_walk | 1.0 | 0.368 | – | – |
| camera_stress | 1.0 | 0.470 | 0.015 | 1.0 |

**Wall bounce.** There's no oscillation. I counted reversals of the camera-to-player distance (more than 1 cm per frame, flipping back within 6 frames): 0 in five scenarios, and 1 in `levy_1v1_sensible` (frame 419, during the fight). The arm still snaps in at once when the view sweeps into a wall, the "bounce" the user liked: up to 1.85 m in one frame in `camera_stress` frame 578, as the post-kill view swings into Corridor A's north wall. That's a single settle, not a wobble.
