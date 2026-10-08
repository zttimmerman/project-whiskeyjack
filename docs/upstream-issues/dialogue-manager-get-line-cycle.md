# Dialogue Manager: reference cycle in `get_line` ("resources still in use at exit")

- **Repo:** nathanhoad/godot_dialogue_manager
- **Action:** **nothing to file.** Upstream fixed it on `main` in PR #1303, "Fix circular references in dialogue line data" (commit bdc9890942, merged 2026-09-27), with the same change as our local patch 3: `data = data.duplicate() # avoid circular reference` before `data.resource = resource` in `get_line`.
- **Released?** Not yet: the latest release is still v4.1.0 (2026-09-04), and `main` is 14 commits ahead of it.
- **What to do:** keep patch 3 until the next release, then drop it in that update's `chore/` branch (the update procedure in `docs/trials/dialogue-manager.md`). No comment is needed on a merged PR.
- **Confirmed 2026-10-08:** in a fresh project, the unpatched v4.1.0 runtime still reported `2 resources still in use at exit` after one line of dialogue, and the one-line change removed it.
