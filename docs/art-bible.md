# Art Bible (v0, minimal)

Derived from shipped assets and `CLAUDE.md` → Visual Style Rules. Faction groupings and design briefs build on `docs/world/`.

**Style:** The look is stylized low-poly with generous budgets: bold colors, readable silhouettes, and simple albedo-only textures over realism.

## Palette

Hex values are either set exactly in a scene or script, or sampled from a shipped texture. Sampled values were quantized to 24-step bins, so they're approximate.

| Name | Hex | Derived from | Use |
|---|---|---|---|
| Garrison Teal | `#0C5454` | Player tunic (`player_character_texture_diffuse.png`, sampled) | Imperial cloth, player identity |
| Saddle Leather | `#4A2A10` | Player straps and boots (same texture, sampled) | Leather, harness, belts |
| Barrow Oak | `#8C5933` | Crate/barrel albedo `Color(0.55, 0.35, 0.2)` (`Level1.tscn`) | Timber, shafts, shield faces |
| Old Bone | `#CCB484` | Skeleton base color (`archer_enemy_skeleton_baseColor.png`, sampled) | Bone, parchment, pale cloth |
| Wet Slate | `#736B66` | Wall albedo `Color(0.45, 0.42, 0.40)` (Level scenes) | Dressed stone, roads |
| Rain Stone | `#4D4740` | Wall albedo `Color(0.3, 0.28, 0.25)` | Field stone, oilskin |
| Peat Black | `#2E2926` | Floor albedo `Color(0.18, 0.16, 0.15)` | Peat, soot, deep shadow areas |
| Blackened Iron | `#242424` | Torch iron (`prop_torch_material_diffuse.png`, sampled) | Iron, helms, fittings |
| Torch Amber | `#FFCC80` | Torch light `Color(1.0, 0.8, 0.5)` (Level scenes) | Firelight, warmth, the player's realm |
| Signal Red | `#C71F14` | HP bar fill (`HUD.gd:52`) | Blood, danger, rare accents |
| Tarnished Gold | `#E6BF1A` | XP bar fill (`HUD.gd:55`) | Brass, rank marks, reward accents |
| Overcast Blue | `#8C8CCC` | UI panel border (`HUD.gd:40`) | Cold light, rain, the Sleet |

**Balance:** scenes should be mostly the cool, muted colors (Wet Slate, Rain Stone, Peat Black), with Torch Amber marking wherever people live. Save Signal Red and Tarnished Gold for accents.

## Budgets (authoritative; this file is their only source)

- **Vertices:** characters 2,000–5,000; props and small objects 500–2,000. Count Blender mesh vertices with modifiers applied, summed across the whole `.glb`.
- **Textures:** albedo (base color) only, one texture per asset, 128×128 to 256×256, or vertex colors. No normal, roughness, metallic, occlusion, emissive or specular maps.
- **Rendering:** one directional light plus ambient per area. Ambient is a `WorldEnvironment` with Wet Slate `#736B66` color at low energy: Level 1 uses 0.5, enough for figures to read against the floor away from torchlight without flattening the torch pools. Local lights are allowed only for visible sources such as torches and candelabras. No bloom, SSAO or SSR.
- **Post-MVP, not now:** palette quantization, vertex-snap or affine-warp shaders, pixel fonts.

## STYLE BLOCK

Paste this in front of any image or 3D generation prompt, then add the entry's visual description after it:

```
Stylized low-poly 3D game art with generous polygon budgets: clean readable
silhouette, slightly exaggerated proportions, smooth limbs, recognizable face
and hands. Simple hand-painted albedo-only texture, matte surfaces, no normal
maps, no metallic or glossy PBR shine, no photorealism. Muted cold palette of
wet slate, rain stone and peat black with warm torch-amber accents. Soft single
directional light, overcast mood, no bloom, no pixel art, no PS1 jitter.
```

## Faction color groupings

Each group owns one **primary** color that no other group uses as a primary, so faction reads from color alone at gameplay distance. Rough area split per character: primary ~60%, secondaries ~30%, accent ≤10%.

| Group | Primary | Secondaries | Accent | Notes |
|---|---|---|---|---|
| **Frontier Line** (player, soldiers, deserters) | Garrison Teal | Saddle Leather, Blackened Iron | Tarnished Gold (rank marks, buckles) | Deserters use the same colors, faded and muddied, with the Notch cut off |
| **Hessane** (Keepers, villagers) | Peat Black | Barrow Oak, Old Bone | Torch Amber (lamps, ward-fire) | Old Bone only as small charms, so they never read as undead |
| **Lantern Charter** | Rain Stone | Tarnished Gold | Overcast Blue (lamp light) | Tall lamp-pole silhouette carries the read |
| **The dead** (Barrow-levies, Stillreach creatures) | Old Bone | Saddle Leather (rot), Blackened Iron | Signal Red (**Back-file only**) | Front-file carry no accent |
| **Environment** | Wet Slate, Rain Stone, Peat Black | Barrow Oak | Torch Amber at inhabited spots | Stays desaturated so characters pop |

