---
id: scenario-search-state
title: "A pillar or doorway replay for the SEARCH state"
status: done
kind: chore
targets: []
after: []
phase: gameplay-2
branch: chore/scenario-search-state
pr: 63
updated: 2026-10-07
---
## Goal

Pin the SEARCH behaviour (last-seen spot, 3.5 s, back to post) in a replay.

## Scope

- the player breaks line of sight behind a pillar or through a doorway; the log shows search start, the visit to the last-seen spot, and the return

## Acceptance

- deterministic; checks on the search timings

## Serves

§3 detection (G2).

## Outcome

`tests/scenarios/search_lost_sight.json` (PR #63): the Corridor B archer loses the player behind the central room's south wall, then walks to the last-seen spot (0.484 m off), looks for 3.517 s, gives up and returns to its post (0.489 m off). New events `search_look`/`search_return` and metrics `search_look_s`, `search_last_seen_m`, `search_post_m`.
