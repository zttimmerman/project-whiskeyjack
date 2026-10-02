---
id: backlog-system
title: "Home-grown backlog: docs/backlog, backlog.py, package-worker agent"
status: done
kind: chore
targets: []
after: [decide-backlog-system]
phase: B
branch: chore/backlog
pr: 42
updated: 2026-10-02
---
## Goal

Track work as one file per item, pick the next item mechanically, and shrink the session handoff.

## Scope

- `docs/backlog/<id>.md` items and `docs/backlog/README.md` (schema and workflow), seeded from the old handoff, the Phase A briefs and the trial notes
- `scripts/tools/backlog.py` (`next`, `status`, `show`, `lint`, all `--json`) with `tests/tools/test_backlog.py`; lint in CI's data-lint job
- `.claude/agents/package-worker.md`: the standing rules for package subagents
- `docs/decisions.md`'s handoff shrunk to pointers; dated decisions moved to its decision record
- CLAUDE.md: a Backlog section, and the third and fourth animation exceptions (scripted keyframe clips; weight transfer onto clothing shells)

## Acceptance

- `backlog.py lint` is clean and runs in CI
- every bullet of the old handoff is in an item or the decision record

## Serves

Orchestration; `decide-backlog-system`.
