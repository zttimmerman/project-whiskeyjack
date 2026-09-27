> ## Status (updated 2026-09-27)
>
> **What this describes:** the findings below describe commit `1467dbf` and are kept as a historical record, unedited. This status block reflects the state committed together with it: the first commit after `1467dbf`, which adds `docs/art-bible.md`, `docs/world/`, and the slice quest/dialogue changes.
>
> **Resolved**
> - **R5** (README vs CLAUDE.md style wording): one canonical style sentence, now in both `README.md` and `CLAUDE.md`.
> - **C13** (vertex budget vs "don't decimate 50K"): budgets are authoritative and the decimate step is mandatory (`CLAUDE.md` → Visual Style Rules and Post-Generation Cleanup).
> - **C14** (normal maps): *policy* resolved as albedo-only (`CLAUDE.md`, `docs/art-bible.md`). Shipped assets still break it: `player_character.glb` is 50,566 vertices with normal and metallic-roughness maps, and the torch and candelabra ship extra maps. That asset work is open.
> - **C15** (lighting): local lights are allowed for visible light sources (`CLAUDE.md`, `docs/art-bible.md`).
> - **C16** (pixel fonts): the default font for MVP; pixel fonts are post-MVP (`CLAUDE.md`, `docs/art-bible.md`).
> - **§5 Phase B scope and B3 archer note:** decided in `docs/world/07-mvp-slice.md`. It's one location, one quest, one NPC, and one enemy model with two variants; all 7 Level 1 skeletons count toward the quest.
> - **T2** (do fake UIDs fall back?): answered by a headless run on Godot 4.6.1. All 9 fake UIDs log "invalid UID … using text path instead" and load. The underlying fix (A3) is still open.
>
> **Partially addressed**
> - **B3 talk stage:** `return_to_keeper` is implemented (`data/quests/clear_eastern_road.json`, `scenes/npcs/NPC.gd` `return_stage_id`, `scenes/world/Level1.gd`), but progression is still hardcoded in `Level1.gd`, so B2/B3's data-driven objectives remain open.
> - **§4 CLAUDE.md split:** the art and asset sections are rewritten in place, but the core/skills split hasn't been done. The `blender-animation` skill and `blender-animator` agent now contradict CLAUDE.md (no per-model keyframing) and need removing or rewriting.
>
> **Open (these feed Phases A–C)**
> - **R1–R4, R6–R8, C1–C12, C17–C19, §1c:** doc and code contradictions, input conflict (E key), and UID/path hygiene. Feeds A3–A5.
> - **All of §2:** damage formula (shield → 0 damage), `died` re-emission, hit-stop on i-frames, arrows through walls, modal/pause conflicts, save without scene or version, resource-cache player state, inventory identity/stacks, quest privates and silent stubs. The kill-before-accept bug (§2.7) still applies to the new stage flow. Feeds B1–B11 and C.
> - **All of §3:** content-in-code. Feeds B2–B11.
> - **§6 tests T1, T3–T9:** not yet written. Feeds A1–A2.

---

# Project Whiskeyjack — Pre-Revamp Audit

**Date:** 2026-09-27  **Commit audited:** `1467dbf` (main, clean)  **Engine:** Godot 4.6, GDScript only
**Scope read:** `CLAUDE.md`, `README.md`, `INPUT_SETUP.md`, `project.godot`, every `.gd` / `.tscn` / `.tres` / `.json` under `autoloads/`, `scenes/`, `scripts/`, `data/`, plus `.uid` sidecars. No code was modified.

**Confidence labels used below**
- **[read]**: verified by reading the code, and the arithmetic or control flow is unambiguous.
- **[unverified]**: depends on engine runtime behavior that reading can't settle. Each one points to a proposed headless test (§6).

---

## 0. Executive summary

The game is a working prototype. Movement, combat, one quest, dialogue, save/load, and two levels are playable. It won't scale to ~20 quests, ~40 items, ~10 enemy types and 5+ areas without structural changes, for five reasons:

1. **Quest logic lives in level scripts.** `Level1.gd` hardcodes the kill count, stage IDs, the reward and the scene gate. The `completion_condition` field in quest JSON is never read.
2. **Player progress likely carries between scenes by accident** (engine resource caching), not by design. Saves don't record which scene they came from, so dying in Level 2 with a Level 1 save puts you at Level 1 coordinates inside Level 2.
3. **The damage formula breaks at the first reward.** With the Elder's Shield equipped, every enemy in the game deals 0 damage [read].
4. **Pausing is not coordinated.** Four UIs each toggle `get_tree().paused` on their own. The quest log can be opened over dialogue or the pause menu, and closing it unpauses the game underneath.
5. **Scene files have broken references.** Ten script references use fake UIDs or a wrong-case path. They probably only work because Godot falls back to the path and macOS's filesystem ignores case.

The plan in §5 starts with low-risk cleanup (a test harness, fixing UIDs and inputs, a docs split). It then makes the existing Level 1 + skeleton + "Clear the Eastern Road" loop fully data-driven as the vertical slice before any new content.

---

## 1. Contradictions: CLAUDE.md vs README vs code

### 1a. README vs code

