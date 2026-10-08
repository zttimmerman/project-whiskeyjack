---
id: decide-target-look
title: "Decide: the target-look direction change (bold colours, proportions) and the concept round"
status: done
kind: decision
targets: []
after: []
phase: C
branch: null
pr: null
updated: 2026-10-08
---
## Goal

Settle the direction change that `spike-target-look` (`docs/trials/target-look.md`) found: the Souls/Witcher look fits the hard rules but conflicts with the "bold colors" Style line and the FORM block's exaggerated proportions.

## Outcome

Decided by the user (2026-10-08), adopting 1–3 and running 4:
1. **Style:** "bold colors" is replaced in CLAUDE.md and the art bible by dark epic fantasy after the Souls series and The Witcher: restrained earthy colour with saturated accents for fire, gold, blood and magic, the read from value contrast and silhouettes, albedo-only textures worn and lived-in.
2. **Proportions:** the FORM block now asks for naturalistic adult proportions, large simple forms and worn, faded colour; CLAUDE.md's Silhouettes line says the silhouette comes from costume masses, not enlarged heads.
3. **Bends:** Tarnished Gold is `#9C7A2E` "dull dark antique gold" on assets; the UI's `#E6BF1A` is a new palette row, XP Gold. Colour-level wear words are allowed in prompts; shape-level wear stays in the albedo.
4. **Concept round:** run the four `player_look_a`–`d` concepts (60 credits, each confirmed through the tripo skill).
5. **Identity mark** (spiky hair or the half-helm): left to the images.

Applied on `docs/target-look` (PR #60).
