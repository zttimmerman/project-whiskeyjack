---
id: level-band-spawning
title: "Wire level-band scaling into spawning"
status: proposed
kind: feature
targets: []
after: []
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

`CharacterStats.scaled_stat` exists (G3) but nothing spawns at a level band, since there are no per-area level bands yet.

## Scope

- per-area level bands (design bible §6), applied at spawn

## Acceptance

- tests first for the scaled stats at spawn

## Serves

§6 level bands.
