# Decisions (asset pipeline)

Settled choices with their one-line reasons. Read this before re-opening any of them. Dates are 2026-09-27 unless noted.

## Session handoff (update at the end of every session)

- **Last session (2026-10-07):** PRs #55–#59, #62, #63, #65–#67 merged: stagger cooldown only when it interrupts an attack, the QuestManager dialogue lint, dodge i-frames 0.30 s + 0.15 s recovery, replay pre-roll stamps, strict path clearance in CI, the SEARCH replay, the two-fight route replay (Level 1 spacing 3.75 s vs 20–60 s target), render luminance checks (crypt corridor and L2 tomb hall floors dark, player contrast 1.00–1.18), dead enemies stop blocking the player. PR #56 recorded decisions (sword waits for the player rework, UAL2 waits, v3.1 face-limit deferred) and added `godot-ai-4-3-trial` and `spike-mixamo-library`. GitHub returned push 500s for ~10 min around 15:07 UTC; retrying worked.
- **Running:** nothing. Open PRs waiting on the user: #64 `player-attack-commitment` (heavy swing roots 2.0 s; `heavy-swing-lock-length`), #61 godot-ai 4.3.0 (all headless checks match; live playtests are `godot-ai-4-3-playtests`, plus an OK to relabel the guard docstring), draft #60 `spike-target-look` (`decide-target-look`: adopt the Style/FORM changes, then a 60-credit concept round). Other needs-user: `level1-spoke-spacing`, `luminance-target-misses`, `level2-burial-platform`, `upstream-issue-reports`, `fal-video-adapter` (Tripo has no video; fal hosts Kling and Seedance).
- **Resume:** `python3 scripts/tools/backlog.py status`, then `next`. Spawn a `package-worker` per item and follow `docs/backlog/README.md`. Open questions are the `needs-user` items; ask them when their area comes up.
- **Tripo:** balance 365; sessions 2026-10-05 and 10-07 spent 90 of 500 (none on 10-07) (the cap resets to 0 each session). Costs: concept 15, multiview 10, P1 model 50, P2 model 110, v3.1 PBR model 30, rig 25, retarget 10 per preset (a failed combined retarget was refunded). Rig-check by task id when the GLB is large. Read the tripo skill before any spend.
- **Permissions (2026-10-02):** in auto mode, ask only before spending credits or tearing down existing worlds or models wholesale.
- **Where things are:** shipped work and its numbers are the `done` items in `docs/backlog/`; current target values are in the design bible's §9; rules are below (Settled, Decided, Learned); the tool list is under Tools.

## Settled

