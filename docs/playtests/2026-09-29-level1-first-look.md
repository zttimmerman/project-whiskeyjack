<!-- Headless playtest via the godot-ai MCP (claude -p in the agent worktree, guard profile "playtest"). Commit 2802572 on chore/godot-ai-trial, Godot 4.7.2, godot-ai 4.2.3. 116 turns, about $2.26 of API usage. Brief: brief-level1-first-look.md. Screenshots were seen by the playtester only (the MCP has no save-to-disk). -->

# Project Whiskeyjack playtest: Level1

## 1. Scripted scenario

| | Player start | Nearest enemy (EnemyCorridorA) | Player after `move_forward` frames 0→60 |
|---|---|---|---|
| Run 1 | (0.000, 0.901, 0.000) | (11.000, 0.901, 0.000) | (0.000, 0.901, -2.708) |
| Run 2 | (0.000, 0.901, 0.000) | (11.000, 0.901, 0.000) | (0.000, 0.901, -2.708) |

**The runs match exactly**, and so did an earlier throwaway run. Three things to know about these numbers:
- They are `position`, not `global_position`. `get_node_info` returns no global transform. Level1's root sits at the origin, so the two should be the same.
- 60 frames moved the player 2.708 units, but `move_speed` is 5. At 60 physics ticks per second that should be about 5 units. So either there is acceleration, or the sequence's "frames" aren't physics ticks at 60 Hz. I couldn't tell which.
- My first attempt used the key `frame` in each step. The tool accepted it without complaint and applied the press and release both at frame 0. Only `at_frame` works. I threw that run away and restarted so both runs were clean.

## 2. What happened

1. **Start:** I turned the camera right and saw the skeleton in Corridor A. It spotted me and charged.
2. **First fight:** I pressed Tab, then made about 3 light attacks and 1 heavy.
   - **The kill worked:** the XP bar filled a little and EnemyCorridorA left the scene tree after its death clip.
   - **Cost:** HP went from 100 to 58. It took roughly 3,300 rendered frames (about 55 s on the clock), but most of that was tool latency, not game time.
3. **Central room:** I walked down Corridor A and killed EnemyCentral1 at the doorway (1 light + 1 heavy), but HP fell to 28. A dodge (Space) and a strafe didn't stop the damage; the archer kept chipping at me. I entered the room with EnemyCentral2 and the archer both on me.
4. **Death 1:** "YOU DIED" came up at about 2 minutes of game time. The scene reloaded about 3 s later.
5. **After respawn:**
   - I came back at (-3.18, 0.90, -0.19), not the spawn at (0, 0, 0), with the camera facing a different way. The XP bar was still partly filled.
   - All 7 enemies were back, including the two I'd killed.
   - So it looks like an old `user://save.json` from an earlier session was loaded. The rest of the level resets while position and XP persist.
6. **Second attempt:**
   - My "turn right and run" input from the first life now ran me into the start room's northeast corner, because the camera heading was different.
   - I killed EnemyCorridorA again (HP 100 to 88).
   - I then stuck on a crate at (3.70, -4.50) before strafing back to the doorway.
   - I reached the central room entrance with three enemies in view, hit the tool-call budget, and stopped.
7. **Not reached:** I never got to Corridor B or the exit room. According to `Level1.tscn`, they're due south (+Z) of the central room, and the ExitDoor is at z 29.5.

## 3. As a player, how it reads

**Level**
- **Layout:** it's a straight line of grey boxes: start room, then a corridor east, a 16×16 central room with pillars, a corridor south, and the exit room.
- **Verticality:** none. Every floor is at y = -0.1, with no steps, ramps or drops.
- **Ceilings:** there are none anywhere. The flat grey sky fills the top 40% of every screenshot, so these read as walled pens, not a crypt. This is clearest in the central room pan and the Corridor A shots.
- **Landmarks and direction:**
  - The only cues are one torch in Corridor A, a dark doorway, and the enemies themselves.
  - The start room gives no hint of the exit. In the first start screenshot you face a blank wall with two crates.
  - After respawning with the camera turned, I walked straight into a corner (the second-attempt corner screenshot).
- **Dressing:** crates and barrels are untextured-looking brown boxes and cylinders. Walls alternate flat light grey and flat dark brown with no texture or trim. The central room has three identical box pillars. There is a torch model and a weapon rack.
- **The Village Elder:**
  - It's a plain white capsule standing right behind the spawn.
  - It fills the lower-left or lower-right quarter of the screen in both start screenshots.
  - It reads as a placeholder or a bug, not a character.

**Lighting and readability**
- **Player:** readable. The teal tunic stands out against grey.
- **Skeletons:** readable as silhouettes against the grey sky and walls. The archer's bow is visible in the central room pan.
- **Walls:** the dark brown walls are nearly black. Corridor walls read as void on one side.
- **Floor:** the flat mid-grey makes depth hard to judge.
- **Torch pools:** the Corridor A torch throws a visible warm pool on the light wall. The room beyond has one faint glow and is otherwise flat.
- **Overall:** it's evenly dim rather than moody.

**Combat feel**
- **Visibility:**
  - In fights 1 and 2, the enemy stood directly in front of the player and was **completely hidden behind the player model** (the mid-fight screenshots).
  - I couldn't see its wind-up or its attack, or whether my hits landed.
  - The only signs anything happened were the HP bar dropping and, later, the XP bar moving.
