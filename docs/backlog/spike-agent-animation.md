---
id: spike-agent-animation
title: "Spike: agent-authored keyframe clips for motions the library can't supply"
status: in-progress
kind: spike
targets: []
after: []
phase: C
branch: spike/agent-animation-baseline
pr: 48
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

## Progress

**Steps 1–3 done** (1–2 in PR #46; 3 on `spike/agent-animation-baseline`). **Step 4 waits on the user:** two reference videos (Kling or Seedance, about $1–3), on the user's video account.

1. **Limb map.** `scripts/review/LimbMap.gd` (feet with contact candidates, hands or striking parts, root bone, bone-space `tips` for leaf bones, a body-plan label). Its defaults are the humanoid map (also `data/rigs/humanoid_limbs.tres`). `foot_slide.gd` measures any number of feet, `game_path.gd` watches the map's limbs, and the motion review takes `--limbs` and `--own-clips`. judge.py needed no change (it reads metric keys, which stay the same). **Humanoid results are byte-identical:** the motion review for the player, Front-file and Back-file on main and on the branch wrote the same 19 metrics and game_path JSON files (SHA-256 compared). `tests/run.sh` passed (171 cases), and so did all six replays and the CI Python checks.
2. **CC0 quadruped:** the Gobkit boar (`assets/meshes/gobkit_Boar.glb`, Gobkit Free Animal Pack Vol. 2, CC0-1.0; licence file and zip hashed in `assets/sources.json`). It's chibi and low-poly: 380 triangles, 16 bones, four single-bone stub legs, and its own idle, attack, dead and walk clips. It went through `import_pack.py`, which needed a cleanup fix: Blender's bind-pose guess pitched the rig 90° nose-down, so sourced glTFs now import at their own node rest. Its map is `data/rigs/gobkit_limbs.tres`: four feet at their soles (tips tested against the mesh), the snout, and Hips. Results from the motion review on its own clips at ground speed 0:
   - idle: travel 0.000 m, slide 0.000.
   - walk: travel 0.000 m, slide p90 1.877 m/s over 126 planted frames. The pack's walk shuffles its rigid legs in place, so the soles skate.
   - attack: travel 3.569 m, slide p90 29.8 m/s. It backs up and charges; the game path shows a 170 m/s snap at attack>idle.
   - dead: travel 3.608 m.
   - bind deviation is at most 1.13 m. The boar is 3.5 m tall at source scale 1.0.

   The gates read all four feet and the snout. **The shipped walk fails foot slide**, which makes it a fair baseline to beat.

3. **Baseline (Tripo, 35 credits, each run confirmed by the user).** Tripo's rig check said the boar mesh is `riggable: false` (quadruped); at the user's request the v2.5 creature rig ran anyway on a mesh-only copy (25 credits) and returned 17 bones: `tripo::Root`, front legs `bone_4/6` → `0_*_Limb_0`, back legs `1_*_Limb_0/1`, a head chain `Head_0/1` that also parents the tail (`Spine_0`), and Tripo rescaled the boar to 1 m long (0.77 m tall). Walk + slash in one retarget failed at 99% (refunded); `preset:quadruped:walk` alone took 10. It's `assets/meshes/gobkit_boar_tripo.glb`, a **derived** sourced prop (`derived_from: gobkit_Boar`; the pipeline now takes a derived asset's file from `.tripo-out/` and needs a `derived` record in `assets/sources.json` with every task id and cost; the prop workaround stays until `sourced-creature-brief`). Its map is `data/rigs/gobkit_tripo_limbs.tres` (soles tested on the skinned rest pose). Motion review at ground speed 0, both looped:

   | | Tripo walk (1.0 m long, 2.58 s) | Gobkit walk (4.6 m long, 1.21 s) |
   |---|---|---|
   | root travel max | 0.011 m | 0.000 m |
   | slide p90, all feet | 0.449 m/s (passes the 0.5 limit) | 1.877 m/s (fails) |
   | front left / right p90 | 0.074 / 0.074 (**frozen**: 0 lift, 0 stride) | 1.882 / 2.225 |
   | back left / right p90 | 0.661 / 0.706 (lift 0.02–0.03 m) | 0.587 / 0.892 |
   | per body length (p90 ÷ length) | 0.45 /s | 0.41 /s |
   | edge stretch max (p99) | 0.685 (0.337), on the face around the eyes | 0.000 (rigid parts) |
   | bind deviation max | 0.089 m | 0.424 m |

   The strip shows the back legs shuffling and kicking, the front legs locked, a head bob that also waves the tail, and the face skin pulling round the eyes. **The Tripo walk passes every numeric gate but isn't a walk:** Tripo's preset drove only the back legs, the head chain and the root bob (6 tracks), so the frozen front feet read as planted with no slide. The gates use absolute metres, so a 1 m boar passes what a 4.6 m one fails; per body length the two slide about the same. Proposed: `motion-gates-gait-and-scale`. Judge packet: `assets/manifests/gobkit_boar_tripo/judge/motion-preset_quadruped_walk-1/packet.json` (the orchestrator runs the judge).

**Step 4 needs:** the user's video account (Kling or Seedance) and their OK for about $1–3.

**Earlier, step 3 needed:** the user's OK for the Tripo spend (about 10 credits, through the tripo skill). It also needs a decision on the subject. Tripo's `quadruped:walk` preset animates a Tripo-rigged model, so either the boar mesh gets rigged by Tripo (rig model `v2.5-20260210`, `--rig-type quadruped`; the dry run gives the price), producing a new skeleton that needs a second limb map, or a Tripo creature is generated instead. Separately, a game-sized subject needs a `source_scale` (about 0.3 for a 1 m boar). Open: `sourced-rigged-creatures`.

