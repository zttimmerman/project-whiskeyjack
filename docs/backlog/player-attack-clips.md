---
id: player-attack-clips
title: "Light combo as three distinct hits; a visible heavy windup"
status: proposed
kind: feature
targets: []
after: []
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-08
---
## Goal

The light combo reads as three hits and the heavy is telegraphed (§3, proposed until playtested).

## Scope

- `Sword_Regular_A`, `B`, `C`, one per hit; roughly 0.35–0.45 s per hit; a 0.6 s window to chain
- heavy: a 0.5–0.7 s windup before contact, always staggers
- trim the heavy clip (`Sword_Regular_C`, 2.0 s) to its windup, strike and a short follow-through; the swing lock (`player-attack-commitment`) follows the clip, so this sets how long a heavy roots the player (user, 2026-10-08, `heavy-swing-lock-length`)

## Acceptance

- clips through the animation library and motion review
- contact markers re-measured (`player-attack-contact-frames`)

## Serves

§3 light combo and heavy attack.
