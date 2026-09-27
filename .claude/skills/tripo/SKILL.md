---
name: tripo
description: Vendor adapter for the Tripo CLI. Owns command construction, spend gating, the per-session credit cap, balance checks and URL expiry. Use for any `tripo` command. The asset-pipeline skill orchestrates everything around it. Supersedes the skill bundled with tripo-cli.
---

# Tripo CLI adapter

**Layering:** this skill is the vendor adapter. The **asset-pipeline** skill (`scripts/pipeline.py`) is the orchestrator: it owns briefs, stage order, cleanup, validation and the manifest. Its concept and model stages print the exact `tripo` command to run. That command runs **here**, under these rules, and `pipeline.py` then ingests the files this skill leaves on disk. `pipeline.py` never runs a paid `tripo` command itself, because a subprocess would bypass the permission gate.

**Budgets aren't set here.** `face_limit` and every other budget number come from the asset's brief YAML (`assets/briefs/<asset-id>.yaml`), which is copied from `docs/art-bible.md`. Use the value `pipeline.py` prints; never choose or adjust one.

The CLI ships its own agent docs (`tripo docs --llm`, `tripo docs --topic commands/make`). Use them as a **reference only**. Where they conflict with this file, this file wins. In particular, the bundled docs:
- say to re-run immediately once a dry run is valid. **Never do that here.**
- use `--yes` and `--for` presets in their examples. **Never use either.**

## Hard rules

1. **Session cap: 500 credits** (1 credit = $0.01). Track the running total of *actual* spend in the conversation and show it as `used / 500` with every confirmation request. Warn once the total reaches 400. Refuse any run whose estimate would push the total past 500, unless the user raises the cap for this session. Failed and unusable attempts count at whatever the balance difference shows.
2. **No spend without explicit confirmation for that specific run.** The flow is always: dry run → show the plan → the user says yes in chat → run. The permission prompt from `.claude/settings.json` is a second gate, not a substitute. Non-interactive runs auto-enable `--yes`, so the CLI itself will never ask.
3. **Invoke as bare `tripo`.** Don't use `npx`, `nvm exec`, an absolute path, or a script wrapper, because the permission rules match on the `tripo <cmd>` prefix. Run one `tripo` command per Bash call, with no `&&`, `;` or pipes around a paid command. Redirecting output to a file is fine.
4. **Art-bible parameters, no presets.** Never pass `--for`. Pass exactly the parameters `pipeline.py` prints (`--model` from the brief's `tripo_model`, `pbr=false`, `texture=true`, and the brief's `face_limit`). Output is GLB only: no `--then convert` (non-default convert options bill at the advanced tier). Don't add a `--then` step unless the user approved that step's cost.
5. **Pin the model; never rely on auto-selection.** Without `--model`, the CLI picks the model itself: explicit low-poly intent in the prompt **or** `face_limit` ≤ 20000 selects P1, anything else v3.1. That's the CLI's internal rule (`knowledge/models.js`), so rewording a prompt or a CLI update could silently switch models. Every brief pins a wire version (e.g. `tripo_model: P1-20260311`); the server accepts only wire values, and the CLI also maps aliases like `tripo-p1` to them. P1 rejects `quad`, `smart_low_poly`, `generate_parts` and `geometry_quality`, and outputs triangles only.
6. **Commands:** use `tripo --version` for the version (there's no `version` subcommand) and `tripo balance --json` for the balance (`{"balance","frozen"}`; there's no `account` subcommand).

## Cost estimate

From https://developers.tripo3d.ai/en/pricing (checked 2026-09-27; re-check if a run's actual cost differs):

**Observed costs, which beat the table for estimating.** The CLI's `credits_consumed` has matched the balance difference exactly so far:

| Date | Operation | Model | Estimate | Actual (balance delta) | CLI-reported |
|---|---|---|---|---|---|
| 2026-09-27 | text → 3D, standard texture, `face_limit` 1000 | P1-20260311 | 20 | **40** | 40 |

The pricing-page table below undercounted P1 by half. The page has H-, P- and Splat-series tabs; this table was read from its flattened text and is most likely the **H-series** price. Estimate P-series work from the observed-costs table, and add each new operation type to it after its first run.

| Operation (likely H-series) | No texture | Standard texture |
|---|---|---|
| Text → 3D | 10 | 20 |
| Image → 3D | 20 | 30 |
| Multiview → 3D | 20 | 30 |

Add-ons stack on top: HD texture +10, Smart Low-poly +10 (not available on P1), Quad +5, HD geometry +20. Text-to-image concept art costs 5–15 depending on the image model. The estimate is guidance only; **the balance difference is the truth.**

## Files this skill writes (all in the gitignored `.tripo-out/`)

