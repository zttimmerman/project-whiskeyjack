---
id: clearance-check-strict
title: "Make the path-clearance check strict in CI"
status: in-review
kind: chore
targets: [lvl_path_clearance_min]
after: []
phase: gameplay-2
branch: chore/clearance-check-strict
pr: 62
updated: 2026-10-07
---
## Goal

Decided 2026-09-30: the clearance check goes `--strict` once the level fixes land. Every segment passes today (narrowest 1.5 m, Level 2 vault → corridor C).

## Scope

- run `check_path_clearance.gd --strict` in the navmesh job, failing below 1.0 m

## Acceptance

- CI green with strict on; a throwaway narrowing shows it fail

## Serves

`lvl_path_clearance_min`.

## Outcome

CI's navmesh job runs the check with `--strict` (PR #62). All 14 segments pass (narrowest 1.5 m, Level 2 vault → corridor C); a throwaway 0.5 m gap in Level 1 corridor A failed strict with exit 1.
