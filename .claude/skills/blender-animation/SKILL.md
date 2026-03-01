---
name: animate
description: Create bone-keyframed animations for a rigged GLB model via Blender MCP. Use when animating 3D models, creating animation sets, or when a GLB needs idle/run/attack/stagger/death animations.
argument-hint: "[glb-path] [optional: animation names]"
context: fork
agent: blender-animator
globs:
  - "assets/meshes/*.glb"
  - "scenes/enemies/**"
  - "scenes/npcs/**"
  - "scenes/player/**"
---

Create bone-keyframed animations for the GLB model at `$ARGUMENTS`.

If only a file path is provided, create the default animation set: idle (60f), run (24f), attack (15f), stagger (12f), death (30f).

If specific animation names are listed after the file path, create only those animations. Recognized animations and their frame counts:
- `idle` (60 frames, looping)
- `run` (24 frames, looping)
- `attack` (15 frames, one-shot)
- `attack_light` (15 frames, one-shot)
- `attack_heavy` (20 frames, one-shot)
- `stagger` (12 frames, one-shot)
- `death` (30 frames, one-shot)
- `dodge_roll` (20 frames, one-shot)
- `shoot` (18 frames, one-shot)
- `cast` (24 frames, one-shot)

Export the result back to the same file path, overwriting the original.
