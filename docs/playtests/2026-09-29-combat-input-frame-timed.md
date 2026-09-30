<!-- Headless playtest via the godot-ai MCP. feature/player-input-polling @ 04d8c6f, Godot 4.7.2, godot-ai 4.2.3; 45 turns, about $0.89. Brief: brief-combat-input-frame-timed.md. -->

# Playtest report: frame-timed combat input (Level1)

The scenario couldn't be run as briefed. `input_sequence` blocks until the whole sequence is done, so there was no way to stop at frames 5, 18 or 70. And inputs sent while the game is suspended don't reach it at all. Both runs fell back to: resume → one `input_sequence` → suspend → read. The dodge is confirmed; neither light attack could be.

Session: `project-whiskeyjack-agent@82f431ee61a717f1`, Godot 4.7.2, plugin 4.2.3. Ticks below are the helper's `process_ticks`, the only counter that stays still while the game is suspended.

## 1. Per-run tables

**Run 1.** The sequence was sent twice: first while suspended (it did nothing), then while running.

| Moment | Tick | `current_animation` | Player position | Screenshot |
|---|---|---|---|---|
| Start (suspended) | 316 | `idle` | (0.000, 0.901, 0.000) | Not taken at start (only once, after the no-op sequence) |
| After the sequence sent **while suspended** | 316 (reported `frames_elapsed: 62`) | `idle` | (0.000, 0.901, 0.000) | Player standing idle from behind, sword in right hand, start room, HP 100/100 |
| + `input_action attack_light` held, 3× `next_frame` | 319 | `idle` | (0.000, 0.901, 0.000) | Not taken; `input_state` shows `attack_light: false` despite no release |
| ~frame 5 | — | not observable | — | — |
| ~frame 18 | — | not observable | — | — |
| After the sequence sent **while running**, then suspend | 618 (~298 ticks after resume) | `dodge_roll` | (0.000, 0.901, **−1.400**) | Player mid-roll, curled on the floor, facing into the room |

**Run 2** (fresh `project_run`)

| Moment | Tick | `current_animation` | Player position | Screenshot |
|---|---|---|---|---|
| Start (suspended) | 45 | `idle` | (0.000, 0.901, 0.000) | Not taken |
| ~frame 5 / ~frame 18 | — | not observable | — | — |
| After the sequence sent while running, then suspend | 319 (~273 ticks after resume) | `dodge_roll` | (0.000, 0.901, **−1.540**) | Player curled mid-roll, same framing as run 1 |
| Extra probe: `attack_light` alone (press 0 / release 2), then suspend | 562 (~242 ticks after resume) | `idle` | not read | Player standing idle; camera closer to the far wall |

## 2. Did each input trigger?

- **Light attack (hit 1): not confirmed.** It was never seen in either run or in the probe. The probe's suspend landed about 242 ticks after resume, by which time the attack would be over and back to `idle`. There were no log lines to check against.
- **Second combo hit: not confirmed**, for the same reason. The combo index can't be read (it isn't an exported property).
- **Dodge: yes.** Both runs ended in `dodge_roll`, with the player moved about 1.4–1.5 m along −Z. The screenshots show the roll pose.
- **Suspended-mode input: no.** Sent to a suspended game, the sequence did nothing and the player stayed idle at the start position. `input_action` plus `next_frame` didn't work either, and the held action didn't survive the stepping.

## 3. Did the runs match?

- **Animations:** they matched at the only comparable moment (`idle` at start, `dodge_roll` at end).
- **Final position: no match.** Run 1 ended at z = −1.400 and run 2 at z = −1.540 (x = 0.000 and y = 0.901 in both). The difference comes from when each suspend landed after the sequence returned (~298 vs ~273 ticks after resume), not from the inputs. This setup can't tell whether the inputs themselves are deterministic.

## 4. Tool friction

1. **`input_sequence` blocks until it completes.** You can't suspend partway through, so lockstep sampling at chosen frames is impossible, and each call adds an uncontrolled run-on of about 180–240 ticks.
2. **`input_sequence` while suspended silently does nothing.** Its `at_frame` follows the rendered-frame counter, which keeps running during a debugger suspend while game logic is frozen. The reply still says `completed: true, frames_elapsed: 62`.
3. **`input_action` with `next_frame` doesn't hold state.** `input_state` showed the action released after the steps. It's unclear whether `next_frame` runs a physics tick at all, and every gameplay input is polled in the physics step.
4. **Every game screenshot came back `stale_frame: true`** (the window was backgrounded), though the images still matched the game state that was read.
5. **Useful fix:** an `input_sequence` option that steps the suspended game itself, or returns immediately.