| # | Claim | Reality | Cite |
|---|---|---|---|
| R1 | "Press F5 … run from the default scene (`TestWorld`)" | Main scene is Level1 | `README.md:22` vs `project.godot:15` |
| R2 | "World: `TestWorld` — a flat test arena…" is the only world listed | Level1 (village + eastern road) and Level2 (crypt) exist and are the real game | `README.md:56-57`; `scenes/world/Level1.tscn`, `Level2.tscn` |
| R3 | Interact = **F**; camera = **Q / E** | **E is bound to both `camera_right` and `interact`**, so pressing E near an NPC rotates the camera *and* opens dialogue | `README.md:34,47` vs `project.godot` `camera_right` (physical_keycode 69) and `interact` (physical_keycode 69) |
| R4 | `autoloads/  Global singletons (GameManager, SaveManager, QuestManager)` | Five autoloads: AudioManager and DialogueRunner are missing from the list, and DialogueRunner lives in `scripts/dialogue/` | `README.md:107` vs `project.godot:19-23` |
| R5 | "aesthetic leans into chunky geometry, bold flat colors, and minimal polygons" | CLAUDE.md targets PS2-era fidelity with PBR textures and ~50K-face AI meshes | `README.md:3` vs `CLAUDE.md:23-26,285` |
| R6 | "auto-respawn at last save point with full HP" | If no save exists, you respawn at the scene's start position with level, XP and inventory *probably* kept (see S1). If a save from another scene exists, you're teleported to that scene's coordinates inside the current scene | `README.md:79,100`; `GameManager.gd:65-89` |
| R7 | "Lock on / cycle targets: Tab" | True, but with 2+ candidates Tab only ever cycles; there's no way to release lock-on except walking 22.5 m away | `README.md:42`; `Player.gd:242-249,264-266` |
| R8 | `INPUT_SETUP.md` says "Add the following actions in Project Settings" | README says the map is already in `project.godot`. INPUT_SETUP also has E on both camera and interact | `INPUT_SETUP.md:3,24,40` vs `README.md:24` |

### 1b. CLAUDE.md vs code

| # | CLAUDE.md says | Reality | Cite |
|---|---|---|---|
| C1 | "HitboxComponent emits `hit(target, damage)`, HurtboxComponent receives it" | HurtboxComponent never connects to `hit`. It listens to its own `area_entered` and reads `hitbox.damage`. Only Player (camera shake) and Projectile (self-free) consume `hit` | `CLAUDE.md:98`; `HurtboxComponent.gd:15-27`; `Player.gd:63`; `Projectile.gd:15` |
| C2 | Project tree: `autoloads/DialogueRunner.gd` | The autoload is `scripts/dialogue/DialogueRunner.gd`. The tree lists it in both places | `CLAUDE.md:43,71`; `project.godot:22` → `scripts/dialogue/DialogueRunner.gd.uid` |
| C3 | Project tree: `data/items/  # JSON item definitions` | Items are `.tres`, as the same file says later | `CLAUDE.md:75` vs `CLAUDE.md:118` |
| C4 | Quest stages have `completion_condition` | Never read anywhere. Stage progression is hardcoded in `Level1.gd` | `CLAUDE.md:129`; `clear_eastern_road.json:9,14`; `Level1.gd:3-4,28-44` |
| C5 | "Dialogue can set quest flags via QuestManager" | Dialogue can only *start* a quest (`set_quest`). It can't advance, complete, check state, set flags or give items | `CLAUDE.md:126`; `DialogueRunner.gd:76-79` |
| C6 | Save serializes "any world flags (doors opened, enemies killed, etc.)" | No world flags exist. The save holds `player` + `quests` only | `CLAUDE.md:137`; `SaveManager.gd:12-15` |
| C7 | Save is "Called by GameManager on scene transitions" | `GameManager.change_scene` never saves | `CLAUDE.md:139`; `GameManager.gd:48-50` |
| C8 | Equipment slots: weapon, helmet, chest, boots | Only `weapon` and `chest` are reachable: every ARMOR goes to `chest`, including the shield | `CLAUDE.md:116`; `Inventory.gd:73-79`; `shield_wooden.tres:10` |
| C9 | States include PATROL | PATROL is a stub identical to IDLE, with no patrol points | `CLAUDE.md:158`; `BaseEnemy.gd:77-81` |
| C10 | Enemy types "override `_get_next_action()`" | ArcherEnemy also overrides `_change_state` and `_tick_attack` (half-documented at `CLAUDE.md:159`). Every enemy subtype *must* have `HitboxComponent`, `HurtboxComponent` and `NavigationAgent3D` child nodes, because BaseEnemy looks them up by name and crashes if one is missing; the archer carries an unused melee hitbox for this reason | `CLAUDE.md:157`; `ArcherEnemy.gd:13,26`; `BaseEnemy.gd:32-34`; `ArcherEnemy.tscn:60-69` |
| C11 | CharacterStats signals: `health_changed`, `died`, `leveled_up` | Also `xp_changed` (additive; the doc is stale) | `CLAUDE.md:110`; `CharacterStats.gd:7` |
| C12 | "Enemies use simpler stat sets" | Enemies use the full CharacterStats (level/XP fields unused), and **`stats.attack` is ignored for enemies**: melee damage comes from the HitboxComponent export, and archer damage is hardcoded in `Projectile.tscn` | `CLAUDE.md:111`; `BaseEnemy.tscn:19,61`; `ArcherEnemy.tscn:19,66`; `Projectile.tscn:24` |
| C13 | Polygon budget ~2,000–5,000 verts per character | The same file says don't decimate ~50K-face Rodin output | `CLAUDE.md:25` vs `CLAUDE.md:259,285` |
| C14 | "No normal maps" | Normal maps ship with the player, torch and candelabra | `CLAUDE.md:27`; `assets/meshes/*_normal.png` |
| C15 | "Single directional light + ambient" | Level1 has 4 OmniLights, Level2 has 6 | `CLAUDE.md:27`; `Level1.tscn:263-285`; `Level2.tscn:486-520` |
| C16 | "UI: Pixel-style fonts" | `assets/fonts/` is empty; all UI uses the default theme font | `CLAUDE.md:31` |
| C17 | "Godot 4.x"; "Mobile or Compatibility renderer" | README and project say 4.6. Renderer is `gl_compatibility`, but the feature tag says `"Forward Plus"` (editor metadata only, but misleading) | `CLAUDE.md:10,12`; `project.godot:16` and last line |
| C18 | Collision layers (from project memory): player hurtbox on layer 1 | `project.godot` names layer 1 "world" and layer 2 "player", but nothing uses layer 2. Player body, player hurtbox, enemy bodies and world geometry all share layer 1 | `project.godot [layer_names]`; `Player.tscn:60` |
| C19 | "Node names … must exactly match" / UIDs "may be regenerated … harmless" | 10 script references use **fake or mismatched UIDs** (below), and Player.tscn points at a **wrong-case path** | See §1c |

