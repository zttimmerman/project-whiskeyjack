---
id: a2a-gdunit4
title: "A2a: gdUnit4 and the first unit tests"
status: done
kind: chore
targets: [ttk_levy_player]
after: []
phase: A
branch: chore/gdunit4
pr: 17
updated: 2026-09-30
---
## Goal

A GDScript test framework in CI, with tests for the systems the design bible changes next. Brief: `docs/plans/phase-a/a2a-gdunit4.md`.

## Outcome

gdUnit4 v6.2.1 (commit 08ffc7c), pinned. `tests/run.sh` runs every suite (about 5 s). Characterization tests cover stats, inventory, quests and saves. Pending tests (the damage ratio, enemy damage share, `ttk_levy_player`, level bands) flipped on in the PRs that implemented them (#23).
