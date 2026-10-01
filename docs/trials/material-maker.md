# Trial B3: Material Maker for palette-locked tileable textures (2026-10-01)

Phase B trial 7 in `docs/tools-review-2026-09.md`. The question: can Material Maker (MIT) make the levels' tileable surfaces from small text `.ptex` graphs, exported from the command line, keeping only the albedo, downscaled to the art-bible size and locked to the art-bible palette? It's evidence for a decision, not the decision.

**Recommendation: keep, with changes** (listed at the end). The command-line export works and is deterministic, the four textures regenerate byte-identically in about 4.5 s, and every texel is on its palette ramp. The catches: it isn't truly headless (it opens a window, so it needs a logged-in Mac session), CI can only verify the textures rather than regenerate them, and the dark-palette floors fall below `lvl_floor_luminance_min` under Level 1's lighting.

## The tool

| | |
|---|---|
| Release | **1.5p1** (the 1.5 patch release; 1.6 and 1.7 exist, and the brief asked for 1.5) |
| Commit | `b57f878bcc6dadb9784375e076a60efdbdcf0686` (tag `1.5p1`, RodZill4/material-maker) |
| Licence | MIT (GitHub licence API) |
| macOS asset | `material_maker_1_5p1.dmg`, SHA-256 `7e817100611b4f22cf7fc755faef389a7a4838cd264861e8a92e5f32503bb673` (matches GitHub's digest) |
| Linux asset | `material_maker_1_5p1_linux.tar.gz`, SHA-256 `d2a65fcadd9719f516b57f57b52b0eb47aa33fa86a40440976fb8c8a907b2a79` (downloaded, not run) |
| Pin check | `Material Maker.pck` SHA-256 `e33a8390…8a` is recorded in `assets/textures/src/textures.json`; `make_textures.py` refuses any other build |
| Where | `.tools/material-maker-1.5p1/Material Maker.app` in the checkout (gitignored), or `$MATERIAL_MAKER` |
| Gatekeeper | No prompt: a Developer ID-signed, notarized universal binary (`spctl`: "accepted, Notarized Developer ID"). No login, account or GUI step |

**Command line.** `Material Maker --export -o <dir> a.ptex b.ptex …` works. Findings:
- **`--headless` crashes** (exit 139, a segfault) right after loading: the renderer uses RenderingDevice compute shaders on Vulkan. Without `--headless` it opens a small window for a few seconds, renders and quits with exit 0. So it needs a logged-in macOS session; over ssh with no session it won't run.
- **`--size` is ignored.** `parse_args.gd` parses it into `texture_size` but passes a hard-coded `image_size = 2048` to the export. Every export is 2048 px. That's harmless here, since we downscale anyway, but it's 16 to 64 times the pixels we keep.
- An **Export node** (suffix `albedo`) instead of a Material node exports only that one image, so no normal, roughness, metallic or height maps are rendered at all.
- **Writes outside the project:** `~/Library/Application Support/material_maker_2/` (shader cache, `mm_config.ini`, logs). Output didn't depend on it: the first run, with a cold cache, gave the same hashes as later runs.
- **Network:** I read the code paths for the CLI run (`parse_args.gd`, `loader.gd`, `globals.gd`). The only HTTP requests are for `website:<id>` graph names or nodes and pasted URLs, which our graphs never use. There's no telemetry on the CLI path. The GUI's splash and about screens and its share and website features do go online.
- Timing: the first launch took 33 s (shader compilation). After that, all four graphs export in **3.0 to 4.0 s** in one call, and one run took 21.8 s. Startup dominates.

## What landed

- `assets/textures/src/*.ptex`: four graphs as plain JSON, 180 to 260 lines each: `stone_dressed` (running-bond blocks, per-block tone, Perlin surface), `plaster` (lime wash, blotches, Voronoi cracks), `packed_earth` (cellular clods, fine grit), `wood_planks` (staggered boards, stretched grain). Every random node has an explicit `seed_int`. They also open in Material Maker's GUI for preview.
- `assets/textures/src/textures.json`: each texture's ramp (art-bible palette names, dark to light), size (128), `ramp_steps` (8), and the Material Maker pin.
- `scripts/tools/make_textures.py` is the one command: Material Maker export → `scripts/tools/palette_lock_textures.gd` (headless Godot) → `assets/textures/surfaces/<name>.png` plus `manifest.json`. `--check` is stdlib Python and needs neither tool.
- `scripts/review/surface_textures.tscn`: rendered evidence (see below).
- `.gitignore`: `.tools/`.

**Palette lock.** The 2048 px export is box-filtered with `Image.shrink_x2` (integer 2×2 averages) down to 128 px. Then every texel snaps to the nearest entry of its ramp: the declared palette colours plus 7 integer-interpolated sRGB steps between neighbours, 17 entries for 3 colours, using squared sRGB distance, with ties going to the lower entry. Everything that decides a pixel is integer arithmetic, so the same export always gives the same pixels. The manifest records a hash of the pixels as well as the PNG, because PNG bytes also depend on Godot's encoder. The graphs' colorize stops must be exact palette colours: `make_textures.py` reads the hexes from `docs/art-bible.md` and fails on any other colour. The art bible remains the only place the numbers live.

**Determinism.** Three full regenerations in a row gave identical PNGs, manifest, and 2048 px Material Maker exports. That was on one Mac (an M2 Pro). Across GPUs or Material Maker versions, the 2048 px export may differ in low bits. The lock removes most of that, but nothing guarantees it. The manifest's `material_maker_export_sha256` shows when the export itself moved.

## Evidence

Renders are local, in the gitignored `.tools/work/stills/`, and are regenerated with `godot --path . res://scripts/review/surface_textures.tscn -- --out <dir>`. The scene uses Level 1's lighting: the same directional light, Wet Slate ambient at 0.5, and torch omni lights at Level 1's colour and energy with the torch prop. Three test bays (stone wall on earth, plaster on planks, planks on stone) sit next to a bay of the shipped KayKit wall and floor. Textures repeat every 2 m (64 texels/m). The material is albedo only, with roughness 1, metallic 0, specular 0 and nearest filtering with mipmaps.
- **Contact sheet** (`surface_sheet.png`): each texture at 1× and tiled 2×2 at 2×. **No visible seams** on any of the four.
- **Bays:** the stone reads as dressed blocks with dark joints. The planks read as boards from the gameplay camera. The plaster reads as a pale wash with a crack network, though the cracks look a little like crazy paving. The earth reads as mottled ground, but its Saddle Leather blotches look rusty. Against the kit bay, our walls are darker and more saturated, because they sit on the palette rather than KayKit's light neutrals.

**Palette ΔE** (CIE76, `scripts/judge.py`'s Lab): distance to the ramp, and the art bible's palette groups. Each texel joins its nearest ramp colour, and the group median is compared with that colour; the bar is `palette_de_after` ≤ 12.

| Texture | Colours | To ramp, before lock (median / p95 / max) | After lock | Palette groups after lock (share, median ΔE) |
|---|---|---|---|---|
| stone_dressed | 16 | 0.47 / 1.00 / 1.35 | 0 | Peat Black 26% 0.0 · Rain Stone 32% 4.0 · Wet Slate 42% 1.7 |
| plaster | 13 | 0.90 / 2.20 / 2.55 | 0 | Wet Slate 32% 9.4 · Old Bone 68% 4.3 |
| packed_earth | 17 | 0.79 / 1.46 / 1.76 | 0 | Peat Black 2% 8.4 · Saddle Leather 33% 6.0 · Rain Stone 65% 2.8 |
| wood_planks | 15 | 0.93 / 1.59 / 3.04 | 0 | Peat Black 11% 3.0 · Saddle Leather 43% 9.4 · Barrow Oak 46% 8.8 |

- Material Maker passes sRGB gradient colours straight through: the export is within 3 ΔE of the ramp before the lock.
- After the lock, every group is within the art bible's 12 ΔE. Group medians aren't 0 because ramp mid-tones join their nearest end.
- On the first plaster gradient, Old Bone came out at 13.3, which failed. Moving the Old Bone stop from 0.75 to 0.6 fixed it. That shows the stats catch a graph whose tones sit between palette colours.

**`lvl_floor_luminance_min` (≥ 0.05).** I measured the mean linear relative luminance (Rec. 709) of the floor region in each bay still, from roughly the gameplay camera. The design bible hasn't specified a method yet, so this is mine.

| Floor | Mean | p10 |
|---|---|---|
| packed_earth | **0.032** | 0.021 |
| wood_planks | **0.037** | 0.015 |
| stone_dressed | 0.057 | 0.014 |
| KayKit floor | 0.106 | 0.099 |

The palette-true earth and planks floors fail the target. Per the art bible (fix it level-side, never by brightening textures), that's a lighting question for any level that uses them. It's also an argument for ramps that end on lighter colours for floors.

**Regeneration time**, three warm runs: 4.2 to 5.0 s for all four textures (Material Maker 3.2 to 4.0 s, lock 1.0 to 1.2 s). The cold first launch was about 33 s. `--check` takes under 0.1 s.

**Checks:** `make_textures.py --check` fails on a hand-edited PNG (tested), on a graph or ramp edited without a regeneration, on a palette hex that drifted in the art bible, and on stray PNGs. The import and load-all log check against `ci/warnings-baseline.txt` passed: 0 errors, 0 new warnings. `gdlint` and `gdformat` are clean.

## Can CI regenerate?

No. The Linux build is the same Vulkan/RenderingDevice app, so CI would need Xvfb plus a software Vulkan driver (lavapipe) in the container. That's untested, and llvmpipe/lavapipe floats would differ from the Mac's GPU, so a CI regeneration wouldn't be byte-identical. **CI can verify:** `python3 scripts/tools/make_textures.py --check` is stdlib-only and fits the `validate` job as one step. It isn't wired in by this PR.

## Cost of adopting it

- **External app:** a 122 MB app pinned outside the repo, installed by hand per machine; the error message says where to get it. Version bumps are deliberate: download, verify the asset SHA-256, update `textures.json` (release, commit, asset hash, pck hash), regenerate, and review the diff in the stills and ΔE. Like godot-ai, it's never updated in place.
- **Pinning risk:** 1.x versions change node shaders, so a bump can change pixels (the manifest's export hash shows this). It also carries its own Godot 4.5 build, so **our Godot upgrades don't touch it.** Only the lock step runs in our Godot. A Godot upgrade could change PNG bytes but not pixels, since those are integer operations; `--check` would flag the PNG hash, and a regeneration fixes it.
- **Mac-session dependency:** regeneration needs a logged-in GUI session (a window flashes for about 4 s), the same constraint as the rendered captures.
- **Authoring:** writing graphs as JSON by hand works for 10 to 15 nodes but is blind. Port numbers and parameter names come from the `.mmg` node files. The GUI is the practical editor for tuning, and the committed text stays diff-reviewable.
- **Upstream bugs:** `--size` is ignored, and `--headless` crashes. Both could be reported upstream; neither blocks this use.

## Changes if kept

1. Add `make_textures.py --check` to CI's `validate` job.
2. Proposed CLAUDE.md line, under Visual Style Rules or 3D Asset Workflow: "**Level-surface textures** (`assets/textures/surfaces/`) are generated: only `scripts/tools/make_textures.py` writes them, from the `.ptex` graphs and ramps in `assets/textures/src/` (Material Maker 1.5p1, pinned in `textures.json`, kept in the gitignored `.tools/`). Never edit the PNGs; change the graph or ramp and rerun. CI runs `--check`."
3. Import surface textures lossless, with mipmaps and with 3D detection off, as these are, so S3TC doesn't add off-palette colours. The kit atlas uses VRAM S3TC, and its ΔE cost on a 17-colour ramp is unmeasured.
4. Decide the floor-luminance question (level lighting, or lighter floor ramps) before a level uses these floors.
5. Decide whether `ramp_steps` 8 is the right amount of locking. 1 gives pure palette colours, which is PS1-CLUT-like and posterized; 8 keeps soft tone.
