---
id: look-dev-c
title: "Look-dev C: a PS3-class PBR player from Tripo v3.1 (paid, about 85 credits)"
status: in-review
kind: spike
targets: []
after: [spike-look-dev]
phase: C
branch: spike/look-dev-c
pr: 52
updated: 2026-10-03
---
## Goal

Show the user what a higher target (PS3+) looks like on our own player before the art direction is settled: Tripo's default high-detail model (v3.1) with PBR materials, from the approved multiview-1 sheet, rendered through `scenes/lookdev/LookDev.tscn` next to A and B.

## Question

Is C worth about 85 credits (55–95; v3.1 has no observed price yet), given that B already recovers the face for free?

## Options

1. **Run C** without HD texture: the model (30–60, unconfirmed) plus the rig (25, observed). The exact `tripo make` and `tripo anim rig` commands and their free dry runs are in `docs/trials/look-dev.md` → C.
2. **Run C with `texture_quality=detailed`** (+10, the dry run warns of a higher price tier).
3. **Skip C**: adopt B's rules (`decide-art-direction`) and stay in the stylized lane.

## Recommendation

Decide `decide-art-direction` first. If B at 1024 px with B2 lighting satisfies the user, skip C; if the user still wants the PS3+ look, run option 1, since it reuses the approved multiview sheet and needs no concept spend. C also needs a variant clean that keeps the PBR maps and the high triangle count, under `assets/lookdev/` like B.

## Scope

- Variant C (user approved 2026-10-02, ~110 credits with the rig): a player from Tripo v3.1 (`v3.1-20260211`, PBR, standard texture, no `face_limit`) built from the approved multiview-1 sheet, then the v1.0 humanoid rig; the orchestrator runs the paid calls through the tripo skill
- Render it beside A and B2 in the look-dev scene (smooth shading, full PBR under Forward+, and an albedo-only Compatibility version), same shots

## Acceptance

- A | B2 | C sheets and a short write-up with cost, triangle count, texture sizes and frame time; the user decides whether the art direction moves to the C tier

## Serves

The art direction (`decide-art-direction`), `player-model-rework`.

## Outcome

Run 2026-10-02 for 55 credits (model 30, rig 25; balance 420 → 365). C as delivered is **1,434,038 triangles** (261× the 5,500 budget) with three 2048 px PBR maps (base colour, metallic-roughness, normal). Built as C-PBR (Forward+), C-albedo (1024 px, Compatibility, B2 lighting) and C-budget (decimated to 20k) under gitignored `assets/lookdev/` by `scripts/lookdev/build_c.sh`; it retargets through the shipped BoneMap unchanged. **C barely shows over B2:** nothing from the gameplay camera, a rounder face and finer hair spikes in the close-up, and PBR adds highlights, not form. It costs 80–120 MB of VRAM per character, a 57 MB GLB, and up to about 1 ms a frame on this Mac (within noise). Decimating it breaks the UVs and the skin (run stretch 33 against B1's 4.6). Recommendation: stay at B2, and try a face-limited v3.1 (`look-dev-c-face-limit`, paid) if the face shape matters. Write-up and sheets: `docs/trials/look-dev.md` → Variant C.