### 1c. Scene-reference hygiene (a contradiction with the stated `.uid` convention)

Each script's `.uid` sidecar (git-tracked) holds its real UID. These `.tscn` references don't match it:

| Referenced as | Real UID in `.gd.uid` | Used in |
|---|---|---|
| `uid://bcharstats0001` → CharacterStats.gd | `uid://lgxb5k27hssk` | `Player.tscn:5`, `BaseEnemy.tscn:4`, `ArcherEnemy.tscn:4` (TestWorld uses the real one, so the same script is referenced two ways) |
| `uid://hitboxcmp001` → HitboxComponent.gd | `uid://c1eqqmvh0fwtd` | Player, BaseEnemy, ArcherEnemy, Projectile `.tscn`, and `metadata/_custom_type_script` |
| `uid://dbaseenemy01gd` → BaseEnemy.gd | `uid://bbei1eunkm4kh` | `BaseEnemy.tscn:3` |
| `uid://archerenemy_gd` → ArcherEnemy.gd | `uid://bhcyptky52dit` | `ArcherEnemy.tscn:3` |
| `uid://projectile_gd1` → Projectile.gd | `uid://b7iv7pwx6fhfg` | `Projectile.tscn:3` |
| `uid://bhudscript001` → HUD.gd | `uid://btv2toyis7ve1` | `HUD.tscn:3` |
| `uid://invuiscript001` → InventoryUI.gd | `uid://bdgt410qv3nq3` | `InventoryUI.tscn:3` |
| `uid://pmenu0gd0001` → PauseMenu.gd | `uid://c57386eovs2pu` | `PauseMenu.tscn:3` |
| `uid://questloguiscript1` → QuestLogUI.gd | `uid://bwvla4ppfra7u` | `QuestLogUI.tscn:3` |
| `path="res://scenes/player/player.gd"` | The file is `Player.gd` (capital P) | `Player.tscn:3` |

Scene UIDs such as `uid://archerenemy_sc` and `uid://projectile_sc1` are also hand-invented. `DialogueUI.gd.uid` itself contains the hand-written `uid://dlguiscript001`: it's consistent, but it isn't a Godot-generated ID.

**[unverified]** Godot normally warns and falls back to the text path when a UID doesn't resolve, which is probably why this works. The wrong-case `player.gd` path resolves on macOS's case-insensitive filesystem via the matching UID, but will likely fail on Linux CI or a case-sensitive export. → Tests T2, T3.

---

## 2. Per-system assessment

Scale targets: **~20 quests, ~40 items, ~10 enemy types, 5+ areas.**

### 2.1 Player (`scenes/player/Player.gd`, `Player.tscn`)

**Works**
- Camera-relative movement, mouse and pad camera, dodge with i-frames, light 3-hit combo and heavy attack, lock-on with camera pivot, forward-raycast interact, footsteps, one-shot vs locomotion animation handling (`Player.gd:110-414`).
- The death guard via `is_physics_processing()` prevents a double death (`Player.gd:419-421`).

**Fragile**
- **`stats.speed` is ignored.** Movement uses the `move_speed` export, so equipment `speed` modifiers and level scaling do nothing (`Player.gd:147-148` vs `Inventory.gd:87-88`) [read].
- **Knockback on the player is mostly lost.** `HurtboxComponent` adds to `velocity`, but `_move` overwrites `velocity.x/z` every frame while input is held (`HurtboxComponent.gd:38`; `Player.gd:147-148`) [read].
- **Lock-on can't be released with 2+ candidates**, the candidate list is never refreshed, and dying enemies stay in group `enemy` for 1.5 s, so corpses are lockable (`Player.gd:242-249`; `BaseEnemy.gd:233-241`) [read].
- **Starting items are hardcoded** (`Player.gd:70-78`).
- **Stats and inventory are shared sub-resources.** `stats` and `inventory` are embedded sub-resources in `Player.tscn:17-30` and are not `resource_local_to_scene`. **[unverified]** Every Player instance, and the Player after `change_scene`/`reload_current_scene`, probably receives the *same* `CharacterStats` and `Inventory` objects through Godot's resource cache. That would be the only reason level, XP and items survive the Level1→Level2 transition and a death with no save. → T1.
- `interact()` requires the collider itself to have `interact()`. `NPC._player_in_range` and the `InteractArea` signals are dead code (`NPC.gd:12,34-41`).

**Blocks scale**
- There's no spawn-point concept, so each area places its own Player instance and can only be entered at one position.
- There's no player-state handoff between scenes (see S1).

### 2.2 Combat (`scripts/combat/*`, combat parts of Player and BaseEnemy)

**Works**
- The component split is sound, and the collision layer/mask pairs are correct: player hitbox 8→4, enemy hitbox 16→1 (`Player.tscn:72-73`, `BaseEnemy.tscn:57-58`).
- Particles, impact SFX and hit-stop all function.

**Fragile**
- **The damage formula breaks progression.** `actual = max(0, amount - defense)` (`CharacterStats.gd:20`). Melee skeletons deal 8 and archer arrows deal 6. The player starts with defense 5 (3 and 1 damage per hit) and gets +1 per level (`CharacterStats.gd:46`). **The Elder's Shield (+4 def, `shield_wooden.tres:11`) takes defense to 9, so every enemy in both levels deals 0 damage** [read, arithmetic].
- **Hit-stop fires even when no damage is taken**: on i-frame dodges and on corpses. `HitboxComponent` triggers it on any hurtbox overlap, before the hurtbox checks `invincible` (`HitboxComponent.gd:28-31`; `HurtboxComponent.gd:19`) [read].
- **`died` re-emits on every hit at 0 HP** (`CharacterStats.gd:23-24`). Current listeners have guards, but any new listener (quest kill counters, achievements) will double-count [read].
- **Enemies are stun-locked by every hit, including hits during their attack** (`BaseEnemy.gd:212-217`), and have **no attack wind-up**: the hitbox goes live the instant ATTACK starts (`BaseEnemy.gd:160-164`) [read]. That's fine for one enemy type but gives no design space for ten.
- **Arrows pass through walls.** The Projectile root Area3D has no collision shape, and its hitbox only watches layer 1 areas, not bodies (`Projectile.tscn:13-27`; `Projectile.gd:18-23`) [read].
- **[unverified]** Re-activating the player hitbox for combo hit 2 while the target is still inside the sphere depends on whether the deferred `monitoring=false` → `true` toggle is seen by physics as an exit and re-enter. → T4.

