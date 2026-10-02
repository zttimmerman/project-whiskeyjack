---
id: import-pack-compress-mode
title: "Have import_pack.py write compress/mode=2 for new kit textures"
status: done
kind: fix
targets: []
after: []
phase: gameplay-2
branch: fix/import-pack-compress-mode
pr: 45
updated: 2026-10-02
---
## Goal

New kit textures should import as the editor detects them (VRAM compressed, `compress/mode=2`), as #28 did by hand.

## Scope

- `scripts/tools/import_pack.py` writes the `.import` with `compress/mode=2`

## Acceptance

- importing a piece leaves the checkout clean after an editor open

## Serves

`kit-texture-import`; Phase C kits.

## Outcome

Merged in PR #45: scripts/tools/texture_imports.py settles generated 3D textures' .import at generation (GLB-extracted and brush textures VRAM as the editor detects them, surface textures lossless); pipeline validate settles GLBs; CI --check fails a texture still awaiting detection.
