# Design Bible (v0, 2026-09-29)

How the game should **play**. The art bible (`docs/art-bible.md`) governs how it looks, and the world bible (`docs/world/`) governs what it's about. This file governs camera, combat, encounters, levels, RPG systems and feedback, as **targets with numbers** wherever a playtest or a script can measure them.

**How to use it**
- Every measurable target has an ID in **Targets** (§9). Playtest reports, the playtest critic and fix PRs cite those IDs ("fixes `cam_melee_occlusion`: 0.62 → 0.18").
- "Current" is the game as measured on 2026-10-01 (Godot 4.7.2, `main` at `523cf6b`), by the replay scenarios in `tests/scenarios/` where a target has one.
- **Status:** a target is *proposed* until the user confirms it, then *settled*. Changing a settled target is the user's call; record the decision in `docs/decisions.md`.
- Fix things against this file, not ad hoc. The backlog in `docs/decisions.md` maps to IDs here.

---

## 1. Direction (decided with the user, 2026-09-29)

- **Genre:** an open-world RPG in the Elder Scrolls, Fallout (gameplay, not setting) and Witcher tradition. Exploration, quests with choices, character growth, and a world that rewards looking.
- **Look:** unchanged. Stylized low-poly with PS1/PS2-era proportions and readability (art bible).
- **Combat:** Witcher-style third-person action: lock-on, dodge/roll, light and heavy attacks, readable enemy tells, with RPG stats underneath. **No stamina bar yet.** Stamina is the planned post-slice upgrade (world bible → magic), as it is in Skyrim.
- **Structure:** **hub and spokes now, built to open up later.** Oskett is the hub. The Eastern Road, the barrows and the Hollow Choir are spokes. Outdoor spokes are designed as open spaces, with sightlines and landmarks, not corridors.
- **Difficulty:** **approachable** in the first area. Enemy stats come from **level bands**, so scaling works from day one even while it's untuned (§6).

