---
id: prop-torch-orphan-texture
title: "Retire prop_torch's unused specular-glossiness texture"
status: proposed
kind: chore
targets: []
after: [import-pack-compress-mode]
phase: later
branch: null
pr: null
updated: 2026-10-02
---
## Goal

`assets/meshes/prop_torch_material_specularGlossiness.png` is extracted from `prop_torch.glb` but sits on no material, so the editor never detects it as 3D and its `.import` still awaits detection. `scripts/tools/texture_imports.py --check` exempts it by name.

## Scope

- when prop_torch goes through the pipeline (it also ships normal, emissive and occlusion maps, against the albedo-only rule), drop the extra maps and the exemption

## Acceptance

- `texture_imports.py --check` passes with an empty `EXEMPT`

## Serves

`import-pack-compress-mode`.
