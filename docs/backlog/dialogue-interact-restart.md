---
id: dialogue-interact-restart
title: "Stop interact reopening a finished conversation"
status: done
kind: fix
targets: []
after: []
phase: B
branch: fix/dialogue-interact-restart
pr: 34
updated: 2026-10-02
---
## Goal

Pressing interact on a conversation's last line reopened it.

## Outcome

Fixed (`DialogueRunner.accepts_interact()`); the playtest review copy is labelled "REVIEW <ref>" and has its own `user://`.
