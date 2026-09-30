# Production tools review (2026-09-29)

Two research passes, one Godot-side and one on content sources, were checked against CLAUDE.md, the art bible and the design bible. The criteria: Godot 4.7 compatibility, licence, maintenance, **agent-operability** (scriptable, headless or MCP-reachable, with deterministic and diffable output) and fit with our rules (albedo-only, low-poly, the Compatibility renderer, generated files changed only by their generators). The order below was agreed with the user; purchases need the user's OK.

## Key findings

1. **Deterministic playtests come free with Godot.**
   - A headless replay harness: `--fixed-fps 60`, and `--write-movie` for deterministic frame capture, with `Input.action_press` driven from a replay file (frame → action) inside `_physics_process`.
   - It writes an **event log** as JSONL, one line per physics frame: attacks, hits, damage, dodges, stagger and deaths.
   - That avoids the godot-ai MCP's limits (8–20 s of latency per call, no pausing mid-sequence), and it measures most of the design bible's combat targets directly.
   - The MCP stays for exploratory play and live diagnosis.
   - Physics isn't bit-exact across machines, so seed every RNG and assert the bible's tolerance **ranges**, not exact values.
2. **Most environment content can be free and CC0,** but only through a **downloaded-asset import path** in the clean stage (facing, flat shading, palette correction, budget assert). That path has been queued in `docs/decisions.md` since the pipeline was built, and it now gates every kit.
3. **One purchase:** Quaternius UAL2 Source ($14.99, still CC0, so it can live in the public repo). It fixes the Back-file's `OverhandThrow` stand-in with real `Bow_*` clips, and adds split combo hits and recoveries on the same rig, with no new BoneMap.

## Plan

