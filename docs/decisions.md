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
- **The art bible is the only source of budget numbers.** Briefs copy them; skills and scripts never hardcode them.

## Observed Tripo costs

- P1 text-to-3D with a standard texture: **40 credits** (twice: attempts 1 and 2). The pricing page's 20 was the H-series price, so it undercounted P1 by 2×. The CLI's `credits_consumed` matched the balance difference every time.
- banana_pro text-to-image (`template=t_pose`, 3:4): **15 credits**, matching the estimate and the CLI's report (Barrow-levy concept-1).
- banana_pro image-to-image refine (same params): **15 credits**, the same as text-to-image (Barrow-levy concept-2).
- **Chained refines converge when the edit is short.** A five-item refine landed 3 of 5 changes (concept-2); a two-item follow-up ("keep everything exactly as it is except …") landed both and preserved the rest (concept-3). Budget 2–3 images per character concept.
- **Three concept images per asset, at most.** This is about cost, and also about drift: each chained image-to-image pass degrades the image a little. By the third, the background had picked up a lighter centre instead of staying even grey, and edges were over-sharpened with slight color banding (Barrow-levy concept-3). Both feed straight into multiview.
- Not yet observed: seedream_v5, image-to-multiview, multiview-to-3D. Add each to the tripo skill's table after its first run.
- Project spend so far: 125 (80 on the blade, 45 on Barrow-levy concepts 1–3); balance 875.

## Open risks

- **Shipped skeleton toe bones sit at the origin in rest pose** (`toe.L_017`, `toe.R_021`), so they'll mis-pivot under retargeting.
- **Shipped skeleton hands are single bones with no finger chain,** so none of the 30 finger bones in `SkeletonProfileHumanoid` map.
- **Tripo's overshoot is unverified on characters.** The 10% triangle headroom rests on a single prop (+2.6% at `face_limit` 1000).
- **The blade's grip wrap has 4 small slits and 16 non-manifold edges** (recorded, not repaired). Mesh health is a baseline only; nothing fails on it yet.
- **The Barrow-levy socket map still names the Sketchfab bones.** Stage 4 fails until `data/rigs/barrow_levy_sockets.tres` is updated for the new rig.

## Next

- Build pipeline stages 1–3 as the chain text-to-image (banana_pro) → image-to-multiview → multiview-to-3D, with a stop for concept approval. Then run the Barrow-levy through it and record each new stage's observed cost.
