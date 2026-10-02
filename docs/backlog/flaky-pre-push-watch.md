---
id: flaky-pre-push-watch
title: "Watch for a flaky test (pre-push exited 100 once)"
status: proposed
kind: fix
targets: []
after: []
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-02
---
## Goal

The pre-push hook ran `tests/run.sh` to exit 100 once; not reproduced.

## Scope

- if it recurs, capture the gdUnit4 report and find the test

## Acceptance

- the flaky test is fixed, or the item is dropped after a few weeks with no recurrence

## Serves

Test reliability.
