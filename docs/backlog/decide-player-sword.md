---
id: decide-player-sword
title: "When and on which model to generate the player's own sword"
status: needs-user
kind: decision
targets: []
after: []
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Question

The player reuses the Levy Blade. The sword waited for the Tripo P2.0 research (2026-09-30 decision: don't spend on the P1 model); that research is done (P1 stays for the player). A sword is a rigid prop, so P2's shell tearing doesn't apply. Generate it now, and on which model?

## Options

1. Now on P1, after `held-prop-tip-check`: about 75 credits (concept 15, multiview 10, model 50).
2. Now on P2: about 135 credits (model 110); tidier meshes, untested on props.
3. Wait for `player-model-rework`, so the sword matches the new player.

## Recommendation

1: P1 is proven on the blade and the bow and the cheapest; generate after `held-prop-tip-check` lands.
