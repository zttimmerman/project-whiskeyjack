---
id: fal-video-adapter
title: "A fal.ai adapter skill for reference videos (Kling, Seedance)"
status: needs-user
kind: chore
targets: []
after: []
phase: C
branch: null
pr: null
updated: 2026-10-05
---
## Question

`spike-agent-animation` step 4 needs two reference videos (Kling or Seedance, about $1–3). On 2026-10-05 the user said they're creating a fal.ai account for this. Once it exists, a fal adapter skill is built like the tripo skill: a dry run with the price, the user's confirmation in chat for every paid call, a per-session spend cap with a running total, and downloads in the same run. The key stays outside the repo (for example `FAL_KEY` in the environment or a file under `~/`), never in chat, code, docs or logs.

Waiting on: the account and key exist, and the user sets the per-session cap and which models (Kling, Seedance) the skill may call.

## Options

1. **A fal adapter skill** (`.claude/skills/fal/`), with a `.claude/settings.json` ask rule on its paid calls, as for `tripo`.
2. **The user generates the two videos by hand** on fal.ai and drops them into `.tripo-out/`; the spike records their hashes and prompts. No adapter yet.

## Recommendation

Option 1 if more than the two spike videos are likely (later creatures, the bow and strafe clips). Option 2 unblocks step 4 at once if the user wants that first. Either way, step 4 of `spike-agent-animation` resumes once the videos exist.