- **Budgets are in triangles, not vertices.** Vertex counts move with UV-seam splitting (the blade was 1,454 as imported but 519 welded, for 1,026 triangles), while triangles are what `face_limit` controls and Godot reports stably. The budget is `face_limit` + 10%.
- **Prompts describe what is there, never "no X".** "No crossguard" failed twice (a thick bar in attempt 1, a thin plate in attempt 2); positive shape and concrete color fixed the color and shrank the guard.
- **Image-to-3D over text-to-3D.** Text alone gives no spatial control against Tripo's strong priors. A concept image does, and iteration happens at the image stage (~15 credits) instead of the model stage (40).
- **The concept image is approved before any 3D spend.** The pipeline stops after the concept stage and waits for the user.
- **banana_pro is the default concept model; seedream_v5 sits behind a flag** for cheap multi-variant exploration. banana_pro is in the CLI's text-to-image whitelist, so it accepts text-only prompts (from the CLI's code and docs; no live call has confirmed it yet).
- **The FORM prompt block goes on image and 3D prompts. Concepts get flat, shadowless CONCEPT LIGHTING on a plain background; the torchlit MOOD LIGHTING is for mood/reference images only.** Multiview-to-3D takes no prompt, so the concept image is FORM's only channel to the mesh, and any directional light in it bakes into the albedo and misleads reconstruction. (Revised 2026-09-27; concepts were torchlit before.)
- **Prompts use plain colors, never palette names.** The pipeline swaps each name for the art bible's plain color, since image models can't resolve "Old Bone" (the same failure as the blade's green sword).
- **Briefs prompt silhouette-level shapes only; wear and small marks go in the albedo.** At `face_limit` 5,000, fine detail vanishes or eats the budget (the blade put 84% of its triangles into the grip wrap).
- **Quaternius + BoneMap over Tripo retarget.** Quaternius is CC0, so the raw animation files can live in this public repo (Mixamo allows shipping its animations in a game but forbids redistributing the raw files, which a public GitHub repo does). Tripo's retarget costs 10 credits per animation per character (7 clips × 4 characters = 280 credits, recurring), while Godot's BoneMap retargeting is free and done once across every character.
- **`pipeline.py` prints `tripo` commands and never runs them.** A subprocess would bypass Claude Code's permission prompt, and non-interactive runs auto-add `--yes`, so the chat confirmation plus the permission gate are the only spend control.
- **The Tripo model is pinned per brief (`tripo_model: P1-20260311`).** The CLI's auto-selection depends on prompt wording and `face_limit`.
- **Props are aligned on their principal axis, and the thinner end is placed at the brief's `tip_end`.** Blade attempt 1 passed every other check while 46° off-axis (45% too long) and upside down.
- **The rig model follows the body plan, not recency.** Tripo's rig docs (developers.tripo3d.ai/en/docs/animations-rig): `v1.0-20240301` is the server default, biped-only and recommended for humanoids; `v2.5-20260210` is the creature rigger (quadruped, hexapod, octopod, serpentine, aquatic, avian). The pipeline defaults to v1.0 and keeps `--rig-model` for creatures such as the Sett-boar. We had it backwards at first: v2.5 on the Barrow-levy returned generic limb chains.
- **Rigid rebind for rigid-part characters** (brief `rigid_parts: true`): each disconnected part goes at weight 1.0 to its nearest weighted bone. This is an explicit exception to CLAUDE.md's no-weight-scripting rule, because it's a deterministic algorithm rather than hand-tuning. It never applies to continuous-skin characters.
- **Quaternius stays the animation source; Tripo's rig v1.0 presets (90+) are a fallback only.** The reasons are the same as for Quaternius over Tripo retarget: licensing, and cost per character.
- **Characters: raw download → Tripo auto-rig → clean.** Tripo's rigger reads models in Tripo's own +X orientation, and the clean stage rotates characters to −Y, so the cleaned Barrow-levy rig-checked as unriggable while the raw download was a riggable biped (both checks free).
- **Cleanup corrects the albedo toward the approved concept, not the palette** (art bible → Color correction). Tripo's delight pass both desaturates and darkens. Hue and saturation are restored fully; lightness is lifted only, to the matched concept tone, which lands on the concept's shaded facets, so it never exceeds a tone the concept contained. Assets read slightly darker than the concept's lit facets by design.
  - **Why not the palette:** nearest-palette grouping put every dark, low-saturation color on the player (a navy tunic, a purple-brown vest) under Blackened Iron.
  - **Why not full lightness:** the concept's shaded facets contaminate lightness anchoring, and the Barrow-levy moved 9.7 ΔE darker.
  - **Why not hue and saturation only:** it left Tripo's darkening, 3.5 lightness below even the shaded tone.
  - **Rules:** concept-less assets use the palette under the same rule; readability problems are fixed level-side (ambient and torch energy), never with per-asset texture brightening.
  - **Measured effect:** 7.5 ΔE median on the Barrow-levy; 5.9 ΔE on the blade against its old palette correction.
- **Specular 0 is set at import in Godot**, by a glTF import extension (`addons/stylized_materials`), because Godot 4.6 ignores glTF's own specular. It was chosen over a per-GLB import script, which every new asset's fresh `.import` would silently miss, and over a shared enemy material, which covers only enemies and would have to override per-asset albedo.
- **The art bible is the only source of budget numbers.** Briefs copy them; skills and scripts never hardcode them.

- **Animation: Quaternius UAL1 and UAL2 Standard, retargeted through two BoneMaps** (Quaternius names and `mixamorig` names, each onto SkeletonProfileHumanoid, set in the GLBs' import settings). Clips are resampled with speed and trim baked in by `scripts/tools/build_animation_library.gd`. There's one small AnimationLibrary per character (player, Front-file, Back-file) over one shared set of clips. Retargeted bones use profile names, so the socket maps now say `RightHand` / `LeftHand`.
- **Locomotion follows native clip speed; gameplay speed moves instead** (playback 0.75–1.5×). No loop in either pack sits between 1.05 and 5.36 m/s. So the Front-file chase went 3.0 → 4.0 m/s (jog at 0.75×) and the Back-file 2.5 → 1.4 m/s (formal walk at 1.44×). The drilled-soldier lore favours human clips over the zombie set, and the idles give the art bible's posture split for free (Front-file hunched `Sword_Idle`, Back-file upright `Idle_Loop`).
- **The dodge is 0.5 s** (was 0.35) at 8.4 m/s, the same 4.2 m. The roll clip is trimmed to its core (0.20–1.10 s) and played at 1.8×.
- **The Back-file bow draw is a stand-in** (`OverhandThrow`). The bow clips are in a non-Standard UAL2 tier; buying it waits until the slice has been judged in motion (it affects 2 of 7 enemies).
- **Enemies are freed after the death clip (2.4 s) and fade over the last 0.3 s through material alpha on per-enemy material copies.** The Compatibility renderer doesn't draw `GeometryInstance3D.transparency` (a 0.5 test rendered fully opaque).

- **Death collapses in place.** The levies' fling had two causes: `Death01` moves the hips about 0.5 m backward, and the enemy kept its knockback velocity through the DEAD state (it still called `move_and_slide()`). The build tool now holds the Hips/Root horizontal position (`in_place`) for death, and `BaseEnemy` zeroes velocity and stops navigation when death starts.
- **Fix Silhouette on the characters' imports** (`retarget/rest_fixer/fix_silhouette/enable`). The A-pose levy retargeted from the T-pose library over-rotated its arms down and behind the back; attaching the weapons didn't help. With it on, the idle, stagger and run arms sit in front. `Walk_Formal_Loop` really is hands-behind-back, so the Back-file walks with `Walk_Loop` (same native speed).
- **Held props through one helper** (`scripts/combat/HeldProps.gd`), used by `BaseEnemy` and now the player (`data/rigs/player_sockets.tres`). Alignment lives in wrapper scenes (`scenes/props/Held*.tscn`, generated by `scripts/tools/make_held_props.gd`) in the hand bone's retargeted frame, which is the same on every character. The player reuses the Levy Blade for now.

- **Levy Bow: concept-1 approved as a mild recurve** (not worth 15 credits to sharpen a curl that 1,320 triangles would smooth out). It came back at 1,192 triangles, with no holes and **the string intact as its own part** (1.4 cm × 86 cm, strung between the tip rings), so no cleanup string was needed. The prompt was rewritten to describe only what's there before generating (the old one had "no hands, no arrow" and "cracks"). It's held in the Back-file's `hand_l` via `scenes/props/HeldLevyBow.tscn`: limbs upright along the thumb side, string toward the archer.

## Decided (dated, with the user)

Moved from the session handoff on 2026-10-02. Each one-off item it created is named in brackets.

- **2026-09-30:**
  - Tool-script warnings count against §8: fix the 10 GDScript warnings in the baseline in a `chore/` PR (`fix-gdscript-warnings`).
  - Level scaling is a static `CharacterStats.level_scale(level)`; scaled integer stats round to nearest.
  - Enemy attack stats get raised to meet the 8–10% enemy-damage target; the target stays.
  - The clearance check runs `--strict` in CI since PR #62 (2026-10-07); a FAIL or DETOUR segment fails the navmesh job.
  - Sourced props have their own budget line in the art bible, textured from the kit's shared atlas. Kit scale stays 1.0 until pieces are first placed; any rescale is one factor per pack.
  - The per-footprint colour measurement stays for sourced assets only. The floor tile's slight brown drift is accepted.
- **2026-09-30 – 10-01 (gameplay batch):** the user approved every default in the batch: the Front-file chase at 4.6 m/s (the player's escape margin is 0.4 m/s), denser torch spacing, and visual-only collision on skirting and plinths. Hearing needs sight; no alerting of nearby enemies; waiting levies hold until a strafe clip exists (`strafe-clip`); short pose holds are allowed in telegraphs; tell sounds wait for the audio pass (`enemy-tell-sounds`). The player's own sword waits until Tripo P2.0 is researched (don't spend on the P1 model); that research is now done (`decide-player-sword`).
- **2026-10-01 (Phase B):** Dialogue Manager kept (4 local patches; never its in-editor updater). Material Maker kept (1.5p1; dark floors are fixed level-side). func_godot kept as **brush shell + kit detail** (the addon stays disabled; build tool only). Our own camera rig, framing A, picked by the user after two playtests; Phantom Camera rejected. Bouncing off tight pillars is accepted as a camera-system limit: level layout keeps pillars clear of the play space instead. `cam_wall_fill` counts only wall between the camera and the player or beside him.
- **2026-10-02:**
  - Animation blend times adopted: every handover under `motion_handover_snap_mps` (5 m/s).
  - The player's skirt skin stretch (3–5× in every clip) is accepted for now. The user finds the player model weak up close with the new camera, and it gets reworked (`player-model-rework`) after `spike-body-only-humanoid`.
  - Tripo P2.0: P1 stays for the player (`docs/trials/tripo-p2.md`).
  - **Licence:** Quaternius's site moved to a no-redistribution licence on 2026-08-28; the UAL1/UAL2 packs we committed on 2026-09-27 ship a CC0 `License.txt`, and the user decided to rely on it and keep the repo public. A future UAL2 Source purchase comes under the new licence, so its source files stay out of the public repo (`ual2-source-purchase`).
  - **Permissions:** in auto mode, ask only before spending credits or tearing down existing worlds or models wholesale.
  - The camera resetting and bumping near walls and pillars (playtest) reads to the user as mostly level design; track it as crypt layouts are built (`camera-wall-snap-in`).
  - **Backlog:** home-grown, one file per item in `docs/backlog/`, with BMAD's ticket semantics (`decide-backlog-system`).
  - **Scripted keyframe clips** for motions the library can't supply, non-humanoids first: CLAUDE.md's third animation exception (`spike-agent-animation`).
  - **Weight transfer onto clothing shells:** CLAUDE.md's fourth animation exception; Phase 0 of `spike-body-only-humanoid` approved (0 credits).
  - **E is `camera_right`;** F is the only keyboard interact key (`fix-e-double-binding`, #44).
  - **Attack-token hand-off delay:** a dead or released melee holder keeps its token reserved until 2.0 s after its last attack start, so `enemy_attackers_max` holds (`attack-token-handoff-delay`, #43).
  - **Texture import settling:** generated 3D textures get the editor's own detection (`compress/mode=2`, mipmaps) at validate time, per folder, not through `[importer_defaults]`; surfaces stay lossless (`import-pack-compress-mode`, #45).
  - The Gobkit boar's mesh escalation is accepted: its near-white tusks and eye rings repainted to Old Bone read as bone.
  - **Sourced rigged creatures are allowed:** a brief type keeps their own rig, validates bones and the limb map, and motion-reviews their clips; humanoids still use our rig flow (`sourced-rigged-creatures` → `sourced-creature-brief`).
  - **P2 with weight transfer is not adopted; P1 stays the player.** The rework waits on the art direction (`decide-player-p2parts`).
  - **Gait minimums** `motion_gait_lift_bh` 0.005 and `motion_gait_swing_bh` 0.05, and motion limits per body height instead of metres; raise the gait numbers if clips pass but still shuffle (`decide-gait-thresholds`, #49).
  - **Art direction** (`decide-art-direction`): character albedo 1024 px (512 the floor), smooth shading on continuous-skin characters (30° flat stays for props, kit and rigid parts), the B2 lighting standard with fog and filmic allowed, stay on Compatibility, and move away from KayKit toward brush shells and a kit closer to the look (`art-rules-b2` #51, `kit-replacement`).
- **2026-10-03:**
  - The Barrow-levy's B2 colours are accepted for now (bone greyer than the concept, harness near-black); revisit in the enemies' art pass.
  - The player's skirt stretch is accepted as a design note (judges don't re-flag it) until `player-model-rework`.
  - **Look-dev C:** stay at B2. The model tier isn't the limit, the concept is: 1.43M PBR triangles barely show over B2 from the gameplay camera (`look-dev-c`, #52; a face-limited v3.1 is `look-dev-c-face-limit`).
- **2026-10-05:** the user's reference games are the Souls series (especially Elden Ring) and The Witcher, "dark epic fantasy" fitting Malazan. That pulls against the art bible's PS1/PS2 "bold colours" line; it's researched and put to the user in `spike-target-look` before any rule changes. The user is opening a fal.ai account for reference videos (`fal-video-adapter`).
- **2026-10-08:** the target look is adopted (`decide-target-look`, `docs/trials/target-look.md`): "bold colors" gives way to restrained earthy colour with saturated accents (fire, gold, blood, magic) and a value-led read, after the Souls series and The Witcher; FORM asks for naturalistic adult proportions and worn, faded colour; Tarnished Gold is a dull antique gold `#9C7A2E` on assets (the UI keeps `#E6BF1A` as XP Gold); colour-level wear words are allowed in prompts. The four `player_look_a`–`d` concepts run next (60 credits); the identity mark (spiky hair or half-helm) is left to the images.

## Learned 2026-10-02 – 10-05

- **The P2 A/B misread its tearing:** most of it was `skirt_reweight` catching P2's boot cuffs, not the shells; the real tear was the harness (`spike-body-only-humanoid`).
- **Tripo's rig-check can say "not riggable" and v2.5 still rigs it** (the Gobkit boar, 17 bones). Check by task id when the GLB is too large to upload.
- **Combined retarget presets can fail** (walk + slash failed at 99%, refunded); run one preset per call.
- **The judge misses frozen limbs:** Tripo's quadruped walk passed every numeric gate with both front legs locked, which is why the gait gate exists (#49).
- **Concept art drives the look more than the model tier:** v3.1 at 1.43M triangles with PBR from the same concept read almost the same as B2 in play. A different look starts at the concept.

## Learned 2026-10-01 – 10-02

- **Open playtests with `playtest-branch.sh <ref>`** (default `--play`). With `--editor`, the user pressed F5 in their own editor on `main` twice and reported "nothing changed". A no-input capture also hid a mouse-pitch bug, so camera evidence must include camera input.
- **P2 hands the rigger separate shells.** Each is weighted on its own and tears at every seam when animated (stretch 7–14× against P1's 3–5×); `skirt_reweight` assumes one continuous body.
- **The pre-push hook stops failing tests before CI,** so the JUnit failure annotations (#36) haven't been seen yet; the first real CI failure will show them.
- **The held-prop generator was non-deterministic** until #38's generator checks caught it.

## Learned 2026-09-28

- **Rest-pose mismatch over-rotates arms:** the A-pose levy on the T-pose Quaternius library swung its arms down and behind the back; the `retarget/rest_fixer/fix_silhouette/enable` import option fixes it. Check this on every new character.
- **Death clips carry baked hip translation** (`Death01` about 0.5 m backward): the build strips it (`in_place`), and code must zero velocity and stop navigation when death starts.
- **`Walk_Formal_Loop` clasps the hands behind the back,** so it's unusable for armed characters.
- **Props attach through generated wrapper scenes** (`scenes/props/Held*.tscn`, `scripts/tools/make_held_props.gd`) in the hand bone's retargeted frame, with one helper (`scripts/combat/HeldProps.gd`) for the player and the enemies.
- **Observed Tripo costs:** concept 15, multiview 10, model 50, rig 25, so a character is about 100 and a prop about 75.

## Learned 2026-09-28 (asset judge)

- **Replays match the user's own calls on 3 of 4 flagged defects.** Levy concept-1: revise for the paired shins, forearms and separate fingers, with an edit prompt close to the one that made concept-3. Blade attempt 1: escalate for the crossguard (4 welded parts) and the olive blade. Player raw model: escalate for the missing back X-straps (the vest decision), found without being told. **Missed: the flattened mouth.** The close-up shows it, but the judge called the face recognizable. Controls (the shipped blade, the approved concept-3) pass. The pre-fix death fling: revise with `in_place`, the fix that shipped.
- **Palette correction can hide a wrong color.** Blade attempt 1's olive blade grouped under Old Bone (27.5 ΔE) and came out bone-colored, so the corrected renders looked plausible. Model packets now carry Tripo's uncorrected preview and a pre-correction distance assertion (`palette_de_before`).
- **Replays must not see later decisions.** The first player replay passed because the art bible's brief section carried the "Shipped design change" bullet. `--no-design-notes` now strips it from the brief section too.
- **A retargeted skeleton's rest pose isn't its bind pose** (the rest fixer moves the rests; 13 cm off on the player). Skinning metrics take bind positions from the mesh vertices.
- **Edges under 1 cm make stretch ratios meaningless** (a 3.6 mm crotch edge read 14×).
- **`in_place` moves travel, it doesn't remove it:** pinning `Death01`'s hips makes the feet sweep along the floor at 1–3 m/s during the fall. The motion review's foot-slide plot shows it; the onion skin alone doesn't.
- **The judge can misdiagnose a cause** (it blamed an "opening lurch" and trimmed 0.15 s; the sweep stayed). One auto-refine, then escalation, is the right budget: the second verdict escalated with the correct diagnosis.
- **Agent definitions load at session start;** a judge added mid-session runs as a general-purpose agent told to follow `.claude/agents/asset-judge.md` with Read only.
- **The packs have only one death clip (`Death01`)** (2026-09-29, fix-ladder step 3). `Hit_Knockback` (a thrown-back knockdown, 0.09 m of hip travel with no pinning) was tried as the levies' death and rejected, because it reads worse than a crumple for undead levies. `LayToIdle` reversed reads as a lie-down, not a death. The levies keep `Death01` with `in_place` and the foot-slide exemption.
- **The face question half-worked:** the judge now reports the player's raw mouth as "faint, a thin line", but it still didn't raise that as a finding, even though the question says it should. Treat mouths and eyes as a known blind spot; check faces yourself on new characters.
- **Pipeline evidence images stay local** (decided 2026-09-29): renders, packet copies, replays and animation sheets under `assets/manifests/` are gitignored (they had reached 121 files, 24 MB). The JSON is committed and records each image's SHA-256, so a verdict's evidence can be checked against a local copy but not viewed from a fresh clone. Finished assets (`assets/meshes/`, `assets/overlays/`) are unaffected.

## Learned 2026-09-29 (Godot MCP trial)

- **The Godot 4.6.1 → 4.7.2 upgrade changed nothing measurable.** Import errors, the library build, validate on four assets, the 16 motion clips and Level 1 movement all matched. Only the animation clips were re-saved in 4.7's format.
- **A vsynced window behind another app crawls on macOS.** A motion review went from minutes per clip to 3.7 s once the review scenes turned vsync off. The metrics were identical.
- **godot-ai's active session is server-global.** The first editor to connect gets it, and any client's `session_activate` moves it. The guard therefore requires the agent's `session_id` on every call and denies `session_activate`.
- **A `settings.json` "ask" rule beats a hook's "allow".** The headless playtester's `project_run` was denied until the tool was taken out of the ask list and the hook alone decided.
- **Synthetic input actions never reach `_input`.** They only affect `Input` polling, so combat read in `_input` needs `input_key`, which the sequencer can't frame-time. `input_sequence` steps need `at_frame`; `frame` is silently treated as 0.
- **The playtester saw what the human sees:** ceiling-less boxes, occluded melee, invisible lock-on, and a broken respawn. It needs lockstep play to judge combat, since real time lags 8–20 s of game time per call.
- **`user://` is keyed by the project name,** so every worktree and review copy shares `save.json`. A playtest can load, or overwrite, the human's save.

## Observed Tripo costs

- P1 text-to-3D with a standard texture: **40 credits** (twice: attempts 1 and 2). The pricing page's 20 was the H-series price, so it undercounted P1 by 2×. The CLI's `credits_consumed` matched the balance difference every time.
- banana_pro text-to-image (`template=t_pose`, 3:4): **15 credits**, matching the estimate and the CLI's report (Barrow-levy concept-1).
- banana_pro image-to-image refine (same params): **15 credits**, the same as text-to-image (Barrow-levy concept-2).
- **Chained refines converge when the edit is short.** A five-item refine landed 3 of 5 changes (concept-2); a two-item follow-up ("keep everything exactly as it is except …") landed both and preserved the rest (concept-3). Budget 2–3 images per character concept.
- **Three concept images per asset, at most.** This is about cost, and also about drift: each chained image-to-image pass degrades the image a little. By the third, the background had picked up a lighter centre instead of staying even grey, and edges were over-sharpened with slight color banding (Barrow-levy concept-3). Both feed straight into multiview.
- image-to-multiview: **10 credits**, matching the CLI's report (Barrow-levy multiview-1). It returns four 1024² JPEGs on a white background.
- P1 multiview-to-3D at `face_limit` 5000: **50 credits**, matching the CLI (Barrow-levy attempt-1). That's 10 more than P1 text-to-3D.
- Tripo auto-rig (biped, `v2.5-20260210` requested): **25 credits**, matching the CLI (Barrow-levy rig-1). Rig-check is free (0 credits, twice).
- P1 multiview-to-3D costs 50 at `face_limit` 1200 too (Levy Bow), so the price doesn't depend on `face_limit`. A generated prop costs about 75 in all (concept 15 + multiview 10 + model 50).
- Not yet observed: seedream_v5. Add each to the tripo skill's table after its first run.
- P2 multiview-to-3D (`P2-20260801`) at `face_limit` 5000: **110 credits**, matching the CLI (player attempt-2, the P2 A/B; plus rig v1.0 25).
- v3.1 PBR multiview-to-3D (`v3.1-20260211`, no `face_limit`): **30 credits** (look-dev C, plus rig v1.0 25). Rig v2.5 quadruped 25; retarget `preset:quadruped:walk` 10; walk + slash in one retarget failed and was refunded (the Gobkit boar, 35).
- Project spend so far: 635 (80 on the blade; Barrow-levy 155; player 100; Levy Bow 75; the P2 A/B 135; the Tripo boar baseline 35; look-dev C 55); balance 365.

## Open risks

- *(Resolved: the Sketchfab skeleton's toe and hand bone defects no longer matter; `archer_enemy.glb` is retired from the enemy scenes.)*
- *(Resolved: Tripo's overshoot on characters is inside the 10% headroom: the levy was +0.9%, and the player came in 2.1% under.)*
- **The blade's grip wrap has 4 small slits and 16 non-manifold edges** (recorded, not repaired). Mesh health is a baseline only; nothing fails on it yet.

- **Tripo's first auto-rig of the Barrow-levy is lopsided** (rig-1, 25 credits). `--spec mixamo` was accepted but ignored: it returned Tripo's generic 22-bone limb rig (`tripo::0_Left_Limb_0`…), which no name heuristic maps to SkeletonProfileHumanoid. The right arm is correct (collarbone, upper arm, forearm, hand). The **left arm is one bone short:** its elbow sits mid upper arm and there's no left hand bone, which is the bow socket. The thighs are only about 55% weighted to the thigh bone, the foot bones point down instead of forward, and two stray bones (`bone_20`, `bone_21`) stick out of the chest and back.
- **Observation, not a rule:** the docs list `spec` as a top-level rig parameter (default `tripo`, alternative `mixamo`) with no model restriction, yet the v2.5 run ignored it. That stays unexplained.
- **Barrow-levy rigid rebind results:** the pelvis and belt went to Hips at 1.00 (the pelvis was 0.26 before), the lower ribs to Spine1 at 1.00 (0.22–0.55 before, partly on the arms), and every limb, the skull and both hands to their own bones at 1.00. **Known quirk:** the Foot bones sit at floor level, so the feet bind to ToeBase, Foot's child. That's harmless, because Quaternius drives Foot and not the toes, and it won't read at gameplay distance.
- **Rig v1.0 (`v1.0-20240301`) honoured `--spec mixamo` where v2.5 didn't** (Barrow-levy rig-2, 25 credits). It returned 23 `mixamorig:` bones with symmetric chains, including LeftHand, and every SkeletonProfileHumanoid required bone maps. No doc limits `spec` to certain rig models; this one observation suggests v2.5 ignores it. The limbs are clean (each arm and leg segment 0.96–1.00 on its own bone). The weight defects are in the torso: the pelvis and belt are split across both thigh bones (Hips 0.37), a few lower ribs are partly on the arm bones, and the foot bones sit at the floor, so the feet are half on the shin and half on the toe. This is **one asset with near-worst-case input** (35 disconnected pieces with gaps at every joint), not a verdict on Tripo's rigger; the player (continuous limbs, a solid tunic) is the real test.
- **Player (normal continuous-skin case): Tripo rig v1.0 works.** It returned the same 23 `mixamorig:` bones, every SkeletonProfileHumanoid bone maps, and the 4 floating face parts (eyes, eyebrows) are bound to Head at 1.00. **The skirt binds to the legs, the known hard case:** the upper skirt is 93% on the thighs (about 7% on Hips and Spine), and the hem is about 60% thighs and about 40% shins, so it will stretch between the legs when walking. Not fixed yet; options are a deterministic skirt reweight (Hips at the waist blending to the thighs at the hem, no shin weight; needs a CLAUDE.md exception like the rigid rebind), skirt bones, or accepting it at gameplay distance.
- **Player skirt reweighted** (brief `skirt_reweight: true`; second exception to the no-weight-scripting rule): the skirt now has no shin weight; the upper skirt is 82% Hips and the hem 78% thighs and 22% Hips.
- **Bone geometry is measured as joint spans (head to child joint), never head to tail.** Blender's glTF importer invents display tails (the player's thigh tail stopped at 0.70 m, with the knee at 0.45 m), and they differed between the rig download and the exported file, which briefly made a correct reweight look wrong.
- **The color-correction lightness ceiling is soft, not strict:** the player's skin landed 0.8 L above its concept tone (66.2 against 65.4), because blending neighbouring groups' shifts adds a little. That's below the perceptual threshold.
- **Player back readability: level-side lighting doesn't fix it** (sweep in the gameplay view). His back renders near-black (luminance 0.020 against a 0.26 floor). The torch doesn't reach it at all. Ambient 0.5 → 0.9 only raises it to 0.040, while the levy's contrast against the corridor drops from 1.57 to 1.33. The key light faces away from his back in that view. Level 1 lighting is unchanged; the fix is on the asset side (the navy and teal albedo is at L 8–19) or the key light's direction.
- **A character fill light fixes it instead:** an OmniLight3D under the player's CameraRig, on the camera side, culled to render layer 2 (only the player's meshes). It's a CLAUDE.md-sanctioned exception to visible-source-only local lights. The layer cull mask works in the Compatibility renderer: floor, wall and levy luminance were **identical** with and without it. Measured on his back: 0.020 at energy 0, 0.082 at 1.0, 0.148 at 3.0, and 0.206 at 6.0, where the skin blows out orange. **Final: energy 3.5 with the light 2.5 m behind the pivot (range 5)**, where no skin clips (95th percentile 0.82, against 0.6% clipped at 3.0 / 1.5 m) and his back reads at 0.133. The skin's albedo saturates long before the navy tunic reaches the floor's 0.26, so "above the floor" isn't reachable without overexposure; at 3.0 his tunic, vest and belt read clearly.
- **Enemies run on the new Barrow-levy** (`BaseEnemy.tscn` and `ArcherEnemy.tscn` instance `barrow_levy.glb`). After retargeting, the sockets use profile names (`RightHand` / `LeftHand`), and both variants animate from the Quaternius library.
- **Every lit GLB now imports with specular 0** after a forced reimport. The retired `archer_enemy.glb` still shows 0.5, but its material is `KHR_materials_unlit`, so specular never applies.
- **Player open questions, recorded not fixed:** skin showing through the tunic (probably near-coincident vest and body surfaces), and 2 open holes plus 13 non-manifold edges where the vest meets the tunic. In the Level 1 comparison at gameplay distance neither shows; judge them again with animation.
- **Level 1 torchlight comparison** (`assets/manifests/comparison/`, made with `scripts/review/level1_compare.tscn`, the level's own ambient and torch energies): the two characters read as one set, with the same flat faceting and matte albedo, and no plastic sheen. The levy's pale bone pops against the dark corridor. **The player's dark teal, navy and dark boots sit close in value to the corridor from behind**, so the spiky hair and vest carry the read. If that's too dark in play, fix it level-side (ambient and torch energy), per the color-correction rule.
- **Rigged meshes are now welded where coincident vertices share identical skin weights** (fixed; it was 13.2% → 24.4% faceted faces on the rigged Barrow-levy, and is back to 13.2%).
## Tools

- `scripts/pipeline.py <id> --stage all`, `scripts/judge.py packet|record|resolve|log`, and `scripts/tools/import_pack.py` for kits;
- `scripts/tools/build_animation_library.gd`, `make_bone_maps.gd`, `make_held_props.gd`, `bake_navmeshes.gd`, `check_path_clearance.gd`, `build_brush_maps.gd`, `make_textures.py` and `playtest-branch.sh`;
- `scripts/tools/backlog.py next|status|show|lint` for the backlog;
- `tests/run.sh` (gdUnit4), `scripts/review/run_scenario.sh <scenario>` (replay twice, compare, metrics) and `scripts/review/capture_evidence.sh <scenario>` (MP4, event frames, contact sheet);
- review scenes in `scripts/review/`: `motion_review`, `anim_sheet`, `level1_play_capture`, `level1_compare`, `replay`;
- the Godot MCP (CLAUDE.md → Godot MCP), and headless playtests with briefs in `docs/playtests/`.

## Next

Planned work lives in `docs/backlog/` (`python3 scripts/tools/backlog.py next`). The queued pipeline path for downloaded CC0 assets shipped as Phase A4 (#16, `a4-asset-import`).

