---
id: fix-invalid-uids
title: "Fix the 13 invalid hand-written UIDs"
status: done
kind: fix
targets: []
after: []
phase: gameplay-2
branch: fix/invalid-uids
pr: 53
updated: 2026-10-07
---
## Goal

Burn down the UID warnings in `ci/warnings-baseline.txt` (§8: no warnings).

## Outcome

PR #53 (merged 2026-10-05): 8 scenes (ArcherEnemy, BaseEnemy, Projectile, Player, HUD, InventoryUI, PauseMenu, QuestLogUI) referenced 9 scripts by invented `uid://` values; each now uses the UID from the script's `.gd.uid` file. The baseline lost 14 invalid-UID lines (the item said 13; there were 14 scene/UID pairs), leaving 9 known warnings. The import logs no invalid UIDs.
