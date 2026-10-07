---
id: spike-mixamo-library
title: "Spike: Mixamo as the animation library, instead of or beside Quaternius"
status: proposed
kind: spike
targets: []
after: []
phase: C
branch: null
pr: null
updated: 2026-10-07
---
## Goal

The user asked (2026-10-07) whether to switch to Mixamo. Find out if it can fill the library's gaps (bow, strafe, more combat clips) where UAL2 Source would cost money under Quaternius's new licence.

## Scope

- Licence first: Adobe's Mixamo terms allow use in games, but check whether committing the downloaded or retargeted clips to a public repo counts as redistribution. If it does, the spike stops or the clips stay in a gitignored folder with a build step.
- Workflow: downloads are manual through an Adobe account, with no API; record how a clip gets in reproducibly (provenance in `assets/sources.json`, hashes).
- Fit: our Tripo v1.0 rigs already use `--spec mixamo` bone names; retarget 2–3 clips (a bow draw, a strafe) through a BoneMap and run them through the motion review gates.

## Acceptance

- A trial note in `docs/trials/mixamo.md` with the licence finding, the workflow and the motion-review results.
- A recommendation: switch, add beside Quaternius, or don't.

## Serves

Animation library (CLAUDE.md → Rigging & Animation); the gaps behind `ual2-source-purchase`.
