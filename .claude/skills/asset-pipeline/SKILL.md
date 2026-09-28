---
name: asset-pipeline
description: Orchestrates 3D asset production for this project with scripts/pipeline.py. It owns briefs, stage order (concept → multiview → model → rig → clean → validate), Blender cleanup, Godot validation and the per-asset manifest. Use when creating, regenerating, cleaning or validating any mesh in assets/meshes/.
---

# Asset pipeline (orchestrator)

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
| `.tripo-out/<asset-id>/` | Tripo downloads, spend records, and `work/` (stage parameters, reports, logs) | no |

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
   - **flat shading:** clears the imported custom normals, then flat-shades every edge sharper than 30° (`SMOOTH_ANGLE_DEG`). Unrigged meshes are welded first so UV-seam splits don't read as hard edges; this keeps UVs and the triangle count;
   - bakes the albedo with Cycles when it comes from a node chain rather than an image (one material only);
   - downscales the texture to `texture_size`, and fails if there's more than one texture;
   - **rigid rebind** (briefs with `rigid_parts: true` only, and never for continuous-skin characters): binds each disconnected part at weight 1.0 to the weighted bone nearest its center, and reports each part's bone and its share before the rebind in `rigid_rebind`;
   - **color correction:** moves the albedo toward the **approved concept** (the palette hex values are the fallback for assets with no concept). It takes 8 main colors from the concept, clusters the texture starting from them, restores hue and saturation fully, and lifts lightness (never lowers it) to the matched concept tone. Colors further than 30 ΔE from every cluster don't move. Reported in `color_correction` (or `palette_correction` for the fallback) with each cluster's color before and after;
   - records **mesh health** as a baseline and never fails on it: triangle/quad/n-gon counts and ratios, non-manifold edges, boundary edges and loops (holes), wire edges, loose vertices, degenerate faces, zero-length edges, and the **part count** (welded connected pieces, each with its triangles, vertices and size). The part count is a rigging risk to watch on characters before auto-rigging. Everything is counted twice: as imported, and welded at 0.01 mm. The glTF importer doesn't merge vertices, so every UV seam shows up as an "as imported" boundary; the welded numbers are the real topology;
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

## Resuming and idempotency

Every stage records the SHA-256 of its inputs (brief, source GLB, spend records, and the stage's own script) and outputs. A re-run skips a stage whose recorded hashes still match what's on disk, so editing the brief or a script re-runs exactly the affected stages. Nothing depends on a stored Tripo `task_id`: generated URLs expire about 5 minutes after success, so the tripo skill downloads in the same run, and the pipeline only ever reads files.

## Adding an asset

1. Write the brief in `docs/art-bible.md`, including the budget, `face_limit`, scale and pivot, and palette.
2. Copy it into `assets/briefs/<asset-id>.yaml`. Pick an ID that isn't an existing file name, because stage 3 refuses to overwrite its own input.
3. Run `python3 scripts/pipeline.py <asset-id> --stage all --dry-run`.
4. Run `--stage concept`, run the printed command through the tripo skill, and show the user the result. Repeat (`--variants`, `--refine`) until they approve one, then record it with `--approve-concept N`. Then `--stage multiview` and `--stage model` the same way: run each printed command through the tripo skill, then re-run the stage.
5. Run `--stage all` until it exits 0. Read the manifest's `clean.report` and `validate.report`.
6. Wire the asset in. Characters need a `SocketMap` (`data/rigs/<rig>_sockets.tres`) and a BoneMap in the GLB's import settings; props go into `held_props`.

## Tools

`BLENDER` and `GODOT` environment variables override the defaults: `blender` / `godot` on PATH, then `/Applications/Blender.app/Contents/MacOS/Blender` and `/Applications/Godot.app/Contents/MacOS/Godot`.

## Known limits

- The Cycles bake path (albedo from a node chain) hasn't yet been exercised on a real asset.
- The humanoid mapping is a name heuristic (it covers Blender, Sketchfab and Mixamo naming). The editor's BoneMap is authoritative.
- The prop up-direction isn't detected; the socket's child `Transform3D` absorbs flips.
- Stage 4 renders `front`, `right`, `back` and `top` **with the albedo texture in true color** (the Standard view transform, since the default AgX made albedo look like grey clay), plus `clay_front` (grey, form only) and `wireframe_front` PNGs into `assets/manifests/<asset-id>/` (Blender Workbench, offline; `assets/manifests/.gdignore` keeps Godot from importing them). Gross-failure flags are warnings only: missing geometry (no triangles, or a view under 0.5% coverage) and holes (welded boundary loops). Fused parts need a human look at the renders.
- The budget unit is triangles. Vertex counts (as imported, split at UV seams; and welded) are recorded as metrics only; the first blade was 1,454 split and 519 welded for 1,026 triangles.
