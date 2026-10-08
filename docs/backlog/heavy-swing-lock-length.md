---
id: heavy-swing-lock-length
title: "How long should the heavy attack lock movement?"
status: done
kind: decision
targets: []
after: []
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-08
---
## Goal

Settle how long a heavy attack locks movement, and confirm the lunge distance.

## Question

Attacks now lock movement for the swing, taken as the attack clip (`player-attack-commitment`). The light clip (`Sword_Regular_A`) is 0.43 s, inside §3's 0.35–0.45 s per hit. The heavy clip (`Sword_Regular_C`) is 2.0 s, so a heavy roots the player for 2.0 s unless he dodges out after its 0.35 s active frames. The design bible doesn't set a heavy swing length, and the lunge (0.4 m, mid-range of §3's 0.3–0.5 m) was also picked here.

## Options

1. Keep the full 2.0 s clip: a heavy is a big commitment, escaped only by a dodge (as now).
2. Trim the heavy clip in the animation library to its windup plus strike (about 0.5–0.7 s windup per §3, then a short follow-through), and lock for that.
3. Lock for a fixed heavy swing time (for example 1.0 s) and let the clip blend out.

## Recommendation

2, folded into `player-attack-clips` (which already gives the heavy a 0.5–0.7 s windup); until then 1 stands. Also confirm the 0.4 m lunge.

## Outcome

User, 2026-10-08: option 2. The heavy clip is trimmed in `player-attack-clips` (its scope says so); until then the full 2.0 s clip lock stands. The 0.4 m lunge is confirmed.
