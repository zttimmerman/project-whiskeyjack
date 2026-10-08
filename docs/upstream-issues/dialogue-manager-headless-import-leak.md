# Dialogue Manager: headless `--import` leaks every global class script at exit

- **Repo:** nathanhoad/godot_dialogue_manager
- **Action:** new issue (our local patch 1, `docs/trials/dialogue-manager-v4.1.0.patch`, `plugin.gd`)
- **Duplicate search (2026-10-08):** `headless`, `leak`, `leaked at exit`, `resources still in use`, `CI`, `--import`, `global class`. The closest are #336 and #340 (leaks at exit, 2023, fixed in 2.x) and #689 (CI import failing, a different error). None covers this.
- **Still present on `main`** (8ffe461f2a, 2026-10-02): `_enter_tree` registers the full editor UI with no headless check.
- **Reproduced 2026-10-08** in a fresh project: unpatched v4.1.0 plus gdUnit4's folder (only so there are many `class_name` scripts; it isn't enabled). The second `--import` printed the errors below; with the patch it printed none.

## Title

Headless editor (`--import`) leaks global class scripts at exit: "resources still in use"

## Body

~~~markdown
**Describe the bug**
Running a headless editor import (`godot --headless --import`, as CI does) with Dialogue Manager enabled ends with leak errors for the project's global class scripts. In a project with many `class_name` scripts:

```
WARNING: 458 ObjectDB instances were leaked at exit (run with `--verbose` for details).
ERROR: 190 resources still in use at exit (run with --verbose for details).
ERROR: Pages in use exist at exit in PagedAllocator: N12VariantPools12BucketMediumE
ERROR: Pages in use exist at exit in PagedAllocator: N12VariantPools11BucketSmallE
ERROR: 10 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.
```

With `--verbose`, the resources still in use are the `class_name` scripts from across the project (other addons' scripts and Dialogue Manager's own). It looks like the editor UI (the code editor's autocomplete and related lookups go through `ProjectSettings.get_global_class_list()` and `load()` each script), which isn't needed in a headless editor. CI logs that fail on `ERROR:` lines fail because of it.

**Affected version**

- Dialogue Manager version: 4.1.0 (tag `v4.1.0`); the same code is on `main` at 8ffe461
- Godot version: 4.7.2.stable.official (ed1daf0bf), macOS 26, Apple Silicon

**To Reproduce**

1. Make a new project, add Dialogue Manager 4.1.0 and enable the plugin.
2. Add a number of `class_name` scripts (copying any addon with many global classes into `addons/` reproduces it; we used gdUnit4's folder without enabling it).
3. Run `godot --headless --path <project> --import` twice (the first run imports everything; the second shows the leak on exit every time).
4. See the errors above at exit.

**Expected behavior**
A headless import exits cleanly. Our workaround registers only the importer and exporter when the editor is headless, which removes every error above:

```gdscript
# plugin.gd, _enter_tree(), straight after add_export_plugin(export_plugin)
if DisplayServer.get_name() == "headless":
	return
```

```gdscript
# plugin.gd, _exit_tree(), straight after export_plugin = null
if DisplayServer.get_name() == "headless":
	instance = null
	return
```

Happy to open a PR with this if the approach suits you.
~~~
