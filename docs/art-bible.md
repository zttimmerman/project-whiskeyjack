# Art Bible (v0, minimal)

Derived from shipped assets and `CLAUDE.md` → Visual Style Rules. Faction groupings and design briefs build on `docs/world/`.

**Style:** The look is stylized low-poly with generous budgets: bold colors, readable silhouettes, and simple albedo-only textures over realism.

## Palette

Hex values are either set exactly in a scene or script, or sampled from a shipped texture. Sampled values were quantized to 24-step bins, so they're approximate.

**Names are for people; prompts get the plain color.** Image models can't resolve a name like "Old Bone" (the blade's first attempt came back green). `scripts/pipeline.py` replaces every palette name in a prompt with its **Plain color**, so briefs can keep using the names. A plain color is a concrete color phrase only: no palette names, and no material words.

| Name | Hex | Plain color | Derived from | Use |
|---|---|---|---|---|
| Garrison Teal | `#0C5454` | deep dark teal | Player tunic (`player_character_texture_diffuse.png`, sampled) | Imperial cloth, player identity |
| Saddle Leather | `#4A2A10` | dark reddish-brown | Player straps and boots (same texture, sampled) | Leather, harness, belts |
| Barrow Oak | `#8C5933` | warm mid-brown | Crate/barrel albedo `Color(0.55, 0.35, 0.2)` (`Level1.tscn`) | Timber, shafts, shield faces |
| Old Bone | `#CCB484` | pale yellowed beige | Skeleton base color (`archer_enemy_skeleton_baseColor.png`, sampled) | Bone, parchment, pale cloth |
| Wet Slate | `#736B66` | mid warm grey | Wall albedo `Color(0.45, 0.42, 0.40)` (Level scenes) | Dressed stone, roads |
| Rain Stone | `#4D4740` | dark brownish grey | Wall albedo `Color(0.3, 0.28, 0.25)` | Field stone, oilskin |
| Peat Black | `#2E2926` | very dark brown-black | Floor albedo `Color(0.18, 0.16, 0.15)` | Peat, soot, deep shadow areas |
| Blackened Iron | `#242424` | near-black charcoal | Torch iron (`prop_torch_material_diffuse.png`, sampled) | Iron, helms, fittings |
| Torch Amber | `#FFCC80` | pale warm amber | Torch light `Color(1.0, 0.8, 0.5)` (Level scenes) | Firelight, warmth, the player's realm |
| Signal Red | `#C71F14` | vivid scarlet red | HP bar fill (`HUD.gd:52`) | Blood, danger, rare accents |
| Tarnished Gold | `#E6BF1A` | bright golden yellow | XP bar fill (`HUD.gd:55`) | Brass, rank marks, reward accents |
| Overcast Blue | `#8C8CCC` | muted lavender blue | UI panel border (`HUD.gd:40`) | Cold light, rain, the Sleet |

**Balance:** scenes should be mostly the cool, muted colors (Wet Slate, Rain Stone, Peat Black), with Torch Amber marking wherever people live. Save Signal Red and Tarnished Gold for accents.

## Budgets (authoritative; this file is their only source)

- **Triangles (the budget unit):** every brief sets a triangle budget of its Tripo `face_limit` + 10%, since Tripo overshoots `face_limit` slightly (the first Levy Blade came in at 1,026 triangles for 1,000). Characters: `face_limit` 5,000, so 5,500 triangles; props are set per brief. The count is triangles after triangulation (an n-gon counts n−2), summed across the whole `.glb`, which is the same number Godot reports. Vertex counts (split at UV seams, and welded) are recorded as metrics only: they shift with seam splitting and can't be compared across assets.
- **Textures:** albedo (base color) only, one texture per asset, 128×128 to 256×256, or vertex colors. No normal, roughness, metallic, occlusion, emissive or specular maps.
- **Shading (a standard cleanup step for every asset):** flat-shaded wherever faces meet at more than 30°, and smooth below that. The clean stage clears the imported custom normals first. Smooth-shaded low poly reads as inflated plastic: the Barrow-levy's belt looked like a tube. Materials have roughness 1.0, metallic 0 and specular 0, because an albedo-only material at the default specular still shows a plastic highlight. Godot 4.6 doesn't import glTF specular (`KHR_materials_specular`), so the `addons/stylized_materials` import extension sets specular 0 on every imported material.
- **Palette correction (a standard cleanup step for every asset):** Tripo's texture pass desaturates, most likely its `delight` step, which is on by default. The Barrow-levy's bone came back #A89C86 against Old Bone #CCB484. After downscaling, the clean stage moves the albedo toward the brief's palette subset, using the hex values above. Each texel joins its nearest palette color in CIE Lab. A color is corrected only if it covers at least 3% of the texture and its median is within 30 ΔE of the target; anything further away is a different material, such as peat staining. Each corrected group shifts by the difference between its target and its median, so stains and wear inside it survive, and texels blend the shifts by distance, so group borders don't band. It's deterministic, with no per-asset tuning. Small groups only get part of the way there (the blade's bone pommel is 5% of its texture and went from 23 to 10 ΔE).
- **Rendering:** one directional light plus ambient per area. Ambient is a `WorldEnvironment` with Wet Slate `#736B66` color at low energy: Level 1 uses 0.5, enough for figures to read against the floor away from torchlight without flattening the torch pools. Local lights are allowed only for visible sources such as torches and candelabras. No bloom, SSAO or SSR.
- **Post-MVP, not now:** palette quantization, vertex-snap or affine-warp shaders, pixel fonts.

