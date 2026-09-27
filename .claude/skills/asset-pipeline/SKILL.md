---
name: asset-pipeline
description: Orchestrates 3D asset production for this project with scripts/pipeline.py. It owns briefs, stage order (concept → model → clean → validate), Blender cleanup, Godot validation and the per-asset manifest. Use when creating, regenerating, cleaning or validating any mesh in assets/meshes/.
---

# Asset pipeline (orchestrator)

**Layering:** this skill orchestrates; the **tripo** skill (`.claude/skills/tripo/`) is the vendor adapter. Any paid `tripo` call, including concept images and models, follows the tripo skill: its confirmation flow, credit cap, balance checks and URL-expiry rules. None of those are repeated here. `pipeline.py` never runs a paid `tripo` command; it prints the command, and the agent runs it through the tripo skill.

**Budgets:** `docs/art-bible.md` is the only source of budget numbers (vertex budget, texture size, `face_limit`, target size, pivot, palette). Each asset carries them in its brief YAML. To change a number, change the art bible first, then copy it into the brief. Never write a number into this skill, the tripo skill, or a script.

## Command

```
python3 scripts/pipeline.py <asset-id> --stage <concept|model|clean|validate|all> [--dry-run] [--force]
```

- `--dry-run` prints what each stage would do and writes nothing.
- `--force` re-runs a stage even if its inputs are unchanged.

| Exit code | Meaning | What to do |
|---|---|---|
| 0 | ok or up to date | nothing |
| 1 | error (bad brief, missing tool) | fix the cause |
| 2 | a stage check failed | read the stage's `message`/`report` in the manifest |
| 3 | waiting on a Tripo run | run the printed command through the tripo skill, then re-run the stage |

## Files

| Path | What | In git? |
|---|---|---|
| `assets/briefs/<asset-id>.yaml` | brief: `asset_id`, `type` (character\|prop), `brief`, `prompt`, `face_limit`, `vertex_budget`, `texture_size`, `target_size_m`, `pivot` (base\|center), `palette` (names from the art bible), plus optional `source_glb`, `socket_map`, `animations`, `exclude_objects` | yes |
| `assets/manifests/<asset-id>.json` | one entry per stage: status, timestamp, inputs and outputs with SHA-256 hashes, prompt, parameters, actual cost in credits, tool versions (Python, Blender, Godot, tripo), and the stage report | yes |
| `assets/meshes/<asset-id>.glb` | the cleaned output of stage 3 | yes |
| `.tripo-out/<asset-id>/` | Tripo downloads, spend records, and `work/` (stage parameters, reports, logs) | no |

The brief YAML uses a strict subset: top-level keys, scalars, `[inline lists]`, `- item` lists, and `|` blocks. No PyYAML is needed.

## Stages

Prompts are composed from `docs/art-bible.md` → Prompt blocks: concept images get FORM + LIGHTING + the brief's `prompt`; 3D models get FORM + the brief's `prompt`.

1. **concept** (optional, never blocks). Resolves the prompt. If a concept image exists under `.tripo-out/<id>/concept-<n>/`, the stage ingests it and the model stage uses it (image-to-3D). Otherwise it prints the `tripo generate text-to-image` command for an optional concept pass.
2. **model**. Uses the brief's `source_glb` for existing assets. Otherwise it ingests the newest usable Tripo download (`attempt-<n>`, skipping attempts whose spend record is `rejected`, `lost` or `failed`) and copies every attempt's spend record into the manifest. If nothing is on disk, it prints the `tripo make` command with the brief's parameters and exits 3.
3. **clean**. Runs `blender -b --factory-startup -P scripts/blender_cleanup.py`:
   - removes Blender's importer-made bone display shapes, and anything listed in `exclude_objects`;
   - fails if a rigged asset has a mesh that isn't attached to the armature;
   - characters: detects facing from the foot bones (heel to toe), falling back to the foot geometry, and snaps to −Y;
   - props: turns the longest axis to +Z (which end points up is flagged as unverified);
   - scales to `target_size_m` (height for characters, length for props) and puts the base or center at the origin;
   - rebuilds every material as albedo-only (a Principled BSDF with base color, plus cutout alpha through Round so glTF writes MASK), dropping normal, roughness, metallic, specular, emission and occlusion maps, and turning unlit/emission setups into albedo;
   - bakes the albedo with Cycles when it comes from a node chain rather than an image (one material only);
   - downscales the texture to `texture_size`, and fails if there's more than one texture;
   - checks the vertex count, and **fails loudly when over budget. It never decimates, and a rigged mesh is never touched.** The fix is to regenerate at the brief's `face_limit`;
   - exports the GLB, then reads it back and fails if a texture was dropped.
4. **validate**. Runs `godot --headless -s scripts/godot_validate.gd` and imports the GLB with `GLTFDocument` at runtime (no `.import` files). It reports:
   - the bone names and a proposed mapping onto `SkeletonProfileHumanoid` (a name heuristic; confirm it in the editor's BoneMap), including missing required bones, which fail a character;
   - whether every socket in `socket_map` resolves to a bone;
   - the vertex count (the GPU count is reported, and the stage-3 Blender count decides against the budget);
   - textures (size, count, extra maps; no albedo *and* no vertex colors fails);
   - material transparency;
   - animations against the brief (missing ones only warn, since they'll come from the shared library).

## Resuming and idempotency

Every stage records the SHA-256 of its inputs (brief, source GLB, spend records, and the stage's own script) and outputs. A re-run skips a stage whose recorded hashes still match what's on disk, so editing the brief or a script re-runs exactly the affected stages. Nothing depends on a stored Tripo `task_id`: generated URLs expire about 5 minutes after success, so the tripo skill downloads in the same run, and the pipeline only ever reads files.

## Adding an asset

1. Write the brief in `docs/art-bible.md`, including the budget, `face_limit`, scale and pivot, and palette.
2. Copy it into `assets/briefs/<asset-id>.yaml`. Pick an ID that isn't an existing file name, because stage 3 refuses to overwrite its own input.
3. Run `python3 scripts/pipeline.py <asset-id> --stage all --dry-run`.
4. Run `--stage concept` / `--stage model`, then run the printed command through the tripo skill, then re-run the stage.
5. Run `--stage all` until it exits 0. Read the manifest's `clean.report` and `validate.report`.
6. Wire the asset in. Characters need a `SocketMap` (`data/rigs/<rig>_sockets.tres`) and a BoneMap in the GLB's import settings; props go into `held_props`.

## Tools

`BLENDER` and `GODOT` environment variables override the defaults: `blender` / `godot` on PATH, then `/Applications/Blender.app/Contents/MacOS/Blender` and `/Applications/Godot.app/Contents/MacOS/Godot`.

## Known limits

- The Cycles bake path (albedo from a node chain) hasn't yet been exercised on a real asset.
- The humanoid mapping is a name heuristic (it covers Blender, Sketchfab and Mixamo naming). The editor's BoneMap is authoritative.
- The prop up-direction isn't detected; the socket's child `Transform3D` absorbs flips.
