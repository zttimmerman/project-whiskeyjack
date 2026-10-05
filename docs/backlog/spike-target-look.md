---
id: spike-target-look
title: "Spike: a target look from the Souls series and The Witcher (dark epic fantasy)"
status: ready
kind: spike
targets: []
after: []
phase: C
branch: null
pr: null
updated: 2026-10-05
---
## Goal

The user named their reference games on 2026-10-05: the Souls series (especially Elden Ring) and The Witcher, a "dark epic fantasy" look that fits Malazan. Find what that look is made of, set it against the art bible, and give the user concept variants and a style anchor to choose from. Look-dev C showed that the concept drives the look more than the model tier, so this spike starts at the concept.

## Scope

1. **Research (free):** list the art traits of the reference games that a stylized, budgeted game can carry: palette and value range, saturation, silhouette and proportion, materials and wear, lighting and fog, architecture scale, armour and costume language. Cite sources.
2. **Reconcile (free):** compare those traits with `docs/art-bible.md`, CLAUDE.md's Visual Style line ("bold colors", PS1/PS2-era proportions) and the B2 rules. Mark which rules hold, which bend and which conflict. **The bold-colours line conflicts, and that's a direction change for the user to decide.** Draft any changed rule text for the user's review; don't edit the art bible or CLAUDE.md.
3. **Concept brief and style-anchor plan (free):** a concept brief for the player in the target look (prompt blocks in the art bible's FORM / CONCEPT LIGHTING format), and a plan for a style anchor: one approved image that every later concept is conditioned on.
4. **Concepts (paid; the user confirms each call through the tripo skill):** 3–4 banana_pro variants, about 15 credits each. The user picks the style anchor.
5. **Model and rig the winner (paid, about 55–75 credits; the user confirms):** through the asset pipeline as a look-dev variant under gitignored `assets/lookdev/`, then render it beside B2 in `scenes/lookdev/LookDev.tscn` with the same shots.

## Acceptance

- A trial write-up `docs/trials/target-look.md`: the trait list with sources, the reconciliation table, the concept brief, the variant sheet, the anchor and the B2 comparison sheets, with the credits spent.
- The direction change (bold colours and anything else in conflict) is put to the user as a `needs-user` item before any shipped rule or asset changes.

## Serves

The art direction (`docs/art-bible.md`), `player-model-rework`, `kit-replacement`.
