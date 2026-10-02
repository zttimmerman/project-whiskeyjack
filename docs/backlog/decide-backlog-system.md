---
id: decide-backlog-system
title: "Choose how the backlog is tracked"
status: done
kind: decision
targets: []
after: []
phase: B
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Pick a spec/backlog framework (an SDD spike: BMAD, Spec Kit, OpenSpec or home-grown) so open work stops living in the handoff and in chat.

## Outcome

**Home-grown** (user, 2026-10-02): one Markdown file per item in `docs/backlog/`, borrowing BMAD's ticket semantics (an item is next when it's ready and everything in
its `after` list is done or in-review). Built by `backlog-system`.
