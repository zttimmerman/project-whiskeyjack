---
id: pipeline-prompt-length
title: "Fail a composed prompt over Tripo's 1,024-character limit at dry run"
status: proposed
kind: chore
targets: []
after: []
phase: C
branch: null
pr: null
updated: 2026-10-07
---
## Goal

Tripo's text-to-image and image-to-image prompts are limited to 1,024 characters (`tripo docs --topic commands/generate`). FORM and CONCEPT LIGHTING take about 490 of them, and the target-look prompts compose to 911–963, so a longer brief would fail only as a paid API error.

## Scope

- `compose_prompt` (or the concept stage) fails with a clear error when the composed prompt is over the limit, at dry run too; the limit is a named constant with its source.
- A unit test.

## Acceptance

- A brief whose composed prompt is 1,025 characters fails `--stage concept --dry-run` with the length and the limit.

## Serves

The asset pipeline (`.claude/skills/asset-pipeline/`).
