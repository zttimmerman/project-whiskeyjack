---
id: a1-ci
title: "A1: CI on GitHub Actions"
status: done
kind: chore
targets: []
after: []
phase: A
branch: chore/ci
pr: 14
updated: 2026-09-30
---
## Goal

Every PR runs the checks that don't need a Mac or Blender and fails on regressions (design bible §8). Brief: `docs/plans/phase-a/a1-ci.md`.

## Outcome

`.github/workflows/ci.yml` runs import, validate, data-lint, lint, hooks, gdunit4, navmesh and replays on every PR. `ci/warnings-baseline.txt` (23 lines) and `ci/data-lint-baseline.txt` (1) are burn-down lists: new warnings fail, and a fixed warning's line is deleted.
