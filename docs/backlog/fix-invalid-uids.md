---
id: fix-invalid-uids
title: "Fix the 13 invalid hand-written UIDs"
status: in-review
kind: fix
targets: []
after: []
phase: gameplay-2
branch: fix/invalid-uids
pr: 53
updated: 2026-10-05
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