**Blocks scale**
- Combat numbers are scattered through code and scenes instead of data: combo multipliers and knockback (`Player.gd:348-368`), hit-stop durations (`HitboxComponent.gd:31`), enemy damage in `.tscn` hitbox exports, and projectile damage fixed for every archer (`Projectile.tscn:24`).

### 2.3 Enemies (`scenes/enemies/*`)

**Works**
- The enum state machine is readable. Per-instance `stats.duplicate()` works (`BaseEnemy.gd:31`). The nav fallback to direct movement is sensible, animation hookup follows convention, and the archer's distance keeping works.

**Fragile**
- **The `_player` reference is cached once in `_ready`** (`BaseEnemy.gd:35`) and relies on the Player node coming *before* enemies in the tree, since the Player joins group `player` in its own `_ready` (`Player.gd:56`). All three worlds happen to order it that way. An enemy spawned later, or placed above the Player, never aggroes [read].
- **Detection ignores walls**: distance only, no line-of-sight check (`BaseEnemy.gd:73,80`).
- Tuning values are `const`, not `@export` (`BaseEnemy.gd:13-15`; `ArcherEnemy.gd:4-7`; `Projectile.gd:3-4`), so every variant needs a script.
- **[unverified]** Runtime `bake_navigation_mesh()` over CSG geometry (`Level1.gd:13`, `Level2.gd:6`) runs asynchronously. Whether it produces polygons from `CSGBox3D` children in 4.6, and how long enemies run straight at the player through walls before it finishes, needs checking. → T5.

**Blocks scale (10 types)**
- Each type currently needs its own `.tscn` *and* `.gd`, even for pure stat or model variants.
- There's no `EnemyDefinition` data resource, no enemy ID (quests can't say "kill 5 skeletons"), no wind-up or telegraph hooks, and no patrol routes.
- The `SkeletonModel` + animation-name convention is good and should be kept.

### 2.4 Stats (`scripts/stats/CharacterStats.gd`)

**Works**
- Simple and signal-driven. Chained level-ups are handled (`CharacterStats.gd:50-52`).

**Fragile**
- The damage formula and `died` re-emission are covered in §2.2.
- The level curve and per-level gains are hardcoded (`CharacterStats.gd:42-46`).
- There's no base-vs-modified split. Equipment mutates the base fields directly (`Inventory.gd:82-94`), which is why saves must store "final" stats and must *not* re-apply modifiers (`SaveManager.gd:124-125,142-143`). If an item's `stats_modifier` changes between save and load, unequipping subtracts the new value from a total built with the old one, and stats drift permanently [read].

**Blocks scale**
- With 40 items, stat drift and double-apply bugs become likely. A derived-stats model (base + sum of modifiers, recomputed) removes the whole class of bug.

### 2.5 Inventory & items (`scripts/inventory/*`, `data/items/*.tres`)

**Works**
- The `.tres` item format loads with no parser. Equip/unequip is symmetric. The UI is functional.

**Fragile**
- **Items are tracked by object identity, not by ID with a count.** `load()` returns the cached Resource, so two potions are the *same object*. `remove_item` works by coincidence, and two identical swords would both show `[EQ]` (`InventoryUI.gd:107-110`; `Inventory.gd:30`) [read].
- **There are no stacks.** Each potion uses one of 20 slots (`Inventory.gd:8`).
- **`add_item` returns `false` when full, and every caller ignores it.** The quest-reward shield is silently lost with a full bag (`Level1.gd:89-90`) [read].
- **Removing an equipped item leaves the equipment reference dangling** (`Inventory.gd:29-35`).
- `stats_modifier` keys aren't validated, so a typo like `"atack"` is silently ignored (`Inventory.gd:82-94`). `Item.use` only knows `"heal"` (`Item.gd:18`).
- **The save format depends on `id == filename`.** Items are loaded as `res://data/items/%s.tres` (`SaveManager.gd:186`), and nothing checks that the two match.

**Blocks scale (40 items)**
- The fixed type→slot mapping, identity bugs, lack of stacking and lack of an item registry or validation all need fixing first. The item icon field is unused.

### 2.6 Dialogue (`scripts/dialogue/DialogueRunner.gd`, `scenes/ui/DialogueUI.*`, `data/dialogues/*.json`)

**Works**
- Clean signal contract, typewriter effect with skip, choices, and a JSON format that's easy to author.

**Fragile**
- The entry node is always `"start"` (`DialogueRunner.gd:21`). A missing or typo'd `next_id` silently ends the conversation (`DialogueRunner.gd:70-73`).
- **The only action is `set_quest`**, which starts a quest (`DialogueRunner.gd:76-79`). Quest-state branching is done by swapping whole files through NPC exports (`NPC.gd:8-10,22-24`), and rewards are handled by a Level script listening to an NPC signal.
- **Choices are mouse-only.** Buttons are created without `grab_focus()` (`DialogueUI.gd:70-76`), so a gamepad user can't pick a choice. **[unverified]** whether `ui_accept` can reach an unfocused button. → T8.
- DialogueUI pauses the tree directly (`DialogueUI.gd:54`); see Pause/UI below.

**Blocks scale (20 quests)**
- Every quest-aware NPC needs extra exports or level code.
- The fix is **conditions** (branch on quest stage, flag or item) and **actions** (start/advance quest, report a talk objective, give item/XP, set flag) inside the dialogue JSON.

### 2.7 Quests (`autoloads/QuestManager.gd`, `data/quests/*.json`, `QuestLogUI`)

