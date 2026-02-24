# Project Whiskeyjack

A 3D low-poly action RPG built in Godot 4, inspired by early PS1/PS2 era titles — think early Final Fantasy, Legend of Dragoon, and Zelda 3D. The aesthetic leans into chunky geometry, bold flat colors, and minimal polygons. Combat is real-time in the style of early Zelda / Dark Souls.

---

## Requirements

- **Godot 4.6** — download the standard (non-Mono) build from [godotengine.org](https://godotengine.org/download)
- No additional plugins or dependencies

---

## Getting Started

```bash
git clone https://github.com/zttimmerman/project-whiskeyjack.git
```

1. Open Godot 4.6 and choose **Import**
2. Navigate to the cloned folder and select `project.godot`
3. Press **F5** (or the Play button) to run from the default scene (`TestWorld`)

The input map is already configured in `project.godot` — no manual setup needed.

---

## Controls

### Movement
| Action | Keyboard | Controller |
|---|---|---|
| Move | W / A / S / D | Left Stick |
| Rotate camera | Arrow Keys / Q / E | Right Stick |

### Combat
| Action | Keyboard | Controller |
|---|---|---|
| Light attack (3-hit combo) | J / Left Click | Button 0 (A/Cross) |
| Heavy attack | K | Button 2 (X/Square) |
| Dodge roll (i-frames) | Space / Shift | Button 1 (B/Circle) |
| Lock on / cycle targets | Tab | R3 |

### Interaction & UI
| Action | Keyboard | Controller |
|---|---|---|
| Interact (talk to NPC) | F | Button 3 (Y/Triangle) |
| Inventory | I | Select/Back |
| Quest log | L | L1/LB |
| Pause | Escape | Start/Options |

---

## What's Implemented

### World
- `TestWorld` — a flat test arena with a player, one enemy, a dummy target, and the village elder NPC

### Player
- Third-person camera with mouse look and gamepad support
- Camera-relative movement and rotation
- Dodge roll with invincibility frames
- Lock-on targeting: locks to the nearest enemy, Tab cycles through multiple targets

### Combat
- 3-hit light attack combo with a reset timer
- Heavy attack (3× damage, strong knockback)
- Hitbox/Hurtbox component system — hitboxes activate for a brief window per swing
- Enemy stagger and knockback on hit

### Enemies
- `BaseEnemy` — NavigationAgent3D pathfinding, IDLE / PATROL / CHASE / ATTACK / STAGGER / DEAD states
- Grants XP to the player on death

### Stats & Progression
- `CharacterStats` resource: HP, attack, defense, speed, level, XP
- Level-up on XP threshold; stats increase on level-up
- HUD: HP bar (flashes red on damage), XP bar, level label
- YOU DIED overlay on death → auto-respawn at last save point with full HP

### Inventory & Equipment
- Starting items: Iron Sword (+5 attack) and a Health Potion (restores 30 HP)
- Open with **I** — click an item to equip/unequip weapons and armor, or use consumables
- Equipped items are marked `[EQ]` in the list

### Dialogue
- Interact with the **Village Elder** (NPC near origin) using **F**
- Branching dialogue tree with choices
- Accepting the elder's quest starts "Clear the Eastern Road"

### Quest Log
- Open with **L** — shows active quests on the left, selected quest's current objective on the right
- Completed quests listed at the bottom of the info panel
- Updates live as quest state changes

### Save / Load / Pause
- **Escape** opens the pause menu
- **Save Game** — writes player position, stats, inventory, equipment, and quest state to `user://save.json`
- **Load Game** — restores from save
- On death, the game reloads and applies the last save automatically

---

## Project Structure

```
autoloads/          Global singletons (GameManager, SaveManager, QuestManager)
scenes/
  player/           Player scene and script
  enemies/          BaseEnemy scene and script
  npcs/             NPC scene and script
  ui/               HUD, InventoryUI, DialogueUI, QuestLogUI, PauseMenu
  world/            TestWorld (main playable scene)
scripts/
  combat/           HitboxComponent, HurtboxComponent
  inventory/        Item, Inventory resources
  stats/            CharacterStats resource
  dialogue/         DialogueRunner
data/
  dialogues/        JSON dialogue trees
  items/            .tres item resources
  quests/           JSON quest definitions
assets/             Meshes, textures, audio, fonts
```

---

## Notes for Contributors

- GDScript only — no C#
- Godot 4 syntax throughout (`CharacterBody3D`, not `KinematicBody`, etc.)
- See `CLAUDE.md` for full coding conventions, system design notes, and data format examples
- See `INPUT_SETUP.md` if you need to re-create the input map from scratch (e.g. after adding a new action)
