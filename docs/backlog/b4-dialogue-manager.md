---
id: b4-dialogue-manager
title: "B4: Dialogue Manager for dialogue and multi-outcome quests"
status: done
kind: feature
targets: []
after: []
phase: B
branch: feature/dialogue-manager-trial
pr: 32
updated: 2026-10-01
---
## Goal

Decide whether Dialogue Manager's `.dialogue` scripts replace our JSON dialogue. Evidence: `docs/trials/dialogue-manager.md`.

## Outcome

Kept: v4.1.0 (`a719088`) with 4 local patches (`docs/trials/dialogue-manager-v4.1.0.patch`; never use its in-editor updater). `DialogueRunner` wraps it with the old signals; `data/dialogues/village_elder.dialogue` has five openings; world flags live in `QuestManager` and save with it. `ci/check_dialogue.gd` compiles every file. Fixed: the quest reward was paid again after loading a save. Follow-ups: `dialogue-questmanager-lint`, `upstream-issue-reports`.
