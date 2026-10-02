---
id: spike-body-only-humanoid
title: "Spike: body plus separate clothing shells, with weight transfer"
status: ready
kind: spike
targets: []
after: []
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Decide whether humanoids are built as **one continuous weight source plus separate garment shells**, with weights transferred deterministically onto each shell (CLAUDE.md → Rigging & Animation, fourth exception), and whether that rescues P2's tidier shells. The research is done; the user approved **Phase 0** on 2026-10-02.

**Findings (research, 2026-10-02):** studios use a base body plus clothing that copies its weights from the body (Bodyslide "Copy Bone Weights"; Reallusion CC4 auto-skin with the inner mesh hidden). Tripo documents base body → segment → armour, and P2's shell separation is deliberate. Our P2 A/B tore because each shell got its own rigger weights (`docs/trials/tripo-p2.md`). There's no published evidence that an AI body plus AI garments beats a fused mesh, so this is a real spike.

## Scope

**Phase 0 (0 credits; approved).**
- **Input:** the paid P2 attempt-2 download and rig-2 in `.tripo-out/player/` (local, gitignored).
- **Weight source:** voxel-remesh the union of the shells into one continuous proxy and project rig-2's weights onto it.
- **Transfer** the proxy's weights back to every shell: first Blender Data Transfer (`POLYINTERP_NEAREST`), then, if needed, Robust Skin Weights Transfer via Weight Inpainting. **Reimplement that algorithm; don't copy the GPL-3 add-on's code.**
- **Hide** body faces fully covered by garments (BVHTree raycasts), and offset garments 3–5 mm.
- **Code** in `scripts/blender_cleanup.py`: `parts_weight_transfer`, `hide_covered_body` and the proxy builder. Brief schema: `parts: [{select, bind: rigid:<bone>|transfer, offset_mm}]`.
- Run the motion review on every clip.

**Phase 1 (about 80–140 credits; only if Phase 0 works, and only with the user's OK on a dry-run price).**
- Tripo `mesh segment` + `mesh complete` (ai_completion) on one clothed generation → body, tunic and boots sharing one UV texture; rig the completed body (25); apply Phase 0.
- A body-only mannequin from an edited concept (about 100) only if segmentation fails. Separately generated garments come last (fit risk).

**Risks:** ai_completion inventing a poor body; the robust transfer's dependencies in Blender (scipy is missing); the tunic may still need `skirt_reweight`-style grading; separate generations break fit and one-texture-per-asset.

## Acceptance

Phase 0 succeeds when, on the P2 player:
- edge stretch is below P1's (3.0–5.0) in every clip, ideally ≤ 1.0;
- a new **seam-gap metric** holds: vertices that touch at bind on different shells stay under 1 cm apart in every frame;
- no body vertex shows outside its garment;
- the mesh-stage judge passes;
- it stays within the player's triangle and texture budget in `docs/art-bible.md` (one texture).

Commit the code if it works and the findings (a `docs/trials/` note) if it doesn't. Phase 1 is a separate go decision for the user.

## Serves

`player-model-rework`; the skin-stretch metric (3–5× on the player today).
