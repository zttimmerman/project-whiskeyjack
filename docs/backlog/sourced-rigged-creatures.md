---
id: sourced-rigged-creatures
title: "Decide how downloaded pre-rigged creatures enter the pipeline"
status: done
kind: decision
targets: []
after: []
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Decide how downloaded, already-rigged creatures (the Gobkit boar, PR #46) enter the pipeline; sourced characters were refused, so the boar came in as a prop.

## Question

`pipeline.py` refuses sourced characters ("rigging a downloaded character is the user's call"), so the spike's Gobkit boar came in as `type: prop`. It keeps its own rig and clips, but validate warns "prop has a Skeleton3D" and the brief can't carry character fields (`socket_map`, animations). How should downloaded creatures that are already rigged come in?

## Options

- **Keep the prop workaround** for spike subjects only, and never put such a prop in a level
- **A `type: creature`** for sourced assets that keep their own rig: no humanoid BoneMap check, a required `limb_map`, and sockets via a SocketMap
- **Allow sourced characters**, with the humanoid checks, which a quadruped would fail

## Recommendation

Keep the workaround until `spike-agent-animation` reaches a go or no-go. On a go, add `type: creature`.

## Outcome

Decided by the user (2026-10-02): **allow sourced rigged creatures.** A brief type for rigged CC0 creatures keeps their own rig, validates bones and the limb map, and checks their clips with the motion review. Humanoid characters still come through our own rig flow. Implementation: `sourced-creature-brief`.
