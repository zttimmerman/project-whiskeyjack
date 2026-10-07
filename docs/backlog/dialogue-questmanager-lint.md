---
id: dialogue-questmanager-lint
title: "Lint QuestManager method names used in .dialogue files"
status: done
kind: chore
targets: []
after: []
phase: gameplay-2
branch: chore/dialogue-questmanager-lint
pr: 57
updated: 2026-10-07
---
## Goal

A typo in `QuestManager.<method>` inside a `.dialogue` expression fails only at runtime (B4 trial follow-up).

## Scope

- extend `ci/data_lint.py` or `ci/check_dialogue.gd`: every `QuestManager.<name>` must exist on the script

## Acceptance

- a throwaway typo fails CI

## Serves

Dialogue integrity (B4).

## Outcome

ci/data_lint.py fails any QuestManager.<name> in a .dialogue line that isn't a top-level member of autoloads/QuestManager.gd (mutations, conditions, inline [if]); tests in tests/tools/test_data_lint.py run in the data-lint job. Merged in PR #57.
