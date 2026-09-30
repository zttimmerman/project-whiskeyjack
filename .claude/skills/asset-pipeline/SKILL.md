---
name: asset-pipeline
description: Orchestrates 3D asset production for this project with scripts/pipeline.py. It owns briefs, stage order (concept → multiview → model → rig → clean → validate), Blender cleanup, Godot validation and the per-asset manifest. Use when creating, regenerating, cleaning or validating any mesh in assets/meshes/.
---

# Asset pipeline (orchestrator)

**Execution:** fully scripted and headless (`pipeline.py`, headless Blender and Godot, `judge.py`, the motion review). Never the Godot MCP: every stage must reproduce exactly without an open editor.

**Layering:** this skill orchestrates; the **tripo** skill (`.claude/skills/tripo/`) is the vendor adapter. Any paid `tripo` call, including concept images and models, follows the tripo skill: its confirmation flow, credit cap, balance checks and URL-expiry rules. None of those are repeated here. `pipeline.py` never runs a paid `tripo` command; it prints the command, and the agent runs it through the tripo skill.

**Budgets:** `docs/art-bible.md` is the only source of budget numbers (`face_limit`, triangle budget, texture size, target size, pivot, palette). Each asset carries them in its brief YAML. To change a number, change the art bible first, then copy it into the brief. Never write a number into this skill, the tripo skill, or a script.

## Command

```
python3 scripts/pipeline.py <asset-id> --stage <concept|multiview|model|rig|clean|validate|all> [--dry-run] [--force]
        [--concept-model banana_pro|seedream_v5] [--variants K] [--refine N --edit TEXT]
python3 scripts/pipeline.py <asset-id> --approve-concept N
```

- `--dry-run` prints what each stage would do and writes nothing.
- `--force` re-runs a stage even if its inputs are unchanged.
- `--concept-model` picks the text-to-image model: `banana_pro` (default) or `seedream_v5` for cheap multi-variant exploration.
- `--variants K` (1–4, concept stage only) prints K new concept commands, even when concepts already exist or one is approved.
- `--refine N --edit TEXT` (concept stage only) prints an image-to-image edit of `concept-N` into the next `concept-<n>`. Write TEXT from the user's review.
- `--approve-concept N` records the user's approval of `concept-N` in the manifest. **Run it only after the user approves that image in chat.** Never approve on their behalf.

| Exit code | Meaning | What to do |
|---|---|---|
| 0 | ok or up to date | nothing |
| 1 | error (bad brief, missing tool) | fix the cause |
| 2 | a stage check failed | read the stage's `message`/`report` in the manifest |
| 3 | waiting on a Tripo run | run the printed command through the tripo skill, then re-run the stage |
| 4 | waiting on the user's concept approval | show the user the listed candidates (Read each image), and stop until they approve one, ask for a refine, or ask for more variants |

## Files

