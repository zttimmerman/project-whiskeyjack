---
id: decide-enc-spacing-standing
title: "Does enc_spacing_s count time spent standing while exploring?"
status: needs-user
kind: decision
targets: [enc_spacing_s]
after: []
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-08
---
## Question

`two_fight_route` now measures 22.8 s between fights (target 20–60 s) after level1-spoke-spacing's side room (PR #72). 4.3 s of that is standing: a 3 s camera survey on entering the room and a 1 s beat after taking the potion. Walking alone is about 18.5 s. Does exploring time count, or only walking?

## Options

- **A. It counts** (the bible says "walking or exploring"). Keep the room and walk as they are.
- **B. Walking only.** Lengthen the passage or the room by about 8 m (another ~1.6 s each way), or drop the pauses and add route.

## Recommendation

A: §4 says "walking or exploring", and a player who enters a torch-lit room and stops to look around is exploring. The margin over 20 s is 2.8 s.
