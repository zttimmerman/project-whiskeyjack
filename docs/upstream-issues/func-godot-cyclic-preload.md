# func_godot: cyclic preload when an FGD resource is the first func_godot file loaded

- **Repo:** func-godot/func_godot_plugin
- **Action:** new issue
- **Duplicate search (2026-10-08):** `cyclic`, `circular`, `preload`, `Parse Error`, `fgd parse error`, `load order`; PRs for `cyclic`. #228 (AssetLib version errors on Godot 4.6) shows editor errors but has no detail to tie it to this, so it isn't linked.
- **Reproduced 2026-10-08** in a fresh project with func_godot 2025.12 (169f2dd) and with `main` (ce8cf99, 2026-09-23): the same errors on both. The plugin doesn't need to be enabled.
- **Our workaround** (`docs/trials/func-godot.md`): our one map-settings resource is loaded first, so `func_godot_map_settings.gd` always compiles before any FGD class resource.

## Title

Loading an FGD resource first fails: cyclic preload through `func_godot_map_settings.gd`

## Body

~~~markdown
**Describe the bug**
If the first func_godot file a process loads is one of the FGD class resources (for example `fgd/phong_base.tres`), script compilation fails and every built-in FGD resource fails to load. There's a preload cycle:

`func_godot_fgd_base_class.gd` → (extends) `func_godot_fgd_entity_class.gd` → (uses) `FuncGodotUtil` → (uses) `FuncGodotMapSettings` → `func_godot_map_settings.gd`, whose `entity_fgd` default is `preload("res://addons/func_godot/fgd/func_godot_fgd.tres")` → that resource's entity list, which includes `phong_base.tres`, the resource still being loaded.

We hit it in CI, where a script loads every resource in the project in path order. In the editor it's usually hidden, because something else has already compiled `func_godot_map_settings.gd`.

**Versions**
- func_godot 2025.12 (169f2dd); the same on `main` at ce8cf99
- Godot 4.7.2.stable.official (ed1daf0bf), macOS 26

**To Reproduce**
1. New project; copy `addons/func_godot` in (the plugin needn't be enabled) and run `godot --headless --import` once.
2. Add this script as `probe.gd`:
   ```gdscript
   extends SceneTree

   func _init() -> void:
   	print(load(OS.get_cmdline_user_args()[0]))
   	quit()
   ```
3. Run `godot --headless --path <project> -s res://probe.gd -- res://addons/func_godot/fgd/phong_base.tres`.

**Actual** (deduplicated):
```
SCRIPT ERROR: Parse Error: Could not preload resource file "res://addons/func_godot/fgd/func_godot_fgd.tres".
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.
ERROR: Failed to load script "res://addons/func_godot/src/fgd/func_godot_fgd_base_class.gd" with error "Compilation failed".
ERROR: res://addons/func_godot/fgd/vertex_merge_distance_base.tres:6 - Parse Error: [ext_resource] referenced non-existent resource at: res://addons/func_godot/src/fgd/func_godot_fgd_base_class.gd.
ERROR: res://addons/func_godot/fgd/func_godot_fgd.tres:15 - Parse Error: [ext_resource] referenced non-existent resource at: res://addons/func_godot/fgd/phong_base.tres.
ERROR: Failed loading resource: res://addons/func_godot/fgd/func_godot_fgd.tres.
... (the same for cull_interior_faces, func_detail, func_detail_illusionary, func_geo, func_illusionary, worldspawn)
```

**Expected**
Any func_godot resource loads, whatever order files are loaded in. Running the same probe on `fgd/func_godot_fgd.tres` first works.

**Possible fix**
Break the cycle at `func_godot_map_settings.gd`: replace the `preload()` default for `entity_fgd` with a runtime `load()` when the value is unset (or no default, with the default FGD loaded where it's used), so compiling the script no longer loads the FGD resources.
~~~
