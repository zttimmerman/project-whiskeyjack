# CLAUDE.md — 3D Low-Poly Action RPG (Godot 4)

## Project Overview
This is a 3D action RPG built in Godot 4, inspired by early PS1/PS2 era games (think early Final Fantasy, Legend of Dragoon, early Zelda 3D). The aesthetic is intentionally low-poly and stylized — embrace chunky geometry, limited vertex counts, and bold colors over realism. Combat is real-time action in the style of Zelda / early Dark Souls.

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

**Target fidelity: PS2 era (~2001–2004).** Think Final Fantasy X field models, Kingdom Hearts, Dark Cloud 2 — not PS1 blockiness, not modern HD. Characters should look like they belong on a PS2 loading screen.

- **Polygon budget:** ~2,000–5,000 vertices per character; ~500–2,000 for props/smaller objects. Smooth limbs with visible edge flow, recognizable faces and fingers — not box people
- **Materials:** vertex colors or simple hand-painted textures (128x128 to 256x256). PBR textures from AI generators are acceptable if downscaled and simplified to match the aesthetic
- No normal maps; keep lighting simple with a single directional light + ambient
- Avoid bloom, SSAO, and screen-space reflections — these break the aesthetic
- **Silhouettes matter:** characters should read clearly from the gameplay camera distance. Exaggerated proportions (slightly large heads, stylized hair) are fine and encouraged
- Camera: Third-person, behind the player, with optional lock-on targeting for combat
- UI: Pixel-style fonts, chunky bordered panels, limited color palette

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

## 3D Asset Workflow (Blender MCP)

This project uses the **Blender MCP** to create, generate, and edit 3D models directly from Claude Code. All meshes live in `assets/meshes/` as `.glb` files.

### Setup
- **MCP install:** `claude mcp add blender uvx blender-mcp` (user-level, one-time)
- **Every session:** Blender must be open with the BlenderMCP addon active and server started (sidebar → BlenderMCP → "Start Server"). If the `mcp__blender__*` tools are missing, remind the user to:
  1. Open Blender
  2. Enable the BlenderMCP addon (Edit → Preferences → Add-ons)
  3. Click "Start Server" in the BlenderMCP sidebar panel
  4. Restart the Claude Code session if the MCP was just installed
- **AI generation integrations** must be enabled per-session in the BlenderMCP sidebar panel (checkboxes + API keys where needed), then reconnect

### AI Model Generation (primary workflow for new assets)

Base meshes should be **AI-generated** whenever possible, then cleaned up and modified via MCP scripting. Do not hand-code complex geometry vertex-by-vertex — that's only appropriate for simple shapes (hair spikes, flat panels, accessories).

**Hyper3D Rodin Gen-2 via fal.ai (primary — $0.40/generation):**
- Pay-per-use through fal.ai, no subscription required
- The BlenderMCP addon has been **patched** to use Rodin v2 endpoints (`fal-ai/hyper3d/rodin/v2` for image-to-3D, `fal-ai/hyper3d/rodin/v2/text-to-3d` for text-to-3D). The addon file is at `~/Library/Application Support/Blender/5.0/scripts/addons/addon.py`
- v2 request params: `quality_mesh_option: "50K Quad"`, `geometry_file_format: "glb"`, `material: "PBR"`, `TAPose: true` — these are hardcoded in the patched addon
- **Important:** fal.ai queue URLs (poll/fetch) use the path `fal-ai/hyper3d/requests/{id}`, NOT the v2 submission path — the addon's poll/import URLs must stay as the original non-v2 format
- Enable in BlenderMCP sidebar → "Use Hyper3D Rodin 3D model generation" → select **fal.ai** mode → enter fal.ai API key
- Workflow: `generate_hyper3d_model_via_text` or `_via_images` → `poll_rodin_job_status` → `import_generated_asset`
- Generated models come in at normalized size (~1 unit) — rescale after import to match the game world
- **Prompt tips:** include "no weapons, empty hands" to avoid baked-in weapons; include "T-pose" or "A-pose" for rigging-ready output; AI may still generate unwanted items — regenerate rather than attempting mesh surgery

**Sketchfab (for sourcing pre-made assets):**
- Search for CC0/free-license low-poly models when AI generation isn't the right fit
- Requires a free Sketchfab API key
- Enable in BlenderMCP sidebar → "Use assets from Sketchfab" + enter API key
- Workflow: `search_sketchfab_models` → `get_sketchfab_model_preview` → `download_sketchfab_model`

### API Spend Safeguards

