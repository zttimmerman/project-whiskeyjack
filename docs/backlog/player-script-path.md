---
id: player-script-path
title: "Fix Player.tscn's script path case"
status: done
kind: fix
targets: []
after: []
phase: A
branch: fix/player-script-path
pr: 15
updated: 2026-09-30
---
## Goal

Player.tscn referenced its script with the wrong case, which breaks on case-sensitive filesystems (CI).

## Outcome

Fixed; CI's Linux import loads the player.
