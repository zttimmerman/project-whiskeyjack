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
- **Textures are albedo (base color) only:** one texture per asset, at the size in the art bible, or vertex colors. No normal, roughness, metallic, occlusion, emissive, or specular maps. Materials are `StandardMaterial3D` with `albedo_texture` set and everything else at defaults
- **Lighting:** one `DirectionalLight3D` + ambient per area; local `OmniLight3D`s are allowed only for visible light sources (torches, candelabras)
- Avoid bloom, SSAO, and screen-space reflections
- **Silhouettes matter:** characters should read clearly from the gameplay camera distance. Exaggerated proportions (slightly large heads, stylized hair) are fine and encouraged
- Camera: Third-person, behind the player, with optional lock-on targeting for combat
- UI: chunky bordered panels, limited color palette, Godot's default font
- **Post-MVP — do not implement unless explicitly asked:** palette quantization, vertex-snapping or affine-texture-warp shaders, pixel fonts

---

## Project Structure

```
res://
├── autoloads/
│   ├── GameManager.gd       # Game state, scene transitions
│   ├── SaveManager.gd       # Save/load via JSON
│   ├── QuestManager.gd      # Active quests, quest state
│   ├── DialogueRunner.gd    # Dialogue tree playback
│   └── AudioManager.gd      # Audio buses, music, SFX helpers
├── scenes/
│   ├── player/
│   │   ├── Player.tscn
│   │   └── Player.gd
│   ├── enemies/
│   │   ├── BaseEnemy.tscn
│   │   └── BaseEnemy.gd
│   ├── npcs/
│   │   ├── NPC.tscn
│   │   └── NPC.gd
│   ├── world/
│   │   └── (individual area/level scenes)
│   └── ui/
│       ├── HUD.tscn
│       ├── InventoryUI.tscn
│       ├── DialogueUI.tscn
│       ├── QuestLogUI.tscn
│       └── PauseMenu.tscn
├── scripts/
│   ├── combat/
│   │   ├── HitboxComponent.gd
│   │   └── HurtboxComponent.gd
│   ├── inventory/
│   │   ├── Inventory.gd
│   │   └── Item.gd
│   ├── dialogue/
│   │   └── DialogueRunner.gd
│   └── stats/
│       └── CharacterStats.gd
├── data/
│   ├── items/               # JSON item definitions
│   ├── dialogues/           # JSON dialogue trees
│   └── quests/              # JSON quest definitions
└── assets/
    ├── meshes/
    ├── textures/
    ├── audio/
    └── fonts/
```

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
- **Animation:** BaseEnemy looks for `$SkeletonModel/AnimationPlayer` in `_ready()` and plays state-driven animations (idle, run, attack, stagger, death). Locomotion anim (idle vs run) updates each frame during CHASE based on horizontal speed. `die()` delays `queue_free()` by 1.5s so death animation can play. Subclasses that override `_change_state()` must call `_play_anim()` themselves for the overridden state (see ArcherEnemy)
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

## Git Practices

- **Commit atomically** — one logical change per commit (e.g. a new system, a bug fix, a scene setup); do not bundle unrelated changes
- **Always commit `.tscn` files alongside their `.gd` files** — a script and its scene are one logical unit
- **Commit `.uid` files** — Godot 4 generates these alongside scripts; they should be tracked
- **Never commit `.godot/`** — already gitignored; contains editor cache and shader cache
- **Never commit `.DS_Store`** — already gitignored
- **Commit message format:** imperative subject line summarizing the "what", body bullet points for the "why" and notable details
- **Ask before committing** — do not create commits unless explicitly asked

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

- **Two skills, two layers:** the **asset-pipeline** skill (`scripts/pipeline.py <asset-id> --stage concept|multiview|model|clean|validate|all`) orchestrates briefs, stages, Blender cleanup, Godot validation and manifests. The Tripo chain is text-to-image → image-to-multiview → multiview-to-3D, and the pipeline stops after the concept until the user approves it (`--approve-concept N`). The **tripo** skill is the vendor adapter, and every paid `tripo` call goes through it (dry run → the user confirms the cost → paid run). `pipeline.py` only prints `tripo` commands; it never runs a paid one.
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
3. **Albedo only:** the material is rebuilt as base color (plus cutout alpha); normal, metallic/roughness, occlusion, emissive and specular maps are dropped; the texture is downscaled to the brief's size
4. **Do NOT attempt fine mesh surgery** (removing baked-in weapons, rebuilding hands, fixing faces) via MCP scripting — it burns tokens and damages the mesh. Regenerate with a better prompt instead, or fix manually in Blender's GUI

### Rigging & Animation

- **Do not build armatures, paint weights, or keyframe animations via MCP scripting.** Animation comes from a shared animation library that is retargeted onto each character; it is not authored per model
- Character models must use a humanoid skeleton that maps onto Godot's `SkeletonProfileHumanoid`, so the shared library can be retargeted through the `BoneMap` in the GLB's import settings. If a model has no such skeleton, stop and ask the user how it should be rigged
- **Socket bones:** every new character needs its socket bones (`hand_r`, `hand_l`, …) mapped in a `SocketMap` resource at `data/rigs/<rig>_sockets.tres`, assigned to the scene's `socket_map` export. That file is the single place to update when a rig changes or is regenerated. Never write bone names in scripts, scenes or call sites; enemies attach props via `held_props` (socket → PackedScene)
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