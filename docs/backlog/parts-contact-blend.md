---
id: parts-contact-blend
title: "Blend a keep shell's weights toward the source near its contact (collar poke-through)"
status: dropped
kind: chore
targets: []
after: [spike-body-only-humanoid]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

On `player_p2parts`, the body's collar (Shoulder/Neck/Head blended) comes out through the head shell's neck (100% Head) by up to 4.6 cm when the head turns; that's 4–7 poke-through vertices per clip (`docs/trials/body-only-humanoid.md`). A plain `transfer` from the body would drag the hair onto the neck.

## Outcome

Not needed: Phase 0b fixed the collar with a `cover: true` head shell, which hides the 18 body faces inside the neck (`docs/trials/body-only-humanoid.md`), and the poke test now skips backsides facing the skin. A blended transfer is still the tool if a contact can't be hidden.
