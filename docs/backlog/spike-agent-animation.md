---
id: spike-agent-animation
title: "Spike: agent-authored keyframe clips for motions the library can't supply"
status: ready
kind: spike
targets: []
after: []
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Find out whether an agent can author clips the shared library can't supply, as **committed keyframe scripts** that headless Blender re-runs
(CLAUDE.md → Rigging & Animation, third exception), starting with non-humanoid body plans. Approved by the user 2026-10-02.

## Scope

Each step is a gate; stop and report if one fails.

1. **Generalise the motion review and the game-path check to a per-rig limb map** (which bones are feet, hands, spine for any body plan) instead of humanoid names. Free.
2. **A CC0 rigged quadruped** as the subject, through the import path with provenance in `assets/sources.json`. Free.
3. **Baseline:** Tripo's `quadruped:walk` preset on it, through the tripo skill (10 credits; the user confirms).
4. **Two reference videos** (Kling or Seedance, about $1–3 in all). The user creates the account; the spike stops and asks at this step.
5. **Agent-written keyframe scripts** (`scripts/tools/keyframe_clips/<asset>_<clip>.py`), re-run headless to produce each clip; the manifest records the reference
   provenance (video hash, prompt, model). Live MCP keyframing is never the source of record.
6. **Gates:** the motion review, the asset judge and the game-path check, the same as library clips.

## Acceptance

- **Success:** a quadruped walk loop and one attack that pass every motion gate and the judge, regenerate identically from their scripts, and read at least as well
  as the Tripo baseline (judge plus the user)
- **Go:** success within the fix ladder, with an iteration cost the user accepts for the Sett-boar and later creatures
- **No-go:** the gates still fail after the fix ladder, or the clip needs live MCP keyframing or hand-tuning to pass
- **Cost:** 10 credits, about $1–3 of video, and agent time; nothing else paid

## Serves

Non-humanoid enemies (the Sett-boar first); possibly humanoid gaps the packs don't cover (see `strafe-clip`, `bow-clips`).
