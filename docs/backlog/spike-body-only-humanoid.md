---
id: spike-body-only-humanoid
title: "Spike: body plus separate clothing shells, with weight transfer"
status: done
kind: spike
targets: []
after: []
phase: C
branch: spike/body-only-humanoid
pr: 47
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

## Outcome

**Final (user, 2026-10-02):** P2 with weight transfer was playtested and not adopted: more clipping than P1 and little visual gain. P1 stays the player. The tools (parts schema with keep/transfer/rigid/cover, weight transfer, hide-covered-body, the seam-gap metric, shell overlays) are merged for the eventual player rework. True body-plus-separate-clothing (Phase 1, segment + complete) was never tried; it waits on the look-dev art direction.


**Phase 0 partly works, but not by the planned route** (`docs/trials/body-only-humanoid.md`; 0 credits). The P2 player was built as the separate asset `player_p2parts`, and the shipped P1 player is untouched.
- **The planned voxel proxy fails.** It closes the seams, but it fuses the legs at the crotch: stretch 21–40×, with either Data Transfer or the reimplemented inpainting (numpy CG, no scipy).
- **What works is keep + transfer.** The body, head and legs keep the rig's weights and the harness copies from them, 4 mm out.
- **Results:**
  - seam gap 0.52–0.71 cm in every clip (6.7–14.9 cm before);
  - stretch 1.60–4.38, below P1's in 5 of 6 clips (dodge_roll 4.38 against 3.88);
  - 4,437 triangles and one texture.
- **Failing:** poke-through (4–7 vertices, the collar under the head shell → `parts-contact-blend`). The mesh packet has two failing assertions (17 holes, the dark-navy share), so the judge will escalate.
- **The A/B's tearing** was mostly `skirt_reweight` catching the boot cuffs. The real tear was the harness.
- **Phase 1** isn't recommended yet (`decide-player-p2parts`). `tripo mesh segment` has no `--dry-run`, so there's no free price.

**Phase 0b** (free, approved after all 7 judge verdicts escalated):
- **Changes:** the tunic is graded on the body shell only, and the head and legs are `cover` shells. That removes the collar under the neck (18 faces) and fixes the poke test's backside false positives.
- **Poke-through:** 2–5 vertices per clip (worst 0.3–2.7 cm), from 4–7 (1.1–4.6 cm). All of them are at one front chest-strap spot, possibly a metric artefact.
- **Seam gap and stretch:** unchanged (0.52–0.71 cm; 1.85–4.38, below P1 in 5 of 6 clips).
- **Skin in the slit:** it's the leg shells' tops, which Tripo painted in skin tones (`p2parts-leg-top-albedo`).
- **"Spike edges":** refuted. The longest edge is 0.20 m against P1's 0.187.
- **Recommendation:** start the player rework from P2 with transfer (`decide-player-p2parts`). The judge packets (mesh-1 and motion-*-2) wait for the judge.