**Works**
- Linear stages with start/advance/complete signals, and live quest log updates.

**Fragile**
- **Unknown quest IDs silently succeed.** A missing file returns a stub with no stages (`QuestManager.gd:71-73`); `advance_quest` on it completes immediately (`QuestManager.gd:39-44`). A typo in dialogue JSON therefore "works" with no error.
- **Other code writes QuestManager's private data.** SaveManager reads and writes `_active_quests` / `_completed_quests` directly (`SaveManager.gd:107-111,171-182`), and QuestLogUI reads them (`QuestLogUI.gd:89-90,111,134-139`).
- **Loading emits no signals** (`SaveManager.gd:170-182`), so the HUD, quest log and level scripts don't learn the new state.
  - Concrete bug [read]: in Level1, advance to `defeat_monsters`, then Load Game from a save taken at `find_monsters`. `Level1._quest_advanced` stays `true` (`Level1.gd:7,35-36`), so the trigger never fires again and **the quest is stuck** until you die or reload the scene.
- **Kills made before the quest starts are counted but never checked.** Kill all 7 enemies first, then accept the quest: the counter already reached 7 before the quest existed, and nothing re-checks it, so **the quest can never complete** (`Level1.gd:28-31`) [read].
- The completed-quest list shows raw IDs, because data is dropped on completion (`QuestLogUI.gd:139-140`).
- `TOTAL_ENEMIES := 7` must be kept in sync with the scene by hand (`Level1.gd:4`).

**Blocks scale (20 quests)**
- Every quest needs bespoke level script, because objectives, rewards and gating all live in code (§3).
- There's no quest registry (for the log and validation), no progress counters, and no reward data.

### 2.8 Save (`autoloads/SaveManager.gd`)

**Works**
- Readable JSON; stats, inventory, equipment and quest round-trip; `save_exists`.

**Fragile**
- **The save doesn't record which scene it came from.** Death reload applies whatever save exists to the *current* scene (`GameManager.gd:72-81`), so saving in Level1 and dying in Level2 teleports you to Level1 coordinates inside Level2 [read].
- **No world state is saved.** Loading mid-level doesn't restore dead enemies, opened doors or level-script locals (see §2.7).
- **No version field**, so any schema change breaks old saves silently.
- The "final stats" design is covered in §2.4. Direct access to QuestManager's private state is covered in §2.7.
- **Scene transitions don't save** (C7). Progress across `change_scene` depends on T1.

**Blocks scale (5+ areas)**
- Needs: a save version, the current scene and spawn point, a per-area flag or kill registry keyed by stable persistent IDs, and explicit player-state handoff.

### 2.9 Audio (`autoloads/AudioManager.gd`)

**Works**
- Three buses, `play_music` / `stop_music` / `play_ui` / `play_sfx_at`, and all assets present in `assets/audio/`.

**Fragile**
- Buses are created at runtime only (`AudioManager.gd:26-31`). There's no `default_bus_layout.tres`, so there's no editor mixing and no persisted volume settings.
- **Music restarts from zero on every death reload**, because `play_music` always calls `play()` (`AudioManager.gd:40-41`).
- `play_sfx_at` parents players to `current_scene`, so sounds are cut on scene change. That's acceptable.

**Blocks scale**
- Minor. Per-area music is a `preload` in each level script (`Level1.gd:12`, `Level2.gd:5`, `TestWorld.gd:15`) and should be a level export.

### 2.10 Cross-cutting: GameManager, pause and modal UI, level composition

**Pause and modal conflicts**
- **Pausing is uncoordinated [read].** `QuestLogUI._input` opens on `open_quest_log` with no check for whether the game is already paused (`QuestLogUI.gd:49-55`), and `_close` sets `paused = false` (`QuestLogUI.gd:69-72`).
  - Open dialogue or the pause menu → press L twice → the tree unpauses while dialogue or the pause menu is still shown, and the player can walk around mid-dialogue.
  - The last commit (`1467dbf`) fixed the mirror case for Escape only.
- **[unverified]** Pressing L during the 3.2 s death wait may carry `paused = true` into the reloaded scene, because the timer in `GameManager.gd:69` defaults to `process_always`. → T9.

**GameManager and level composition**
- **Unused GameManager signals:** `game_over` is never emitted, and nothing listens to `scene_changed` (`GameManager.gd:3-4`).
- **Every level copies the full UI stack** (5 instances under a CanvasLayer) plus a Player and a nav bake call (`Level1.tscn:345-365`; `Level2.tscn:576-596`; `TestWorld.tscn:80-100`). Five areas means five copies to keep in sync.
- **TestWorld is stale:** it's not the main scene, and it has no nav region even though enemies use NavigationAgent3D.

---

## 3. Where adding content requires code changes instead of data

