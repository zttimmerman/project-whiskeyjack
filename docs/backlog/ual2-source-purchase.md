---
id: ual2-source-purchase
title: "Buy Quaternius UAL2 Source for the bow and strafe clips?"
status: done
kind: decision
targets: []
after: []
phase: C
branch: null
pr: null
updated: 2026-10-07
---
## Goal

Decide whether to buy Quaternius UAL2 Source for the bow and strafe clips.

## Question

The real bow clips (and possibly a strafe clip so waiting levies circle) are in UAL2's non-Standard tier, which costs money. Quaternius moved to a no-redistribution licence on 2026-08-28; our committed UAL1/UAL2 packs ship a CC0 `License.txt`, but a new purchase comes under the new licence, so its source files stay out of the public repo. Settled earlier: the purchase waits until the slice has been judged in motion (it affects 2 of 7 enemies).

## Options

1. Buy now; source files in a gitignored folder, checked first that the new licence allows committing the retargeted clips in a public repo.
2. Wait until the slice is judged in motion (the earlier decision).
3. Don't buy: keep the stand-ins, or try `spike-agent-animation` on these humanoid gaps.

## Recommendation

2, and check the new licence's terms on derived clips before buying; the spike may cover the strafe more cheaply.

## Outcome

User, 2026-10-07: option 2, wait until the slice is judged in motion. The user raised Mixamo as a possible library switch; that's `spike-mixamo-library`.
