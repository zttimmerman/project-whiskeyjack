---
id: art-rules-b2
title: "Adopt the look-dev B2 rules: 1024 px character textures, smooth character shading, B2 lighting"
status: in-review
kind: feature
targets: []
after: [decide-art-direction]
phase: C
branch: feature/art-rules-b2
pr: 51
updated: 2026-10-02
---
## Goal

Apply the art-bible changes the user adopted on 2026-10-02 (`decide-art-direction`, evidence in `docs/trials/look-dev.md`) to the shipped game.

## Scope

- **Art bible:** the Textures and Shading lines as proposed in `docs/trials/look-dev.md` (characters 1024 px, 512 floor; smooth normals for continuous-skin characters, the 30° flat rule for props, kit pieces and rigid-part characters); add fog and filmic tonemapping to the allowed rendering list; the B2 lighting standard as level guidance; Compatibility stays
- **Briefs and clean stage:** character briefs get `texture_size` 1024 and a smooth-shading flag; `blender_cleanup.py` keeps the source normals for continuous-skin characters; regenerate the mouth overlay at 1024; re-clean the player (and any continuous-skin character) through the pipeline, re-validate, re-run the motion review and judge packets (the orchestrator runs the judge)
- **Levels:** apply the B2 lighting standard to Level 1, Level 2 and the crypt trial (WorldEnvironment ambient, tonemap, fog; torch OmniLight range/attenuation), keeping `lvl_floor_luminance_min` and the readability targets in band; replays and camera checks stay green
- **Not in scope:** replacing KayKit pieces (`kit-replacement`), and anything from variant C

## Acceptance

- The shipped player renders like look-dev B2 in play (face readable at the shoulder camera), all CI green, judge verdicts recorded, the user playtests it

## Serves

The art direction; `player-model-rework`.
