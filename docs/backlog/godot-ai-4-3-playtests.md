---
id: godot-ai-4-3-playtests
title: "Run the saved MCP playtests on godot-ai 4.3.0"
status: ready
kind: chore
targets: []
after: [godot-ai-4-3-trial]
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-08
---
## Goal

Run the two saved MCP playtests on godot-ai 4.3.0 to finish the update trial's regression set. The trial (PR #61) ran everything headless, and all of it matched 4.2.3, but it skipped these. The shared server on :8000/:9500 was serving the user's 4.2.3 editor, and the guard only admits the `project-whiskeyjack-agent` worktree.

**Decided 2026-10-08 (user): option A.** Merge the trial first. The user then restarts their editor, so the shared server is 4.3.0, and an agent runs both briefs from a `project-whiskeyjack-agent` worktree off main. The user also OK'd relabelling the guard docstring to v4.3.0 (label only), which was done in PR #61.

## Scope

- After #61 merges and the user confirms their editor has restarted, create the `project-whiskeyjack-agent` worktree off main.
- Launch its editor as in CLAUDE.md → Godot MCP.
- Run `docs/playtests/brief-combat-input-frame-timed.md` and `brief-level1-first-look.md` headless under `GODOT_AI_GUARD_PROFILE=playtest`.
- Write their reports in `docs/playtests/`.

## Acceptance

- Both playtests' outcomes match their 2026-09-29 reports under 4.2.3, or each difference is explained.
- Afterwards the agent's editor is closed and the worktree is removed.

## Serves

Tooling (CLAUDE.md → Godot MCP → Updates, step 4).
