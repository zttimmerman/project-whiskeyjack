# CLAUDE.md — 3D Low-Poly Action RPG (Godot 4)

## Project Overview
This is a 3D action RPG built in Godot 4, inspired by early PS1/PS2 era games (think early Final Fantasy, Legend of Dragoon, early Zelda 3D). The look is stylized low-poly with generous budgets: bold colors, readable silhouettes, and simple albedo-only textures over realism. Combat is real-time action in the style of Zelda / early Dark Souls.

---

## Tech Stack & Conventions

- **Engine:** Godot 4.x
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
│   └── stylized_materials/  # glTF import extension: specular 0 on every imported material
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
│   ├── pipeline.py          # asset pipeline orchestrator (asset-pipeline skill)
│   ├── blender_cleanup.py   # pipeline clean stage (headless Blender)
│   ├── blender_views.py     # review renders
│   ├── godot_validate.gd    # pipeline validate stage (headless Godot)
│   ├── judge.py             # asset judge packets and verdict log
│   ├── judge_images.py      # judge image copies and color metrics (headless Blender)
│   ├── make_texture_overlay.py
│   ├── tools/               # build_animation_library, make_bone_maps, make_held_props
│   └── review/              # motion_review, anim_sheet, level1_play_capture, level1_compare
├── data/
│   ├── items/               # Item .tres resources
│   ├── dialogues/           # JSON dialogue trees
│   ├── quests/              # JSON quest definitions
│   ├── rigs/                # BoneMaps and per-rig SocketMaps
│   └── animations/          # per-character AnimationLibraries and shared clips (built, don't hand-edit)
├── docs/                    # art-bible.md (budgets, palette, briefs, judge tolerances), decisions.md (handoff), world/
└── assets/
    ├── briefs/              # per-asset brief YAML (copied from the art bible)
    ├── manifests/           # per-asset pipeline manifests and judge logs (JSON committed, images local)
    ├── meshes/              # cleaned, shipped .glb files
    ├── overlays/            # texture overlays composited at clean time
    ├── animations/          # Quaternius packs (CC0)
    ├── textures/
    ├── audio/
    └── fonts/
```
Outside `res://`: `.claude/skills/` (asset-pipeline, tripo), `.claude/agents/` (asset-judge), and the gitignored `.tripo-out/` (raw Tripo downloads, spend records, scratch work).

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
- Dialogue trees stored as JSON in res://data/dialogues/
- Format: array of dialogue nodes, each with: id, speaker, text, choices (optional array of {text, next_id})
- DialogueRunner autoload reads a dialogue file, steps through nodes, emits `dialogue_started`, `line_ready(speaker, text, choices)`, `dialogue_ended`
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

### Dialogue JSON (res://data/dialogues/village_elder.json)
```json
[
  { "id": "start", "speaker": "Elder", "text": "Traveler, you've arrived at last.", "choices": [
    { "text": "What do you need from me?", "next_id": "quest_offer" },
    { "text": "Just passing through.", "next_id": "farewell" }
  ]},
  { "id": "quest_offer", "speaker": "Elder", "text": "Monsters have taken the eastern road. Will you help?", "choices": [
    { "text": "I'll do it.", "next_id": "quest_accept" },
    { "text": "Not my problem.", "next_id": "farewell" }
  ]},
  { "id": "quest_accept", "speaker": "Elder", "text": "Thank you. Be safe.", "set_quest": "clear_eastern_road", "next_id": null },
  { "id": "farewell", "speaker": "Elder", "text": "Safe travels.", "next_id": null }
]
```

---

## Scene Files (.tscn)
- Claude writes `.tscn` files directly — do not ask the user to set up scenes manually in the editor
- Always create the `.tscn` alongside its `.gd` when building a new scene
- UIDs (`uid://...`) in `.tscn` files may be regenerated by Godot on first open — this is harmless
- When instancing one scene inside another, reference it via `[ext_resource type="PackedScene"]` and an `instance=ExtResource(...)` node entry
- Always verify node types match the script's `extends` (e.g. root must be `CharacterBody3D`, not `CharacterBody2D`)
- Node names in `.tscn` must exactly match `$NodeName` references in the attached script
- UI panels that must remain active while the game is paused (`get_tree().paused = true`) need `process_mode = 3` (`PROCESS_MODE_ALWAYS`) on their root node; child nodes inherit this automatically via `PROCESS_MODE_INHERIT`

---

## Git Workflow

### Branches and pull requests
- **Never commit directly to `main`.** Start each feature or session on a short-lived branch off an up-to-date `main`, named after the work (`playtest-slice`, `cc0-import`).
- **Merge through a pull request** (`gh pr create`, then `gh pr merge --merge --delete-branch`). Use a merge commit so the atomic commit history survives; don't squash. Merge only when the user says to; GitHub doesn't allow approving your own PR, so "approve" means the user's OK in chat.
- **Merge often.** GLBs, textures and hand-edited `.tscn` files don't merge well, so two long-lived branches touching the same asset or scene means one side gets redone by hand.
- **Delete branches once merged.** GitHub deletes head branches automatically; locally, `git fetch --prune` and the `clean_gone` command. Mark milestones with tags (`poc-slice`, `mvp`), not kept branches.
- **Parallel agents** each get their own worktree and branch; clean both up when done.
- **Refresh the session handoff** in `docs/decisions.md` before opening a PR.

### Commits
- **Commit atomically:** one logical change per commit (a new system, a bug fix, a scene setup); don't bundle unrelated changes.
- **Ask before committing** unless the user has asked for commits in this session (for example "commit at logical checkpoints").
- **Commit message format:** an imperative subject line saying what changed, then body bullets for the why and notable details.
- **Always commit `.tscn` files with their `.gd` files:** a script and its scene are one logical unit.
- **Commit `.uid` files:** Godot 4 generates them alongside scripts, and they should be tracked.

### What stays out of git
- **Never commit** `.godot/` (editor and shader cache), `.DS_Store`, or `.tripo-out/` (raw downloads and scratch). All are gitignored.
- **Commit finished assets, not their working artifacts.** `assets/meshes/`, `assets/overlays/`, briefs and manifest JSON are committed. Pipeline evidence images under `assets/manifests/` (review renders, judge packet copies, replays, animation sheets) stay local and gitignored; the committed JSON records each image's SHA-256.
- **Secrets never go in the repo or the remote URL.** GitHub access goes through `gh` (`gh auth login`, `gh auth setup-git`), and `origin` is the bare `https://github.com/...` URL. Check new commits for tokens before a first push.
- **Never rewrite pushed history.** To drop files, make a removal commit (`git rm --cached` plus a `.gitignore` rule), not a rewrite.

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

- **Do not build armatures, paint weights, or keyframe animations via MCP scripting.** Animation comes from a shared animation library that is retargeted onto each character; it is not authored per model
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

## What Claude Should Always Do
- Write complete, runnable GDScript — no pseudocode or placeholder stubs unless explicitly asked
- Use Godot 4 syntax (not Godot 3) — e.g., `CharacterBody3D` not `KinematicBody`, `velocity` not `move_and_slide(velocity)`
- Prefer signals and composition over inheritance chains deeper than 2 levels
- Omit `class_name` if it causes a "hides a global script class" error — it is not required for scene scripts and can conflict with Godot's global class registry
- When modifying an existing system, preserve all existing signals and public method signatures
- Add brief comments on non-obvious logic; skip comments on self-explanatory lines
- If a task touches multiple files, list all files to be changed before writing any code