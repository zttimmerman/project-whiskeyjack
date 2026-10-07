---
id: godot-ai-4-3-playtests
title: "Run the saved MCP playtests on godot-ai 4.3.0"
status: needs-user
kind: decision
targets: []
after: [godot-ai-4-3-trial]
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-07
---
## Question

The 4.3.0 trial ran everything headless: the guard tests, validate, the tests, the replays and the motion metrics, all matching 4.2.3. It didn't run the live MCP playtests (`docs/playtests/brief-combat-input-frame-timed.md`, `brief-level1-first-look.md`). The shared godot-ai server on :8000/:9500 was a 4.2.3 one serving your open editor. A 4.3.0 agent editor would have attached to it with mismatched versions. Also, the guard admits only the `project-whiskeyjack-agent` worktree, which doesn't exist right now. When should they run?

## Options

- **A. After merge.** You restart your editor, so the shared server becomes 4.3.0. Then an agent creates `project-whiskeyjack-agent` from main and runs both briefs.
- **B. Before merge.** You close your editor for about 30 minutes, and an agent runs the briefs from a `project-whiskeyjack-agent` worktree on `chore/godot-ai-4.3.0`.
- **C. Skip.** The headless regression set already matched, and the changed ops (`node_set_property`, `reparent`) aren't used by the playtest profile.

## Recommendation

A. The release changes nothing the playtest profile calls (run, stop, step, input), so merging first is low-risk, and it avoids interrupting your editor. A small related guard edit needs your OK: the guard's docstring still says "v4.2.3" (`.claude/hooks/godot_ai_guard.py:2`). It's a label only, and its tables need no change.
