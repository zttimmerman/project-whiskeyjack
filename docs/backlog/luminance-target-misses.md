---
id: luminance-target-misses
title: "Floor and character luminance misses found by the rendered checks"
status: needs-user
kind: decision
targets: [lvl_floor_luminance_min, read_char_contrast_min]
after: [render-luminance-checks]
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-07
---
## Question

The rendered checks (`scripts/review/capture_luminance.sh`, render-luminance-checks) put several places under
the readability targets. Lighting is a look decision, so nothing was changed. Which levers, if any, should
fix them, and which view does `read_char_contrast_min` hold in?

Measured on the Mac, gameplay camera, every 30 frames (minimums):

- **Floor (≥ 0.05):** crypt trial corridor 0.041 (`crypt_trial_walk`; 0.043 on the critical path),
  Level 2 tomb hall 0.021 (`tomb_hall_group`), Level 1 exit 0.0497 on the critical path (its replays stay
  at 0.070 or more).
- **Enemies (≥ 1.3):** the skeleton levy against Level 1's pale corridor floor reads 1.12 to 1.28 in the
  1v1 and central-room replays, while the critical-path view (5 m, eye height, from the path side) gives
  1.45 to 1.70. Bone-pale albedo on a sandy floor is close in luminance, not hue.
- **Player (≥ 1.3):** 1.00 to 1.18 in every scenario; already player-contrast-b2's work.

## Options

1. Raise ambient or torch energy (or add torches) in the crypt corridor and Level 2's tomb hall until the
   floor clears 0.05; leave Level 1 as is.
2. Hold enemy contrast in the gameplay view (the replay numbers): the levy needs a darker or more saturated
   albedo, or the Level 1 corridor floor a darker ramp.
3. Hold enemy contrast in the 5 m critical-path view only (today's design-bible method): the levy passes.

## Recommendation

1 for the floors (the art bible's levers), and 3 for enemies until playtests say the levy is hard to read,
with the gameplay-view number recorded alongside.
