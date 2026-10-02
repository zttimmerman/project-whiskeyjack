---
id: fix-invalid-uids
title: "Fix the 13 invalid hand-written UIDs"
status: ready
kind: fix
targets: []
after: []
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Burn down the UID warnings in `ci/warnings-baseline.txt` (§8: no warnings).

## Scope

- let Godot regenerate or correct the 13 hand-written `uid://` values the import warns about
- delete their baseline lines

## Acceptance

- the import logs none of them; the baseline shrinks by 13

## Serves

§8 stability.