**Reserved colors:**
- **Garrison Teal:** the Line only.
- **Signal Red:** Back-file wraps, blood and the HP bar only.
- **Overcast Blue:** the Sleet, Charter light and UI only.
- **Torch Amber:** fire, Kindle and Hessane lamps only.

## Design brief format

Every asset gets a brief before any generation spend. Fields:

- **File / Source:** the target path, and whether it's existing, AI-generated or sourced.
- **Role:** what it does in play.
- **Silhouette:** what must read at ~10 m.
- **Budget:** vertex ceiling, texture size, and the Tripo `face_limit`. These numbers live **only** here; each is copied into the asset's brief YAML (`assets/briefs/<asset-id>.yaml`), which the pipeline reads. A `face_limit` at or below the vertex ceiling leaves headroom, since a triangulated mesh has roughly half as many vertices as faces before UV seams.
- **Palette:** primary, secondary and accent, from the groupings above.
- **Materials & wear**
- **Rig / attachment:** skeleton or socket.
- **Scale & pivot**
- **Animation:** clip names the code plays, from the shared library.
- **Prompt:** the STYLE BLOCK plus the visual description.
- **Accept when:** a checklist for commit.
- **Cost:** the number of Tripo generations needed. Prices, estimates and confirmation live in the tripo skill (`.claude/skills/tripo/`).

---

## Brief: Player — Line soldier

