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
- **Autoloads (Singletons):** Use sparingly — only for truly global systems (GameManager, SaveManager, QuestManager)

---

## Visual Style Rules

- Low polygon counts — avoid subdivided meshes; embrace faceted shading
- Flat or vertex-colored materials where possible; minimal texture resolution (64x64 or 128x128 preferred)
- No normal maps; keep lighting simple with a single directional light + ambient
- Avoid bloom, SSA, and screen-space reflections — these break the aesthetic
- Camera: Third-person, behind the player, with optional lock-on targeting for combat
- UI: Pixel-style fonts, chunky bordered panels, limited color palette

---

## Project Structure

```
res://
├── autoloads/
│   ├── GameManager.gd       # Game state, scene transitions
│   ├── SaveManager.gd       # Save/load via JSON
│   └── QuestManager.gd      # Active quests, quest state
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
│       └── QuestLogUI.tscn
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
- Attack combos tracked via a combo timer and attack index
- Enemy stagger/knockback on successful hits
- Player i-frames during dodge roll
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

## What Claude Should Always Do
- Write complete, runnable GDScript — no pseudocode or placeholder stubs unless explicitly asked
- Use Godot 4 syntax (not Godot 3) — e.g., `CharacterBody3D` not `KinematicBody`, `velocity` not `move_and_slide(velocity)`
- Prefer signals and composition over inheritance chains deeper than 2 levels
- Omit `class_name` if it causes a "hides a global script class" error — it is not required for scene scripts and can conflict with Godot's global class registry
- When modifying an existing system, preserve all existing signals and public method signatures
- Add brief comments on non-obvious logic; skip comments on self-explanatory lines
- If a task touches multiple files, list all files to be changed before writing any code