### Phase A: foundations (free, before any new content)
1. **CI on GitHub Actions** (`barichello/godot-ci:4.7.2`, https://github.com/abarichello/godot-ci). On every PR:
   - a headless import that fails on errors or new warnings;
   - gdUnit4;
   - `godot_validate.gd` on committed assets;
   - a JSON lint for dialogues and quests.

   Linux has no display and renders through llvmpipe, so luminance and contrast targets stay measured on the Mac. Blender isn't in the image, so the pipeline's clean stage stays local. Runner minutes are free while the repo is public.
2. **gdUnit4 v6.2.1** (MIT, https://github.com/godot-gdunit-labs/gdUnit4), **the replay harness and the event log.**
   - Unit tests: the damage formula, level bands, CharacterStats, Inventory, QuestManager, a SaveManager round-trip.
   - Replay scenarios asserted against design-bible target IDs.
   - Its README lists Godot 4.5–4.7.1, so confirm 4.7.2.
   - GUT is the alternative; pick one.
3. **Edit-time navmesh bake, plus a path-clearance check.** Bake with `NavigationRegion3D.bake_navigation_mesh(false)` from a script and save the result, which removes the runtime-bake warning. Bake with a 0.5 m agent radius and path-find along the critical path, which proves `lvl_path_clearance_min`.
4. **The downloaded-asset import path** through `pipeline.py` and the clean stage, with a sources manifest (URL, author, licence per file). Allow CC0 only unless the user decides otherwise.

### Phase B: trials, each on its own branch and scored against the design bible
5. **Camera:**
   - Phantom Camera v0.11.0.3 (MIT, https://github.com/ramokz/phantom-camera): a third-person spring arm with a shape probe, a shoulder offset and damping; priority-based modes (first person later); two-target framing; noise for camera shake.
   - Against it: our own rig with a sphere-probe spring arm, about 150 lines.
   - Keep whichever scores better on the `cam_*` targets. Phantom Camera is pre-1.0 and broke once on 4.7.1, and our `CameraRig/FillLight` would need re-wiring.
6. **func_godot** (MIT, https://github.com/func-godot/func_godot_plugin), with Quake `.map` files for crypt interiors.
   - The format is plain text an agent can write and diff, and the user can open it in TrenchBroom.
   - Brushes are inherently low-poly.
   - Use an albedo-only material template, count triangles in validate, and pin a commit.
7. **Material Maker 1.5** (MIT): command-line export of palette-locked, regenerable tileable textures from small text `.ptex` graphs. Keep only the albedo and downscale it to 128 or 256 px.
8. **Dialogue Manager 4.1** (MIT, https://github.com/nathanhoad/godot_dialogue_manager) for the next quest.
   - Script-like `.dialogue` text, compiled at import so CI catches syntax errors.
   - Suits multi-outcome quests.
   - Keep `DialogueRunner`'s signals as a wrapper.

### Phase C: content sources (after step 4)

| Source | Cost | Fills |
|---|---|---|
| KayKit Dungeon Remastered (about 200 pieces on one texture atlas that downsamples to 128 px) | free, CC0 | crypts, dressing |
| Quaternius Medieval Village MegaKit (300+ grid-modular pieces); texture size and triangle count unverified | free Standard tier, CC0 | the terraced village |
| Kenney Retro Medieval (low-res, PS1-like), Graveyard, Castle, Nature | free, CC0 | barrows, graveyards, exteriors |
| Kenney Impact Sounds and RPG Audio (180 sounds) | free, CC0 | replaces the 5 placeholder sounds |
| Screaming Brain Studios Tiny Texture Packs; PS1 Retro Dungeon textures | free, CC0 | level surfaces (palette-corrected) |
| **Quaternius UAL2 Source** | **$14.99**, CC0 | bow draw, combos |

## Later
- **Behaviour-tree AI** (LimboAI 1.8.1 or Beehave 2.9.3): revisit at 4+ enemy archetypes. The design bible's AI targets need only an attack-token node, a line-of-sight helper and a WINDUP state, within CLAUDE.md's rule of an enum plus a match statement.
- **ProtonScatter** (pin `main`) and **a data-driven terrace generator** (JSON to a flat-shaded mesh), when outdoor spokes start. Terrain3D only if the world truly opens up: it's smooth, its data is binary, and its 4.7 support is only on main.
- **debug_draw_3d:** probe visualisation in captures.
- **godot-debug-menu:** an fps overlay.
- **ElevenLabs** sound effects and music, about $5/month: rain, wind and creature ambience. Read the music terms first, since self-serve plans exclude "Studio Games".
- **Freesound,** filtered to CC0 through its API.
- **Kokoro-82M:** local text-to-speech, Apache-2.0.
- **KayKit Character Animations:** 161 clips, but it would need a third BoneMap.
- **Quaternius animals** as a stand-in boar.
- **Cheaper concept images:** Tripo's seedream and banana models at 5 credits, for mood boards.

## Skipped
- **Licence:** Mixamo (raw files can't be redistributed), Sonniss GDC bundles, Pixabay and Mixkit audio (no standalone redistribution), Bandai Namco mocap (non-commercial).
- **Fit:**
  - Quaternius Universal Base Characters: about 13,000 triangles each, and rigged, so they can't be decimated;
  - Dialogic 2: alpha;
  - Cyclops Level Builder: GUI-bound, with open 4.7 bugs;
  - HTerrain and Spatial Gardener;
  - GodotTestDriver (C# only);
  - other Godot MCPs.
- **Check before use:** the Quaternius Bestiary says "QAL License", not CC0.

## Risks
- **Pre-1.0 tools and GDExtension binaries** break or lag on engine bumps. Pin exact tags or commits, and record them in `docs/decisions.md`.
- **Binary or opaque data** (Terrain3D regions, GridMap cell arrays, LimboAI `.tres` behaviour trees) weakens diff review. Text formats (`.map`, `.dialogue`, JSON replays and event logs) review best.
- **Per-file licences** (Freesound, OpenGameArt, Poly Pizza) need a sources manifest. Allowing only CC0 is simplest.