**Hard rules — Claude must follow these without exception:**
- **$5 max per session** (~12 Rodin generations at $0.40 each)
- **Always state the cost and get explicit user confirmation** before every generation call — no silent API spend
- **Track a running total** of generations and estimated cost in the conversation; display it with each confirmation prompt
- **Stop and warn** when approaching the cap (e.g., at $4.00 / 10 generations)
- **Refuse to generate** if the session cap would be exceeded, unless the user explicitly raises the limit for that session
- If a generation fails or produces unusable results, it still counts toward the session total (the API was still called)

### Post-Generation Cleanup (MCP scripting)

AI-generated meshes will need adjustment before use in-game:
- **Do NOT decimate or downscale textures** unless explicitly asked — Rodin v2 output already looks PS2-era appropriate at ~50K faces
- **Rescale** to match the game world (e.g., character height ~1.8m). Move mesh vertices so feet sit at Z=0 in Blender (Y=0 in Godot)
- **Rig with armature** — generated models don't have skeletons. Create a 21-bone humanoid armature via MCP scripting, parent with automatic weights. The T-pose output from v2 makes this straightforward
- **Create animations** via keyframing pose bones in Blender. Required set: `idle`, `run`, `dodge_roll`, `attack_light`, `attack_heavy`, `death`. Arms in T-pose rest need ~55° Z rotation on UpperArm bones to hang at sides
- **Do NOT attempt fine mesh surgery** (removing baked-in weapons, rebuilding hands, fixing faces) via MCP scripting — it burns tokens and damages the mesh. Regenerate with a better prompt instead, or fix manually in Blender's GUI

### Manual MCP Editing (for modifications, not base meshes)

Use direct bmesh/Python scripting via MCP for:
- Modifying existing geometry (hair restyling, adding accessories, patching gaps)
- Simple procedural shapes (spikes, flat panels, gem shapes)
- Vertex color adjustments and material fixes
- Rigging weight assignments

**Do NOT** hand-code complex organic meshes (characters, creatures, weapons with curves). Generate those via AI instead.

Editing workflow:
1. **Import:** clear the Blender scene, then `import_scene.gltf(filepath=...)` to load the existing `.glb`
2. **Inspect first:** use `get_scene_info` and `get_viewport_screenshot` to understand the current model before making changes
3. **Analyze mesh data** before modifying — check vertex groups, color attributes, material setup, and bounding boxes via bmesh so edits land in the right place
4. **Preserve rigging:** when adding/removing geometry, always assign vertex group weights (via the `deform` layer) to the correct bone so the armature still works
5. **Preserve vertex colors:** set the color attribute on every loop of every new face — missing colors will render black
6. **Validate coverage:** for geometry meant to cover other geometry (hair over a skull, armor over a body), check the actual Z/position of the underlying mesh vertices — don't assume; the model may extend higher than expected
7. **Screenshot from multiple angles** after changes — top-down, front, back, side — to catch gaps or artifacts before exporting
8. **Export:** `export_scene.gltf(filepath=..., export_format='GLB', export_animations=True, export_skins=True, export_yup=True)` — note that `export_colors` is not a valid parameter in Blender 5.x; vertex colors export automatically

### Blender → Godot Integration Gotchas
- **Facing direction:** Models face -Y in Blender. After GLB export with `export_yup=True`, this becomes +Z in Godot. Godot's forward is -Z, so the model appears to face backward. **Fix:** add a 180° Y rotation on the model node in the `.tscn`: `Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, 0, 0)`
- **Model grounding:** CharacterBody3D collision capsule (height 1.8) centers at the node origin, so the capsule bottom is at Y=-0.9. The model's feet (at local Y=0) must be offset to match: set model node Y translation to -0.9. Example: `Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, -0.9, 0)`
- **Blender 5.x Action API:** Uses layered actions (`.layers`, `.slots`) instead of legacy `.fcurves`. Use `keyframe_insert()` on pose bones directly — don't try to access `action.fcurves`
- **Axis conversion:** Blender Z-up → Godot Y-up. Blender (X, Y, Z) → Godot (X, -Z, Y) approximately. Bone positions, animations, and mesh data all get converted by the GLB exporter
- **GLB >4 joint influences warning** is normal for dense meshes — the exporter auto-selects the top 4 weights per vertex

### Other MCP Gotchas
- Hair/accessory geometry is typically disconnected from the body mesh (no shared vertices), making it safe to delete and rebuild independently
- Always check both local and world coordinates — if `matrix_world` is identity, they're the same
- `bmesh.ops.delete` with `context='FACES'` deletes faces but may leave orphan vertices; clean them up with a second pass
- Rotating armatures without also rotating the child mesh vertices breaks skinning — avoid; use Godot-side `Transform3D` rotation on the model node instead
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