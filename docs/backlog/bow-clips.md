---
id: bow-clips
title: "Real bow clips for the Back-file"
status: proposed
kind: asset
targets: [enemy_ranged_telegraph]
after: [ual2-source-purchase]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Replace the `Spell_Simple_Enter` / `OverhandThrow` stand-ins with real bow draw and release clips.

## Scope

- UAL2 Source bow clips through the animation library; the 0.9 s draw kept as the telegraph

## Acceptance

- motion review and judge pass; `enemy_ranged_telegraph` holds

## Serves

`enemy_ranged_telegraph`.