## Prompt blocks

Generation prompts are built from these blocks plus the brief's own description, with palette names swapped for their plain colors (see Palette). `scripts/pipeline.py` reads FORM and CONCEPT LIGHTING from this section, so edit them here only. Which lighting applies depends on what the image is for:
- **Concept images: anything that feeds multiview-to-3D** (every pipeline concept and refine, characters and props alike): FORM + CONCEPT LIGHTING + description. The image is the model's only input, so its lighting must show true base colors and clean forms. Directional light bakes shadows into the generated texture and misleads reconstruction.
- **Mood and reference images, never fed to 3D** (how an area or character should feel in-game): FORM + MOOD LIGHTING + description. The pipeline never produces these, and never uses one as a concept.
- **3D-model prompts:** FORM + description, with no lighting. The pipeline's 3D step is multiview-to-3D, whose endpoint takes no prompt, so this composition applies only where a 3D endpoint takes text.

**The concept image is the only channel for FORM.** Multiview-to-3D takes no prompt, so FORM reaches the model only through the approved concept. Judge concepts as low-poly game assets (flat shading, simple forms, minimal fine surface detail), not as attractive illustrations. A detailed, painterly concept produces a detailed mesh, and `face_limit` will destroy that detail rather than simplify it.

### FORM block

```
Stylized low-poly 3D game asset with a clean, readable silhouette and slightly
exaggerated proportions. Flat color blocking with minimal fine surface detail,
matte hand-painted albedo-only texture, restricted muted palette. No
photorealism, no glossy PBR shine, no pixel art.
```

### CONCEPT LIGHTING block

```
Flat, even, shadowless lighting from all sides on a plain, uniform mid-grey
background. Every surface shows its true base color at the same brightness,
front and back, with no cast shadows and no highlights.
```

### MOOD LIGHTING block

For mood and reference images only. Never use it in anything that feeds multiview-to-3D.

```
Lit for a low-ambient torchlit interior: dim slate-grey ambient, one warm
torch-amber key light, deep but not black shadows. No lighting or shadow
painted into the texture. No bloom.
```

**Why two lightings:** a concept's pixels become the mesh's texture and shape cues, so any light in the image ends up baked into the albedo, and the engine lights the asset a second time. Concepts are therefore flat-lit. Whether the albedo's values *read* in the levels' low Wet Slate ambient and warm torch key (see Rendering above) is judged afterwards, on the in-engine asset or on a mood image, never by lighting the concept.

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
- **Budget:** the Tripo `face_limit`, the triangle budget (`face_limit` + 10%), and the texture size. These numbers live **only** here; each is copied into the asset's brief YAML (`assets/briefs/<asset-id>.yaml`), which the pipeline reads.
- **Palette:** primary, secondary and accent, from the groupings above.
- **Materials & wear**
- **Rig / attachment:** skeleton or socket.
- **Scale & pivot**
- **Animation:** clip names the code plays, from the shared library.
- **Prompt:** the visual description at silhouette level: the shapes that must read at gameplay distance, with colors given by palette name (the pipeline swaps in the plain colors). Wear, small marks and surface detail belong in the albedo, never in the prompt. At the `face_limit`, modelled fine detail either vanishes or eats the budget (the Levy Blade spent 84% of its triangles on the grip wrap). The pipeline prepends the FORM block, plus the CONCEPT LIGHTING block for concept images.
- **Accept when:** a checklist for commit.
- **Cost:** the number of Tripo generations needed. Prices, estimates and confirmation live in the tripo skill (`.claude/skills/tripo/`).

---

## Brief: Player — Line soldier