**Pillars.** When a choice is unclear, these win, in this order:
1. **Readable, fair combat.** You can always see what's about to hit you and why you took damage.
2. **The world rewards looking.** Every detour pays something: loot, lore, a view, a shortcut, a fight worth having.
3. **A soldier's-eye scale.** The spaces, people and problems are grounded and worn (world bible → tone). Nothing is grand for its own sake.
4. **Choices leave marks.** Quests have more than one resolution, and the world remembers kills, doors and deals (the save's world state).

---

## 2. Camera and controls

The third-person camera behind the player is the lens for everything else. Most of the first playtest's worst findings were camera findings.

- **Modes, not one camera (settled):** the rig supports swappable modes: third-person over-the-shoulder now, first person later, as in Skyrim or Fallout 4. Aiming, lock-on and interaction use the **camera's** forward ray, never the character's facing, so they work in either mode.
  - First person is post-slice. It needs a first-person viewmodel (arms and weapon), and assets that hold up much closer than the 256 px texture budget assumes.
- **Framing (settled; over the shoulder, variant A, decided by the user 2026-10-01):** the lens sits about 1.55 m above the floor, about 0.7 m right of the player and 1.6 m behind (2.2 m when locked on, to fit both), with a 65° FOV, looking forward past his right shoulder; he sits in the left third of the frame. Looking up and down turns the **look**; the lens stays near shoulder height, within about 0.35 m of rest. Close in (a short arm) the shoulder offset tucks in, and the look turns only as far as it must to keep his head and torso in frame. **Current:** as above (`scenes/player/CameraRig.gd`, `framing = A_MEDIUM`; the earlier framing and variants B and C stay selectable by that export for comparison in play).
  - An over-the-shoulder offset is what stops the player model hiding the enemy at melee range (`cam_melee_occlusion`).
- **Collision:** the spring arm uses a sphere probe with a margin, not a ray, and eases in and out.
  - The player must stay fully in frame (`cam_player_in_frame`), and wall must never fill the frame (`cam_wall_fill`).
  - When the arm is squeezed shorter than 80% of its length, the camera may rise, but not clip into the player.
  - **Current:** a 0.3 m sphere probe. A probe that starts touching a wall doesn't move, and each move stops 5 cm short of its hit (fixed 2026-10-01: a touching start passed through walls).
- **Lock-on (Witcher model):**
  - A reticle on the target, always visible while locked.
  - Only living enemies in line of sight are candidates.
  - Cycling picks the next-nearest to screen centre.
  - The camera keeps both the player and the target in frame (`cam_lock_both_in_frame`).
  - When the target dies, the lock moves at once to the nearest living enemy in range and in sight, or releases (user, 2026-10-01).
  - Lock releases when the target stays hidden behind world geometry for more than about 1 s (user, 2026-10-01; a moment behind a pillar keeps it), or beyond 1.5× range.
  - **Current:** all of the above, with a Signal Red ring reticle on the target (`scenes/ui/LockOnReticle.tscn`, in the HUD); camera input is disabled while locked.
- **Respawn and loads** restore the saved view heading, so the same input moves the same way (fixed in #6).
- **Bindings:** one action per key. **Current:** E is `camera_right` and F is the only interact key (user, 2026-10-02; pinned by `test_input_bindings.gd`). Gameplay actions are polled in the physics step, so automated input can frame-time them.

---

## 3. Combat feel

**Player moveset: keep the shape, add commitment and sync.**
- **Movement:** 5 m/s, stops in about 0.1 s. Keep it.
- **Dodge (settled):**
  - Keep 4.2 m over 0.5 s.
  - I-frames cover the first 0.30 s, not the whole roll, so late dodges are punished a little (Witcher).
  - A 0.15 s recovery before the next dodge or attack. **Current:** i-frames for the whole 0.5 s, no recovery.
- **Attacks commit (settled):**
  - Movement is locked for the swing, with a short forward lunge (0.3–0.5 m) toward a locked target.
  - A dodge can cancel an attack only after its active frames.
  - **Current:** you can move freely while swinging, and there's no lunge.
- **Hitboxes sync to the animation:** a swing's hitbox opens within ±2 physics frames of the clip's contact frame (`atk_hitbox_sync`). **Current:** it opens on the press frame, regardless of the clip.
- **The light combo reads as three distinct hits:**
  - `Sword_Regular_A`, `B` and `C`, one per hit (already in the backlog);
  - roughly 0.35–0.45 s per hit;
  - a 0.6 s window to chain.
- **The heavy attack has a visible windup** of 0.5–0.7 s before contact, and always staggers.

**Feedback on every hit:**
- **Keep:** hit-stop (60 ms light, 120 ms heavy), the particle burst and the impact SFX.
- **Add:**
  - a **hit flash** on the target, 0.08–0.12 s;
  - a **health bar** on the locked or recently damaged enemy;
  - a **player flinch** when hit, 0.2 s, at most one per second, so you can't be stun-locked.
- **Hit-stop and hit effects never fire on a dodged (i-framed) hit.** **Current:** they do.

**Enemy tells and fairness (pillar 1):**
- **Melee tell:** at least 0.5 s of readable windup before an attack becomes active (`enemy_melee_telegraph`). The pose must be visible from the gameplay camera. **Current:** 0.6 s (`Sword_Attack` with a short hold on the raised blade).
- **Archers show the draw:** at least 0.8 s (`enemy_ranged_telegraph`) with the bow up. Arrows collide with walls, and archers only shoot with line of sight. **Current:** 0.9 s draw (`Spell_Simple_Enter` stand-in until the UAL2 bow clips); arrows stop at walls; archers shoot only with sight.
- **Detection needs line of sight** within a 120° view cone at the detection range, plus a 4 m hearing radius. **Current:** met; hearing also needs a clear line. An enemy that loses sight searches the last-seen spot for 3.5 s, then returns to its post.
- **Attack tokens:** at most **2 melee attackers** engage the player at once, while others circle at 3–5 m. At most **1 archer** fires in any 2 s window (`enemy_attackers_max`). **Current:** met, except that tokenless levies hold 3–5 m off facing the player instead of circling (no strafe clip yet).
- **Staggers:**
  - Light hits stagger on the third combo hit, or when accumulated poise breaks (about 25 damage within 2 s).
  - Heavies always stagger.
  - Stagger cancels the enemy's attack **and** starts its cooldown.
  - **Current:** every overlap staggers; stagger skips the cooldown, so an enemy can attack straight after.

---

## 4. Encounters and pacing

- **The first standard 1-on-1 costs a reasonable player 10–15% HP** (`enc_first_fight_hp_cost`), measured by the scripted "sensible player" scenario (§10). This is the approachable target.
- **Time to kill** at equal level: see `ttk_*` in §9. Front-file takes 3–4 light hits (about 2.5–3.5 s of combat); Back-file takes 2–3; a levy kills the player in 10–14 hits.
- **Group sizes:**
  - In the first area, a fight has **3 or fewer** enemies (`enc_group_max_first_area`).
  - Introduce the Back-file **alone** before mixing it with the Front-file.
  - An encounter never pulls enemies from another room: detection needs line of sight (§3).
- **Rhythm on a spoke:**
  - 20–60 s of walking or exploring between fights (`enc_spacing_s`).
  - After a fight, a payoff within sight: loot, a view, a lore object, a shortcut.
  - A rest point (a Hessane ward-stone) at least once per spoke, never more than 3 fights apart.
- **Retreat is always possible.** Enemies leash at about 1.5× detection range; keep that.

---

## 5. World and level design

Units are metres; the player is 1.8 m tall.

**Interiors (crypts, barrow halls, longhouses):**
- **Ceilings everywhere indoors** (`lvl_interior_ceiling`). Heights:
  - corridors 3.5–4.5 m;
  - halls 5–8 m;
  - a 2.5 m ceiling only in crawl-tight flavour spots, never in combat.

  **Current:** no ceilings anywhere; the flat grey background fills about 40% of every frame.
- **Clearances:**
  - combat corridors at least 3 m wide (`lvl_corridor_width_min`), which the camera needs;
  - doorways 2.2–3 m;
  - rooms holding 2 or more attackers at least 8 × 8 m.
- **Visual rhythm:**
  - no bare wall run longer than 8 m without a break: a niche, pillar, prop, light or opening (`lvl_bare_wall_run_max`);
  - 1–3 dressing props per 10 m² of floor in lived-in or tomb spaces (`lvl_dressing_density`).
- **Props never snag the critical path:** it keeps at least 1.0 m of clear navmesh width (`lvl_path_clearance_min`), and small clutter has rounded or no collision. **Current:** every Level 1 segment passes at 3.0 m; the old crate snag was off-path player movement.

**Outdoors (the road, terraces, the village):**
- **Terraces are the verticality** (world bible → geography): at least one elevation change of 1 m or more per 20 m of path on a spoke (`lvl_verticality`). Steps, ramps, drops and barrow mounds all count. **Current:** every floor in both levels is at y = 0, apart from one 0.5 m platform in Level 2.
- **Depth:** fog and drizzle for depth. Mid-grey distance, never a flat background colour.
- **Discovery cadence:** something worth stopping for every 30–45 s of walking (`lvl_poi_interval_s`), which is about 150–225 m at 5 m/s. That's the Skyrim cadence, scaled down.

**Guidance, for both:**
- **Landmarks:** every area has a landmark visible from its entrance (`lvl_landmark_visible`), such as a banner pole, a lit doorway, a ward-stone, a broken tower or a barrow door. From the hub, every spoke's entrance is marked.
- **The critical path reads by light and landmark**, not by a compass. A compass and objective marker may come later as optional UI.
- **The exit or next goal** is visible or signposted within 10 s of entering a space.

**Lighting and readability** (these follow the art bible's rules; the numbers are gameplay targets):
- **Interior paths:** a visible light source every 8–12 m (`lvl_light_spacing`).
- **Floor:** walkable floor is never near-black. Its luminance stays at 0.05 or more from the gameplay camera (`lvl_floor_luminance_min`), measured the way the player's back was.
- **Characters:** player and enemies stand out from their background with a luminance contrast ratio of at least 1.3 (`read_char_contrast_min`). Earlier measurements: the levy at 1.57; the player's back at 0.02 before the fill light.

---

## 6. RPG systems

- **Levelling:** keep the curve (XP to next level ×1.5, and +10 HP, +2 attack, +1 defense per level). In the slice, about 130 XP reaches level 2 (current). Target: one level per spoke in the early game.
- **Level bands:**
  - Each area has a level band, and enemies spawn at the player's level clamped to it.
  - Enemy stats are defined as `base × (1 + 0.12 × (level − 1))`, so scaling exists from day one, untuned.
  - The first area's band is 1–3.
- **Damage (settled):** damage = `max(1, round(damage × 100 / (100 + 10 × defense)))`, a ratio, not a subtraction.
  - Today's `damage − defense` lets armour zero out damage completely: the Elder's Shield makes the player immune to both levy variants. That kills tension and makes scaling brittle.
- **Gear:** equipping must be visible and matter. **Current:** the starting Iron Sword isn't auto-equipped, so most players fight at base attack.
- **Quests** follow the world bible's text limits (2 sentences per dialogue node; objectives in 12 words or fewer).
  - Main quests have **at least two resolutions**, with at least one non-combat option where the fiction allows (Fallout).
  - Quest state and world flags persist in the save.
- **The hub (Oskett):**
  - at least one quest giver, one trader (post-slice), one rest or save point, and one lore object per 20 m of village;
  - NPCs are characters, never placeholder capsules;
  - interaction has an on-screen prompt.

---

## 7. UI and feedback

- **Required:**
  - the lock-on reticle;
  - the enemy health bar (locked or recently damaged);
  - an interact prompt;
  - the current objective, one line of 12 words or fewer, on quest change and on demand;
  - damage feedback on the player (the existing HP flash, plus the flinch).
- **Chunky bordered panels and a limited palette,** as today (art bible). No damage numbers.
- **Post-slice:** a compass with quest markers (optional, toggleable), and stamina once it exists.

---

## 8. Performance and stability

- **60 fps** on the development Mac in the Compatibility renderer (`perf_fps_min`) at the gameplay camera in any area.
- **Navmeshes are baked at edit time,** not at runtime. **Current:** met (`scripts/tools/bake_navmeshes.gd`; CI fails a stale bake).
- **No errors, and no new warnings, in a normal playthrough.** **Current:** 23 known warnings in `ci/warnings-baseline.txt` (13 invalid hand-written UIDs, 10 GDScript warnings); CI fails any new one.

---

## 9. Targets

| ID | Target | How measured | Current (2026-10-01) |
|---|---|---|---|
| `cam_melee_occlusion` | ≤ 0.25 | locked on, target within 3 m: fraction of the target's screen box covered by the player (replay: mean over those frames) | 0.01–0.11 (was 0.60–0.87, trial B1) |
| `cam_player_in_frame` | 1.0 | fraction of sampled frames with the player's head and torso fully in frame | 1.0 in every scenario (was 0.58 in `camera_stress`) |
| `cam_wall_fill` | ≤ 0.6 | the largest fraction of the frame covered by one wall surface, counting only wall between the camera and the player or beside him (no deeper along the view than his axis), so a wall he deliberately faces close up doesn't count (user, 2026-10-01) | 0.00–0.47 (was 0.01–0.57) |
| `cam_lock_both_in_frame` | ≥ 0.95 | while locked, fraction of frames with both player and target in frame | 1.0 (was 0.36–1.0) |
| `atk_hitbox_sync` | ±2 frames | hitbox open frame vs the clip's contact frame | hitbox opens on the press |
| `enemy_melee_telegraph` | ≥ 0.5 s | windup from the tell's start to the hitbox opening | 0.6 s |
| `enemy_ranged_telegraph` | ≥ 0.8 s | draw start to release | 0.9 s |
| `enemy_attackers_max` | 2 melee, 1 archer per 2 s | simultaneous attackers in the scripted group fight | 2 melee, 1 archer per 2 s |
| `ttk_player_frontfile` | 3–4 light hits | hits to kill at equal level | 4 |
| `ttk_player_backfile` | 2–3 light hits | same | 3 |
| `ttk_levy_player` | 10–14 hits | levy hits to kill the player, equal level, starting gear equipped | 12 (9 damage per hit) |
| `enc_first_fight_hp_cost` | 10–15% | HP lost in the scripted sensible-player 1-on-1 | 0% for the scripted perfect dodger (the skilled ceiling); no "reasonable player" scenario yet |
| `enc_group_max_first_area` | ≤ 3 | enemies engaged in any one fight, first area | 3 |
| `enc_spacing_s` | 20–60 s | walking time between fights on a spoke | about 5–10 s |
| `lvl_interior_ceiling` | present | every interior space has a ceiling | none |
| `lvl_corridor_width_min` | ≥ 3 m | narrowest combat corridor | 4 m |
| `lvl_bare_wall_run_max` | ≤ 8 m | longest unbroken wall run | 16 m |
| `lvl_dressing_density` | 1–3 per 10 m² | props per floor area, lived-in or tomb spaces | 1.05–1.18 (Level 1, KayKit dressing) |
| `lvl_path_clearance_min` | ≥ 1.0 m | narrowest navmesh width on the critical path | 3.0 m (Level 1); 1.5 m (Level 2 vault → corridor C) |
| `lvl_verticality` | ≥ 1 per 20 m | elevation changes of 1 m or more per 20 m of spoke path | 0 |
| `lvl_poi_interval_s` | 30–45 s | walking time between points of interest outdoors | not applicable (no outdoor space yet) |
| `lvl_landmark_visible` | yes | a landmark visible from each area's entrance | no |
| `lvl_light_spacing` | 8–12 m | distance between visible light sources along interior paths | largest gap 11 m (13 torches); some 5–6 m, accepted as denser (2026-09-30) |
| `lvl_floor_luminance_min` | ≥ 0.05 | walkable floor luminance from the gameplay camera | not measured |
| `read_char_contrast_min` | ≥ 1.3 | character vs background luminance contrast | levy 1.57; player fixed by the fill light |
| `perf_fps_min` | ≥ 60 | fps at the gameplay camera, any area | not measured |

---

## 10. How it gets checked

- **Scripted scenarios** (`docs/playtests/brief-*.md`) replay fixed inputs and measure targets. Each target that is "not measured" needs a scenario or a probe before it can be settled.
- **The in-game event log** (planned, playtest skill) records attacks, hits, damage, dodges, stagger and deaths, each with its physics frame. It's how the combat targets get measured through the MCP, which can't pause mid-sequence.
- **Exploratory playtests** judge what numbers can't: flow, readability, "does this feel like a place".
- **The playtest critic** (planned) is a fresh-context agent with this file as its rubric: pass, revise or escalate, as with the asset judge. Feel and taste always escalate to the user.

---

## 11. Decisions (with the user, 2026-09-29)

1. **Damage:** the ratio formula with a minimum of 1 replaces `damage − defense`.
2. **Dodge:** i-frames cover the first 0.30 s, then a 0.15 s recovery.
3. **Attacks commit:** movement is locked during swings, with a short lunge toward a locked target.
4. **Camera:** over the shoulder, built as swappable modes so first person can follow later.
5. **Enemy damage:** about 8–10% of the player's HP per hit at equal level (`ttk_levy_player`, 10–14 hits).
6. **Stamina:** stays out of the slice, per the world bible.

Everything else in this file is **proposed** until a playtest or the user settles it.
