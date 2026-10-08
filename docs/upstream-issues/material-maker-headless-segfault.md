# Material Maker: `--headless` segfaults on command-line export

- **Repo:** RodZill4/material-maker
- **Action:** new issue
- **Duplicate search (2026-10-08):** `headless`, `segfault`, `command line`, `--export`. Related but different: #1506 (1.7, Linux: segfault on `--export-material` without `--headless`) and #1373 (crash after a command-line export that succeeded). Neither is about `--headless`; the body links them.
- **Before filing, re-check on 1.7.** Found on 1.5p1 in our trial (`docs/trials/material-maker.md`, 2026-10-01) and not re-run since: Material Maker isn't installed in this checkout's `.tools/`, and trying 1.7 is its own backlog trial. If the crash is gone in 1.7, don't file. If it remains, update the version line, and paste the first lines of the crash output (the signal and backtrace) where the body says so.
- **Probable cause** (not confirmed): a headless Godot uses the dummy renderer, with no `RenderingDevice`, and Material Maker's generators use RenderingDevice compute shaders. A clear "headless is unsupported" error would be a fine outcome too, and the body says so.

## Title

Command-line export with `--headless` crashes (segfault, exit 139)

## Body

~~~markdown
**Material Maker version:**
1.5p1 (tag `1.5p1`, b57f878). <!-- update after re-checking on 1.7 -->

**OS/device including version:**
macOS 26, Apple M2 Pro.

**Issue description:**
Adding Godot's `--headless` to a command-line export crashes right after the graph loads, with exit code 139 (segfault) and no output files. The same command without `--headless` works: it opens a small window for a few seconds, exports and exits with 0.

<!-- paste the crash lines (signal and backtrace) here -->

This matters for CI or ssh use, where there's no window session. If headless can't work (headless Godot has no RenderingDevice, which the generators' compute shaders need), an error message saying `--headless` isn't supported would be enough, instead of a crash.

Possibly related: #1506 and #1373 (command-line export crashes on Linux, without `--headless`).

**Steps to reproduce:**
1. Take any `.ptex` (ours had a single Export node).
2. Run `material_maker --headless --export -o out graph.ptex`.
3. It crashes with exit code 139. Without `--headless`, the same command exports and exits with 0.
~~~
