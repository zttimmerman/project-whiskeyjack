---
id: b1-camera-rig
title: "B1: our own over-the-shoulder camera rig (Phantom Camera rejected)"
status: done
kind: feature
targets: [cam_melee_occlusion, cam_player_in_frame, cam_wall_fill, cam_lock_both_in_frame]
after: []
phase: B
branch: feature/camera-trial
pr: 33
updated: 2026-10-02
---
## Goal

An over-the-shoulder camera built as modes (§2) that meets every `cam_*` target. Evidence: `docs/trials/phantom-camera.md`.

## Outcome

Our own `scenes/player/CameraRig`; Phantom Camera rejected. Framing A, picked by the user after two playtests: 1.6 m arm (2.2 locked), 0.7 m right, lens about 1.55 m, 65°. Mouse pitch turns the look; the lens stays within ±0.35 m. Lock-on: living enemies in sight only, drops after 1 s hidden, jumps to the next enemy when the target dies, with a red reticle. Every `cam_*` check passes in every scenario (`scripts/review/camera_probe.gd`, `tests/scenarios/camera_stress.json`). Other framings stay selectable through `CameraRig.framing`. Follow-ups: `camera-wall-snap-in`, `camera-first-person`.
