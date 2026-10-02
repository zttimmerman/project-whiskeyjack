---
id: kit-texture-import
title: "Commit kit texture imports as the editor detects them"
status: done
kind: fix
targets: []
after: []
phase: gameplay-1
branch: fix/kit-texture-import
pr: 28
updated: 2026-10-01
---
## Goal

Opening the editor rewrote the kit textures' `.import` files, so checkouts went dirty.

## Outcome

Committed as the editor detects them (VRAM compressed), so checkouts stay clean. New kit textures still get the wrong mode from `import_pack.py`: `import-pack-compress-mode`.