| To add… | You currently must edit code at… | Should be |
|---|---|---|
| A quest objective ("reach X", "kill N") | New level script logic, as in `Level1.gd:3-4,22-44` | `objective` entries in quest JSON, driven by generic `QuestTrigger` areas and enemy-kill reports |
| A quest reward | Level script plus an NPC signal (`Level1.gd:80-90`, `NPC.gd:25-27`); not saved, so it can be claimed again after reload [read] | `rewards: {xp, items}` in quest JSON, granted once on completion |
| Quest-aware NPC lines | NPC exports `completion_quest_id` / `completion_dialogue_id` (`NPC.gd:8-10`), limited to one boolean branch | Conditional branches inside dialogue JSON |
| Dialogue side effects beyond starting a quest | `DialogueRunner._show_node` (`DialogueRunner.gd:76-79`) | A generic `actions` array |
| A gated area exit | Level script with a hardcoded path and quest (`Level1.gd:46-52`) | A `SceneExit` node with exports `target_scene`, `spawn_id`, `requires_quest` / `requires_flag` |
| Area music | `preload` in the level `_ready` (`Level1.gd:12`, `Level2.gd:5`) | `@export var music: AudioStream` on a shared level root script |
| An area | A new level `.gd` (music, nav bake, triggers) plus copying the UI stack and Player | A level template: `LevelRoot` script, one `UIRoot.tscn` instance, `SpawnPoint` nodes |
| An enemy stat variant | A new `.tscn`, because damage lives on the hitbox node (`BaseEnemy.tscn:61`) and timings are `const` (`BaseEnemy.gd:13-15`) | `EnemyDefinition.tres` (stats, damage, timings, XP, ID, model) assigned to a shared behavior scene |
| Ranged-enemy damage or speed variants | `Projectile.tscn:24` and `Projectile.gd:3-4` are shared by all archers | Passed from `EnemyDefinition` at spawn |
| Starting items | `Player.gd:70-78` | `@export var starting_items: Array[Item]` or a `data/player/start.tres` |
| An item with a new effect (e.g. +max_hp potion, buff) | `Item.use` (`Item.gd:15-20`) | A small effect vocabulary in `stats_modifier` / `use_effects`, validated at load |
| An item in helmet or boots | `Inventory._slot_for_type` (`Inventory.gd:73-79`) | `@export var equip_slot` on Item |
| Level-up curve changes | `CharacterStats.level_up` (`CharacterStats.gd:42-46`) | A `progression.tres` resource |
| A new saved stat or field | `SaveManager.gd:75-84,129-136` (manual field lists) | Derive from `@export` properties, or own serializers per system (`get_state` / `set_state`) |
| Quest-complete banner text | Fixed "Quest Complete!" (`HUD.tscn:67`); doesn't show the quest title | Read from quest data |

---

## 4. Proposed CLAUDE.md split

CLAUDE.md is 333 lines, and about 45% (lines 239–326) is Blender/asset workflow that's irrelevant to most GDScript tasks. Some of it also contradicts the style rules (C13–C15). The proposal is a **core file of about 90 lines, always loaded**, plus **on-demand skills** under `.claude/skills/`. The existing `blender-animation` skill and `blender-animator` agent already follow this pattern.

### 4a. Core `CLAUDE.md` (always loaded)

1. **Project in one paragraph.** PS2-era target, one reconciled art sentence (resolves R5, C13).
2. **Hard rules.** Godot 4.6, GDScript only, Compatibility renderer, snake/Pascal naming, `class_name` caveat, autoload allowlist, signals over references, write `.tscn` directly, ask before committing.
3. **Repo map.** The *actual* tree, corrected for C2 and C3, with one line per system naming the owning file.
4. **Public contracts.** The signal and method list per system, generated from code and kept accurate. This is what "preserve signals and public methods" refers to.
5. **Data-driven content rules.** "Adding content = adding files in `data/`; if you need code, stop and say why." Links to the `content-authoring` skill.
6. **Testing.** How to run the headless suite (§6). Every behavior change adds or updates a test.
7. **Git rules** (current lines 227–237, condensed).
8. **Asset guardrail (must stay in core):** "Never call any `mcp__blender__generate_*` tool without stating the cost and getting explicit confirmation; $5/session cap; see the `asset-pipeline` skill." This stays in core because a skill that hasn't loaded can't enforce anything. Also make these tools `ask` in `.claude/settings.json` permissions, so the harness enforces the rule and not just the prompt.
9. **Skill index.** One line per skill saying when to load it.

### 4b. Skills (on demand)

| Skill | Contents (source lines in current CLAUDE.md) | Trigger |
|---|---|---|
| `godot-scene-authoring` | `.tscn` rules (216–226), no `#` comments in `.tscn`, UID hygiene (use the real `.uid`; never invent UIDs; path case must match), node naming, `process_mode=3` for pause UIs, collision layer table | Creating or editing any `.tscn` |
| `asset-pipeline` | Rodin/fal.ai workflow, patched-addon notes, Sketchfab, spend-tracking procedure, post-generation cleanup (239–310) | Generating, sourcing or cleaning up a mesh |
| `blender-godot-import` | Facing and grounding transforms, axis conversion, Blender 5.x Action API, GLB export flags, joint warnings, bmesh and undo gotchas (311–326, 159–160) | Importing or exporting a GLB, or wiring a model into a scene |
| `blender-animation` *(exists)* | Keep. Align the required animation list with the enemy/player sets and fix the frontmatter `name: animate` vs directory `blender-animation` mismatch | Animating |
| `content-authoring` *(new, after plan step 7)* | JSON/`.tres` schemas for items, quests (objectives, rewards), dialogue (conditions, actions), `EnemyDefinition`, level template; worked examples (179–214 moves here) | Adding a quest, item, enemy, NPC or area |
| `visual-style` | Poly budget, materials, lighting, UI look (21–31), reconciled with what actually ships | Art or UI styling decisions |

Also: the project memory (`MEMORY.md`) duplicates a lot of status and gotchas. After the split, keep status in memory and move durable rules into the skills, so there's one source of truth.

---

## 5. Ranked plan

Each step is sized as **one spec'd change = one atomic commit**, with the `.tscn` committed together with its `.gd`. "Keep" means existing signal names and public methods stay unchanged; any deliberate API change is flagged **API**, with the reason.

### Phase A — Safety net (no gameplay change)

**A1. Headless test harness.**
- *Files:* `tests/TestRunner.tscn`, `tests/test_runner.gd`, `tests/unit/test_*.gd`.
- *Spec:* A scene-based runner (so autoloads load normally). It discovers `test_*` methods, supports `await` for frame stepping, prints `PASS`/`FAIL`, and calls `get_tree().quit(failures)`. Run with:
  `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/TestRunner.tscn`
  No plugin, so it keeps README's "no dependencies".
- *Accept:* Exit code 0 on an empty suite, 1 on a deliberate failing test.

**A2. Characterization tests for today's behavior.** Write T1–T9 (§6) as-is, marking known-bad behaviors as `expected_fail` so later steps flip them green.

