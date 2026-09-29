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
- **Skirt reweight (a standard step for skirted characters, brief `skirt_reweight: true`):** the skirt is the region between knee and waist that sits more than 8.5 cm from both thigh bones; inside that radius is the trousers. It's graded from Hips at the waist to the thighs at the hem, split between the thighs by distance, with no shin weight. Over the 2.5 cm just inside that radius, weights blend from the leg's own to the skirt's, so there's no hard seam: a skirt vertex 2.5 cm from a trouser vertex at 72% shin had stretched that edge 8.7× in the run. Auto-riggers bind skirts to the legs: the player's hem came back about 40% on the shins. It's deterministic, like the rigid rebind. There are no separate skirt bones, because Quaternius clips wouldn't drive them.
- **Rigged meshes are welded too, but only where the coincident seam vertices carry identical skin weights.** Weights never change, and the faceting matches the unrigged path (the Barrow-levy is back to 13.2% faceted faces, from 24.4%).
- **Texture overlays (for small painted details the generator loses):** a brief's `texture_overlays` lists checked-in transparent PNGs, drawn in the mesh's UV space by `scripts/make_texture_overlay.py` (it ray-casts a stroke on the model and maps it to UV). The clean stage composites them after color correction. They're deterministic and re-runnable; don't hand-edit the baked texture. Each overlay's sidecar records the hash of the mesh whose UVs it was drawn on, and the clean stage refuses to composite onto any other mesh: regenerate the overlay whenever the model or rig is regenerated. The same mechanism can later adjust the eyes.
- **Rigid rebind (a standard step for rigid-part characters only):** when a brief sets `rigid_parts: true`, the clean stage binds each disconnected part at weight 1.0 to the bone whose rest segment is nearest the part's center. Only bones that already carry weight are candidates, so a control bone like Root never captures a part. Auto-riggers blend weights across neighbours, which smears rigid parts: the Barrow-levy pelvis was 0.26 on Hips and the rest on both thighs. The rebind is deterministic, so it isn't hand-painting (CLAUDE.md → Rigging & Animation). **Never for continuous-skin characters** such as the player; their blended weights are the point.
- **Color correction (a standard cleanup step for every asset):** Tripo's `delight` pass **both desaturates and darkens**. The Barrow-levy's bone came back at lightness 64 and saturation 13, against the concept's 68–75 and 20–23. **The palette governs briefs (what we ask for); the approved concept governs correction (what we got).** Where they disagree, the concept wins; for example, "deep dark teal" rendered as navy #13303E. How it works:
  - The clean stage takes 8 main colors from the approved concept (background removed), clusters the texture starting from those colors, and moves each texture cluster back toward the concept color it came from.
  - **Hue and saturation are restored fully. Lightness is only lifted, never lowered, to the matched concept tone.** The concept's facets are shaded, so its lightness is lit-or-shadowed per face rather than albedo, and texture clusters land on the shaded tones. Lightness therefore never exceeds a tone the concept actually contained, and **assets read slightly darker than the concept's lit facets by design** (the Barrow-levy's bone at lightness 67.8, against 75 on lit facets).
  - Colors the concept doesn't have fade to no shift beyond 30 ΔE.
  - Assets with no concept (text-to-3D, such as the blade) fall back to the brief's palette hex values under the same rule.
  - It's deterministic, with no per-asset tuning. **If assets read too dark under torchlight, fix it level-side** (the `WorldEnvironment` ambient energy and torch energy), never by brightening textures per asset.
- **Rendering:** one directional light plus ambient per area. Ambient is a `WorldEnvironment` with Wet Slate `#736B66` color at low energy: Level 1 uses 0.5, enough for figures to read against the floor away from torchlight without flattening the torch pools. Local lights are allowed only for visible sources such as torches and candelabras, with one exception: the player's **character fill light** (`Player.tscn` → `CameraRig/FillLight`: Torch Amber, energy 3.5, range 5 m, 0.6 m above and 2.5 m behind the camera pivot, so the skin doesn't clip). Its cull mask is render layer 2, and only the player's meshes are on it, so walls, floor and enemies are unaffected. **Readability fixes go in this order: character fill light, then level lighting, and albedo brightening only as a last resort** (it fights color correction, only helps in dark areas, and has to be redone per character). No bloom, SSAO or SSR.
- **Post-MVP, not now:** palette quantization, vertex-snap or affine-warp shaders, pixel fonts.

