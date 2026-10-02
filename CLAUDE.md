# CLAUDE.md — 3D Low-Poly Action RPG (Godot 4)

## Project Overview
This is a 3D open-world RPG built in Godot 4. **Gameplay** follows the Elder Scrolls, Fallout (gameplay, not setting) and The Witcher: exploration, quests with choices, character growth, hub-and-spoke areas built to open up later. **Combat** is Witcher-style third-person action: lock-on, dodge, light and heavy attacks, RPG stats underneath. **The look** draws on early PS1/PS2-era games (early Final Fantasy, Legend of Dragoon, early Zelda 3D): stylized low-poly with generous budgets, bold colors, readable silhouettes, and simple albedo-only textures over realism. **`docs/design-bible.md` governs how it plays** (camera, combat, encounters, levels, RPG systems, with measurable targets). `docs/art-bible.md` governs how it looks, and `docs/world/` governs what it's about.

---

## Tech Stack & Conventions

- **Engine:** Godot 4.7 (`/Applications/Godot.app`; 4.6.1 kept as `/Applications/Godot-4.6.1.app` for old branches)
- **Language:** GDScript exclusively (no C#)
- **Renderer:** Mobile or Compatibility renderer preferred to maintain low-poly aesthetic; avoid expensive post-processing
- **Naming:** snake_case for variables and functions, PascalCase for class names and node names
- **Scenes:** One scene per major system or entity (Player, Enemy, NPC, UI, etc.)
- **Scripts:** Attach scripts directly to the relevant root node of each scene
- **Signals:** Prefer Godot signals over direct node references for loose coupling between systems
- **Autoloads (Singletons):** Use sparingly — only for truly global systems (GameManager, SaveManager, QuestManager, DialogueRunner, AudioManager)

---

## Visual Style Rules

**Target: the look is stylized low-poly with generous budgets: bold colors, readable silhouettes, and simple albedo-only textures over realism.** PS1/PS2-era games are the reference for proportions and readability, not something to emulate authentically. Smooth limbs, recognizable faces and hands — not box people.

- **Budgets are hard ceilings, and `docs/art-bible.md` is their only source.** Triangle budgets, texture sizes and Tripo face limits are set there and copied per asset into `assets/briefs/<asset-id>.yaml`; never write the numbers anywhere else. **The budget unit is triangles** (after triangulation, summed across the `.glb`); vertex counts shift with UV-seam splitting and are recorded as metrics only. Meshes are brought within budget at generation (the brief's `face_limit`); the pipeline fails anything over budget rather than decimating it, and a rigged mesh is never decimated. No exceptions for "it already looks fine"
- **Textures are albedo (base color) only:** one texture per asset, at the size in the art bible, or vertex colors. No normal, roughness, metallic, occlusion, emissive, or specular maps. Materials are `StandardMaterial3D` with `albedo_texture` set and everything else at defaults, **except specular (`metallic_specular`) = 0**: Godot's default 0.5 gives stylized albedo-only assets a plastic sheen. The `addons/stylized_materials` glTF import extension sets it on every imported material (Godot 4.6 ignores glTF's own specular), so keep that plugin enabled and reimport GLBs imported before it
- **Lighting:** one `DirectionalLight3D` + ambient per area; local `OmniLight3D`s are allowed only for visible light sources (torches, candelabras). **One exception:** the player's `CameraRig/FillLight`, a dim warm fill on the camera side of the player. It's culled to render layer 2, which only the player's meshes are on (set in `Player.gd`), so it never lights walls or enemies. It exists because the camera sits behind the player and his back otherwise renders near-black in dark interiors
- Avoid bloom, SSAO, and screen-space reflections
- **Silhouettes matter:** characters should read clearly from the gameplay camera distance. Exaggerated proportions (slightly large heads, stylized hair) are fine and encouraged
- Camera: Third-person, behind the player, with optional lock-on targeting for combat
- UI: chunky bordered panels, limited color palette, Godot's default font
- **Post-MVP — do not implement unless explicitly asked:** palette quantization, vertex-snapping or affine-texture-warp shaders, pixel fonts

---

## Project Structure

```
res://
├── autoloads/               # Global singletons (DialogueRunner is registered from scripts/dialogue/)
│   ├── GameManager.gd       # Game state, scene transitions
│   ├── SaveManager.gd       # Save/load via JSON
│   ├── QuestManager.gd      # Active quests, quest state
│   └── AudioManager.gd      # Audio buses, music, SFX helpers
├── addons/
│   ├── stylized_materials/  # glTF import extension: specular 0 on every imported material
│   ├── godot_ai/            # Godot MCP editor plugin, pinned v4.2.3 (see Godot MCP); never updated in place
│   ├── gdUnit4/             # test framework, pinned v6.2.1; never updated in place
│   ├── dialogue_manager/    # Dialogue Manager, pinned v4.1.0 + local patches; never updated in place
│   └── func_godot/          # .map brush builder, pinned 2025.12; disabled, used only by build_brush_maps.gd
├── scenes/
│   ├── player/              # Player.tscn / Player.gd
│   ├── enemies/             # BaseEnemy, ArcherEnemy, Projectile
│   ├── npcs/                # NPC.tscn / NPC.gd
│   ├── props/               # Held*.tscn wrappers aligning held props to a hand bone
│   ├── world/               # area/level scenes (Level1, Level2)
│   └── ui/                  # HUD, InventoryUI, DialogueUI, QuestLogUI, PauseMenu
├── scripts/
│   ├── combat/              # HitboxComponent, HurtboxComponent, HeldProps
│   ├── inventory/           # Inventory.gd, Item.gd
│   ├── dialogue/            # DialogueRunner.gd (autoload)
│   ├── stats/               # CharacterStats.gd
│   ├── debug/               # EventLog.gd (autoload, off unless enabled)
│   ├── pipeline.py          # asset pipeline orchestrator (asset-pipeline skill)
│   ├── blender_cleanup.py   # pipeline clean stage (headless Blender)
│   ├── blender_views.py     # review renders
│   ├── godot_validate.gd    # pipeline validate stage (headless Godot)
│   ├── judge.py             # asset judge packets and verdict log
│   ├── judge_images.py      # judge image copies and color metrics (headless Blender)
│   ├── make_texture_overlay.py
│   ├── tools/               # build_animation_library, make_bone_maps, make_held_props, playtest-branch.sh
│   └── review/              # motion_review, anim_sheet, level1_play_capture, level1_compare
├── data/
│   ├── items/               # Item .tres resources
│   ├── dialogues/           # JSON dialogue trees
│   ├── quests/              # JSON quest definitions
│   ├── rigs/                # BoneMaps and per-rig SocketMaps
│   └── animations/          # per-character AnimationLibraries and shared clips (built, don't hand-edit)
├── docs/                    # design-bible.md (gameplay targets), art-bible.md (budgets, palette, briefs, judge tolerances), decisions.md (handoff), world/,
│                            # playtests/ (briefs and reports), godot-ai-integration.md (MCP research and permission table)
└── assets/
    ├── briefs/              # per-asset brief YAML (copied from the art bible)
    ├── manifests/           # per-asset pipeline manifests and judge logs (JSON committed, images local)
    ├── meshes/              # cleaned, shipped .glb files
    ├── atlases/             # shared kit atlases, corrected once per pack
    ├── overlays/            # texture overlays composited at clean time
    ├── animations/          # Quaternius packs (CC0)
    ├── textures/
    ├── audio/
    ├── fonts/
    └── sources.json         # provenance of every downloaded asset (CC0 only)
```
Outside `res://`: `.claude/skills/` (asset-pipeline, tripo, playtest-branch), `.claude/agents/` (asset-judge), `.claude/hooks/` (the Godot MCP guard), `.mcp.json` (the Godot MCP server), `.github/workflows/ci.yml` and `ci/` (CI and its baselines), `.githooks/` (pre-commit and pre-push), `tests/` (gdUnit4 suites, replay scenarios, critical paths), and the gitignored `.tripo-out/` (raw Tripo downloads, spend records, scratch work), `.downloads/` (CC0 packs) and `.replay-out/` and `reports/` (replay and test output).

---

## Core Systems

### Player (scenes/player/Player.gd)
- Extends CharacterBody3D
- Third-person movement using camera-relative directions
- Actions: move, dodge/roll, light attack, heavy attack, interact, open inventory
- Lock-on system: cycle through nearby enemies, adjust camera to face target
- Integrates with: CharacterStats, Inventory, HitboxComponent

### Combat
- Real-time, no menus — all actions mapped to controller/keyboard inputs
- Hitbox/Hurtbox component pattern: HitboxComponent emits `hit(target, damage)`, HurtboxComponent receives it
- `HurtboxComponent` has `@export var impact_sfx: AudioStream` — assign the hit sound in the scene; plays via `AudioManager.play_sfx_at()` alongside the particle burst
- Attack combos tracked via a combo timer and attack index
- Enemy stagger/knockback on successful hits
- Player i-frames during dodge roll
- Heavy attacks trigger camera shake; all hits trigger a particle burst at the hurtbox position
- Death: emit `died` signal, trigger death animation, notify GameManager

### CharacterStats (scripts/stats/CharacterStats.gd)
- Resource-based (extends Resource) so it can be saved and shared
- Fields: max_hp, current_hp, attack, defense, speed, level, experience, experience_to_next_level
- Method: `take_damage(amount)`, `heal(amount)`, `gain_experience(amount)`, `level_up()`
- Emit signals: `health_changed`, `died`, `leveled_up`
- Used by both Player and Enemies (enemies use simpler stat sets)

### Inventory & Equipment (scripts/inventory/)
- `Item` is a Resource with fields: id, name, description, icon, type (weapon/armor/consumable/key), stats_modifier (Dictionary)
- `Inventory` manages an Array of Items with a max capacity
- Equipment slots: weapon, helmet, chest, boots
- Equipping an item applies its stats_modifier to CharacterStats
- Item data stored as `.tres` files in res://data/items/ — use Godot's native Resource format, not JSON, so items load directly via `load()` with no custom parser

### Dialogue System (scripts/dialogue/DialogueRunner.gd)
- Dialogue lives in `data/dialogues/<id>.dialogue` (Dialogue Manager v4.1.0 in `addons/dialogue_manager/`, pinned, with 4 local patches in `docs/trials/dialogue-manager-v4.1.0.patch`; never use its in-editor updater). Every file starts at `~ start`
- Conditions and mutations call `QuestManager.start_quest/advance_quest/complete_quest("id")` and `set_flag/get_flag("name")`; world flags live in QuestManager and are saved with it
- DialogueRunner autoload wraps the addon with the original API: `start(id)`, `advance(choice)`, `is_active()`, `accepts_interact()`; emits `dialogue_started`, `line_ready(speaker, text, choices)`, `dialogue_ended`
- CI compiles every file (`ci/check_dialogue.gd`) and lints its text limits (`ci/data_lint.py`)
- DialogueUI listens to DialogueRunner signals and renders text box + choices
- NPCs trigger dialogue via their interact() method calling DialogueRunner.start(dialogue_id)
- Dialogue can set quest flags via QuestManager

### Quest System (autoloads/QuestManager.gd)
- Quests defined in JSON: id, title, description, stages (array of {id, description, completion_condition})
- QuestManager tracks active quests and their current stage as a Dictionary
- Methods: `start_quest(id)`, `advance_quest(id)`, `complete_quest(id)`, `is_quest_active(id)`, `get_quest_stage(id)`
- Emits signals: `quest_started`, `quest_updated`, `quest_completed`
- QuestLog UI subscribes to these signals

### Save System (autoloads/SaveManager.gd)
- Saves to user://save.json
- Serializes: player position, CharacterStats, Inventory contents, equipment, QuestManager state, any world flags (doors opened, enemies killed, etc.)
- Methods: `save_game()`, `load_game()`, `save_exists()`
- Called by GameManager on scene transitions and from pause menu

### Audio System (autoloads/AudioManager.gd)
- Three buses created programmatically at startup: **Music**, **SFX**, **UI** — all route to Master
- `play_music(stream)` — assigns stream, enables OGG looping, starts playback on the Music bus
- `stop_music()` — stops the music player
- `play_ui(stream)` — one-shot playback on the UI bus (stings, UI feedback)
- `play_sfx_at(stream, world_position)` — spawns a temporary `AudioStreamPlayer3D` at a world position on the SFX bus; auto-frees on finish
- Audio files live in `assets/audio/` as `.ogg`; assign streams via `.tscn` ext_resource references
- Music is started per-level in the world scene's `_ready()` via `AudioManager.play_music(preload(...))`
- Footsteps: timer-based in Player (0.4 s interval), only fires when `is_on_floor()` and lateral velocity > 0.5
- Sword swing: fires at `hitbox.activate()` in both `_attack_light()` and `_attack_heavy()`

---

## Enemy Design Pattern
- All enemies extend a `BaseEnemy` scene/script (CharacterBody3D)
- BaseEnemy handles: health, taking damage, death, basic NavigationAgent3D pathfinding toward player
- Each enemy type is its own scene that extends BaseEnemy and overrides `_get_next_action()` for unique behavior
- States: IDLE, PATROL, CHASE, ATTACK, STAGGER, DEAD — use a simple enum + match statement, not a full state machine plugin
- **Animation:** BaseEnemy looks for `$SkeletonModel/AnimationPlayer` in `_ready()` and plays state-driven animations (idle, run, attack, stagger, death). Locomotion anim (idle vs run) updates each frame during CHASE based on horizontal speed. On death, velocity and navigation stop that frame, and the enemy is freed after the death clip (2.4 s), fading out over the last 0.3 s through material alpha. Subclasses that override `_change_state()` must call `_play_anim()` themselves for the overridden state (see ArcherEnemy)
- **Model node convention:** Enemy scenes use a `SkeletonModel` node (instanced GLB) with `Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, -0.9, 0)` — same 180° Y rotation + grounding offset as the player

---

## Input Map (expected actions defined in Project Settings)
```
move_forward, move_backward, move_left, move_right
camera_left, camera_right, camera_up, camera_down
attack_light, attack_heavy
dodge
interact
lock_on
open_inventory
open_quest_log
pause
```

---

## Data Format Examples

### Item resource (res://data/items/sword_iron.tres)
```
[gd_resource type="Resource" script_class="Item" format=3 uid="uid://..."]

[ext_resource type="Script" uid="uid://bwm1ug8dkvml6" path="res://scripts/inventory/Item.gd" id="1_item"]

[resource]
script = ExtResource("1_item")
id = "sword_iron"
name = "Iron Sword"
description = "A dependable iron blade."
type = 0
stats_modifier = {"attack": 5}
```
`type` is the Item.Type enum index: WEAPON=0, ARMOR=1, CONSUMABLE=2, KEY=3.
For consumables, use `stats_modifier = {"heal": 30}` — the `use()` method reads this key.

### Dialogue (res://data/dialogues/village_elder.dialogue)
See the file itself: one `~ start` cue branching on quest state and world flags, speaker lines (`Idrenna: ...`), choices (`- text`), mutations (`$> QuestManager.start_quest("clear_eastern_road")`) and jumps (`=> cue`, `=> END`). Each line keeps the world bible's limit of 2 sentences.
---

## Scene Files (.tscn)
- Claude builds scenes itself — do not ask the user to set up scenes manually in the editor. **Prefer the Godot MCP** (node, scene and signal tools) for hand-authored scenes when the agent's editor is running: Godot writes valid UIDs, types and properties. Otherwise write the `.tscn` directly. **Never hand-edit generated scenes** (`scenes/props/Held*.tscn`); rerun their generator
- Always create the `.tscn` alongside its `.gd` when building a new scene
- UIDs (`uid://...`) in `.tscn` files may be regenerated by Godot on first open — this is harmless
- When instancing one scene inside another, reference it via `[ext_resource type="PackedScene"]` and an `instance=ExtResource(...)` node entry
- Always verify node types match the script's `extends` (e.g. root must be `CharacterBody3D`, not `CharacterBody2D`)
- Node names in `.tscn` must exactly match `$NodeName` references in the attached script
- UI panels that must remain active while the game is paused (`get_tree().paused = true`) need `process_mode = 3` (`PROCESS_MODE_ALWAYS`) on their root node; child nodes inherit this automatically via `PROCESS_MODE_INHERIT`

---

## Git Workflow

### Branches and pull requests
- **Never commit directly to `main`.** Start each feature or session on a short-lived branch off an up-to-date `main`, with a prefix and a name for the work: `feature/` (gameplay and systems code), `fix/` (bug fixes), `asset/` (a pipeline run for one asset, e.g. `asset/sett-boar`), `docs/` (docs and CLAUDE.md), `chore/` (tooling, config, cleanup).
- **Merge through a pull request** (`gh pr create`, then `gh pr merge --merge --delete-branch`). Use a merge commit so the atomic commit history survives; don't squash. **Claude merges its own PRs once they're validated** (tests, checks and the PR's own acceptance criteria pass), unless the user asks to review first. Open questions or design decisions in a PR go to the user before merging.
- **`gh pr merge --delete-branch` also deletes the local branch and the worktree it's checked out in.** Run it only after that worktree's work is committed, and never assume the worktree still exists afterwards.
- **Merge often.** GLBs, textures and hand-edited `.tscn` files don't merge well, so two long-lived branches touching the same asset or scene means one side gets redone by hand.
- **Delete branches once merged.** GitHub deletes head branches automatically; locally, `git fetch --prune` and the `clean_gone` command. Mark milestones with tags (`poc-slice`, `mvp`), not kept branches.
- **Name the branch right before opening its PR.** Renaming a PR's head branch on GitHub closes the PR (PR #2 was lost that way and replaced by #3).
- **Parallel agents** each get their own worktree and branch; clean both up when done.
- **Worktree commands never depend on a `cd`.** Use `git -C <absolute path>` and absolute paths, and fail closed if the directory is missing (`test -d <dir> || exit 1`). A failed `cd` in a chained command once ran the rest in the human's checkout and switched its branch.
- **Refresh the session handoff** in `docs/decisions.md` before opening a PR.

### Commits
- **Commit atomically:** one logical change per commit (a new system, a bug fix, a scene setup); don't bundle unrelated changes.
- **Ask before committing** unless the user has asked for commits in this session (for example "commit at logical checkpoints").
- **Commit message format:** an imperative subject line saying what changed, then body bullets for the why and notable details.
- **Always commit `.tscn` files with their `.gd` files:** a script and its scene are one logical unit.
- **Commit `.uid` files:** Godot 4 generates them alongside scripts, and they should be tracked.

### What stays out of git
- **Never commit** `.godot/` (editor and shader cache), `.DS_Store`, `.tripo-out/` (raw downloads and scratch), `.downloads/` (CC0 packs; `assets/sources.json` records their SHA-256), or `.replay-out/` and `reports/` (replay captures and test reports). All are gitignored.
- **Commit finished assets, not their working artifacts.** `assets/meshes/`, `assets/overlays/`, briefs and manifest JSON are committed. Pipeline evidence images under `assets/manifests/` (review renders, judge packet copies, replays, animation sheets) stay local and gitignored; the committed JSON records each image's SHA-256.
- **Secrets never go in the repo or the remote URL.** GitHub access goes through `gh` (`gh auth login`, `gh auth setup-git`), and `origin` is the bare `https://github.com/...` URL. Check new commits for tokens before a first push.
- **Never rewrite pushed history.** To drop files, make a removal commit (`git rm --cached` plus a `.gitignore` rule), not a rewrite.

---

## Godot MCP (godot-ai)

The `addons/godot_ai` editor plugin (pinned v4.2.3, signature-verified; research and the full permission table in `docs/godot-ai-integration.md`) exposes the running Godot editor and game to Claude through `.mcp.json` (server `godot-ai`, telemetry off, 18 tool domains excluded at the server: materials, particles, UI, themes, animation, filesystem, autoloads, input map and more).

**Which route for which work (every skill states its own Execution):**
- **Scripted and headless, never the MCP:** anything that must reproduce exactly: the asset pipeline, the judge, the motion review, the animation library build, validation and imports. These run without an open editor.
- **The Godot MCP:** live work in the editor or game: playtests (input, screenshots, the live scene tree, logs), diagnosing a running editor or game, and hand-authored scene, UI-layout and signal edits.
- **Generated files are changed only by their generators**, whatever the tool (`data/animations/`, `data/rigs/`, `assets/meshes/`, `scenes/props/Held*.tscn`, `scenes/world/*_navmesh.tres`, written only by `scripts/tools/bake_navmeshes.gd`: rerun it after changing level geometry and commit the result; CI fails a stale bake; `scenes/world/trials/*_brushes.tscn`, built from `.map` files by `scripts/tools/build_brush_maps.gd`; and `assets/textures/surfaces/`, written only by `scripts/tools/make_textures.py` from the `.ptex` graphs and ramps in `assets/textures/src/` with Material Maker 1.5p1 in the gitignored `.tools/`, Mac only; CI runs `--check`).

**One editor per worktree.** The agent works in its own worktree with its own Godot editor, so the human can keep building in theirs:
- **One server, one session per editor.** Every editor connects to the same local server as a session (`<worktree-dir>@<hex>`). Pass the agent's `session_id` on every call. Never use `session_activate`, which moves the server-global default and can point calls at the human's editor.
- **Launch the agent's editor** from its worktree: `GODOT_AI_DISABLE_TELEMETRY=true GODOT_AI_TELEMETRY_ENDPOINT=invalid WHISKEYJACK_SAVE_SLOT=agent /Applications/Godot.app/Contents/MacOS/Godot --path . -e &`. The save slot keeps its playtests off the human's `save.json`, which every checkout shares (`user://` is keyed by the project name). It takes effect once the save-slot fix lands.
- **Keep the editor's hands off the setup.** Never press the plugin dock's Configure or Update, which rewrite client configs or the addon. Editor settings for 4.7 (shared by every 4.7 editor on the machine) keep telemetry off, the domain exclusions, and `save_before_running = false`.

**The guard.** `.claude/settings.json` plus `.claude/hooks/godot_ai_guard.py` (fail-closed, with tests) enforce:
- the agent's session on every call;
- a per-op allow/ask/deny table;
- `project_run(autosave=false)`;
- no writes to generated paths.

A denial is a project rule: don't retry it or work around it. Change the guard only with the user's OK. It applies only to Claude sessions started in a checkout that contains it.

**Playtests** run as a headless Claude session in the agent's worktree, so the guard applies:
```
GODOT_AI_GUARD_PROFILE=playtest claude -p "$(cat <brief>)" --mcp-config .mcp.json --strict-mcp-config \
  --allowedTools mcp__godot-ai Read --disallowedTools Bash Edit Write NotebookEdit WebFetch WebSearch --output-format json
```
- **The profile** allows running, stopping, stepping and input; edits stay blocked.
- **Briefs and reports** go in `docs/playtests/`.
- **No lockstep in godot-ai 4.2.3.** `input_sequence` blocks until the sequence ends, and input sent to a suspended game is silently dropped. So time inputs inside one `input_sequence`, and read the outcome afterwards; don't try to observe mid-sequence. Real-time play through tool calls lets 8–20 s of game time pass per call. The event log is how outcomes get checked: launch the agent's editor with `WHISKEYJACK_EVENT_LOG=<path>` and the game writes frame-stamped JSONL. For exact numbers, use a replay scenario instead (Testing). An input pressed during physics frame N reads as just-pressed on N+1.
- **Input:** every gameplay input is an Input Map action polled in the physics step (`move_*`, `attack_light`, `attack_heavy`, `dodge`, `lock_on`, `interact`), so frame-timed `input_sequence` drives movement and combat alike. Only UI keys (inventory, pause, mouse look) are read in `_input`.
- **Screenshots** reach the playtester only (there's no save-to-disk), so the report must describe them.

**Updates.** The pin (`addons/godot_ai/plugin.cfg` and `godot-ai==X` in `.mcp.json`) only changes deliberately:
- **The check:** a SessionStart hook runs `scripts/tools/godot_ai_update.py check --hook`. It queries GitHub at most weekly and is silent unless a newer stable release exists or the two pins disagree. Tell the user when it reports one. Run `godot_ai_update.py check --force` for the full list and changelog link.
- **Never update in place:** no dock Update button, and no editing the pin by hand on `main`.
- **An update is a trial on `chore/godot-ai-<version>`,** held to the same bar as the Godot 4.7.2 upgrade:
  1. Verify the new signed release with its own verifier. The signing key's SPKI fingerprint must match the one in `docs/godot-ai-integration.md`, and a changed key stops the update.
  2. Swap `addons/godot_ai/` and the `.mcp.json` pin, keeping the editor settings' domain exclusions in step.
  3. Diff the server's tool surface against the guard's tables. The hook denies anything unknown, so new tools can't slip in, but new ops and changed defaults get reviewed on purpose.
  4. Re-run the guard tests, validate, the motion metrics, the movement test and the saved playtest scenarios; they must match the pinned version.
  5. Open a PR with the changelog, the surface diff and the results.
- **Wanted features** (pausing mid-sequence, screenshots saved to disk) are reasons to look at a release sooner; **security fixes** are reasons to update promptly.

**The human playtesting the agent's work:** use the `playtest-branch` skill. It opens a disposable review copy, and the human's checkout is never touched.

---

## 3D Asset Workflow

All meshes live in `assets/meshes/` as `.glb` files. There are two tools:
- **Tripo CLI** (`tripo`): AI generation of base meshes. Every generation goes through the **`tripo` project skill** (`.claude/skills/tripo/`), which owns the procedure, the manifests and spend tracking.
- **Blender MCP:** inspection, cleanup and simple manual edits. It isn't used for generation.

### Setup
- **Tripo CLI:** `tripo-cli` is installed globally under Node 20. The nvm default is Node 16, so the wrapper `~/.local/bin/tripo` pins Node 20; always call plain `tripo`.
- **Tripo auth:** `tripo login` (browser device flow) saves the API key to `~/.tripo/config.json`. Never paste keys into chat, code, docs or logs.
- **Tripo credits:** buy API credits in the console at https://platform.tripo3d.ai (API credits are separate from studio.tripo3d.ai). `tripo topup` opens a stale page.
- **Blender MCP install:** `claude mcp add blender uvx blender-mcp` (user-level, one-time)
- **Every Blender session:** Blender must be open with the BlenderMCP addon active and the server started (sidebar → BlenderMCP → "Start Server"). If the `mcp__blender__*` tools are missing, remind the user to:
  1. Open Blender
  2. Enable the BlenderMCP addon (Edit → Preferences → Add-ons)
  3. Click "Start Server" in the BlenderMCP sidebar panel
  4. Restart the Claude Code session if the MCP was just installed

### AI Model Generation (Tripo CLI)

Base meshes should be **AI-generated** whenever possible, then brought within the triangle budget and texture rules (see Visual Style Rules). Do not hand-code complex geometry vertex-by-vertex — that's only appropriate for simple shapes (hair spikes, flat panels, accessories).

- **Two skills, two layers:** the **asset-pipeline** skill (`scripts/pipeline.py <asset-id> --stage concept|multiview|model|rig|clean|validate|all`) orchestrates briefs, stages, Blender cleanup, Godot validation and manifests. The Tripo chain is text-to-image → image-to-multiview → multiview-to-3D, and the pipeline stops after the concept until the user approves it (`--approve-concept N`). Characters are rigged from the **raw** download before cleaning, because Tripo's rigger expects its own +X orientation. The **tripo** skill is the vendor adapter, and every paid `tripo` call goes through it (dry run → the user confirms the cost → paid run). `pipeline.py` only prints `tripo` commands; it never runs a paid one.
- **Judge every stage:** after each stage `pipeline.py` prints a `judge:` command. Build the packet (`scripts/judge.py packet`), spawn the `asset-judge` subagent on it, and `record` its verdict. `revise` gets one auto-refine per stage (paid refines still go through the tripo skill's confirmation), and an `escalate` goes to the user with its findings. Animation clips are judged from the motion review (`scripts/review/motion_review.tscn`). Details are in the asset-pipeline skill; tolerances are in the art bible. The judge misses faint facial features, so check faces on new characters yourself.
- **Art-bible parameters:** `--param pbr=false --param texture=true --param face_limit=<from the brief>`, GLB output only. Never use the `--for` presets; they request PBR materials, 15K faces and 2048² FBX conversion.
- **Manifest:** `assets/manifests/<asset-id>.json` (committed), written by `pipeline.py`. Each stage records its inputs and outputs (with hashes), the prompt, parameters, the actual credit cost, tool versions (tripo, Blender, Godot, Python) and a timestamp. The CLI is a moving dependency, so versions are always recorded.
- **Output URLs expire ~5 minutes after a task succeeds:** download in the same run. Resuming is file-based (raw output in the gitignored `.tripo-out/`), never task-ID-based.
- **Prompt tips:** include "no weapons, empty hands" to avoid baked-in weapons; include "T-pose" or "A-pose" so the model can be fitted to the shared humanoid skeleton; AI may still generate unwanted items — regenerate rather than attempting mesh surgery
- **Don't use Blender MCP's generation tools** (`mcp__blender__generate_*`, including its Rodin, Hunyuan and Tripo integrations). They bypass the manifest and credit tracking.

**Sourced CC0 kits (KayKit, Quaternius, Kenney):** download with curl into the gitignored `.downloads/<pack>/`, then import with `scripts/tools/import_pack.py` (asset-pipeline skill → Sourced assets). They skip generation and run clean and validate like any asset; `assets/sources.json` is committed, and only CC0 passes validate.

**Sketchfab (for sourcing pre-made assets):**
- Search for CC0/free-license low-poly models when AI generation isn't the right fit; sourced models follow the same budget and albedo-only rules
- Requires a free Sketchfab API key
- Enable in BlenderMCP sidebar → "Use assets from Sketchfab" + enter API key
- Workflow: `search_sketchfab_models` → `get_sketchfab_model_preview` → `download_sketchfab_model`

### API Spend Safeguards

**Hard rules — Claude must follow these without exception:**
- **500 credits max per session** (1 credit = $0.01; a textured text-to-3D model is ~20 credits)
- **Always state the estimated cost and get explicit user confirmation** before every paid `tripo` command, with no silent spend. The CLI auto-confirms when run non-interactively, so the confirmation must come from the user in chat. `.claude/settings.json` also forces a permission prompt on paid `tripo` subcommands and on Blender MCP generation tools.
- **Track a running total** of *actual* spend (the balance difference) in the conversation; display `used / 500` with each confirmation prompt
- **Stop and warn** at 400 credits
- **Refuse to generate** if the session cap would be exceeded, unless the user explicitly raises the limit for that session
- Failed or unusable generations still count, at whatever the balance difference shows

### Post-Generation Cleanup (pipeline stage 3)

Every generated or sourced mesh goes through `python3 scripts/pipeline.py <asset-id> --stage clean` (headless Blender, `scripts/blender_cleanup.py`) before it lands in `assets/meshes/`. The asset-pipeline skill describes what it does:
1. **Scale, pivot, facing:** to the brief's target size, with the base or center at the origin, and characters facing −Y
2. **Budget:** asserted, never fixed by decimation. Over budget fails loudly; regenerate at the brief's `face_limit`
3. **Albedo only:** the material is rebuilt as base color (plus cutout alpha); normal, metallic/roughness, occlusion, emissive and specular maps are dropped; the texture is downscaled to the brief's size and its color corrected toward the approved concept (hue and saturation fully, lightness lifted only; the palette when there's no concept), since Tripo's delight pass desaturates and darkens
4. **Flat shading:** imported smooth normals are cleared and every edge sharper than 30° is flat-shaded
5. **Do NOT attempt fine mesh surgery** (removing baked-in weapons, rebuilding hands, fixing faces) via MCP scripting — it burns tokens and damages the mesh. Regenerate with a better prompt instead, or fix manually in Blender's GUI

### Rigging & Animation

- **Do not build armatures, paint weights, or keyframe animations via MCP scripting.** Animation comes from a shared animation library that is retargeted onto each character; it is not authored per model. **For any animation work (a new character's clips, a clip swap, a speed or trim change), use the asset-pipeline skill → Animation library, then judge the clips with the motion review. To fix a bad clip, follow that skill's fix ladder; Quaternius stays the source.** There's no hand-keyframing skill or agent; the old `blender-animation` skill and `blender-animator` agent were removed
- **One exception: rigid rebinding.** For characters built from rigid, disconnected parts (brief `rigid_parts: true`, e.g. the Barrow-levy skeleton), the clean stage binds each part at weight 1.0 to its nearest weighted bone. That's a deterministic algorithm, not hand-painted weights; the rule above exists to prevent unreproducible hand-tuning, and this is the opposite. It never applies to continuous-skin characters such as the player
- **Second exception: skirt reweighting.** For characters with a skirt (brief `skirt_reweight: true`, e.g. the player's tunic), the clean stage identifies the skirt as the region between knee and waist further than a trouser radius from both thigh bones, and grades it from Hips at the waist to the thighs at the hem, with zero shin weight. Auto-riggers bind skirts to the legs, so they stretch when walking. It's the same kind of deterministic algorithm on an identified region, not hand-painted weights. Separate skirt bones aren't used, because the Quaternius clips wouldn't drive them
- **Animation library:** Quaternius UAL1 and UAL2 (CC0) in `assets/animations/quaternius/`, retargeted through `data/rigs/*_bone_map.tres` in the GLBs' import settings; per-character AnimationLibraries in `data/animations/`, built by `scripts/tools/build_animation_library.gd` (the mapping table is in the asset-pipeline skill). Retargeted bones use SkeletonProfileHumanoid names, so socket maps do too
- **Bone geometry in scripts:** measure a bone as its joint span (head to its child's head), never head to tail; Blender's glTF importer invents display tails, and they differ between files
- **Rig model follows body plan, not recency:** Tripo rig `v1.0-20240301` (server default) is the humanoid rigger and the pipeline default; `v2.5-20260210` is the creature rigger (quadruped, hexapod, octopod, serpentine, aquatic, avian), passed with `--rig-model` (e.g. for the Sett-boar)
- Character models must use a humanoid skeleton that maps onto Godot's `SkeletonProfileHumanoid`, so the shared library can be retargeted through the `BoneMap` in the GLB's import settings. If a model has no such skeleton, stop and ask the user how it should be rigged
- **Socket bones:** every new character needs its socket bones (`hand_r`, `hand_l`, …) mapped in a `SocketMap` resource at `data/rigs/<rig>_sockets.tres`, assigned to the scene's `socket_map` export. That file is the single place to update when a rig changes or is regenerated. Never write bone names in scripts, scenes or call sites; characters (enemies and the player) attach props via `held_props` (socket → PackedScene) through `scripts/combat/HeldProps.gd`, with alignment in a `scenes/props/Held*.tscn` wrapper
- Game code plays animations by name, so retargeted clips must be exposed under these names — player: `idle`, `run`, `dodge_roll`, `attack_light`, `attack_heavy`, `death`; enemies: `idle`, `run`, `attack`, `stagger`, `death`

### Manual MCP Editing (for modifications, not base meshes)

Use direct bmesh/Python scripting via MCP for:
- Modifying existing geometry (hair restyling, adding accessories, patching gaps)
- Simple procedural shapes (spikes, flat panels, gem shapes)
- Vertex color adjustments and albedo material fixes

**Do NOT** hand-code complex organic meshes (characters, creatures, weapons with curves). Generate those via AI instead. Make geometry edits **before** a mesh is skinned; don't edit geometry on a rigged mesh via MCP.

Editing workflow:
1. **Import:** clear the Blender scene, then `import_scene.gltf(filepath=...)` to load the existing `.glb`
2. **Inspect first:** use `get_scene_info` and `get_viewport_screenshot` to understand the current model before making changes
3. **Analyze mesh data** before modifying — check color attributes, material setup, vertex count and bounding boxes via bmesh so edits land in the right place
4. **Preserve vertex colors:** set the color attribute on every loop of every new face — missing colors will render black
5. **Validate coverage:** for geometry meant to cover other geometry (hair over a skull, armor over a body), check the actual Z/position of the underlying mesh vertices — don't assume; the model may extend higher than expected
6. **Stay within budget:** re-check the summed triangle count after edits
7. **Screenshot from multiple angles** after changes — top-down, front, back, side — to catch gaps or artifacts before exporting
8. **Export:** `export_scene.gltf(filepath=..., export_format='GLB', export_animations=True, export_skins=True, export_yup=True)` — note that `export_colors` is not a valid parameter in Blender 5.x; vertex colors export automatically

### Blender → Godot Integration Gotchas
- **Facing direction:** Models face -Y in Blender. After GLB export with `export_yup=True`, this becomes +Z in Godot. Godot's forward is -Z, so the model appears to face backward. **Fix:** add a 180° Y rotation on the model node in the `.tscn`: `Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, 0, 0)`
- **Model grounding:** CharacterBody3D collision capsule (height 1.8) centers at the node origin, so the capsule bottom is at Y=-0.9. The model's feet (at local Y=0) must be offset to match: set model node Y translation to -0.9. Example: `Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, -0.9, 0)`
- **Axis conversion:** Blender Z-up → Godot Y-up. Blender (X, Y, Z) → Godot (X, -Z, Y) approximately. Bone positions and mesh data both get converted by the GLB exporter

### Other MCP Gotchas
- Hair/accessory geometry is typically disconnected from the body mesh (no shared vertices), making it safe to delete and rebuild independently
- Always check both local and world coordinates — if `matrix_world` is identity, they're the same
- `bmesh.ops.delete` with `context='FACES'` deletes faces but may leave orphan vertices; clean them up with a second pass
- Don't rotate armatures in Blender to fix orientation — it breaks skinning; use Godot-side `Transform3D` rotation on the model node instead
- `bpy.ops.ed.undo()` in MCP scripts can crash or disconnect the Blender session — avoid relying on undo; work non-destructively instead

---

## Testing (test-first for new gameplay)

- **Rules with a right answer are test-first.** Damage, i-frame and recovery windows, attack tokens, telegraph durations, level bands, save rules. Write the failing gdUnit4 test first, named after its design-bible target ID where there is one (for example `test_enemy_melee_telegraph`), then implement until it passes.
- **Behaviour measured in play is scenario-first.** Camera framing, encounter pacing, level metrics. Write the replay scenario (`tests/scenarios/`) and its target check first, confirm it fails at today's value, then iterate. Feel is still judged by playtests and the user.
- **Existing code gets characterization tests before a refactor,** written after the fact, so behaviour is pinned before it changes.
- **Commit the test before the implementation,** so the order shows in review. Throwaway spikes on scratch branches are fine, but the real branch starts with the failing test.
- **CI requires tests to pass;** it doesn't police the order. CI (`.github/workflows/ci.yml`) must be green before merging.
- **Running them:** `tests/run.sh` runs every gdUnit4 suite (`tests/unit/test_*.gd`; scene-reloading tests run as their own process from `tests/integration/`). A pending design target is a test with `do_skip := true, skip_reason := "pending: …"`; the implementing PR deletes the skip. Replay scenarios are `tests/scenarios/*.json`, run with `scripts/review/run_scenario.sh <scenario>` (two headless runs, compared, then metrics); each check carries a target, `pending` and a `baseline`, and the implementing PR updates the baseline and drops `pending`. `scripts/review/capture_evidence.sh <scenario>` renders an MP4, event frames and a contact sheet for review.
- **Every Godot and Blender call runs under a time limit** (`scripts/tools/godot_timeout.sh` / `.py`). On macOS a fatal Godot error waits at a modal alert forever, so exit 124 means it hung: raise the named `GODOT_TIMEOUT_*` / `BLENDER_TIMEOUT` variable, never remove the limit.
- **Warnings only go down:** a new warning is fixed, never added to `ci/warnings-baseline.txt`; a fixed one's line is deleted.
- **Git hooks** (`git config core.hooksPath .githooks`, with `pipx install gdtoolkit==4.5.0`): pre-commit runs gdformat and gdlint (config in `gdlintrc`, 120 columns) and the data lint; pre-push runs the warnings check and the tests. Format with `gdformat --line-length=120`.

---

## What Claude Should Always Do
- Write complete, runnable GDScript — no pseudocode or placeholder stubs unless explicitly asked
- Use Godot 4 syntax (not Godot 3) — e.g., `CharacterBody3D` not `KinematicBody`, `velocity` not `move_and_slide(velocity)`
- Prefer signals and composition over inheritance chains deeper than 2 levels
- Omit `class_name` if it causes a "hides a global script class" error — it is not required for scene scripts and can conflict with Godot's global class registry
- When modifying an existing system, preserve all existing signals and public method signatures
- Add brief comments on non-obvious logic; skip comments on self-explanatory lines
- If a task touches multiple files, list all files to be changed before writing any code