---
id: crypt-trial-kit-detail
title: "Dress the crypt trial shell with kit detail"
status: ready
kind: feature
targets: [lvl_dressing_density, lvl_bare_wall_run_max]
after: [crypt-trial-textures]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Brush shell + kit detail, the adopted interior method (func_godot follow-up 5).

## Scope

- pillars, door frames and dressing as kit pieces in `CryptTrial.tscn`; the baker already reads them

## Acceptance

- navmesh rebaked; clearance passes; dressing density reported

## Serves

`lvl_dressing_density`, `lvl_bare_wall_run_max`.
