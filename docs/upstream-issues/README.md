# Upstream issue drafts

Drafts of bug reports for the pinned third-party tools, from the Phase B trials (`docs/trials/`). Backlog item: `upstream-issue-reports`. The user decided on 2026-10-08: the agent drafts each issue, the user OKs the text, then the agent files it with `gh issue create` (or `gh issue comment`). **Nothing here has been posted.**

Each draft gives the target repo, whether it's a new issue or a comment, the duplicate search that was done, any checks still due before filing, then the title and body exactly as they would be posted. Bodies follow each repo's bug-report template and contain no local paths or account details.

| Draft | Repo | Action |
|---|---|---|
| [dialogue-manager-headless-import-leak.md](dialogue-manager-headless-import-leak.md) | nathanhoad/godot_dialogue_manager | New issue (patch 1) |
| [dialogue-manager-debugger-capture-exit.md](dialogue-manager-debugger-capture-exit.md) | nathanhoad/godot_dialogue_manager | New issue (patch 2) |
| [dialogue-manager-get-line-cycle.md](dialogue-manager-get-line-cycle.md) | nathanhoad/godot_dialogue_manager | Nothing to file: fixed on `main` by PR #1303 (patch 3) |
| [material-maker-cli-size-ignored.md](material-maker-cli-size-ignored.md) | RodZill4/material-maker | New issue |
| [material-maker-headless-segfault.md](material-maker-headless-segfault.md) | RodZill4/material-maker | New issue (re-check on 1.7 first) |
| [func-godot-cyclic-preload.md](func-godot-cyclic-preload.md) | func-godot/func_godot_plugin | New issue |

After filing, record each issue's URL in its draft and in the trial note that mentions the bug, and drop the matching patch when an upstream release fixes it (`docs/trials/dialogue-manager-v4.1.0.patch`).
