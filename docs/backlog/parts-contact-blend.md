---
id: parts-contact-blend
title: "Blend a keep shell's weights toward the source near its contact (collar poke-through)"
status: proposed
kind: chore
targets: []
after: [spike-body-only-humanoid]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

On `player_p2parts`, the body's collar (Shoulder/Neck/Head blended) comes out through the head shell's neck (100% Head) by up to 4.6 cm when the head turns; that's 4–7 poke-through vertices per clip (`docs/trials/body-only-humanoid.md`). A plain `transfer` from the body would drag the hair onto the neck.

## Scope

- A `bind: blend` (or a `blend_m` part key): the shell keeps its own weights beyond a distance from the source and takes the source's at contact, inpainted in between (the harmonic fill already in `blender_cleanup.py`).
- Require normal agreement for a contact, so neighbouring limbs (the crotch) never share weights.
- Make the seam-gap poke test skip a shell's own underside (the harness straps count falsely now).

## Acceptance

`player_p2parts`: poke-through 0 in every clip, seam gap still under 1 cm, edge stretch no worse.

## Serves

`spike-body-only-humanoid` acceptance (no body vertex outside its garment); `player-model-rework`.
