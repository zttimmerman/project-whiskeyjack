---
id: b2-func-godot
title: "B2: func_godot brush shells for crypt interiors"
status: done
kind: feature
targets: [lvl_interior_ceiling]
after: []
phase: B
branch: feature/func-godot-trial
pr: 31
updated: 2026-10-01
---
## Goal

Decide whether crypt interiors are built as `.map` brushwork. Evidence: `docs/trials/func-godot.md`.

## Outcome

Kept as **brush shell + kit detail**: func_godot 2025.12 (`169f2dd`), disabled, build-tool only (`scripts/tools/build_brush_maps.gd`, headless; CI fails a stale build). `scripts/tools/brush_boxes.py` writes brushes from box layouts. The brush budget (per brush entity) is in the art bible. Trial room: `scenes/world/trials/CryptTrial.tscn`. Follow-ups: `trenchbroom-config`, `crypt-trial-textures`, `crypt-trial-kit-detail`, `upstream-issue-reports`.