- **File / Source:** `assets/meshes/player.glb`, **generated with Tripo from this brief** and run through the asset pipeline. It replaces the shipped `player_character.glb` (Rodin v2: 50,566 vertices, a 2048² albedo, normal and metallic-roughness maps), which isn't cleaned or reused.
- **Role:** the player; the camera sits behind them, so the back and shoulders read most.
- **Silhouette:** spiky dark hair (the player's identity mark), knee-length tunic flare, harness straps crossing the back.
- **Budget:** ≤ 5,000 vertices; one albedo at 256×256; Tripo `face_limit` 5,000.
- **Palette:** Garrison Teal tunic · Saddle Leather harness and boots · Blackened Iron buckles · Tarnished Gold company-number stitching under a Notch on the left shoulder.
- **Materials & wear:** wool, oiled leather; rain-darkened hem, scuffed boots, a patched elbow.
- **Rig / attachment:** the generated mesh needs a humanoid skeleton that maps onto Godot's `SkeletonProfileHumanoid`; how it gets rigged is still open (CLAUDE.md → Rigging & Animation). Pipeline stage 4 proposes the `BoneMap`. The right hand is the weapon socket, mapped in a `SocketMap` like every other rig.
- **Scale & pivot:** 1.8 m tall, feet at origin, facing −Y in Blender. The `.tscn` transform is unchanged (CLAUDE.md → Blender → Godot gotchas).
- **Animation:** library clips `idle`, `run`, `dodge_roll`, `attack_light`, `attack_heavy`, `death`. The current hand-keyed clips are retired.
- **Prompt:** STYLE BLOCK + *"A young frontier soldier in a knee-length Garrison Teal wool tunic, Saddle Leather harness and boots, spiky dark hair, empty hands, T-pose. Rain-darkened hem, scuffed leather, a small notched teal square patch on the left shoulder."*
- **Accept when:** ≤ 5,000 vertices; albedo only at ≤ 256²; retarget previews all 6 clips without breaking; teal and the hair read from the gameplay camera; face and hands still recognizable.
- **Cost:** 1 Tripo generation, plus one per rejected attempt.

## Brief: Barrow-levy — skeleton (Front-file and Back-file)

- **File / Source:** `assets/meshes/barrow_levy.glb`, **generated with Tripo from this brief**. This is the pilot for the Tripo path. It replaces the shipped Sketchfab `archer_enemy.glb` (1,277 vertices, a 28-bone rig with rest-pose defects; see `docs/audit.md`), which stays in the game until the new mesh passes the pipeline.
- **Role:** the slice's only enemy model: Front-file melee (×5) and Back-file archer (×2).
- **Silhouette:** Front-file hunched forward with a blade; Back-file upright with a bow. Posture and the held prop carry the read.
- **Budget:** ≤ 5,000 vertices (there's room to add harness straps and rags); albedo at 256×256; Tripo `face_limit` 5,000 for the planned regeneration.
- **Palette:** Old Bone · Saddle Leather harness scraps · Blackened Iron (via props) · **Back-file only:** Signal Red rag wraps on the forearms and brow.
- **Back-file variant:** a second albedo, `barrow_levy_backfile_baseColor.png` (256²), identical except for the painted Signal Red wraps. It's applied as a material override in `ArcherEnemy.tscn`, so there's no second mesh.
- **Materials & wear:** peat-stained joints, root tendrils, cracked bone, rotted leather.
- **Rig / attachment:** the new rig must map onto `SkeletonProfileHumanoid`; pipeline stage 4 proposes the `BoneMap`. Sockets `hand_r` (blade) and `hand_l` (bow) are mapped to bones **only** in `data/rigs/barrow_levy_sockets.tres`, which still names the Sketchfab bones: update that file for the new rig, and nothing else. Stage 4 fails until the sockets resolve.
- **Scale & pivot:** 1.8 m tall, feet at origin, facing −Y in Blender. The model node keeps `Transform3D(-1,0,0,0,1,0,0,0,-1,0,-0.9,0)`.
- **Animation:** the code plays `idle`, `run`, `attack`, `stagger`, `death` for **both** variants. The library must provide a melee `attack` for Front-file and a bow-draw `attack` for Back-file, remapped per variant. **Open item:** the shared library needs a bow-draw clip.
- **Prompt:** STYLE BLOCK + *"A humanoid skeleton of Old Bone stained peat-brown at the joints, in a rotted Saddle Leather harness, scraps of wool clinging to the ribs, roots threading the pelvis, empty hands, T-pose."*
- **Accept when:** the retarget plays all 5 clips on both variants; Back-file is distinguishable from Front-file at 15 m in the Level 1 corridor with props hidden; budget still met.
- **Cost:** 1 Tripo generation, plus one per rejected attempt. The Back-file texture and the bone map are manual or scripted work.

## Brief: Levy Blade *(pilot asset)*

- **File / Source:** `assets/meshes/prop_levy_blade.glb`, AI-generated (Tripo), then run through the full Post-Generation Cleanup. **This is the pipeline's first run.**
- **Role:** visual only, held by Front-file levies. Damage stays on the existing `HitboxComponent`.
- **Silhouette:** a short, broad leaf-shaped blade with no crossguard and a stubby wrapped grip. It must read as a blade, not a club, at 10 m.
- **Budget:** ≤ 2,000 vertices (aim for the low end, ~500); albedo at 128×128; Tripo `face_limit` 1,000.
- **Palette:** Blackened Iron blade, pitted · Saddle Leather grip wrap, rotted · Old Bone pommel cap.
- **Materials & wear:** centuries of burial, with a chipped edge, rust bloom and a frayed wrap.
- **Rig / attachment:** no skeleton. Held in socket `hand_r` via `held_props` on the enemy scene; alignment is fixed with a child `Transform3D`, never by editing the mesh.
- **Scale & pivot:** about 0.55 m overall (blade 0.40, grip 0.15). Origin at the base (pommel end), blade along Blender +Z. The socket's child `Transform3D` shifts it to the grip.
- **Animation:** none.
- **Prompt:** STYLE BLOCK + *"A single short leaf-shaped iron sword with no crossguard, isolated prop, no hands, side view. Pitted Blackened Iron blade with a chipped edge, grip wrapped in rotted Saddle Leather, a small Old Bone pommel cap."*
- **Accept when:** ≤ 2,000 vertices; albedo only at ≤ 128²; sits in the skeleton's right hand through all Front-file clips without clipping into the skull or ribs; reads as a blade from the gameplay camera.
- **Cost:** 1 Tripo generation; regenerate rather than doing mesh surgery.

## Brief: Levy Bow *(pilot asset)*

- **File / Source:** `assets/meshes/prop_levy_bow.glb`, AI-generated (Tripo), then run through the full Post-Generation Cleanup.
- **Role:** visual only, held by Back-file levies. Projectiles stay as they are; an arrow prop is out of scope.
- **Silhouette:** a short recurve bow with strongly curled tips, so it reads as a bow edge-on and face-on. The string is one thin strip and static.
- **Budget:** ≤ 2,000 vertices (aim for ~600); albedo at 128×128; Tripo `face_limit` 1,200.
- **Palette:** Barrow Oak limbs, darkened · Old Bone tip caps · **Signal Red grip wrap**, which echoes the Back-file rag cue.
- **Materials & wear:** warped, cracked wood; frayed string; a faded wrap.
- **Rig / attachment:** no skeleton. Held in socket `hand_l` via `held_props`, aligned with a child `Transform3D`.
- **Scale & pivot:** about 1.0 m tip to tip. Origin at the center (the grip), limbs along Blender ±Z.
- **Animation:** none. The string doesn't deform (acceptable for MVP).
- **Prompt:** STYLE BLOCK + *"A single short recurve bow with strongly curled tips, isolated prop, no hands, no arrow, front view. Darkened Barrow Oak limbs with cracks, small Old Bone tip caps, a faded Signal Red cloth grip wrap, one thin string."*
- **Accept when:** ≤ 2,000 vertices; albedo only at ≤ 128²; sits in the left hand through all Back-file clips; the curled silhouette reads at 15 m.
- **Cost:** 1 Tripo generation.

**Pilot total:** 4 Tripo generations (player, Barrow-levy, blade, bow), plus any rejected attempts. The tripo skill estimates and confirms each before it runs.