**A3. Scene-reference hygiene.**
- Replace the 9 fake script UIDs with the real `.uid` values (§1c).
- Fix `Player.tscn:3` to `Player.gd`.
- Drop invented scene UIDs, or regenerate them by opening in the editor.
- *Accept:* T2 prints zero "invalid UID" warnings; T3 passes on Linux.

**A4. Input conflict.** Remove E from `interact`, keeping F / pad Y. Update README and INPUT_SETUP. *Accept:* No physical key is bound to two gameplay actions (a test iterates `InputMap`).

**A5. Docs truth pass + CLAUDE.md split (§4).** Fix R1–R8 and C1–C19 in the docs. This is docs-only.

### Phase B — Vertical slice: Level1 "Eastern Road" × Skeleton (melee) × "Clear the Eastern Road"

Goal: the slice's quest, enemy and area are 100% data-driven, and save/load, death and transition behave explicitly and are covered by tests.

**B1. QuestManager public state API.**
- Add `get_active_quest_ids()`, `get_completed_quest_ids()`, `get_quest_data(id)`, `get_state() -> Dictionary`, `set_state(d)`.
- `set_state` emits a new `quests_reloaded` signal.
- Migrate SaveManager and QuestLogUI off the private fields.
- *Keep:* all existing methods and signals.
- *Accept:* `grep '_active_quests\|_completed_quests'` finds no hits outside QuestManager; save round-trip test is green.

**B2. Objective-driven quests.**
- *Schema:* each stage gets `"objective": {"type": "reach"|"kill"|"talk"|"collect", "target": "<id>", "count": N}`. Keep `completion_condition` readable as a legacy alias.
- Add `QuestManager.report(event_type: StringName, target_id: String, amount := 1)`, which advances any active stage whose objective matches.
- Add signal `quest_progress(quest_id, stage_id, current, required)`.
- Progress counters live in quest state and are saved.
- *API:* `_load_quest_data` for a missing file now `push_error`s and `start_quest` refuses. The silent stub hides typos, which matters at 20 quests.
- *Why `report()` on QuestManager rather than a new EventBus autoload:* CLAUDE.md limits autoloads, and quests are the only consumer today.
- *Accept:* Unit tests for each objective type; a missing quest ID produces an error.

**B3. Generic triggers + kill reporting.**
- New `scenes/world/QuestTrigger.tscn/.gd` (Area3D, `@export var area_id`) that calls `report("reach", area_id)` on player entry.
- `BaseEnemy` gets `@export var enemy_id: String`. `die()` calls `QuestManager.report("kill", enemy_id)`.
- Rewrite `clear_eastern_road.json` with objectives: reach `eastern_road`, kill `skeleton_melee` ×5, **talk** `village_elder`.
- Delete the kill counter and advance-area code from `Level1.gd`.
- *Note:* the quest now counts only the 5 melee skeletons; the 2 archers become optional. Say so explicitly, or use kill target `tag:eastern_road` if the designer wants all 7 counted.
- *Accept:* The "kill before accepting" and "load older save" bugs (§2.7) have passing regression tests.

**B4. Quest rewards in data.**
- Add `"rewards": {"xp": 50, "items": ["shield_wooden"]}`, granted once by QuestManager on `complete_quest`. This needs a new `GameManager.give_player_item(id) -> bool`; if it returns false (bag full), push a warning and queue the item.
- Remove `Level1._on_elder_reward`.
- *API:* `NPC.quest_reward_given` is deprecated but kept (emitted, no listeners) until B5 lands, then removed. Rewards tied to an NPC instance can't be saved, which is what enables the dupe.
- *Accept:* Reload after completion doesn't grant a second shield.

**B5. Dialogue conditions and actions.**
- Nodes may have `"branches": [{"if": {"quest_stage": ["clear_eastern_road", "talk_elder"]}, "goto": "thanks"}, …]`, evaluated in order, falling through to the node itself.
- Nodes may have `"actions": [{"start_quest": id}, {"report": ["talk", "village_elder"]}, {"set_flag": name}]`.
- `set_quest` stays as an alias for `start_quest`.
- Merge `village_elder_complete.json` into `village_elder.json`. The NPC completion exports become optional (keep them for back-compat).
- *Keep:* `start`, `advance`, `dialogue_started`, `line_ready`, `dialogue_ended`.
- *Accept:* Dialogue tests cover each branch; the elder's full flow works from one file.

**B6. Combat math fix.**
- Change `take_damage` to `actual = max(1, amount - defense)` (the minimal change), or `max(1, round(amount * 100.0 / (100 + defense * 10)))` (scales better; the designer picks).
- Emit `died` only on the transition to 0 HP.
- *API:* signature unchanged; behavior changes are deliberate and argued in §2.2.
- *Accept:* With the shield, enemies deal ≥ 1 damage; `died` fires once per death.

**B7. `EnemyDefinition` resource for the slice enemy.**
- New `scripts/enemies/EnemyDefinition.gd` (Resource) with fields: `id`, `display_name`, `stats: CharacterStats`, `melee_damage` (or derive from `stats.attack`), `attack_windup`, `attack_active_time`, `attack_cooldown`, `stagger_duration`, `detection_range`, `attack_range`, `xp_reward`.
- New `data/enemies/skeleton_melee.tres`.
- BaseEnemy gets `@export var definition: EnemyDefinition`. When it's set, it overrides the current exports and constants. Add a wind-up phase before `_hitbox.activate()`.
- Also fix the `_player` lookup (`get_first_node_in_group` at acquisition time, not only in `_ready`), `remove_from_group("enemy")` plus disabling the hurtbox on death, and ignoring hits on DEAD.
- *Accept:* Level1 skeletons use the `.tres`; tuning happens without script edits.

**B8. Hit-stop only on real damage.** Move `trigger_hit_stop` from `HitboxComponent._on_area_entered` into `HurtboxComponent` after the invincible and dead checks. *Keep:* `hit` signal. *Accept:* An i-frame dodge through an attack doesn't freeze time.