| What | Where |
|---|---|
| Raw CLI output | `.tripo-out/<asset-id>/<kind>-<n>/<slug>-<id8>/` (`kind` is `concept` or `attempt`; `-o` is a base folder, so the CLI creates the subfolder) |
| Run stdout and stderr | `.tripo-out/<asset-id>/<kind>-<n>.result.json`, `.log` |
| Spend record | `.tripo-out/<asset-id>/<kind>-<n>.spend.json` (schema below). `pipeline.py` copies these into the committed manifest |

## URL expiry and resuming

- Tripo's output URLs **expire about 5 minutes after the task succeeds.** Artifacts must be downloaded in the same run. Let `tripo make` / `tripo generate` block until they finish downloading, and never pass `--no-wait` or `--no-download`.
- **Resuming is file-based, never task-ID-based.** On re-entry, look at `.tripo-out/<asset-id>/`:
  - artifacts present → the attempt is done; run the pipeline stage to ingest it;
  - artifacts missing after a charged attempt → set the spend record's `status` to `lost` and tell the user.
- Don't try to recover by task ID. Task IDs go in the spend record for provenance only.

## Procedure (one paid call)

1. **Get the command.** Run `python3 scripts/pipeline.py <asset-id> --stage concept|model` and take the `tripo …` command it prints. The next attempt number `<n>` is in the `-o` path.
2. **Preflight (free).** Run `tripo --version`, `tripo balance --json` and `tripo whoami --json` (for the region). If the balance is below the estimate, stop and ask the user to top up at https://platform.tripo3d.ai. `tripo topup` points at a stale page.
3. **Dry run (free, no network).** Run the printed command with `--dry-run --json` added. It must return `valid: true`. Note `model` (the wire version string, e.g. `P1-20260311`) and any `warnings`/`cost_notes`. A warning that mentions a price tier needs the user's explicit OK.
4. **Ask.** Show the user: the asset ID, prompt, model version, parameters, estimated credits, the current balance, and `used / 500`. Wait for a clear yes.
5. **Record the before balance.** Run `tripo balance --json` immediately before the paid run. Write `<kind>-<n>.spend.json` with status `running`, the before balance, the CLI version, the model version, the prompt, parameters and the confirmation time.
6. **Run (paid)**, with the Bash tool's `run_in_background`, because it can block for up to 15 minutes:
   `<printed command> > .tripo-out/<asset-id>/<kind>-<n>.result.json 2> .tripo-out/<asset-id>/<kind>-<n>.log`
   The CLI writes artifacts to `<-o dir>/tripo-out/<slug>-<id8>/`; take the real path from `output_dir` in the result.
   Wait for the completion notification; don't poll. Exit codes:
   - `0` ok
   - `4` insufficient credits
   - `5` content policy (change the prompt)
   - `6` task failed (credits auto-refunded)
   - `7` network
   - `9` rate limit
7. **Record the after balance.** Run `tripo balance --json`. The actual spend is `(before.balance + before.frozen) − (after.balance + after.frozen)`. If `after.frozen > 0`, re-check the balance before closing. Compare with `credits_consumed` from the result JSON, and flag any mismatch. Finish the spend record (status `generated` or `failed`, the actual spend, exit code, task IDs). Add the actual spend to the session total.
8. **Hand back.** Re-run the pipeline stage from step 1. It ingests the artifacts and the spend record into `assets/manifests/<asset-id>.json`. Everything after that belongs to the asset-pipeline skill.
9. **Rejecting a result:** if the user or the pipeline rejects an attempt, set its spend record's `status` to `rejected`. The pipeline then skips it and prints the next attempt's command. Don't delete the files; the spend history stays.

## Spend record schema (`.tripo-out/<asset-id>/<kind>-<n>.spend.json`)

```json
{
  "status": "running | generated | failed | lost | rejected",
  "started_at": "2026-09-27T12:00:00Z",
  "user_confirmed_at": "2026-09-27T11:59:00Z",
  "tripo_cli_version": "0.5.1",
  "model_version": "<dry-run model wire string>",
  "region": "ov",
  "command": "<the exact command run>",
  "prompt": "<prompt>",
  "params": {"pbr": false, "texture": true, "face_limit": "<from the brief>"},
  "dry_run": {"valid": true, "warnings": [], "cost_notes": []},
  "estimate_credits": 0,
  "estimate_source": "<where the estimate came from>",
  "balance_before": {"balance": 0, "frozen": 0},
  "balance_after": {"balance": 0, "frozen": 0},
  "actual_spend": 0,
  "cli_reported_credits": 0,
  "exit_code": 0,
  "task_ids": ["provenance only; never used to resume"]
}
```

- `model_version` is the dry run's `model` wire string. If the run's `task.json` reports a different version, record both and tell the user.
- `tripo_cli_version` comes from `tripo --version` at preflight. The CLI updates independently of this repo, so a version change between attempts is worth noting.
