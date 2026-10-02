---
id: scenario-search-state
title: "A pillar or doorway replay for the SEARCH state"
status: ready
kind: chore
targets: []
after: []
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Pin the SEARCH behaviour (last-seen spot, 3.5 s, back to post) in a replay.

## Scope

- the player breaks line of sight behind a pillar or through a doorway; the log shows search start, the visit to the last-seen spot, and the return

## Acceptance

- deterministic; checks on the search timings

## Serves

§3 detection (G2).
