---
id: decide-player-p2parts
title: "Decide: P2 with weight transfer, P1, or Phase 1 for the player rework"
status: needs-user
kind: decision
targets: []
after: [spike-body-only-humanoid]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Question

Phase 0 made the paid P2 player hold together: seams under 1 cm, and edge stretch below P1 in 5 of 6 clips (`docs/trials/body-only-humanoid.md`). Does `player-model-rework` start from it, stay on P1, or go to Phase 1 (paid segmentation and completion)?

## Options

1. **Start from `player_p2parts`** (0 credits). The collar is fixed (Phase 0b). Next, fix the leg-top albedo (`p2parts-leg-top-albedo`), then the user looks at it in play (`playtest-branch`) next to P1. The mesh judge still flags P2's 17 open holes, a slightly short dark-navy share, a faint face and missing back straps.
2. **Phase 1** (about 80–140 credits; `tripo mesh segment` has no `--dry-run` in tripo-cli 0.5.1, so there's no free price): a completed body plus garments, which the `keep` + `transfer` code already handles.
3. **Stay on P1** and fix its skirt another way.

## Recommendation

Option 1: it's free, its seams hold under 1 cm, it stretches less than P1 in 5 of 6 clips, and its remaining defects are texture and concept, not weights. Hold Phase 1 until the user has seen option 1 in play.
