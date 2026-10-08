# Material Maker: the command-line export ignores `--size`

- **Repo:** RodZill4/material-maker
- **Action:** new issue
- **Duplicate search (2026-10-08):** `--size`, `export size`, `texture_size`, `image_size`, `2048`, `--export`, `command line`, `CLI`, `parse_args`. Command-line issues exist (#1132, #1373, #1506, #804) but none mention the size.
- **Still present on `master`** (174f15edec, 2026-10-07; `parse_args.gd` last changed in 04a932dbc0, 2026-09-16) and in 1.7: code read, not run. Found on 1.5p1 in our trial (`docs/trials/material-maker.md`).

## Title

Command-line export ignores `--size` (always exports 2048 px)

## Body

~~~markdown
**Material Maker version:**
1.5p1 (tag `1.5p1`, b57f878). The same code is in 1.7 and on `master` (174f15e).

**OS/device including version:**
macOS 26, Apple M2 Pro.

**Issue description:**
`--size` is parsed but never used, so a command-line export always renders at 2048 px. In `parse_args.gd`, `--size` is read into `texture_size`, but `export_files()` is called with `image_size`, which is hard-coded to 2048:

```gdscript
var image_size : int = 2048
...
var texture_size : int = 0
...
"--size":
	i += 1
	texture_size = int(OS.get_cmdline_args()[i])
...
await export_files(expanded_files, output_dir, target, output_file, image_size)
```

Expected: `--size 256` exports 256 px images. Actual: 2048 px.

**Steps to reproduce:**
1. Take any `.ptex` with an Export node or a Material node.
2. Run `material_maker --export --size 256 -o out graph.ptex`.
3. The exported images are 2048 × 2048.

A minimal fix would be to use the parsed value when one was given (assuming `--size` is meant in pixels):

```gdscript
if texture_size > 0:
	image_size = texture_size
```

We export small tileable textures and downscale the 2048 px output ourselves, so this only costs render time for us.
~~~
