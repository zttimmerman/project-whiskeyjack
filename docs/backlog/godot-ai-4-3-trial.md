---
id: godot-ai-4-3-trial
title: "Trial the godot-ai 4.3.0 update"
status: in-review
kind: chore
targets: []
after: []
phase: gameplay-2
branch: chore/godot-ai-4.3.0
pr: 61
updated: 2026-10-07
---
## Goal

Move the godot-ai pin from 4.2.3 to 4.3.0 (released 2026-10-03) through the update trial in CLAUDE.md → Godot MCP → Updates. Wanted from it: the idle-editor redraw fix, `node_set_property` assigning Node-typed exports, and the headless game-run fixes. No security fixes, so it isn't urgent. User approved the trial on 2026-10-07.

## Scope

On `chore/godot-ai-4.3.0`: verify the signed release (the SPKI fingerprint must match `docs/godot-ai-integration.md`; a changed key stops the trial), swap `addons/godot_ai/` and the `.mcp.json` pin, keep the editor settings' domain exclusions in step, diff the tool surface against the guard's tables and review new ops and changed defaults.

## Acceptance

- Guard tests, validate, the motion metrics, the movement test and the saved playtest scenarios match the pinned version.
- The PR carries the changelog link, the surface diff and the results; CI green.
- `scripts/tools/godot_ai_update.py check` is silent afterwards.

## Serves

Tooling (CLAUDE.md → Godot MCP → Updates).
