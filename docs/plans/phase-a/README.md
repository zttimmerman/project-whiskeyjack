# Phase A: foundations (plan)

These are the agreed first step from `docs/tools-review-2026-09.md`: tooling that makes content measurable before more content gets made. Each package is one short-lived branch and PR, implemented by a subagent in its own worktree. An orchestrating session reviews and merges.

| Package | Brief | Branch | Order |
|---|---|---|---|
| A1 CI | `a1-ci.md` | `chore/ci` | first, alone |
| A2a gdUnit4 and unit tests | `a2a-gdunit4.md` | `chore/gdunit4` | after A1, in parallel with A3 and A4 |
| A2b replay harness, event log and capture | `a2b-replay-harness.md` | `feature/replay-harness` | after A2a |
| A3 edit-time navmesh bake | `a3-navmesh-bake.md` | `chore/navmesh-bake` | after A1, parallel |
| A4 downloaded-asset import path | `a4-asset-import.md` | `feature/asset-import-path` | after A1, parallel |

## Rules for every package (the subagent reads these first)

- Read `CLAUDE.md`, then the relevant parts of `docs/design-bible.md` and the asset-pipeline skill. Conventions: GDScript only; preserve existing signals and public methods; list the files to change before writing code.
- **Worktree:** `git -C /Users/zach/Documents/repos/project-whiskeyjack worktree add -b <branch> /Users/zach/Documents/repos/project-whiskeyjack-<pkg> origin/main`.
  - Work only there, using `git -C` and absolute paths, and fail closed if the directory is missing.
  - Never touch the human's checkout (`project-whiskeyjack`) or another package's worktree.
  - A fresh worktree needs one `godot --headless --path <wt> --import` first.
  - Godot is `/Applications/Godot.app/Contents/MacOS/Godot` (4.7.2).
- **No Godot MCP** in Phase A. Everything is headless or scripted.
- **Don't edit** `docs/decisions.md` or CLAUDE.md. Put the handoff notes and any CLAUDE.md or skill text you propose in your final report; the orchestrator merges docs.
- **Commits** are atomic, with an imperative subject and body bullets, and end with the `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` line. Scan for tokens before pushing.
- **Push and open a PR** (`gh pr create`); **don't merge.** The PR body lists what changed, how it was verified (with commands and output), and open questions.
- **Report back** in 30 lines or fewer: the PR link, the verification evidence, the design-bible target IDs served, proposed doc text, and follow-ups.
- **Determinism first:** seed RNGs; assert tolerance ranges, not exact floats; generated files come only from their generators.
- Anything that costs money, or is a design decision, goes back to the orchestrator; don't decide it.
