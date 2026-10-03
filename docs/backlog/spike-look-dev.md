---
id: spike-look-dev
title: "Spike: look development — settle the art direction (A today, B limits lifted, C PS3+)"
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
