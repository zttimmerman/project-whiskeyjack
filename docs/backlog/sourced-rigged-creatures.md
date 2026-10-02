---
id: sourced-rigged-creatures
title: "Decide how downloaded pre-rigged creatures enter the pipeline"
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

`pipeline.py` refuses sourced characters ("rigging a downloaded character is the user's call"), so the spike's Gobkit boar came in as `type: prop`. It keeps its own rig and clips, but validate warns "prop has a Skeleton3D" and the brief can't carry character fields (`socket_map`, animations). How should downloaded creatures that are already rigged come in?

## Options

- **Keep the prop workaround** for spike subjects only, and never put such a prop in a level
- **A `type: creature`** for sourced assets that keep their own rig: no humanoid BoneMap check, a required `limb_map`, and sockets via a SocketMap
- **Allow sourced characters**, with the humanoid checks, which a quadruped would fail

## Recommendation

Keep the workaround until `spike-agent-animation` reaches a go or no-go. On a go, add `type: creature`.
