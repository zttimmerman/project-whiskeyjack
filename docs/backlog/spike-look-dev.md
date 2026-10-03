---
id: spike-look-dev
title: "Spike: look development — settle the art direction (A today, B limits lifted, C PS3+)"
status: done
kind: spike
targets: []
after: []
phase: C
branch: spike/look-dev
pr: 50
updated: 2026-10-02
---
## Goal

Decide the game's art direction from evidence, before more asset work. The user (2026-10-02): models read as "OG RuneScape at best, not even PS1 or PS2", and the KayKit kit reads as Roblox. Likely causes, mostly our own rules: forced flat shading (edges > 30°), 256 px AI textures (Tripo's soft textures lose the face at that size; PS2 art was hand-painted), generators pushed away from their strengths, flat dark lighting, and no single style (toy-like KayKit next to Tripo characters).

## Scope

Render the **same player and the same Level 1 room**, side by side, from the gameplay camera and a close-up:
- **A, today:** as shipped.
- **B, limits lifted (free):** smooth shading (no forced flat-shade), Tripo's full-resolution texture (the raw download's, not 256 px), and better lighting within reason (ambient, fill, fog, vertex lighting or the Forward+ renderer as a variant). Uses files already on disk; no paid calls.
- **C, PS3+ target (paid, later, the user confirms the dry-run price):** a player from Tripo's default high-detail model with PBR materials, under Forward+.

Stop after A and B with a comparison sheet and a short write-up; the user decides whether C is worth the credits. Nothing in the shipped game changes in this spike.

## Acceptance

- A vs B comparison sheet (gameplay camera, close-up face, the room), with the settings for each, and frame times on this Mac for each variant
- A recommendation on which art-bible rules to change, with the trade-offs (animation and lighting show more at higher fidelity, cost per asset, renderer)

## Serves

The art bible, `player-model-rework`, Phase C kit choice (a kit in the chosen style instead of KayKit).

## Outcome

A and B done at 0 credits (`docs/trials/look-dev.md`; tools in `scenes/lookdev/` and `scripts/lookdev/`; nothing shipped changed). **256 px is what loses the face:** even smooth-shaded, the 256 px albedo smears the eyes and nose; 512 px brings them back and 1024 px is close to the 2048 px source. Smooth shading removes the facets but needs better lighting to hold up. **B2 lighting** (warmer ambient, filmic tonemap, depth fog, warmer torches with a steeper falloff) is the biggest change from the gameplay camera and runs in Compatibility. **Forward+ alone changes 0.3% of the image**; its SSAO and torch shadows are subtle. The crypt brush shell sits with the smooth player better than the KayKit room. Every variant runs at 1–4 ms a frame (M2 Pro, 1280×720; Forward+ locks to 120 Hz at 2560×1440). The rule changes are `decide-art-direction` (needs-user). **C is prepared, not run:** v3.1 with PBR from the approved multiview-1 sheet, then the v1.0 rig, both commands dry-run valid, about 85 credits (55–95, unconfirmed), in `look-dev-c` (needs-user).