**B9. Modal and pause coordination.**
- Add `GameManager.push_modal(owner)` / `pop_modal(owner)`. `paused` is true while the stack is non-empty, and mouse mode follows it.
- Each UI refuses to open if another modal is on top, unless it's the pause menu over nothing.
- Migrate DialogueUI, InventoryUI, QuestLogUI and PauseMenu.
- *Accept:* The "L twice during dialogue" regression test passes, and T9 passes.

**B10. Explicit player-state handoff + save v2.**
- Move stat and inventory serialization behind `CharacterStats.to_dict()/from_dict()` and `Inventory.to_dict()/from_dict()`.
- Save schema: `{"version": 2, "scene": path, "spawn_id": id, "player": …, "quests": QuestManager.get_state(), "flags": {…}, "killed": [persistent_ids]}`. Include v1 migration.
- `GameManager.change_scene(path, spawn_id := "")` snapshots player state, changes scene, and restores it. Death reload uses the save's `scene`.
- Player duplicates `stats` and `inventory` in `_ready`, so state no longer relies on the resource cache (T1 then asserts the new, intended behavior).
- *API:* `change_scene` gains an optional parameter (additive).
- Stats become base + derived: equipment modifiers are recomputed after load, not baked in. That removes the "final stats" drift (§2.4).
- *Accept:* Save in Level1, die in Level2 → you respawn in Level1 at the saved position. Level1→Level2 keeps level and items with the resource cache cleared.

**B11. Level template.**
- New `scenes/world/LevelRoot.gd` with exports `music`, `bake_nav_on_ready`, and the default spawn.
- New `scenes/ui/UIRoot.tscn` bundling the five UI scenes.
- New `SpawnPoint.tscn` and `SceneExit.tscn` (exports `target_scene`, `spawn_id`, `requires_quest`, `sealed_message`).
- Convert Level1 to use them. `Level1.gd` should shrink to zero or near-zero lines.
- *Accept:* Level1's script has no quest IDs, paths or counts. **This completes the vertical slice.**

### Phase C — Scale out, in priority order

1. **Inventory v2.** `ItemStack {item, count}` and `Item.max_stack`; `@export var equip_slot` on Item; ID-based equipment. *API:* `Inventory.items` becomes a read-only computed `Array[Item]`, kept for UI and save back-compat, with a new `stacks` field alongside. `add_item(item, count := 1)` is additive. Also add an item validation test (`id == filename`, known modifier keys, valid slot).
2. **Player uses `stats.speed`**, and knockback is applied as a decaying impulse rather than overwritten.
3. **Lock-on:** tap cycles, hold (or cycling past the last target) releases; refresh the candidate list on each cycle.
4. **Projectile wall collision** (body mask on the root, damage and speed passed from `EnemyDefinition`).
5. **Archer → `EnemyDefinition`** (second enemy type through the new pipeline); remove the unused melee hitbox dependency by making `$HitboxComponent` optional in BaseEnemy.
6. **Level2 → LevelRoot**, spawn from Level1's exit, and add a crypt save point.
7. **`content-authoring` skill**, written from the now-stable schemas (§4b).
8. **Controller UI focus** (dialogue choices, inventory, quest log) plus input-hint text from InputMap (T8).
9. **Audio:** `default_bus_layout.tres`, don't restart music when the same stream is already playing, and a volume setting in the pause menu.
10. **Enemy behaviors 3–10:** a small behavior-component set (melee, ranged, charger, caster, patrol path), so most new types are just a `.tres` plus a model.

---

## 6. Proposed headless tests (for [unverified] items)

All run via `tests/TestRunner.tscn` (A1) unless noted.

| ID | Question | Test sketch |
|---|---|---|
| T1 | Do Player `stats` / `inventory` survive `change_scene` / `reload_current_scene` as the same object? | Instantiate `Player.tscn` twice → assert `a.stats == b.stats`. Then keep `a` alive, drop all PackedScene references, `load()` Player.tscn again with `CACHE_MODE_REUSE`, instantiate → compare `get_instance_id()`. Also: `change_scene_to_file(Level2)` from Level1 with `stats.level = 5`, await 2 frames, assert level. |
| T2 | Do fake UIDs cause fallback warnings or load failures? | Shell: `Godot --headless --path . --quit 2>&1 \| grep -i "uid"` and, in-runner, `ResourceLoader.load()` every `.tscn`, asserting non-null. |
| T3 | Does `player.gd` (wrong case) break on a case-sensitive filesystem? | Run the suite in a Linux container (`barichello/godot-ci:4.6` or equivalent) against the repo. |
| T4 | Does combo hit 2 register on a target still inside the hitbox? | Player + a static dummy hurtbox inside the sphere; `_attack_light()`, step physics until `_attack_timer <= 0`, `_attack_light()` again, step → count `health_changed` emissions == 2. |
| T5 | Does runtime nav bake over CSG produce a mesh, and how fast? | Load Level1, await `NavigationRegion3D.bake_finished` (timeout 5 s), assert `navigation_mesh.get_polygon_count() > 0`, log elapsed frames. |
| T6 | Does the death → reload → `load_game` sequence apply to the new Player after exactly 2 frames? | Save at a known position, call `GameManager.on_player_died()` with the timer shortened (inject a duration), assert the new player's position and full HP. |
| T7 | Save round-trip fidelity | Equip sword → save → change `sword_iron.stats_modifier` in memory → load → unequip → assert attack equals base (expected FAIL today, passes after B10). |
| T8 | Can the gamepad pick dialogue choices? | Start `village_elder`, finish typing, `Input.parse_input_event` a `ui_accept` / `ui_down` → assert `DialogueRunner` advanced to `quest_offer`. |
| T9 | Is the tree left paused after pressing L during the death wait? | Trigger player death, toggle the quest log open, wait for reload → assert `get_tree().paused == false`. |

Regression tests for **[read]** bugs (a failing test first, then the fix): shield → 0 damage (B6); `died` re-emission (B6); kill-before-accept (B3); stale `_quest_advanced` after load (B3); quest log unpausing dialogue (B9); reward dupe on reload (B4); speed modifier ignored (C2); arrows through walls (C4).
