---
id: git-hooks
title: "Git hooks and the CI lint job"
status: done
kind: chore
targets: []
after: []
phase: A
branch: chore/git-hooks
pr: 21
updated: 2026-09-30
---
## Goal

Catch format, lint, warning and test failures before they leave the machine.

## Outcome

`.githooks/` (enable with `git config core.hooksPath .githooks`; needs `pipx install gdtoolkit==4.5.0`). pre-commit runs gdformat/gdlint/data-lint, pre-push runs the warnings check and the tests. All scripts are gdformatted at 120 columns.