- **File / Source:** `assets/meshes/player.glb`, **generated with Tripo from this brief** and run through the asset pipeline. It replaces the shipped `player_character.glb` (Rodin v2: 50,566 vertices, a 2048² albedo, normal and metallic-roughness maps), which isn't cleaned or reused.
- **Role:** the player; the camera sits behind them, so the back and shoulders read most.
- **Silhouette:** spiky dark hair (the player's identity mark), knee-length tunic flare, harness straps crossing the back.
- **Budget:** ≤ 5,500 triangles (Tripo `face_limit` 5,000 + 10%); one albedo at 256×256.
- **Palette:** Garrison Teal tunic · Saddle Leather harness and boots · Blackened Iron buckles · Tarnished Gold company-number stitching under a Notch on the left shoulder.
- **Materials & wear:** wool, oiled leather. The wear (a rain-darkened hem, scuffed boots, a patched elbow) and the Notch patch are painted in the albedo during the texture pass, and kept out of the prompt.
- **Rig / attachment:** the generated mesh needs a humanoid skeleton that maps onto Godot's `SkeletonProfileHumanoid`; how it gets rigged is still open (CLAUDE.md → Rigging & Animation). Pipeline stage 4 proposes the `BoneMap`. The right hand is the weapon socket, mapped in a `SocketMap` like every other rig.
- **Rig order:** raw Tripo download → Tripo auto-rig → clean. Tripo's rigger expects its own +X orientation, and a cleaned, rotated GLB rig-checks as unriggable.
- **Scale & pivot:** 1.8 m tall, feet at origin, facing −Y in Blender. The `.tscn` transform is unchanged (CLAUDE.md → Blender → Godot gotchas).
- **Animation:** library clips `idle`, `run`, `dodge_roll`, `attack_light`, `attack_heavy`, `death`. The current hand-keyed clips are retired.
- **Prompt:** FORM block + *"A young frontier soldier in a knee-length wool tunic in Garrison Teal that flares at the hem, a leather harness in Saddle Leather with two straps crossing the chest and back, leather boots in Saddle Leather, spiky dark hair, empty hands, T-pose."*
- **Accept when:** ≤ 5,500 triangles; albedo only at ≤ 256²; retarget previews all 6 clips without breaking; teal and the hair read from the gameplay camera; face and hands still recognizable.
- **Cost:** 1 Tripo generation, plus one per rejected attempt.

## Brief: Barrow-levy — skeleton (Front-file and Back-file)

- **File / Source:** `assets/meshes/barrow_levy.glb`, **generated with Tripo from this brief**. This is the pilot for the Tripo path. It replaces the shipped Sketchfab `archer_enemy.glb` (1,277 vertices, a 28-bone rig with rest-pose defects; see `docs/audit.md`), which stays in the game until the new mesh passes the pipeline.
- **Role:** the slice's only enemy model: Front-file melee (×5) and Back-file archer (×2).
- **Silhouette:** Front-file hunched forward with a blade; Back-file upright with a bow. Posture and the held prop carry the read.
- **Budget:** ≤ 5,500 triangles (Tripo `face_limit` 5,000 + 10%); albedo at 256×256.
- **Palette:** Old Bone · Saddle Leather harness scraps · Blackened Iron (via props) · **Back-file only:** Signal Red rag wraps on the forearms and brow.
- **Back-file variant:** a second albedo, `barrow_levy_backfile_baseColor.png` (256²), identical except for the painted Signal Red wraps. It's applied as a material override in `ArcherEnemy.tscn`, so there's no second mesh.
- **Materials & wear:** peat-stained joints, cracked bone and rotted leather, all painted in the albedo. The root tendrils and wool scraps are lore (`docs/world/05-bestiary.md`), not geometry, and are kept out of the prompt.
- **Rig / attachment:** the new rig must map onto `SkeletonProfileHumanoid`; pipeline stage 4 proposes the `BoneMap`. Sockets `hand_r` (blade) and `hand_l` (bow) are mapped to bones **only** in `data/rigs/barrow_levy_sockets.tres`, which still names the Sketchfab bones: update that file for the new rig, and nothing else. Stage 4 fails until the sockets resolve.
- **Rig order:** raw Tripo download → Tripo auto-rig → clean (see the player brief).
- **Scale & pivot:** 1.8 m tall, feet at origin, facing −Y in Blender. The model node keeps `Transform3D(-1,0,0,0,1,0,0,0,-1,0,-0.9,0)`.
- **Animation:** the code plays `idle`, `run`, `attack`, `stagger`, `death` for **both** variants. The library must provide a melee `attack` for Front-file and a bow-draw `attack` for Back-file, remapped per variant. **Open item:** the shared library needs a bow-draw clip.
- **Prompt:** FORM block + *"A humanoid skeleton in Old Bone, stained peat-brown at the joints, with a clearly readable skull and ribcage, wearing a rotted leather harness in Saddle Leather: a belt at the waist and two straps crossing the chest and back. Empty hands, T-pose."*
- **Accept when:** the retarget plays all 5 clips on both variants; Back-file is distinguishable from Front-file at 15 m in the Level 1 corridor with props hidden; budget still met.
- **Cost:** 1 Tripo generation, plus one per rejected attempt. The Back-file texture and the bone map are manual or scripted work.

## Brief: Levy Blade *(pilot asset)*

- **File / Source:** `assets/meshes/prop_levy_blade.glb`, AI-generated (Tripo), then run through the full Post-Generation Cleanup. **This is the pipeline's first run.**
- **Role:** visual only, held by Front-file levies. Damage stays on the existing `HitboxComponent`.
- **Silhouette:** a short, broad leaf-shaped blade with no crossguard and a stubby wrapped grip. It must read as a blade, not a club, at 10 m.
- **Budget:** ≤ 1,100 triangles (Tripo `face_limit` 1,000 + 10%); albedo at 128×128.
- **Palette:** Blackened Iron blade, pitted · Saddle Leather grip wrap, rotted · Old Bone pommel cap.
- **Materials & wear:** centuries of burial, with a chipped edge, rust bloom and a frayed wrap.
- **Rig / attachment:** no skeleton. Held in socket `hand_r` via `held_props` on the enemy scene; alignment is fixed with a child `Transform3D`, never by editing the mesh.
- **Scale & pivot:** about 0.55 m overall (blade 0.40, grip 0.15). Origin at the base (pommel end), blade along Blender +Z, so the tip (the thinner end) is at the top (`tip_end: top`). The socket's child `Transform3D` shifts it to the grip.
- **Animation:** none.
- **Prompt:** FORM block + *"A single short leaf-shaped sword as an isolated prop, seen from the side. The blade tapers straight into the leather-wrapped grip in one continuous piece, its shoulders meeting the grip directly. The blade is blackened, near-black desaturated iron with a cold grey-brown cast, pitted, with a chipped edge. The grip is wrapped in rotted dark leather and capped with a small bone pommel."*
- **Accept when:** ≤ 1,100 triangles; true length 0.55 m along its principal axis; albedo only at ≤ 128²; sits in the skeleton's right hand through all Front-file clips without clipping into the skull or ribs; reads as a blade from the gameplay camera.
- **Cost:** 1 Tripo generation; regenerate rather than doing mesh surgery.

## Brief: Levy Bow *(pilot asset)*

- **File / Source:** `assets/meshes/prop_levy_bow.glb`, AI-generated (Tripo), then run through the full Post-Generation Cleanup.
- **Role:** visual only, held by Back-file levies. Projectiles stay as they are; an arrow prop is out of scope.
- **Silhouette:** a short recurve bow with strongly curled tips, so it reads as a bow edge-on and face-on. The string is one thin strip and static.
- **Budget:** ≤ 1,320 triangles (Tripo `face_limit` 1,200 + 10%); albedo at 128×128.
- **Palette:** Barrow Oak limbs, darkened · Old Bone tip caps · **Signal Red grip wrap**, which echoes the Back-file rag cue.
- **Materials & wear:** warped, cracked wood; frayed string; a faded wrap.
- **Rig / attachment:** no skeleton. Held in socket `hand_l` via `held_props`, aligned with a child `Transform3D`.
- **Scale & pivot:** about 1.0 m tip to tip. Origin at the center (the grip), limbs along Blender ±Z; both ends are tips (`tip_end: symmetric`).
- **Animation:** none. The string doesn't deform (acceptable for MVP).
- **Prompt:** FORM block + *"A single short recurve bow with strongly curled tips, isolated prop, no hands, no arrow, front view. Darkened Barrow Oak limbs with cracks, small Old Bone tip caps, a faded Signal Red cloth grip wrap, one thin string."*
- **Accept when:** ≤ 1,320 triangles; true length 1.0 m along its principal axis; albedo only at ≤ 128²; sits in the left hand through all Back-file clips; the curled silhouette reads at 15 m.
- **Cost:** 1 Tripo generation.

**Pilot total:** 4 Tripo generations (player, Barrow-levy, blade, bow), plus any rejected attempts. The tripo skill estimates and confirms each before it runs.
