# A1: CI on GitHub Actions

**Goal:** every PR runs the checks that don't need a Mac or Blender, and fails on regressions. This covers design bible §8: "no errors, and no new warnings".

**Scope:**
- **Workflow** `.github/workflows/ci.yml`: on `pull_request`, and on `push` to `main`. Use the container `barichello/godot-ci:4.7.2`, or `chickensoft-games/setup-godot` pinned to 4.7.2. Pin actions and images by version or SHA.
- **Job `import`:**
  - `godot --headless --path . --import`, run twice; the first run on a fresh checkout reports missing UID-cache errors;
  - fail if the second run logs any `ERROR` or `SCRIPT ERROR`;
  - check warnings against a committed baseline, `ci/warnings-baseline.txt`, generated from current `main`: new warnings fail, and fixed warnings shrink the baseline. The current known warnings are the invalid hand-written UIDs in 9 scenes and 3 GDScript warnings, all listed in `docs/decisions.md`. The baseline is the list of warnings to burn down, not something to hide.
- **Job `validate`:**
  - run `scripts/godot_validate.gd` for each committed asset, the same call `pipeline.py --stage validate` makes, minus the Blender renders (Blender isn't in the image);
  - either add a `--no-views` flag to `pipeline.py` or call Godot directly; say which and why;
  - fail on a validate failure.
- **Job `data-lint`:** a small stdlib Python script under `ci/` that validates `data/dialogues/*.json` and `data/quests/*.json`:
  - structure: ids unique, `next_id` targets exist, no unreachable nodes;
  - the world bible's text limits: 2 sentences or fewer per dialogue node, and objectives of 12 words or fewer;
  - fail on violations; report current violations as a baseline if some exist, rather than rewriting content.
- **Job `hooks`:** `python3 .claude/hooks/test_godot_ai_guard.py`.
- Keep the runtime under about 10 minutes, and cache the import (`.godot/`) keyed on the lockfile or `project.godot` hash if that's easy.
- Add a status badge to README.md if a README exists.

**Out of scope:** gdUnit4 (A2a adds its own job), render or luminance checks, macOS runners.

**Acceptance:**
- The workflow runs green on its own PR.
- A deliberately broken throwaway commit makes it fail: a GDScript parse error, and a bad `next_id`. Show those runs in the PR, then drop the commits.
- The job logs show each check.

**Serves:** §8 of the bible, `perf`-adjacent stability, and the guard hook's tests.
