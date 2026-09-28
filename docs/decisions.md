# Decisions (asset pipeline)

Settled choices with their one-line reasons. Read this before re-opening any of them. Dates are 2026-09-27 unless noted.

## Settled

- **Budgets are in triangles, not vertices.** Vertex counts move with UV-seam splitting (the blade was 1,454 as imported but 519 welded, for 1,026 triangles), while triangles are what `face_limit` controls and Godot reports stably. The budget is `face_limit` + 10%.
- **Prompts describe what is there, never "no X".** "No crossguard" failed twice (a thick bar in attempt 1, a thin plate in attempt 2); positive shape and concrete color fixed the color and shrank the guard.
- **Image-to-3D over text-to-3D.** Text alone gives no spatial control against Tripo's strong priors. A concept image does, and iteration happens at the image stage (~15 credits) instead of the model stage (40).
- **The concept image is approved before any 3D spend.** The pipeline stops after the concept stage and waits for the user.
- **banana_pro is the default concept model; seedream_v5 sits behind a flag** for cheap multi-variant exploration. banana_pro is in the CLI's text-to-image whitelist, so it accepts text-only prompts (from the CLI's code and docs; no live call has confirmed it yet).
- **The FORM prompt block goes on image and 3D prompts. Concepts get flat, shadowless CONCEPT LIGHTING on a plain background; the torchlit MOOD LIGHTING is for mood/reference images only.** Multiview-to-3D takes no prompt, so the concept image is FORM's only channel to the mesh, and any directional light in it bakes into the albedo and misleads reconstruction. (Revised 2026-09-27; concepts were torchlit before.)
- **Prompts use plain colors, never palette names.** The pipeline swaps each name for the art bible's plain color, since image models can't resolve "Old Bone" (the same failure as the blade's green sword).
- **Briefs prompt silhouette-level shapes only; wear and small marks go in the albedo.** At `face_limit` 5,000, fine detail vanishes or eats the budget (the blade put 84% of its triangles into the grip wrap).
- **Quaternius + BoneMap over Tripo retarget.** Quaternius is CC0, so the raw animation files can live in this public repo (Mixamo allows shipping its animations in a game but forbids redistributing the raw files, which a public GitHub repo does). Tripo's retarget costs 10 credits per animation per character (7 clips × 4 characters = 280 credits, recurring), while Godot's BoneMap retargeting is free and done once across every character.
- **`pipeline.py` prints `tripo` commands and never runs them.** A subprocess would bypass Claude Code's permission prompt, and non-interactive runs auto-add `--yes`, so the chat confirmation plus the permission gate are the only spend control.
- **The Tripo model is pinned per brief (`tripo_model: P1-20260311`).** The CLI's auto-selection depends on prompt wording and `face_limit`.
- **Props are aligned on their principal axis, and the thinner end is placed at the brief's `tip_end`.** Blade attempt 1 passed every other check while 46° off-axis (45% too long) and upside down.
- **The rig model follows the body plan, not recency.** Tripo's rig docs (developers.tripo3d.ai/en/docs/animations-rig): `v1.0-20240301` is the server default, biped-only and recommended for humanoids; `v2.5-20260210` is the creature rigger (quadruped, hexapod, octopod, serpentine, aquatic, avian). The pipeline defaults to v1.0 and keeps `--rig-model` for creatures such as the Sett-boar. We had it backwards at first: v2.5 on the Barrow-levy returned generic limb chains.
- **Rigid rebind for rigid-part characters** (brief `rigid_parts: true`): each disconnected part goes at weight 1.0 to its nearest weighted bone. This is an explicit exception to CLAUDE.md's no-weight-scripting rule, because it's a deterministic algorithm rather than hand-tuning. It never applies to continuous-skin characters.
- **Quaternius stays the animation source; Tripo's rig v1.0 presets (90+) are a fallback only.** The reasons are the same as for Quaternius over Tripo retarget: licensing, and cost per character.
- **Characters: raw download → Tripo auto-rig → clean.** Tripo's rigger reads models in Tripo's own +X orientation, and the clean stage rotates characters to −Y, so the cleaned Barrow-levy rig-checked as unriggable while the raw download was a riggable biped (both checks free).
- **Cleanup corrects the albedo toward the palette.** Tripo's texture pass desaturates (bone #A89C86 against Old Bone #CCB484, likely its `delight` step). The correction is deterministic and driven by the brief's palette subset (art bible → Shading and palette correction).
- **Specular 0 is set at import in Godot**, by a glTF import extension (`addons/stylized_materials`), because Godot 4.6 ignores glTF's own specular. It was chosen over a per-GLB import script, which every new asset's fresh `.import` would silently miss, and over a shared enemy material, which covers only enemies and would have to override per-asset albedo.
- **The art bible is the only source of budget numbers.** Briefs copy them; skills and scripts never hardcode them.

## Observed Tripo costs

- P1 text-to-3D with a standard texture: **40 credits** (twice: attempts 1 and 2). The pricing page's 20 was the H-series price, so it undercounted P1 by 2×. The CLI's `credits_consumed` matched the balance difference every time.
- banana_pro text-to-image (`template=t_pose`, 3:4): **15 credits**, matching the estimate and the CLI's report (Barrow-levy concept-1).
- banana_pro image-to-image refine (same params): **15 credits**, the same as text-to-image (Barrow-levy concept-2).
- **Chained refines converge when the edit is short.** A five-item refine landed 3 of 5 changes (concept-2); a two-item follow-up ("keep everything exactly as it is except …") landed both and preserved the rest (concept-3). Budget 2–3 images per character concept.
- **Three concept images per asset, at most.** This is about cost, and also about drift: each chained image-to-image pass degrades the image a little. By the third, the background had picked up a lighter centre instead of staying even grey, and edges were over-sharpened with slight color banding (Barrow-levy concept-3). Both feed straight into multiview.
- image-to-multiview: **10 credits**, matching the CLI's report (Barrow-levy multiview-1). It returns four 1024² JPEGs on a white background.
- P1 multiview-to-3D at `face_limit` 5000: **50 credits**, matching the CLI (Barrow-levy attempt-1). That's 10 more than P1 text-to-3D.
- Tripo auto-rig (biped, `v2.5-20260210` requested): **25 credits**, matching the CLI (Barrow-levy rig-1). Rig-check is free (0 credits, twice).
- Not yet observed: seedream_v5. Add each to the tripo skill's table after its first run.
- Project spend so far: 235 (80 on the blade; Barrow-levy 155: concepts 45, multiview 10, model 50, rigs 50); balance 765.

## Open risks

- **Shipped skeleton toe bones sit at the origin in rest pose** (`toe.L_017`, `toe.R_021`), so they'll mis-pivot under retargeting.
- **Shipped skeleton hands are single bones with no finger chain,** so none of the 30 finger bones in `SkeletonProfileHumanoid` map.
- **Tripo's overshoot is unverified on characters.** The 10% triangle headroom rests on a single prop (+2.6% at `face_limit` 1000).
- **The blade's grip wrap has 4 small slits and 16 non-manifold edges** (recorded, not repaired). Mesh health is a baseline only; nothing fails on it yet.
- **The Barrow-levy socket map still names the Sketchfab bones.** Stage 4 fails until `data/rigs/barrow_levy_sockets.tres` is updated for the new rig.

- **Tripo's first auto-rig of the Barrow-levy is lopsided** (rig-1, 25 credits). `--spec mixamo` was accepted but ignored: it returned Tripo's generic 22-bone limb rig (`tripo::0_Left_Limb_0`…), which no name heuristic maps to SkeletonProfileHumanoid. The right arm is correct (collarbone, upper arm, forearm, hand). The **left arm is one bone short:** its elbow sits mid upper arm and there's no left hand bone, which is the bow socket. The thighs are only about 55% weighted to the thigh bone, the foot bones point down instead of forward, and two stray bones (`bone_20`, `bone_21`) stick out of the chest and back.
- **Observation, not a rule:** the docs list `spec` as a top-level rig parameter (default `tripo`, alternative `mixamo`) with no model restriction, yet the v2.5 run ignored it. That stays unexplained.
- **Barrow-levy rigid rebind results:** the pelvis and belt went to Hips at 1.00 (the pelvis was 0.26 before), the lower ribs to Spine1 at 1.00 (0.22–0.55 before, partly on the arms), and every limb, the skull and both hands to their own bones at 1.00. **Known quirk:** the Foot bones sit at floor level, so the feet bind to ToeBase, Foot's child. That's harmless, because Quaternius drives Foot and not the toes, and it won't read at gameplay distance.
- **Rig v1.0 (`v1.0-20240301`) honoured `--spec mixamo` where v2.5 didn't** (Barrow-levy rig-2, 25 credits). It returned 23 `mixamorig:` bones with symmetric chains, including LeftHand, and every SkeletonProfileHumanoid required bone maps. No doc limits `spec` to certain rig models; this one observation suggests v2.5 ignores it. The limbs are clean (each arm and leg segment 0.96–1.00 on its own bone). The weight defects are in the torso: the pelvis and belt are split across both thigh bones (Hips 0.37), a few lower ribs are partly on the arm bones, and the foot bones sit at the floor, so the feet are half on the shin and half on the toe. This is **one asset with near-worst-case input** (35 disconnected pieces with gaps at every joint), not a verdict on Tripo's rigger; the player (continuous limbs, a solid tunic) is the real test.
- **Rigged meshes aren't welded, so UV seams render hard.** The faceted-face ratio went from 13% (welded, unrigged) to 24% (rigged). It isn't visible in 512 px review renders. Welding rigged meshes wherever the coincident vertices share identical skin weights would fix it; not done yet.
## Next

- **Queued:** weld rigged meshes wherever coincident vertices carry identical skin weights, to undo the 13.2% → 24.4% faceting change on every character.

- Build pipeline stages 1–3 as the chain text-to-image (banana_pro) → image-to-multiview → multiview-to-3D, with a stop for concept approval. Then run the Barrow-levy through it and record each new stage's observed cost.
