# Trial: look development, A today vs B limits lifted (2026-10-02)

**Outcome: the 256 px texture is what loses the face; smooth shading and better lighting are the next two wins, and Forward+ alone buys nothing visible.** The same P1 player (attempt-1, rig-1; no new generation) at 512 px or more, smooth-shaded, reads as a clean stylized character with eyes and brows, where today's 256 px flat-shaded build reads as smeared. The lighting pass (B2) is the biggest change from the gameplay camera, and stays in the Compatibility renderer. Forward+ (B3) looks the same as B2; its extras (B3plus: SSAO, volumetric fog, torch shadows) are subtle and cost the most. Every variant runs far inside 60 fps on this Mac. Spend: 0 credits. Nothing shipped changed: the variants are built into gitignored `assets/lookdev/` and applied at runtime by `scenes/lookdev/LookDev.tscn`.

**Recommendation (the user's call):** raise character albedo to **1024 px** (512 px as the floor), drop forced flat shading **on characters**, adopt B2-style lighting as the level standard, and **stay on Compatibility** until a C-type asset proves it needs Forward+. Then decide whether C (a PS3-class PBR player) is worth about 85 credits.

![summary](look-dev/summary_level1.jpg)

## The variants

| Variant | Player mesh | Lighting | Renderer |
|---|---|---|---|
| **A** (shipped) | `assets/meshes/player.glb`: flat shading over 30°, 256 px albedo with the mouth overlay | Level as shipped: ambient Wet Slate at 0.5, torches at 0.5 energy (range 5 m, attenuation 1), a white key, no tonemap, no fog | Compatibility |
| **B1** | `assets/lookdev/player_b1.glb`: the same rig-1 source through the clean stage with the **source's smooth normals kept** and the **source's 2048 px texture** (concept colour correction kept, mouth overlay left out since it's drawn at 256 px) | as A | Compatibility |
| **B2** | B1 | Ambient warm grey `#8F8073` at 0.8; filmic tonemap, exposure 1.15; depth fog `#1F1712` at density 0.03; torches warmer (`#FFB366`), energy 1.6, range 7 m, attenuation 1.6 (a steeper falloff); the key cooler (`#C7D6FF`) at 0.55; a near-black background instead of the default grey sky. The player's fill light is unchanged | Compatibility |
| **B3** | B1 | B2 | **Forward+** (`--rendering-method forward_plus` on the command line; the project setting is untouched, which was cleaner than a temporary project change) |
| **B3plus** | B1 | B2 + SSAO (radius 1.2, intensity 1.6), volumetric fog (density 0.01), shadows on every torch | Forward+ |

Shots, identical per variant: the gameplay camera as the player spawns, a face close-up (32° FOV, 0.8 m), a full-body 3/4 (45°, 3 m) and the room overview, in Level 1 (KayKit kit) and the crypt trial (brush shell). The player idles under `--fixed-fps 30`, so the pose matches frame for frame.

## Sheets (A | B1 | B2 | B3 | B3plus)

| Shot | Level 1 (KayKit) | Crypt trial (brush shell) |
|---|---|---|
| Gameplay camera | [level1_gameplay](look-dev/level1_gameplay.jpg) | [crypt_gameplay](look-dev/crypt_gameplay.jpg) |
| Face close-up | [level1_face](look-dev/level1_face.jpg) | [crypt_face](look-dev/crypt_face.jpg) |
| Full body, 3/4 | [level1_body34](look-dev/level1_body34.jpg) | [crypt_body34](look-dev/crypt_body34.jpg) |
| Room | [level1_room](look-dev/level1_room.jpg) | [crypt_room](look-dev/crypt_room.jpg) |

Turntables (the idle keeps playing): [A](look-dev/turntable_A.mp4), [B2](look-dev/turntable_B2.mp4). The other variants' clips are rebuilt by `scripts/lookdev/run_lookdev.sh`.

![face](look-dev/level1_face.jpg)
![crypt room](look-dev/crypt_room.jpg)

## Which rule change bought what

**Texture size: the face.** To separate texture size from shading, the same smooth-shaded mesh was also built at 256, 512 and 1024 px (`SIZE=… scripts/lookdev/build_b1.sh`), all under B2 lighting:

![texture size](look-dev/texture_size_face.jpg)

At 256 px the face is blotches even when smooth-shaded: the eyes smear into the brows and the nose becomes streaks. At 512 px the eyes, brows and jaw come back; 1024 px is close to indistinguishable from 2048 px at this distance. From the gameplay camera and the 3/4 shot ([texture_size_body34](look-dev/texture_size_body34.jpg)) the difference is small: the tunic and harness read at any size, and 256 px only shows as muddier edges. **So the user's "not even PS2" is mostly the close-up and dialogue distance, and it's the texture.**

**Smooth shading: the surfaces and the animation.** Smooth normals take away the crumpled facets on the cheeks, the tunic and the hands (B1 against A in the face and 3/4 sheets). It has a cost under today's lighting: at mid-distance the flat facets that face the fill light catch it, so A reads brighter and higher-contrast than B1 (turntable frame 40, the tunic and face). Smooth shading needs the B2 lighting to hold up, so the two changes go together. The art bible's reason for the rule (the Barrow-levy's belt "looked like a tube") was about hard-surface parts; it wasn't tested here, so the recommendation keeps the angle rule for props and kit pieces and lifts it for characters.

**Lighting (B2): the room and the gameplay camera.** This is the biggest change from the gameplay camera. The torches now throw visible warm pools with a falloff, the walls between them drop toward a warm dark, the far end of the room recedes in the fog, and the player reads warmer and less muddy against the floor. Compatibility draws all of it. The default grey sky over Level 1's ceiling-less rooms becomes near-black: Level 1 has no ceiling, which the crypt shell does.

**Forward+ (B3): nothing visible alone.** B3 differs from B2 by 0.3–0.4% RMSE in every shot (A to B2 is 6–15%). Forward+ only pays through the features Compatibility lacks (B3plus): SSAO grounds the crypt's pillars with a soft contact shadow on the floor and darkens the wall corners, and torch shadows add some depth, but both are subtle at these lighting levels (the crypt room moves 1.3% RMSE from B2). Volumetric fog at the same density as the depth fog washes out Level 1's open top. None of it is what the user was reacting to.

**Style consistency: the crypt shell over the KayKit kit.** Under B2 the crypt's brush shell and its Material Maker brick (crypt sheets) sit with the smooth-shaded player better than the KayKit room: its flat, chunky toy pieces (rounded barrels, bevelled crates, chamfered wall caps) are the "Roblox" read. The white capsule in the Level 1 3/4 shot is the Village Elder's placeholder mesh, which adds to it. This supports the brush shell plus a kit chosen in the target style (Phase C kit choice).

## Costs

**Per asset (the player):**

| Texture | GLB on disk | Extracted PNG | VRAM (S3TC, mipmaps) |
|---|---|---|---|
| 256 px (A) | 0.51 MB | 95 KB | 44 KB |
| 512 px | 0.69 MB | — | 175 KB |
| 1024 px | 1.39 MB | — | 0.70 MB |
| 2048 px (B1) | 3.43 MB | 3.0 MB | 2.80 MB |

At 1024 px, ten characters on screen are 7 MB of VRAM, which no target machine notices. Repo size is the real cost (each character GLB plus its extracted PNG roughly doubles). The triangle count doesn't change (4,893 in every variant), and smooth shading doesn't add vertices (it keeps the source's normals, so no welding).

**Frame time on this Mac** (Apple M2 Pro, windowed with `--always-on-top`, vsync off, 600 frames after a 120-frame warm-up; the median wall-clock frame in ms, gameplay camera / room overview). The viewport's GPU timer reads 0 on this Mac, so these are frame deltas:

| Variant | Level 1, 1280×720 | Level 1, 2560×1440 | Crypt, 1280×720 | Crypt, 2560×1440 |
|---|---|---|---|---|
| A | 1.1 / 2.5 | 2.1 / 4.2 | 1.9 / 1.7 | 2.4 / 2.9 |
| B1 | 1.6 / 3.2 | 2.2 / 4.5 | 2.0 / 1.7 | 2.5 / 2.8 |
| B2 | 1.8 / 3.4 | 2.1 / 3.9 | 1.3 / 1.2 | 2.8 / 3.3 |
| B3 | 1.3 / 0.9 | ≤ 8.3 (capped) | 1.8 / 1.7 | ≤ 8.3 (capped) |
| B3plus | 2.3 / 4.2 | ≤ 8.3 (capped) | 1.9 / 2.0 | ≤ 8.3 (capped) |

- Run-to-run noise is about ±1 ms (A's Level 1 gameplay frame was 2.1 ms in an earlier run), so A, B1 and B2 are the same within noise. Everything is far inside the 16.7 ms of `perf_fps_min` (60 fps).
- Forward+ at 2560×1440 locks to the display's 120 Hz (8.33 ms) even with `--disable-vsync` (driver-level sync on Metal), so it can't be resolved there; at 1280×720 it's uncapped and in the same range. Its p95 is worse (B3plus up to 11.3 ms in Level 1's room overview against A's 4.6 ms).
- Full numbers: [timing.json](look-dev/timing.json).

**What higher fidelity exposes.** Smooth shading and a sharper texture make the animation and skinning more visible, not less. The skirt's skin stretch (3–5×, `player-model-rework`) and any clip pops will read more plainly than they do through facets, and a lit room with falloff shows a stiff idle more than a flat one does. These are costs to budget for in `player-model-rework` and the motion gates, not reasons against.

## Proposed art-bible changes (for the user)

1. **Textures:** characters get one albedo at **1024×1024** (512 the floor), still albedo only. Props and kit pieces stay at 256 px until a sheet shows they need more.
2. **Shading:** continuous-skin characters keep the source's smooth normals; the flat-by-30° rule stays for hard-surface props, kit pieces and rigid-part characters (the Barrow-levy belt case).
3. **Rendering:** a level lighting standard like B2: a warmer ambient around 0.8, filmic tonemap, depth fog, torches with a range around 7 m and a steeper falloff, a dim cool key. Fog and tonemapping join the allowed list; bloom, SSAO and SSR stay out.
4. **Renderer:** stay on Compatibility. Revisit only if C is adopted, since PBR materials and their roughness and normal maps are what Forward+ would earn its keep on.

Proposed text for the art bible's Textures and Shading lines, if the user agrees:

> - **Textures:** albedo (base color) only, one texture per asset, or vertex colors. Characters 1024×1024 (512 minimum: at 256 the face smears, `docs/trials/look-dev.md`); props and kit pieces 128×128 to 256×256. No normal, roughness, metallic, occlusion, emissive or specular maps.
> - **Shading:** continuous-skin characters keep the generator's smooth normals. Props, kit pieces and rigid-part characters are flat-shaded wherever faces meet at more than 30°, and smooth below that (smooth-shaded hard surfaces read as inflated plastic: the Barrow-levy's belt looked like a tube).

## C, as prepared (PS3+ target, paid; run 2026-10-02, results in Variant C below)

A player from Tripo's default high-detail model (v3.1) with PBR materials, from the **already-approved multiview sheet** (multiview-1), so no concept or multiview spend. The dry runs below are free (no network) and both returned `valid: true`:

```
tripo make .tripo-out/player/multiview-1/tripo-out/tripo-out-player-concept-1-tripo-e62305da/generate_multiview_image.front_view.jpeg .tripo-out/player/multiview-1/tripo-out/tripo-out-player-concept-1-tripo-e62305da/generate_multiview_image.left_view.jpeg .tripo-out/player/multiview-1/tripo-out/tripo-out-player-concept-1-tripo-e62305da/generate_multiview_image.back_view.jpeg .tripo-out/player/multiview-1/tripo-out/tripo-out-player-concept-1-tripo-e62305da/generate_multiview_image.right_view.jpeg --model v3.1-20260211 --param pbr=true --param texture=true -o .tripo-out/player_c/attempt-1 --no-open --json
```

- Dry run: `model: v3.1-20260211` (explicit), payload `{pbr: true, texture: true}` with the four views keyed front/left/back/right, no `face_limit` (the model's default, high-poly), no warnings or cost notes.
- Option: `--param texture_quality=detailed` (HD texture). Its dry run is valid but warns `texture_quality detailed: higher price tier`, so it needs the user's separate OK.
- Then the rig, as for P1 (rig-check free first): `tripo anim rig .tripo-out/player_c/attempt-1/tripo-out/<slug>/model.glb --rig-type biped --spec mixamo --out-format glb --param model=v1.0-20240301 -o .tripo-out/player_c/rig-1 --no-open --json`

**Estimate (unconfirmed for v3.1; nothing in the observed-cost table yet):** the model 30–60 (the pricing page's multiview row is 30 and P1 came in at 50), plus 10 for HD texture if chosen, plus the rig at 25 (observed): **about 55–95 credits, most likely about 85.** The balance is 420; this session's spend is 0 / 500.

What C needs besides the credits: a variant clean that keeps the PBR maps and the high triangle count (both break today's art-bible rules, so it lives under `assets/lookdev/` like B), Forward+ (or Compatibility with its simpler PBR) for the comparison, and a check that the v1.0 rigger accepts a mesh without a `face_limit`. Rendering it through `LookDev.tscn` is one more `--model` argument.

## Variant C (run 2026-10-02): Tripo v3.1 with PBR

**Outcome: C buys very little over B2 that the camera can see, at about 260 times the triangle budget.** From the gameplay camera and the 3/4 shot, C-albedo and B2 are hard to tell apart; the difference shows only in the face close-up, and it's shape, not detail: a rounder jaw, finer hair spikes and a cleaner neckline. The 1.43 million triangles are mostly smooth surface, since v3.1 tessellates the same stylized design densely and doesn't model extra detail. Full PBR (C-PBR) adds a sheen on the hair and rim highlights on the leather; its normal map is nearly flat. Decimating to 20k triangles (C-budget) keeps the shape but breaks the UVs and the weights: dark seam specks on the face, and skin stretch 5–7 times B1's. Spend: 55 credits (the model 30, the rig 25; balance 420 → 365), plus the earlier free rig-checks. **Recommendation: stay at B2.** Spend the budget headroom on texture (done: 1024 px) and on a face-limited v3.1 trial, not on PS3-class meshes.

### What was built

Same multiview-1 sheet as the shipped player, so no concept or multiview spend. `tripo make … --model v3.1-20260211 --param pbr=true --param texture=true` (no `face_limit`), then `tripo anim rig` with v1.0 (biped, mixamo spec, 23 joints, the same skeleton as P1, so `data/rigs/mixamorig_bone_map.tres` retargets it unchanged).

**C as delivered:** one mesh, **1,434,038 triangles** (740,608 vertices; 716,982 welded, one connected shell), one material with **three 2048×2048 maps**: base colour (JPEG), metallic-roughness (JPEG; mostly rough and non-metal, mean roughness 0.86, metallic 0.05, with metal patches on the buckles and bracers) and a tangent-space normal map (PNG, nearly flat apart from a few creases). No occlusion or emissive map. The download is 43 MB, the rigged one 57 MB.

| Variant | Mesh | Material | Lighting, renderer |
|---|---|---|---|
| **C-PBR** | `assets/lookdev/player_c_pbr.glb`: the rigged download through the clean stage (facing, 1.8 m, skirt reweight), source normals kept | as delivered: base colour, metallic-roughness and normal maps at 2048 px, no colour correction; Godot's default specular (0.5) put back, since our import extension zeroes it | B2, **Forward+** |
| **C-albedo** | `player_c.glb`: the same 1.43M-triangle mesh | albedo only at **1024 px**, colour-corrected toward concept-1 like B1, specular 0 | B2, Compatibility |
| **C-budget** | `player_c_budget.glb`: collapse-decimated to **19,998 triangles** before the clean (spike only; the pipeline never decimates a rigged mesh) | as C-albedo | B2, Compatibility |

Built by `scripts/lookdev/build_c.sh` (gitignored outputs); `LookDev.tscn` takes `--variant C-albedo|C-PBR|C-budget`.

### Sheets (A | B2 | C-albedo | C-PBR | C-budget)

| Shot | Level 1 (KayKit) | Crypt trial (brush shell) |
|---|---|---|
| Gameplay camera | [c_level1_gameplay](look-dev/c_level1_gameplay.jpg) | [c_crypt_gameplay](look-dev/c_crypt_gameplay.jpg) |
| Face close-up | [c_level1_face](look-dev/c_level1_face.jpg) | [c_crypt_face](look-dev/c_crypt_face.jpg) |
| Full body, 3/4 | [c_level1_body34](look-dev/c_level1_body34.jpg) | [c_crypt_body34](look-dev/c_crypt_body34.jpg) |
| Room | [c_level1_room](look-dev/c_level1_room.jpg) | [c_crypt_room](look-dev/c_crypt_room.jpg) |

Turntables: [C-albedo](look-dev/turntable_C-albedo.mp4), [C-PBR](look-dev/turntable_C-PBR.mp4) (A and B2 above).

![face close-up, B2 | C-albedo | C-PBR | C-budget](look-dev/c_face_closeup.jpg)

### What C buys over B2

- **The face close-up, a little.** The cheeks and jaw are rounder and the hair spikes thinner and sharper at the tips; the eyes and brows read the same as B2's (the texture carries them in both). The nose is still a painted line, not geometry.
- **Nothing from the gameplay camera.** In both rooms the player is a few hundred pixels tall; B2 and C-albedo differ only in the hair's outline.
- **PBR: highlights, not form.** C-PBR's metallic-roughness map gives the hair and leather a sheen and the buckles a glint under the torches; the normal map adds almost nothing because the mesh already carries the shape. It also pushes the look toward realism, against the art bible's "albedo-only over realism".
- **At a budget, the advantage goes.** C-budget at 20k triangles looks like B2 with seam specks: collapse decimation smears the UVs (thin dark lines across the face and tunic). A face-limited generation would avoid that, but wasn't run (it's paid).

### What C costs

| | A (shipped) | B2 | C-budget | C-albedo | C-PBR |
|---|---|---|---|---|---|
| Triangles (art bible: 5,500) | 4,893 | 4,893 | 19,998 (3.6×) | 1,434,038 (261×) | 1,434,038 (261×) |
| Textures | 1 × 256 | 1 × 2048 | 1 × 1024 | 1 × 1024 | 3 × 2048 (PBR) |
| GLB on disk | 0.51 MB | 3.4 MB | 1.8 MB | 56.5 MB | 57.6 MB |
| VRAM, whole Level 1 scene (Compatibility) | 72.8 MB | 75.4 MB | 74.2 MB | 156.5 MB | — |
| VRAM, Forward+ | — | 240.3 MB | — | — | 360.7 MB |
| Primitives drawn, gameplay camera | 13,656 | 13,656 | 28,761 | 188,017 | 188,017 |

- **VRAM** is the renderer's own counter for the whole scene (`--mode mem`). C's mesh adds about 83 MB of buffers (the mesh, its auto-generated LODs and shadow mesh); C-PBR's two extra 2048 maps add about 40 MB of textures. **Per C-tier character that's 80–120 MB** (instances of one mesh share it), so ten different characters on screen is around 1 GB, against 3–7 MB for ten B2 characters at 1024 px.
- **Frame time** (M2 Pro, as before; median ms, gameplay / room overview; [timing_c.json](look-dev/timing_c.json)): Level 1 at 1280×720: A 2.3 / 4.8, B2 1.9 / 5.5, C-albedo 2.7 / 3.5, C-PBR 2.1 / 1.9, C-budget 2.3 / 4.3. Crypt at 1280×720: A 2.1 / 2.0, B2 2.2 / 2.1, C-albedo 2.9 / 1.8, C-PBR 1.6 / 1.7, C-budget 2.3 / 2.2. At 2560×1440 Compatibility stays at 3–6.5 ms and Forward+ is capped at 8.3 ms (vsync, as before). **One C player costs at most about 1 ms on this Mac**, within the ±1 ms noise; the auto LODs draw about 175k of its 1.43M triangles at gameplay distance. A scene of C-tier enemies would multiply that, and it was not tested.
- **Repo and pipeline:** a 57 MB GLB per character can't be committed as our assets are (Git LFS or an external store would be needed), the two full-resolution builds (clean and import) took 94 s together against B1's 48 s alone, and the motion review can't measure the mesh (below).
- **Credits:** 30 for the model and 25 for the rig, against 50 + 25 for P1 at `face_limit` 5,000. The model is cheaper than P1 was.
- **Renderer:** C-PBR was shown under Forward+, as the item asked; Compatibility also draws metallic-roughness and normal maps, and Forward+ adds only what B3plus showed (SSAO, volumetric fog, shadowed omni lights). Forward+'s VRAM is about 165 MB higher for the same scene before any asset changes (B2: 240 against 75 MB).

### Animation and skinning

The retarget works unchanged: the v1.0 rig is the same 23-joint mixamo skeleton, so the shipped player's BoneMap and Fix Silhouette import settings drive the library on C: idle and run were reviewed, and the game-path pass played every handover on the full mesh (the run strip is in `.tripo-out/lookdev_c/motion/player_c_budget/`). Skin stretch from the motion review (`motion_review.tscn --clips idle,run --ground-speed run=5.0`; art bible `motion_edge_stretch` ≤ 1.0):

| Model | Idle stretch max (p99) | Run stretch max (p99) | Worst bone | Edges measured |
|---|---|---|---|---|
| B1 (P1, smooth) | 3.03 (0.51) | 4.56 (0.59) | LeftUpperLeg | 10,490 |
| C-budget (20k) | 14.87 (1.26) | 32.99 (1.58) | RightUpperLeg | 37,122 |
| C full (1.43M) | 0.014 (0.0) | not finished | Chest | 2,174,498 |

- **Full C can't be measured by today's review:** its edges are about 2 mm, under the review's 1 cm floor (`MIN_EDGE`), so the stretch reads near zero. The CPU-skinned review also takes about 4 minutes a clip at 740k vertices, and the run clip stalled while the window was in the background. Lowering the floor would make it comparable.
- **C-budget's stretch is decimation plus the skirt.** The worst edges sit at the skirt hem and the top of the boots, where the skirt reweight meets the knee, and the front slit tears open in the run. The weights are the v1.0 rigger's, interpolated by the decimation: the same weakness as P1 (`player-model-rework`), made worse by the decimation's long thin triangles.
- **What higher fidelity shows:** a smoother, denser mesh hides no facets, so the skirt's stretch and the knee crease show more plainly on C than on A, as B already suggested. The v1.0 rigger is the limit, not the mesh: C has the same skeleton and the same auto-weights.

### Recommendation and what the art bible would change

1. **Stay at B2 (recommended).** The B rules already adopted (1024 px character albedo, smooth shading for characters, B2 lighting, Compatibility) stand unchanged. C's only visible gain, the face's shape at dialogue distance, is worth a paid trial of **v3.1 at a game budget** (`face_limit` 10–20k, generated rather than decimated), which might keep C's shape without its UV and weight damage. The art bible doesn't change.
2. **A C-tier for hero characters only** (the player and named NPCs at dialogue distance). The art bible would need a second character budget (for example `face_limit` 15,000, so 16,500 triangles), a named hero list, and the motion review's `MIN_EDGE` made relative to edge length. Albedo only at 1024 px still; no PBR. Enemies and props stay at today's budgets.
3. **C-tier everywhere** (1M+ triangles and PBR). The art bible would drop triangle budgets as hard ceilings (or move them to LOD targets), allow metallic-roughness and normal maps, drop "albedo-only over realism" from the Style line, move the renderer to Forward+, and move the GLBs to Git LFS. That is a different game's art direction, and the sheets don't show a gain from the gameplay camera that would justify it.

## Reproduce

```
scripts/lookdev/build_b1.sh                  # assets/lookdev/player_b1.glb (2048 px); SIZE=256|512|1024 for the others
scripts/lookdev/run_lookdev.sh               # every variant's stills, turntable and timings, then the sheets in .tripo-out/lookdev/sheets
scripts/lookdev/build_c.sh                   # assets/lookdev/player_c{,_pbr,_budget}.glb from .tripo-out/player_c (v3.1 + rig-1)
VARIANTS="A B2 C-albedo C-PBR C-budget" scripts/lookdev/run_lookdev.sh .tripo-out/lookdev_c   # the C sheets
# VRAM: godot --path . res://scenes/lookdev/LookDev.tscn -- --variant <v> --room level1 --mode mem --out <dir>
```

The sources are the gitignored Tripo downloads in `.tripo-out/player/` (the builder falls back to the main checkout's). Windowed, on the Mac, hands off while it runs.
