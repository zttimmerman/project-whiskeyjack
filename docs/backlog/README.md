# Backlog

All work that's planned, running or waiting on the user is here: one Markdown file per item, `docs/backlog/<id>.md`. This replaces backlog lists in `docs/decisions.md`'s handoff and in chat. Decided by the user on 2026-10-02 (`decide-backlog-system`): home-grown, borrowing BMAD's ticket semantics.

```
python3 scripts/tools/backlog.py next          # what can start now
python3 scripts/tools/backlog.py status        # counts and a table per status
python3 scripts/tools/backlog.py show <id>
python3 scripts/tools/backlog.py lint          # CI's data-lint job runs this
```

Every command takes `--json`.

## An item

```yaml
---
id: atk-hitbox-sync               # kebab-case, the same as the file name
title: "Open the player's hitbox on the clip's contact frame and check it"
status: ready                     # see below
kind: feature                     # feature | fix | chore | spike | asset | docs | decision
targets: [atk_hitbox_sync]        # design-bible §9 target IDs; may be []
after: [player-attack-contact-frames]   # item ids this waits for; may be []
phase: gameplay-2                 # A | gameplay-1 | B | gameplay-2 | C | later
branch: null                      # set when work starts
pr: null                          # set when the PR opens
updated: 2026-10-02
---
```

Lists are inline (`[a, b]`); `null` means unset. Quote titles that contain `#` or start with a quote.

The body follows the status:
- **Open work** (proposed, ready, in-progress, in-review) is a package brief in the Phase A format (`docs/plans/phase-a/`): `## Goal`, `## Scope`, `## Acceptance`, `## Serves` (the target IDs or bible sections it moves).
- **done** and **dropped** items are short: `## Goal` and `## Outcome` (what shipped, the PR, the numbers, what it left for which items).
- **needs-user** items hold an open question: `## Question`, `## Options`, `## Recommendation`.

## Statuses

| Status | Meaning |
|---|---|
| `proposed` | Worth doing, but not yet settled: a design question, a spend, or a condition that isn't met yet |
| `ready` | Settled and scoped; a package worker can start it |
| `in-progress` | Someone is on it (`branch` set) |
| `in-review` | The PR is open (`pr` set) |
| `done` | Merged (`pr` set), or decided, for a `decision` or `docs` item |
| `dropped` | Not doing it; the Outcome says why |
| `needs-user` | Waiting on the user's answer |

An item is **next** when it's `ready` and every item in its `after` list is `done` or `in-review`. `next` sorts by phase (in the order above), then id.

## Workflow

1. **Pick:** the orchestrator runs `backlog.py next` and chooses from it.
2. **Start:** set `status: in-progress` and `branch`, and spawn a `package-worker` subagent (`.claude/agents/package-worker.md`) with the item's id.
3. **PR:** set `status: in-review` and `pr` when the PR opens. **Every PR body names its item** (`Backlog: <id>`).
4. **Merge:** set `status: done` with an Outcome, in the PR or straight after it; refresh `docs/decisions.md`'s handoff at the same time.
5. **Found work** becomes a new item (`proposed` unless it's settled), not a note in a report.
6. **Open questions are `needs-user` items, never only chat.** When the user answers, record the answer in the item's Outcome (`status: done`, usually `kind: decision`), add a line to `docs/decisions.md`'s Decided section if it's a lasting rule, and unblock what was waiting.

`lint` fails on: a bad front-matter line, missing or unknown keys, unknown statuses, kinds or phases, ids that aren't kebab-case or don't match their file, `after` naming a missing or dropped item, `after` cycles, target IDs not in the design bible's §9 table, a `done` or `in-review` item without a `pr` (except `decision` and `docs` kinds), and a body missing its status's sections.

Work before Phase A (PRs #1–#13: the world bible slice, the pipeline, the Godot MCP trial, the design bible) isn't itemised; `docs/decisions.md` and git history cover it.
