---
id: crypt-trial-textures
title: "Replace the crypt trial's placeholder tileables with Material Maker output"
status: ready
kind: feature
targets: [lvl_floor_luminance_min]
after: []
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

The brush shells use the real palette-locked surfaces (func_godot follow-up 4).

## Scope

- swap the four placeholder textures (`assets/textures/brush/`, `make_brush_textures.py`) for `assets/textures/surfaces/` through the same albedo-only template
- level-side lighting for earth and plank floors where they're used (Material Maker follow-up; dark floors are fixed level-side, never by lightening ramps)

## Acceptance

- `build_brush_maps.gd` rebuild committed; crypt tests pass; floor luminance reported (`render-luminance-checks` if landed)

## Serves

`lvl_floor_luminance_min`.
