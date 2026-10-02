---
id: strafe-clip
title: "A strafe clip so waiting levies circle"
status: proposed
kind: asset
targets: [enemy_attackers_max]
after: [ual2-source-purchase]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Tokenless levies hold 3–5 m off facing the player instead of circling, because there's no strafe clip (decided: they hold until one exists).

## Scope

- a strafe clip (UAL2 Source, or `spike-agent-animation` if that's a go), and circling for tokenless levies

## Acceptance

- motion review passes (foot slide); `tomb_hall_group` shows circling and still holds the token limits

## Serves

`enemy_attackers_max`.
