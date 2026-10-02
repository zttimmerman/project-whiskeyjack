---
id: camera-wall-snap-in
title: "Camera snap-in near walls and pillars"
status: proposed
kind: fix
targets: [cam_wall_fill, cam_player_in_frame]
after: [crypt-trial-kit-detail]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

The user reports the camera resets and bumps a lot near walls and pillars (playtest 2026-10-02) and reads it as mostly level design (tight geometry). The arm also snaps in at once when the view swings into a wall.

## Scope

- track it as real crypt layouts are built; revisit the rig's snap-in (an eased pull-in) only if it persists in open layouts
- bouncing off tight pillars is accepted as a camera limit (2026-10-01); layouts keep pillars clear of the play space

## Acceptance

- a playtest in the dressed crypt; `cam_*` checks still pass

## Serves

`cam_wall_fill`, `cam_player_in_frame`.
