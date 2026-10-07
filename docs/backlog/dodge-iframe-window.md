---
id: dodge-iframe-window
title: "Dodge i-frames for the first 0.30 s, then a 0.15 s recovery"
status: in-review
kind: feature
targets: []
after: []
phase: gameplay-2
branch: feature/dodge-iframe-window
pr: 58
updated: 2026-10-07
---
## Goal

The settled dodge (design bible §3, §11.2): late dodges are punished a little.

## Scope

- I-frames cover the first 0.30 s of the 0.5 s roll, not all of it
- a 0.15 s recovery before the next dodge or attack
- existing replays: update baselines that move, and say why

## Acceptance

- a failing gdUnit4 test (`test_dodge_iframe_window`) committed first, then passing
- `levy_1v1_sensible` still kills the levy, or its schedule is retimed and explained

## Serves

§3 dodge; §11 decision 2.
