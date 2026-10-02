---
id: kit-atlas-s3tc-cost
title: "Measure what S3TC costs the kit atlas in ΔE"
status: proposed
kind: chore
targets: []
after: []
phase: later
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Kit textures import VRAM compressed (#28); surface textures import lossless so S3TC adds no off-palette colours. How far off is the kit atlas?

## Scope

- measure ΔE between the source atlas and its compressed import

## Acceptance

- a number and a keep/lossless recommendation

## Serves

Palette fidelity (art bible).
