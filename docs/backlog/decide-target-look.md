---
id: decide-target-look
title: "Decide: the target-look direction change (bold colours, proportions) and the concept round"
status: needs-user
kind: decision
targets: []
after: []
phase: C
branch: null
pr: null
updated: 2026-10-07
---
## Question

`spike-target-look` (`docs/trials/target-look.md`) found that the Souls/Witcher look fits the hard rules (albedo only, triangle budgets, Compatibility, no bloom/SSAO/SSR, B2 lighting), but conflicts with two style lines, and needs a spend to go on:

1. **"Bold colors"** (CLAUDE.md → Visual Style Rules, art bible → Style): the references are low-saturation and value-led. Replace it with the trial's proposed Style text (restrained earthy colour, saturated accents for fire, gold, blood and magic, the read from value and silhouette)?
2. **Proportions:** the FORM block's "slightly exaggerated proportions" and CLAUDE.md's "slightly large heads" against the references' naturalistic adult proportions. Adopt the trial's proposed FORM block and Silhouettes text?
3. **Bends:** Tarnished Gold's plain colour for assets becomes "dull dark antique gold" (the UI keeps `#E6BF1A`); colour-level wear words ("faded", "rain-darkened") are allowed in prompts, shape-level wear stays out.
4. **The concept round:** run the four banana_pro concepts (`player_look_a`–`d`: Witcher gambeson, Souls half-helm, Elden Ring cape, today's design grounded), 60 credits, and pick a style anchor?
5. **Identity mark:** spiky hair (today) or the Line's half-helm (`02-factions.md`)? The round tests both.

## Options

- **Adopt 1–3, then run 4** (the composed prompts lose today's "exaggerated" vs "natural" contradiction).
- **Run 4 first under today's FORM** and decide 1–3 from the images (the prompts already ask for natural proportions and a darker tone).
- **Keep today's style lines** and drop the concept round.

## Recommendation

Adopt 1–3, then run 4 (60 credits). The palette's Balance line is already muted; only the Style line and FORM still say otherwise, and a concept round under contradictory FORM text wastes credits. Leave 5 to the images.