- **Hit feedback:** I saw no particle burst, flash, or stagger in any screenshot, and there's no enemy health bar. That said, I only captured still frames between calls.
- **Lock-on:**
  - Tab never visibly changed anything. There was no reticle, and the camera didn't turn toward the target in any of 4 uses.
  - In the central room, pressing Tab with an archer 5 m away left the camera unchanged.
  - Later, camera_right stopped turning the camera. That was probably because lock-on was stuck on, but there was no indicator to tell me.
- **Enemy pressure:**
  - Enemies do a lot of damage: about 40 HP per skeleton, even when I won.
  - At the central room the melee skeletons and the archer come at once. The archer does chip damage from out of view (HP 28 → 24 → 22 → 20 → 17 while I wasn't in melee).
  - Walking into the central room at full HP puts you straight into a 3-on-1.

**Camera and controls**
- **Wall collision:**
  - After respawn, the camera was pushed into the start-room corner. The frame showed about 90% wall, with only the top of the player's head at the bottom edge (the "Camera jammed" screenshot).
  - Backing out left the camera high, with the player clipped at the bottom of the frame.
- **Respawn heading:** respawning with a different camera heading is disorienting. The same input took me somewhere completely different.
- **Crates:** they snag the player at the corridor mouth. I lost a whole 5-second move pushing into one.

## 4. Bugs and errors

1. **The death reload loads an old save:**
   - The player came back at (-3.18, 0.90, -0.19) with XP kept, while all enemies respawned, including ones already killed.
   - Killed enemies aren't persisted, but position and XP are.
2. **Lock-on shows no effect or indicator.** It may also leave the camera stuck: camera_right did nothing late in the second life.
3. **The enemy is fully hidden behind the player at melee range,** because the camera sits directly behind the player at the same height.
4. **The camera pushes into the wall or corner** until the player is out of frame.
5. **Log warnings, repeated on every scene load including the death reload:**
   - Invalid UIDs, with Godot falling back to text paths:
     - Player.tscn: `bcharstats0001`, `hitboxcmp001`
     - BaseEnemy.tscn: `dbaseenemy01gd`, plus the same two
     - ArcherEnemy.tscn: `archerenemy_gd`
     - Projectile.tscn: `projectile_gd1`
     - HUD.tscn: `bhudscript001`
     - InventoryUI.tscn: `invuiscript001`
     - PauseMenu.tscn: `pmenu0gd0001`
     - QuestLogUI.tscn: `questloguiscript1`
   - `Level1.gd:13`: the navmesh is baked at runtime from RenderingServer meshes. Godot warns this is a significant performance issue.
   - The navmesh bake says `agent_height` and `agent_radius` are ceiled to the cell size, losing precision.
   - GDScript reload warnings:
     - `Inventory.gd:82`: a parameter named `sign` shadows the built-in function.
     - `GameManager.gd:4`: the `game_over` signal is never used.
     - `Player.gd:361`: integer division.
6. **No game errors** (only warnings), and no crashes.

## 5. Tool friction

- **Real-time combat through tool calls is very laggy.** About 8–20 s of game time passed between calls (`frames_drawn` jumped 600–1,300 per call).
  - Enemies kept attacking while I was deciding what to do.
  - A dodge can't be timed to a telegraph, so the combat result mostly reflects latency, not how the game plays.
  - The fix would be to let the game pause between calls (`suspend`/`next_frame` exist, but mixing them with input is awkward), or to allow key events inside `input_sequence`.
- **`input_sequence` only accepts actions.** `key` steps are rejected ("steps[0].action is required"), yet combat keys have to go through `input_key`. So attack combos can't be frame-timed, and each press and release costs 2 separate calls.
- **The step key name is undocumented.** `frame` was accepted without complaint and applied at frame 0; only `at_frame` works. The tool description was truncated.
- **Reading a position is expensive:**
  - `get_node_info` with `include_properties:false` returns no transform, so every position read dumps about 60 properties.
  - It has no `global_position`, and no way to request specific properties.
  - It can't read script vars such as enemy HP, AI state or lock-on target (non-exported vars, or sub-resources like `stats`).
- **There's no "time passed" or event feed.** I couldn't tell whether a hit landed, when an enemy died, or what damaged me without guessing from HUD pixels or diffing the scene tree.
- **`logs_read` source "all" is flooded by plugin traffic.** The first 30 lines were MCP recv/send noise.
- **Screenshots are 640 px only.** Small things like torch flames, arrows and hit particles are hard to judge.
- **No denied calls** in this session.

## 6. Top 5 problems to fix (by player impact)

1. **At melee range the player model hides the enemy, and lock-on shows nothing.** You can't see attacks coming or tell whether your hits connect, which undercuts a Zelda/Souls-style combat loop.
2. **Encounters are too harsh for a first room:**
   - Each skeleton costs about 40% HP even when you win.
   - The central room is a 3-on-1 including an off-screen archer.
   - There's no hit feedback telling you why you're losing HP.
3. **Death and respawn are inconsistent:**
   - You come back at an old save position and heading, keeping XP.
   - Every enemy is back.
   - The camera faces a different way, so you walk into corners.
4. **The level reads as unfinished and gives no direction:**
   - There are no ceilings; the grey sky dominates every screenshot.
   - Rooms are flat and untextured, with near-black dark walls and no verticality.
   - The layout is linear with no landmarks at the start.
   - The Elder is a white capsule blocking the spawn view.
5. **The camera collides badly with walls and corners** (the view fills with wall and the player leaves the frame), and props snag the player at the corridor mouth.