| Path | What | In git? |
|---|---|---|
| `assets/briefs/<asset-id>.yaml` | brief (optional `rigid_parts: true` for characters built from separate rigid parts): `asset_id`, `type` (character\|prop), `brief`, `prompt`, `face_limit`, `tripo_model` (a pinned wire version, passed as `--model`), `triangle_budget` (`face_limit` + 10%), `tip_end` (props only: top, bottom or symmetric), `texture_size`, `target_size_m`, `pivot` (base\|center), `palette` (names from the art bible), plus optional `source_glb`, `socket_map`, `animations`, `exclude_objects` | yes |
| `assets/manifests/<asset-id>.json` | one entry per stage: status, timestamp, inputs and outputs with SHA-256 hashes, prompt, parameters, actual cost in credits, tool versions (Python, Blender, Godot, tripo), and the stage report. Also `concept_approval`: the approved attempt, the image's path and SHA-256, and the time | yes |
| `assets/meshes/<asset-id>.glb` | the cleaned output of stage 3 | yes |
| `assets/manifests/<asset-id>/` and `judge_replays/` | review renders, judge packets (`packet.json`, `verdict.json`) and their image copies, animation sheets | JSON yes, **images no** (local only; every image's SHA-256 is in the committed JSON) |
| `.tripo-out/<asset-id>/` | Tripo downloads, spend records, and `work/` (stage parameters, reports, logs) | no |
| `assets/sources.json` | sourced assets only: one entry per asset (pack, URL, author, licence, pack version, source file and its SHA-256) plus one per pack (archive and licence-file hashes, import settings) | yes |
| `assets/atlases/<pack>/` | a kit's shared atlas, downscaled and palette-corrected once, with a JSON sidecar | yes |
| `.downloads/<pack>/` | the original zip and its extracted files | no |

The brief YAML uses a strict subset: top-level keys, scalars, `[inline lists]`, `- item` lists, and `|` blocks. No PyYAML is needed.

## Stages

The Tripo chain is **text-to-image → (optional refine) → image-to-multiview → multiview-to-3D**. Text-to-3D is never printed. Prompts are composed from `docs/art-bible.md` → Prompt blocks: concept images get FORM + LIGHTING + the brief's `prompt`, and a refine gets FORM + LIGHTING + the edit text. **Multiview-to-3D takes no prompt** (the API has no `prompt` parameter on that endpoint), so FORM reaches the 3D stage only through the concept image. Image-to-multiview takes no prompt or model either.

**Hard stop:** no 3D spend (multiview or model) happens until the user has approved a concept. Iteration belongs at the image stage. The concept, multiview and model stages report "not needed" once a base mesh is on disk (`source_glb` or a usable `attempt-<n>`), so shipped assets aren't affected.

1. **concept**. Characters get `template=t_pose` and a portrait frame (`aspect_ratio=3:4` on banana models, `size=1536x2048` on seedream, which ignores `aspect_ratio`); props get neither.
   - No usable concept yet: it prints `tripo generate text-to-image …` and exits 3.
   - Usable concepts but none approved: it lists them and exits 4. The pipeline stops here until the user decides.
   - An approved concept: `ok`. The approval stays valid only while the image's SHA-256 matches and its spend record isn't `rejected`, `lost` or `failed`. A changed or rejected image blocks the later stages again.
   - Concepts are `.tripo-out/<id>/concept-<n>/`, one image each (the CLI's `preview.png` copy is ignored). A hand-made concept dropped into a `concept-<n>/` folder works too, and needs no spend record.
2a. **multiview**. Needs the approved concept (otherwise it exits 4). It prints `tripo generate image-to-multiview <approved image>` into `multiview-<n>` and exits 3. It ingests the newest usable sheet **whose spend record's `command` names the approved image**, so a sheet made from an older concept is never used. It fails (exit 2) if the sheet has no front view or fewer than 2 views. Show the user the sheet (the four `*_view` images) before asking to spend on the model.
2b. **model**. Uses the brief's `source_glb` for existing assets. Otherwise it ingests the newest usable Tripo download (`attempt-<n>`, skipping attempts whose spend record is `rejected`, `lost` or `failed`) and copies every attempt's spend record into the manifest. If nothing is on disk, it prints `tripo make <front> <left> <back> <right> --model <tripo_model> --param pbr=false --param texture=true --param face_limit=<brief>` from the current sheet and exits 3. `make` is used rather than `generate multiview-to-model` because only `make` has `--dry-run`.
2c. **rig** (characters only; props and `source_glb` assets skip it). Rigs the **raw** download, because Tripo's rigger expects its own +X orientation and a cleaned, rotated GLB rig-checks as unriggable. It prints `tripo anim rig <raw model.glb> --rig-type biped --spec mixamo --out-format glb --param model=<rig model>` into `rig-<n>` and exits 3. **The rig model follows the body plan:** `v1.0-20240301` (the default) for humanoids; pass `--rig-model v2.5-20260210` for creatures. Mark a rejected rig's spend record `rejected` so the next `rig-<n>` is printed. It ingests the newest usable `rig-<n>` whose spend record's `command` names the current raw download. Before the paid run, rig-check the same file (`tripo anim check`, free); it has to return `riggable: true`. After the run, check the bone names and the part-to-bone weights. v2.5 on a humanoid returned a generic limb rig with a defective left arm; v1.0 returned `mixamorig:` names.
3. **clean**. For characters it reads the rigged GLB from 2c; for props, the model download. Runs `blender -b --factory-startup -P scripts/blender_cleanup.py`:
   - removes Blender's importer-made bone display shapes, and anything listed in `exclude_objects`;
   - fails if a rigged asset has a mesh that isn't attached to the armature;
   - characters: detects facing and snaps it to −Y. A rig uses its foot bones (heel to toe). Without a rig, it reads the source's export axis from the Tripo `task.json` beside the download (`export_orientation`, or the API default `+x` when that's unset) and cross-checks it against the geometry: the arm span gives the lateral axis, the feet give forward. If the metadata and the geometry disagree it **fails**; with neither, it warns and assumes −Y. **Tripo's rigger expects Tripo's own +X orientation**, so rig the raw download before cleaning; a cleaned, rotated GLB rig-checks as unriggable;
   - props: aligns the **principal axis** (largest spread) to +Z and the second axis to +X, then re-measures and **fails if the residual tilt exceeds 2°**; warns when a prop has no clear long axis. It then finds the **tip** (the thinner end, comparing each end's cross-section over 12% of the length), flips the prop 180° if the tip isn't at the brief's `tip_end`, re-measures, and **fails** if it still doesn't match. When the ends are too similar (thin/thick above 0.8) it only warns; `symmetric` skips the check;
   - scales to `target_size_m` (height for characters, length for props) and puts the base or center at the origin;
   - rebuilds every material as albedo-only (a Principled BSDF with base color, plus cutout alpha through Round so glTF writes MASK), with roughness 1, metallic 0 and specular 0. It drops normal, roughness, metallic, specular, emission and occlusion maps, and turns unlit/emission setups into albedo;
   - **flat shading:** clears the imported custom normals, then flat-shades every edge sharper than 30° (`SMOOTH_ANGLE_DEG`). Unrigged meshes are welded first so UV-seam splits don't read as hard edges; rigged meshes are welded only where coincident vertices carry identical skin weights. Both keep UVs and the triangle count;
   - bakes the albedo with Cycles when it comes from a node chain rather than an image (one material only);
   - downscales the texture to `texture_size`, and fails if there's more than one texture;
   - **rigid rebind** (briefs with `rigid_parts: true` only, and never for continuous-skin characters): binds each disconnected part at weight 1.0 to the weighted bone nearest its center, and reports each part's bone and its share before the rebind in `rigid_rebind`;
   - **skirt reweight** (briefs with `skirt_reweight: true` only): grades the skirt region from Hips at the waist to the thighs at the hem, with no shin weight, blending over `SKIRT_BLEND_WIDTH` just inside the trouser radius so the skirt/trouser boundary has no seam, and reports `skirt_reweight`. Bones are measured as joint spans (head to child joint), never head to tail;
   - **color correction:** moves the albedo toward the **approved concept** (the palette hex values are the fallback for assets with no concept). It takes 8 main colors from the concept, clusters the texture starting from them, restores hue and saturation fully, and lifts lightness (never lowers it) to the matched concept tone. Colors further than 30 ΔE from every cluster don't move. **Sourced assets** (`source: download`) are measured over their UV footprint and may be darkened as well as lifted (see Sourced assets). Reported in `color_correction` (or `palette_correction` for the fallback) with each cluster's color before and after;
   - **texture overlays** (brief `texture_overlays: [assets/overlays/<name>.png]`): composites checked-in overlay PNGs over the albedo after color correction. Make them with `blender -b --factory-startup -P scripts/make_texture_overlay.py -- --glb <cleaned glb> --uv-source <the clean stage's input glb> --out assets/overlays/<name>.png --size <texture_size> --stroke-z <m> --half-width <m>`. The clean stage fails if the overlay's sidecar hash doesn't match its input, so regenerate overlays after any model or rig regeneration;
   - records **mesh health** as a baseline and never fails on it: triangle/quad/n-gon counts and ratios, non-manifold edges, boundary edges and loops (holes), wire edges, loose vertices, degenerate faces, zero-length edges, and the **part count** (welded connected pieces, each with its triangles, vertices, size and open boundary loops). The part count is a rigging risk to watch on characters before auto-rigging. Everything is counted twice: as imported, and welded at 0.01 mm. The glTF importer doesn't merge vertices, so every UV seam shows up as an "as imported" boundary; the welded numbers are the real topology;
   - records the true dimensions (`true_dims_m`, `true_length_m`) after alignment;
   - checks the **triangle** count (n-gons count n−2), and **fails loudly when over budget. It never decimates, and a rigged mesh is never touched.** The fix is to regenerate at the brief's `face_limit`;
   - exports the GLB, then reads it back and fails if a texture was dropped.
4. **validate**. Runs `godot --headless -s scripts/godot_validate.gd` and imports the GLB with `GLTFDocument` at runtime (no `.import` files). It reports:
   - the bone names and a proposed mapping onto `SkeletonProfileHumanoid` (a name heuristic; confirm it in the editor's BoneMap), including missing required bones, which fail a character;
   - whether every socket in `socket_map` resolves to a bone;
   - the triangle count against the budget, and whether it matches stage 3's Blender count (GPU vertices are recorded as a metric only);
   - textures (size, count, extra maps; no albedo *and* no vertex colors fails);
   - each material's imported roughness, metallic and specular. It warns when specular is above 0; Godot 4.6 ignores glTF specular, so this currently always warns;
   - material transparency;
   - animations against the brief (missing ones only warn, since they'll come from the shared library).

## Judge (after every stage)

A fresh-context subagent rules on each stage's output from an evidence packet: `pass`, `revise` (with a concrete edit), or `escalate` (to the user). **Checkable questions only:** does it match the concept (or, with no concept, the brief's prompt), are the colors within tolerance, is anything missing or malformed, is it in budget, does the motion drift, slide, stretch or break. Style and taste always escalate.

```
python3 scripts/judge.py packet <asset-id> --stage concept|multiview|model|mesh|motion [--subject N] [--clip NAME --motion-dir DIR]
python3 scripts/judge.py record <packet-dir> <verdict.json>      # exit 0 pass, 5 revise, 6 escalate
python3 scripts/judge.py resolve <asset-id> --stage KEY --decision TEXT
python3 scripts/judge.py log <asset-id>
```

1. `pipeline.py` prints a `judge:` line after each stage that has something to judge: concepts while they wait for approval, then multiview, model (the raw download, **before** rig spend) and mesh (after validate).
2. `packet` copies every image the judge will see into `assets/manifests/<asset-id>/judge/<stage>-<n>/` (so the log keeps the exact render behind each verdict; the images stay local and gitignored, and the committed `packet.json` and log hold their SHA-256), adds metrics and numeric assertions (tolerances from the art bible's **Judge tolerances**, the only source), the stage's questions, and the brief's recorded design decisions. The model stage cleans the raw download into the packet's scratch `work/` and adds Tripo's uncorrected preview, because color correction can repaint a wrong color (blade attempt 1's olive blade came out bone).
3. Spawn the **`asset-judge`** subagent (`.claude/agents/asset-judge.md`, Read-only) with the packet path. Agent definitions load at session start, so in a session that began before the file existed, spawn a general-purpose agent told to Read that file, follow it, and use only Read. Save its reply to `verdict.json`.
4. `record` validates the reply, appends it to the manifest's `judgments` (with the images' hashes, and any the judge didn't report reading), and prints the next action:
   - **pass:** go on. A `pass` with failing assertions is recorded as `escalate`.
   - **revise:** one auto-refine per stage (`AUTO_REFINES_PER_STAGE`). `refine_concept` prints the `--refine N --edit` command and `reroll` a re-run: **both are paid, so they go through the tripo skill's confirmation like any other spend.** `library_change` (motion) is free: apply it, rebuild the library, re-run the motion review and judge again. A second `revise` for the same stage is recorded as `escalate`, regardless of what the judge said.
   - **escalate:** show the user the reason and findings. After they decide, `resolve` records the decision and resets the stage's refine budget.
5. **Replays** (`--replay NAME`, plus `--input`, `--concept`, `--no-design-notes`) judge historical inputs into `assets/manifests/judge_replays/NAME/` without touching the asset's manifest or mesh. Use `--no-design-notes` for an input judged before a recorded decision existed; otherwise the judge reads the decision.

**Motion review** (the motion stage's evidence), a windowed Godot run:

```
godot --path . res://scripts/review/motion_review.tscn -- --model res://assets/meshes/<id>.glb --library res://data/animations/<lib>.tres \
    [--clips a,b] [--ground-speed run=<m/s>] [--raw UAL1:Death01=death_raw] --out .tripo-out/<id>/motion[/<variant>]
```

For each clip it writes a timestamped 14-frame strip (side and three-quarter, origin marked), an onion skin (every frame overlaid blue to red over a 0.25 m grid, with the Hips path), plots (Hips offset, heights, ground-relative foot vs root speed with contacts shaded, per-frame bind deviation and stretch), a close-up of the worst skin-stretch frame, and `<clip>_metrics.json`. Pass each locomotion clip's gameplay speed (the table below) as `--ground-speed`, or the foot-slide numbers mean nothing. `--raw` reviews a pack clip before the build options (how the pre-fix death fling is replayed). Judge one packet per clip (`--stage motion --clip <name>`).

## Animation library (Quaternius, CC0)

`assets/animations/quaternius/UAL1_Standard.glb` and `UAL2_Standard.glb` (the Universal Animation Library 1 and 2, **Standard** tier, 43 clips each, non-root-motion) are committed. The extracted packs next to them are gitignored and have `.gdignore`. Both packs share one 65-bone Unreal-mannequin-style skeleton.

**Retargeting.** There are two BoneMaps onto SkeletonProfileHumanoid, one per bone-naming scheme: `data/rigs/quaternius_bone_map.tres` (both packs) and `data/rigs/mixamorig_bone_map.tres` (Tripo rig v1.0 characters). Both are generated by `scripts/tools/make_bone_maps.gd`. Each GLB's `.import` sets `retarget/bone_map` on `Armature/Skeleton3D`, and the characters also set `retarget/rest_fixer/fix_silhouette/enable`: the Barrow-levy is rigged in an A-pose and the library in a T-pose, and without it the levy's arms over-rotated down and behind the back in every clip. so Godot renames bones to profile names (`Hips`, `RightHand`, …) under a unique `%GeneralSkeleton`. Socket maps therefore use profile names; validate translates them back through the brief's `bone_map`.

**Libraries.** `scripts/tools/build_animation_library.gd` resamples each clip at 30 fps with its speed and trim baked in, keeps only the characters' 23 bones (fingers dropped), saves each unique clip once in `data/animations/clips/`, and writes one AnimationLibrary per character: `player`, `levy_frontfile` and `levy_backfile` in `data/animations/*_library.tres`. Each character scene has an `AnimationPlayer` under its model (`root_node ..`) using its library. Godot's importer strips a `_Loop` suffix from clip names. Contact sheets: `scripts/review/anim_sheet.tscn` (→ `assets/manifests/animation/*_sheet.png`); in-game check: `scripts/review/level1_play_capture.tscn`.

**Locomotion rule:** pick the clip whose native speed (root travel in the `_RM` file) is closest to the gameplay speed, keep playback within 0.75–1.5×, and change the gameplay speed rather than distort the clip. No loop in either pack sits between 1.05 and 5.36 m/s.

| Code plays | Character | Clip (pack) | Baked | Notes |
|---|---|---|---|---|
| `idle` | player | `Sword_Idle` (UAL1) | loop | sword-ready stance |
| `run` | player | `Jog_Fwd_Loop` (UAL1) | 0.93×, loop | native 5.36 m/s; the player moves at 5.0 |
| `dodge_roll` | player | `Roll` (UAL1) | trim 0.20–1.10 s, 1.8× → 0.5 s | dodge raised to 0.5 s at 8.4 m/s (the same 4.2 m) |
| `attack_light` | player | `Sword_Regular_A` (UAL2) | | all 3 combo hits use A. **Future code change:** per-hit names for `_A`, `_B`, `_C` |
| `attack_heavy` | player | `Sword_Regular_C` (UAL2) | | a spinning slash |
| `death` | player | `Death01` (UAL1) | in place | Hips/Root horizontal travel held at the first frame (the clip falls about 0.5 m backward) |
| `idle` | Front-file | `Sword_Idle` (UAL1) | loop | reads hunched and forward, the art bible's Front-file posture |
| `run` | Front-file | `Jog_Fwd_Loop` (UAL1) | 0.75×, loop | 4.0 m/s: **chase speed raised from 3.0 to 4.0** |
| `attack` | Front-file | `Sword_Regular_A` (UAL2) | | |
| `idle` | Back-file | `Idle_Loop` (UAL1) | loop | upright, the art bible's Back-file posture |
| `run` | Back-file | `Walk_Loop` (UAL1) | 1.44×, loop | 1.4 m/s: **speed lowered from 2.5 to 1.4**. Not `Walk_Formal_Loop`, which clasps the hands behind the back |
| `attack` | Back-file | `OverhandThrow` (UAL2) | | **STAND-IN for a bow draw.** No bow clip in either Standard pack; Quaternius's setup sheet shows `Bow_Aim_*` / `Bow_Notch` in a non-Standard UAL2 tier (not bought yet) |
| `stagger` | both levies | `Hit_Chest` (UAL1) | | 0.33 s for the 0.4 s stagger |
| `death` | both levies | `Death01` (UAL1) | in place | the enemy's velocity and navigation stop the frame death starts; it's freed after the clip (2.4 s), fading over the last 0.3 s through material alpha |

### Fixing a bad clip (the fix ladder)

**Quaternius stays the source.** This ladder fixes how its clips are applied to a character's rig. Step 3 means another Quaternius clip, and step 6 fills a gap the library can't cover; it never replaces the library.

**Step 0: diagnose before fixing.** Run the motion review and judge the clip. Then:
- The whole body is wrong (hip travel, drift, fling, foot slide) or the pose is wrong (arms behind the back, twisted limbs): use this ladder.
- The skin is wrong (stretch, tearing, clipping): it's a rig or weights problem, not animation. Fix it in the clean stage (skirt reweight, rigid rebind), as with the player's hem.
- It only happens in the game (the motion review looks fine): go straight to step 4.
- Every clip wrong the same way points to step 1; a single clip points to steps 2 or 3.

| Step | What changes | Where | Signs it's this step | Past case | Who decides |
|---|---|---|---|---|---|
| 1. Import and retarget | BoneMap, Fix Silhouette, rest-pose handling; the character's own rig if Tripo's rigger got it wrong | the character GLB's `.import`, `data/rigs/` | every clip wrong the same way | levy arms behind the back: Fix Silhouette | free; do it |
| 2. Build options | trim, speed (0.75–1.5×), loop, `in_place` | `build_animation_library.gd`, per clip | one clip's timing, length, drift, or an opening lurch | death fling: `in_place`; dodge roll trimmed to 0.5 s | free; the judge's auto-refine |
| 3. Different Quaternius clip | another clip from UAL1 or UAL2 | the library table above | the clip's pose is wrong for the character, not just its playback | `Walk_Formal_Loop` → `Walk_Loop` | free; the judge's auto-refine; note why in the table |
| 4. Game side | velocity and navigation, gameplay speed matched to the clip, blend times, held-prop alignment, upper-body layering | scripts and scenes | fine in the motion review, wrong in play | knockback carried into death; chase speed raised to the jog's | free, but it changes gameplay: show the user before merging |
| 5. Scripted correction | a held-pose clip or a per-bone rotation offset over a time range, generated by the build tool | `build_animation_library.gd` (not built yet) | a static pose or small offset no clip provides | none yet | the first use needs the user's OK (a new exception, like the rigid rebind) |
| 6. Fill a gap | the UAL2 tier with `Bow_*` clips, another CC0 pack, or Tripo presets (fallback) | outside the repo | a motion with real timing that neither pack has | the bow draw (open) | money or credits: always the user's call |
| 7. Accept and record | nothing; a `docs/decisions.md` entry | — | not visible at gameplay distance, or not worth the cost | player knee creases (POC) | the user |

Rules:
- **One step at a time.** Re-run the motion review and the judge after each, and stop when the numeric checks and the judge pass.
- **Fix at the most general level:** a fault in every clip is fixed once at step 1, not in each clip.
- **Don't trade one defect for another.** A fix that moves the problem elsewhere hasn't worked (`in_place` on `Death01` moved the hip travel into the feet).
- **Loosening a tolerance is not a step.** It's the user's decision, recorded with its reason in the art bible and `docs/decisions.md`.
- **Auto-refines cover steps 2 and 3 only,** within the judge's one-refine budget. Step 4 changes gameplay, and steps 5 to 7 need the user.
- **Never hand-key clips in Blender** (CLAUDE.md → Rigging & Animation).

## Resuming and idempotency

Every stage records the SHA-256 of its inputs (brief, source GLB, spend records, and the stage's own script) and outputs. A re-run skips a stage whose recorded hashes still match what's on disk, so editing the brief or a script re-runs exactly the affected stages. Nothing depends on a stored Tripo `task_id`: generated URLs expire about 5 minutes after success, so the tripo skill downloads in the same run, and the pipeline only ever reads files.

## Adding an asset

1. Write the brief in `docs/art-bible.md`, including the budget, `face_limit`, scale and pivot, and palette.
2. Copy it into `assets/briefs/<asset-id>.yaml`. Pick an ID that isn't an existing file name, because stage 3 refuses to overwrite its own input.
3. Run `python3 scripts/pipeline.py <asset-id> --stage all --dry-run`.
4. Run `--stage concept`, run the printed command through the tripo skill, and show the user the result. Repeat (`--variants`, `--refine`) until they approve one, then record it with `--approve-concept N`. Then `--stage multiview` and `--stage model` the same way: run each printed command through the tripo skill, then re-run the stage.
5. Run `--stage all` until it exits 0. Read the manifest's `clean.report` and `validate.report`.
6. Wire the asset in. Characters need a `SocketMap` (`data/rigs/<rig>_sockets.tres`) and a BoneMap in the GLB's import settings; props go into `held_props`.

### Sourced assets (downloaded CC0 kits)

**Generate what carries identity; download the rest** (art bible → Sourcing). Kit pieces (KayKit, Quaternius, Kenney) go through the same clean and validate stages as generated assets. There's no spend and no concept.

1. **Download** the pack with `curl` from its official URL (the author's own site or GitHub organisation) into `.downloads/<pack>/`, keep the zip, and extract it beside the zip. Never use the Blender MCP download tools. If a download needs a browser login, stop and ask the user.
2. **Import** the pieces with the pack helper. The first import of a pack records its provenance and settings in `assets/sources.json`; later runs read them back:
   ```
   python3 scripts/tools/import_pack.py .downloads/<pack>/<extracted> --pack <pack> --pieces wall floor_tile_large box_large:obj ...
       [--glob 'wall_*'] [--describe NAME=TEXT]
       # first import only:
       --title T --homepage URL --url <archive URL> --author A --license CC0-1.0 --version V --archive <zip> --license-file <path in pack>
       --palette "Wet Slate,Rain Stone,..." --budget "Sourced props (kit dressing)" --source-scale 1.0 --prefix <prefix>_ [--atlas-source <path in pack>]
   ```
   For each piece it writes `assets/briefs/<prefix><piece>.yaml` and the piece's `sources.json` entry, runs `pipeline.py <id> --stage all`, and prints the triangle count against the budget. It's idempotent. `--budget` names the art-bible budget line (`**Sourced props (kit dressing):**` under Budgets), or a section whose `**Budget:**` line supplies the triangle budget and texture size, so no number is written anywhere else. `--describe` gives the prompt the judge checks the piece against, so describe what the piece actually is.
3. **Judge** each piece at the mesh stage (`judge.py packet <id> --stage mesh`); the packet's `sourcing` block tells the judge there's no concept.

**The brief** has `source: download` plus `pack`, `source_url`, `author`, `license` and `source_file` (under `.downloads/`), and no Tripo fields (`face_limit`, `tripo_model`). It also has:
- **Orientation:** `orientation: source` (the default for sourced assets) keeps the kit's axes, since a wall or stair lives on the kit's grid. `principal_axis` (with `tip_end`) aligns a downloaded held prop the way generated props are aligned.
- **Pivot:** `pivot: source` keeps the kit's origin, which is its snap point (KayKit stairs start at their front edge). `base` and `center` recentre as usual.
- **Scale:** `source_scale` is the pack's uniform scale into metres, which keeps every piece on one grid. `target_size_m` instead fits the piece to a size.
- **Atlas:** `atlas` and `atlas_source` are for kits that share one texture atlas.

**Stages:**
- concept, multiview and rig report "not needed".
- **model** checks that `source_file` is on disk, that its SHA-256 matches `sources.json`, and that the licence is allowed.
- **clean** imports glTF, OBJ or FBX. It then keeps or sets orientation, pivot and scale as above, and applies the usual albedo rebuild, flat shading and triangle budget (it fails over budget and never decimates). Colour correction uses the palette fallback, since there's no concept, with two differences from generated assets: the groups are measured only over the texels the piece's UVs sample (its **UV footprint**: every texel whose center is inside a UV triangle, plus the texel under each UV vertex and centroid), and **lightness may be lowered as well as lifted**, since a kit's colors are its author's, not a darkened copy of the design. Generated assets keep lift-only and whole-texture metrics.
- **validate** runs as usual, and also fails when the asset has no `sources.json` entry, when its licence isn't CC0 (`ALLOWED_LICENSES` in `pipeline.py`), or when its provenance disagrees with the brief. CI runs the same check (`ci/validate_assets.py`, `ci/test_sources.py`).

**Shared atlases.** Kits usually put every piece on one texture atlas. The clean stage builds `assets/atlases/<pack>/<atlas>_<texture_size>.png` **once**: `blender_cleanup.py --atlas` downscales the atlas to `texture_size` and runs `palette_correct` on it, measured over the **union of the UV footprints of every piece on the atlas** (every brief naming it), with darkening allowed; the shift is applied to the whole atlas as one function of color. The JSON sidecar records the source hash, the palette, the clean script's hash, the pieces (with their source hashes and footprint sizes) and the correction report, and the atlas is rebuilt whenever one of those changes. **Importing another piece therefore re-corrects the atlas, and every piece's clean stage re-runs** on the next `pipeline.py` run (their input hashes include the atlas); re-run `import_pack.py` with the whole piece list, or `--stage all` per piece, then re-judge. Each piece's clean stage checks, by pixel hash, that its embedded texture is that atlas (it fails otherwise), then swaps in the corrected pixels without re-correcting them, so every piece ships byte-identical texture pixels. Each piece's `palette_correction` is measured over its own footprint (the embedded atlas downscaled the same way, before, against the corrected pixels, after), with the atlas-level correction kept as `atlas_correction`.

**Judging kit pieces.** The palette assertions read the piece's footprint metrics. Holes use the sourced-kit rule `mesh_kit_max_loops_per_part` (art bible → Judge tolerances) instead of `mesh_max_holes`: kit parts are open-backed shells (a wall body plus raised blocks flush on its face), so open loops are counted per welded part, and they're allowed only where none shows in the views, which the judge checks.

**Licences:** CC0 only. Any other licence fails validation, and allowing one is the user's decision, because it brings attribution duties this pipeline doesn't track.

## Tools

`scripts/tools/import_pack.py` imports sourced kit pieces (above).

`BLENDER` and `GODOT` environment variables override the defaults: `blender` / `godot` on PATH, then `/Applications/Blender.app/Contents/MacOS/Blender` and `/Applications/Godot.app/Contents/MacOS/Godot`.

## Known limits

- The Cycles bake path (albedo from a node chain) hasn't yet been exercised on a real asset.
- The humanoid mapping is a name heuristic (it covers Blender, Sketchfab and Mixamo naming). The editor's BoneMap is authoritative.
- The prop up-direction isn't detected; the socket's child `Transform3D` absorbs flips.
- Stage 4 renders `front`, `right`, `back` and `top` **with the albedo texture in true color** (the Standard view transform, since the default AgX made albedo look like grey clay), plus `clay_front` (grey, form only) and `wireframe_front` PNGs into `assets/manifests/<asset-id>/` (Blender Workbench, offline; `assets/manifests/.gdignore` keeps Godot from importing them). Gross-failure flags are warnings only: missing geometry (no triangles, or a view under 0.5% coverage) and holes (welded boundary loops). Fused parts need a human look at the renders.
- The budget unit is triangles. Vertex counts (as imported, split at UV seams; and welded) are recorded as metrics only; the first blade was 1,454 split and 519 welded for 1,026 triangles.
