---
id: pipeline-style-anchor
title: "Condition concepts on a style anchor image (image-to-image with references)"
status: proposed
kind: feature
targets: []
after: [decide-target-look]
phase: C
branch: null
pr: null
updated: 2026-10-07
---
## Goal

Once the user picks a style anchor (`spike-target-look`), every later concept is made in its hand, not from text alone.

## Scope

- A brief field `style_anchor` (or one art-bible line with the anchor's path and SHA-256) that the concept stage reads.
- The concept stage prints `tripo generate image-to-image` with `inputs` = [the anchor] and a prompt naming the subject "in the art style, palette and rendering of [image 1]" (banana_pro accepts up to 10 references, `tripo docs --topic commands/generate`), instead of text-to-image.
- The judge's concept packet carries the anchor, and checks palette and value structure against it.
- Tests in `scripts/pipeline.py`'s test suite for the composed command; no paid call.

## Acceptance

- `--stage concept --dry-run` on an anchored brief prints the image-to-image command with the anchor's path; the approval records the anchor's hash.

## Serves

The art direction (`docs/art-bible.md`), `player-model-rework`, `kit-replacement`.
