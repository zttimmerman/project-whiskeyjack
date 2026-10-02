---
id: junit-summary
title: "Summarise gdUnit4 results on the CI run"
status: done
kind: chore
targets: []
after: []
phase: B
branch: chore/junit-summary
pr: 36
updated: 2026-10-02
---
## Goal

Failing tests are visible on the PR without downloading artifacts.

## Outcome

The gdunit4 job posts a JUnit summary (`mikepenz/action-junit-report`). Failure annotations haven't been seen yet (the pre-push hook stops a failing test reaching CI); the first real failure will show them.