## Judge tolerances

The numeric assertions the asset judge checks (`scripts/judge.py`, which reads this table; nothing else holds these numbers). ΔE is CIE76 in Lab. Each value is set on principle and checked against the replays in `assets/manifests/judge_replays/`: the known-bad inputs fail, and where a shipped asset or clip fails too, it's a real finding recorded in `docs/decisions.md`, not a reason to loosen the limit.

| Check | Limit | Applies to | Why |
|---|---|---|---|
| `concept_palette_de` | 25 | concept | A brief palette color counts as present when one of the concept's main colors (≥ 3% of the figure) sits within this distance. Loose on purpose: the player's approved "deep dark teal" rendered as navy #14313F. |
| `color_min_share` | 0.05 | model, mesh | Colors covering less of the concept (or texture) than this are details, not checked. |
| `color_kept_ratio` | 0.33 | model, mesh | A concept color must keep at least this fraction of its concept share in the texture, or the model lost it. |
| `color_dab_after` | 5 | model, mesh | Hue/saturation distance (Lab a, b) between a corrected texture cluster and its concept color. |
| `palette_de_before` | 20 | model, mesh | Concept-less assets: distance before correction for a palette group covering at least `color_min_share`. Correction can repaint a wrong color: blade attempt 1's olive-green blade grouped under Old Bone (27.5 ΔE) and came out bone-colored. |
| `palette_de_after` | 12 | model, mesh | Concept-less assets: distance between a corrected palette group's median and its palette color. |
| `mesh_max_holes` | 10 | model, mesh | Open boundary loops after welding. Fewer are reported for the judge to weigh (the blade's 4 grip slits are recorded and accepted). |
| `motion_root_travel_m` | 0.15 | death, in-place clips | Horizontal Hips travel from the first frame. The pre-fix `Death01` travelled 0.45–0.51 m; shipped idles and runs stay under 0.07. |
| `motion_foot_slide_mps` | 0.5 | in-place clips | 90th-percentile ground-relative speed of a planted foot (near its lowest point and not moving vertically), at the clip's gameplay speed: 10% of the player's run. Reported only for action clips (attacks and rolls pivot on planted feet on purpose) and deaths (the feet kick out as the body collapses onto its pinned Hips; `Death01` can't meet both this and the travel limit, since keeping 30% of its travel still slid 0.80 m/s). |
| `motion_bind_deviation_m` | 1.8 | every clip | Largest vertex displacement from the bind pose in the Hips frame; a character's height, because no attached vertex gets that far from the hips. Normal clips reach 0.5–1.6 (arms swinging from the T-pose). |
| `motion_edge_stretch` | 1.0 | every clip | Largest relative length change of any mesh edge of at least 1 cm from the bind pose: an edge has doubled. Rigid-part characters read 0. |

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

## Sourcing: generate or download

**Generate what carries identity; download the rest.** Characters, faction-marked gear and anything the camera lingers on go through the Tripo pipeline and a brief. Generic dressing (barrels, crates, rubble, furniture) can come from CC0 sources. Downloaded assets go through the same clean stage (facing, flat shading, color correction toward the palette, budget assert), so they land in the same color space and shading standard as generated ones. (That import path is queued; see `docs/decisions.md` → Next.)

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
- **Shipped design change (concept-1, 2026-09-27):** the harness came back as a **leather vest with two straps crossed over it**, plus a waist belt, iron-grey wrist bracers, and dark trousers under the tunic. Accepted, because a solid chest piece rigs better than floating straps; thin, separate geometry is what hurt the Barrow-levy. The multiview sheet (multiview-1, approved) gave the vest a **plain back panel with two horizontal waist straps**, so the X-straps are **front-only**. The back now reads from the vest panel and the spiky hair. Also accepted: re-rolling the sheet risked losing what came through well. **Mouth:** Tripo's delight pass flattened the mouth into the skin; a texture overlay (`assets/overlays/player_mouth.png`) paints it back at clean time.
- **Budget:** ≤ 5,500 triangles (Tripo `face_limit` 5,000 + 10%); one albedo at 256×256.
- **Palette:** Garrison Teal tunic · Saddle Leather harness and boots · Blackened Iron buckles · Tarnished Gold company-number stitching under a Notch on the left shoulder.
- **Materials & wear:** wool, oiled leather. The wear (a rain-darkened hem, scuffed boots, a patched elbow) and the Notch patch are painted in the albedo during the texture pass, and kept out of the prompt.
- **Rig / attachment:** the generated mesh needs a humanoid skeleton that maps onto Godot's `SkeletonProfileHumanoid`; how it gets rigged is still open (CLAUDE.md → Rigging & Animation). Pipeline stage 4 proposes the `BoneMap`. The right hand is the weapon socket, mapped in a `SocketMap` like every other rig.
- **Rig order:** raw Tripo download → Tripo auto-rig → clean. Tripo's rigger expects its own +X orientation, and a cleaned, rotated GLB rig-checks as unriggable. **The rig model follows the body plan, not recency:** `v1.0-20240301` is the humanoid rigger (and the server default), and `v2.5-20260210` is for creatures. Continuous skin, so no rigid rebind.
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
- **Rig order:** raw Tripo download → Tripo auto-rig (`v1.0-20240301`, humanoid) → clean (see the player brief). **Rigid rebind** (`rigid_parts: true`): each of the 35 separate bone pieces is bound at weight 1.0 to its nearest bone. **Known quirk:** Tripo puts the Foot bones at floor level, so the feet bind to ToeBase, which is Foot's child and follows it rigidly. Quaternius drives Foot, not the toes, so it doesn't read at gameplay distance.
- **Scale & pivot:** 1.8 m tall, feet at origin, facing −Y in Blender. The model node keeps `Transform3D(-1,0,0,0,1,0,0,0,-1,0,-0.9,0)`.
- **Animation:** the code plays `idle`, `run`, `attack`, `stagger`, `death` for **both** variants. The library must provide a melee `attack` for Front-file and a bow-draw `attack` for Back-file, remapped per variant. Built: each variant has its own library over the shared clips (asset-pipeline skill → Animation library). Front-file: `Sword_Idle` (hunched), `Jog_Fwd_Loop`, `Sword_Regular_A`. Back-file: `Idle_Loop` and `Walk_Loop` (upright), plus **`OverhandThrow` as a stand-in for the bow draw**. Neither Standard pack has a bow clip; they're in a UAL2 tier not bought yet.
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
- **Prompt:** FORM block + *"A single short recurve bow standing upright, seen from the front, as an isolated prop. Two Barrow Oak limbs curl strongly outward at each tip and end in small Old Bone caps; the grip in the middle is wrapped in Signal Red cloth, and one thin straight string runs from tip to tip."* (Rewritten 2026-09-28 to describe only what's there, without negatives; the cracks and wear go in the albedo.)
- **Accept when:** ≤ 1,320 triangles; true length 1.0 m along its principal axis; albedo only at ≤ 128²; sits in the left hand through all Back-file clips; the curled silhouette reads at 15 m.
- **Cost:** 1 Tripo generation.

**Pilot total:** 4 Tripo generations (player, Barrow-levy, blade, bow), plus any rejected attempts. The tripo skill estimates and confirms each before it runs.
