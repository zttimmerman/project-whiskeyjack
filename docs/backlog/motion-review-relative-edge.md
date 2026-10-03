---
id: motion-review-relative-edge
title: "Motion review: an edge floor that scales with mesh density"
status: proposed
kind: fix
targets: []
after: []
phase: later
branch: null
pr: null
updated: 2026-10-03
---
## Goal

The motion review skips edges under 1 cm (`MIN_EDGE`), which suits 5k-triangle characters but leaves a dense mesh unmeasured: look-dev C (1.43M triangles, edges about 2 mm) read a skin stretch of 0.014. It also CPU-skins every vertex in GDScript, about 4 minutes a clip at 740k vertices.

## Scope

- only if characters get a higher budget: a floor relative to the mesh's median edge (or stretch measured over 1 cm geodesic spans), and a vertex sample for dense meshes; humanoid results at today's budget unchanged

## Acceptance

- the shipped player's metrics unchanged; a dense mesh reports a stretch comparable to its decimated copy's

## Serves

The motion gates, a possible C-tier character budget (`look-dev-c-face-limit`).
