---
name: playtest-branch
description: Let the human play the agent's work in their own Godot without touching their checkout. Opens a disposable review copy of a branch (right Godot version, imported, launched) and removes it afterwards. Use when the user asks to try, play, playtest or see a branch or the agent's changes, or says they're done playtesting.
---

# Playtest a branch (human in the loop)

The human's checkout, editor, uncommitted work and `.godot` cache are never touched. The review copy is a separate git worktree at `../project-whiskeyjack-review`, a separate Godot project that can be open alongside their own editor. Nothing needs "swapping back": `--done` deletes the copy.

**Execution:** a plain script, `scripts/tools/playtest-branch.sh`. No Godot MCP involved.

## Open it

1. **Find the ref.** Usually the branch the agent's work is on, e.g. its worktree's branch: `git -C <worktree> branch --show-current`.
2. **Uncommitted work isn't included:** the script checks out commits only. Check `git -C <worktree> status --short`. If there are relevant changes, commit them (when the user has allowed commits this session), or say they won't appear.
3. **Stale remote copies:** a branch name that exists on `origin` resolves to `origin/<name>`. If the local branch has newer commits (`git rev-parse <name>` != `git rev-parse origin/<name>`), pass the local sha instead.
4. **Run it** from any worktree of the repo:
   ```
   scripts/tools/playtest-branch.sh <ref-or-sha>            # default --play: straight into the game
   scripts/tools/playtest-branch.sh <ref-or-sha> --editor   # a second Godot editor on the copy
   ```
   **Use `--play` unless the user asks for the editor.** The human usually has their own editor open on their checkout (`main`). With `--editor` there are two editors on what looks like the same project, and F5 in their usual one runs `main`. That cost two playtest rounds on 2026-10-01: the user reported "nothing changed" because they were playing `main`. The script writes an `override.cfg` that renames the copy to "REVIEW <ref> · Project Whiskeyjack", so its windows say which branch they are; tell the user to look for that title. It also gives the copy its own `user://`, so playtests never touch the human's `save.json`.

   The first import takes about a minute. The script picks the installed Godot matching the branch's `project.godot` (`config/features`), and prints the ref, commit and Godot version. Relay that banner.

   **If the user says nothing changed,** first check which Godot is running the game (`ps -axo pid,command | grep Godot.app`) before debugging the branch.
5. **The user can also run it themselves:** `/playtest-branch <branch>` in Claude Code, or the script directly. Mention this when you open a copy for them.
6. **Tell the user** in a few lines:
   - what changed on the branch;
   - what to try, as concrete steps: where to go and what to do to see the change;
   - what to look for.

   Offer to note their findings.

## Close it

When they say they're done:
```
scripts/tools/playtest-branch.sh --done
```
It also removes the review copies' own save folders (`app_userdata/REVIEW *`). Then record what they found. A bug or design note goes to the backlog in `docs/decisions.md`. Anything checkable becomes a playtest scenario or rubric item, so the automated playtester catches it next time.

`--status` shows whether a review copy exists. Check it at the end of a session and remove stale copies.

## Rules

- Never run `git switch`, `checkout`, `stash` or `reset` in the human's checkout to "show" them a branch; that's what this avoids.
- Never edit files in the review copy. Every run of the script resets it (`reset --hard`, `clean -fdx`), so anything written there is lost.
- One review copy at a time. Opening another branch reuses and resets it.
