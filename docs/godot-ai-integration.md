# godot-ai v4.2.3 trial: integration report

Source: the clone at `.../scratchpad/godot-ai` (HEAD = tag `v4.2.3` = commit `f58314d9473d11efef94dd68b523e1b52643d736`; a lightweight tag, so `git tag -v` has nothing to check). Target: `/Users/zach/Documents/repos/project-whiskeyjack-agent` (branch `chore/godot-ai-trial`). Host has `uv`/`uvx` at `/opt/homebrew/bin`, Python 3.14.7 and OpenSSL 3.6.3.
Doc citations are `file:line`. "Code" means I read the plugin or server source because the docs were silent.

---

## 1. Install (pinned v4.2.3)

**Use the signed release triple, not a source copy.** README.md:42-47 says to install the release package and not a source snapshot. packaging-distribution.md:22-26 says the only v4 ZIP is `godot-ai-v4-plugin.zip`, bound by `godot-ai-v4-plugin.manifest.json` (every path, size and SHA-256) and `.manifest.sig` (RSA-4096). The trust root is SPKI fingerprint `84ebbd811f3a12c09ff4e236bbbbb9310fc23e03fcfc3717ba546747d0d21072` (packaging-distribution.md:151-153; the same value is `PUBLIC_KEY_SPKI_SHA256` in `src/godot_ai/release_verify.py:61`).

1. Download the three canonical assets, and only those (the other three are the v3 capsule):
   `gh release download v4.2.3 -R hi-godot/godot-ai -D <scratch>/rel -p godot-ai-v4-plugin.zip -p godot-ai-v4-plugin.manifest.json -p godot-ai-v4-plugin.manifest.sig`
2. Verify with the clone's standalone verifier. It needs Python 3.11-3.14 and uses `cryptography`, falling back to the `openssl` CLI (`release_verify.py:208-249`), so nothing has to be installed:
   ```
   python3 <clone>/script/v4-release verify \
     --archive rel/godot-ai-v4-plugin.zip --manifest rel/godot-ai-v4-plugin.manifest.json \
     --signature rel/godot-ai-v4-plugin.manifest.sig \
     --expected-repository hi-godot/godot-ai --expected-channel stable \
     --expected-tag v4.2.3 --expected-version 4.2.3 \
     --expected-source f58314d9473d11efef94dd68b523e1b52643d736
   ```
   This checks the signature, the identity, the archive hash and every entry (self-update.md:65-81).
3. **Extract with `unzip` into the absent `addons/godot_ai/`.** Every archive entry sits under `addons/godot_ai/` (self-update.md:77-79), so run `unzip rel/godot-ai-v4-plugin.zip -d <worktree>`. Then re-hash the tree against `manifest.inventory[]` (`{path,size,sha256}`, `release_verify.py:310-318`) with a 5-line Python check.
   **Don't use `script/v4-release install`** for this. It writes `addons/.godot_ai_update/pending.json` with `"replace_owned_mismatches": true` (`script/v4-release:~700`), so the plugin's first start repins "every owned entry that launches Godot AI" in client configs (self-update.md:200-206). That is a client-config rewrite we don't want.
4. Commit `addons/godot_ai/**`, including the `.uid` files, and add `addons/.godot_ai_update/` to `.gitignore` (the updater's staging, lock and backup directory).
5. **Enable it in `project.godot`.** Edit it with the editor closed:
   `[editor_plugins] enabled=PackedStringArray("res://addons/stylized_materials/plugin.cfg", "res://addons/godot_ai/plugin.cfg")`.
   On first enable the plugin also writes `_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"` into `[autoload]` and saves (see §5). Commit that line together with the enable, so later editor starts don't dirty `project.godot`.
6. **Prewarm the server package.** uvx resolves `godot-ai==4.2.3` from PyPI with no hash pinning (packaging-distribution.md:126-139). A cold build is about 67 packages and can exceed an MCP client's connect timeout (client-configuration.md:81-93). Run the same uvx argv as below, ending in `godot-ai --version`, once before the first Claude Code session.

**Claude Code registration: use project scope (`.mcp.json`) in the agent worktree only, committed on the trial branch.**
- Why project scope: the entry is versioned and reviewable next to the pinned addon, it never loads into other projects, and the user's main worktree only gets it on merge. Claude Code also asks once to approve a project server (README.md:98-100). Alternatively, pre-approve it with `"enabledMcpjsonServers": ["godot-ai"]` in `.claude/settings.json`.
- Why not user scope: that's the plugin's default (README.md:90-92), and it would expose Godot tools in every Claude session.
- **Never press the dock's Configure or Configure all.** Configure "removes existing `godot-ai` entries from every scope before writing the selected one" and can rewrite a checked-in `.mcp.json` (README.md:94-96).

Run this from the agent worktree root. The argv is exactly what the plugin generates (`client_configurator.gd:1383-1427`, `utils/uv_resolution_policy.gd:14-62`, `clients/claude_code.gd`):
```
claude mcp add --scope project godot-ai \
  -e GODOT_AI_DISABLE_TELEMETRY=true -e DISABLE_TELEMETRY=true -- \
  /opt/homebrew/bin/uvx --isolated --no-config --no-env-file --no-sources --no-build \
  --index-strategy first-index --keyring-provider disabled \
  --index https://pypi.org/simple --default-index https://pypi.org/simple \
  --find-links https://pypi.org/simple/godot-ai/ --link-mode copy \
  --from godot-ai==4.2.3 godot-ai attach --port 8000 --ws-port 9500 \
  --exclude-domains animation,audio,autoload,batch,camera,client,csg,custom,filesystem,gridmap,input_map,material,navigation,particle,theme,tilemap,tileset,ui \
  --disable-telemetry
```
- **Server name `godot-ai`**: it's the plugin's `SERVER_NAME` (`client_configurator.gd:33`), so tools appear as `mcp__godot-ai__<tool>`.
- **`--exclude-domains`** (`tools/domains.py:28-104`): the server drops those domains' tools before registration, so they can't be called at all. This is stronger than a permission rule. The four core tools always survive (`domains.py:63-74`), and `session` can't be excluded.
- **The exclusion list must equal the Editor Setting `godot_ai/excluded_domains`**, which is the Tools tab in the dock (`server_lifecycle.gd:1532`). A plugin-spawned server uses the editor's list, and the bridge refuses a backend whose exclusions differ (`attach/ensure.py:735-752`). It fails closed, with an "incompatible backend" error.

## 2. Self-update: disabling it and verifying it's off

- **What updates, and when.** On every editor start the plugin runs `check_for_updates()`, a GET to `api.github.com/.../releases/latest` (`utils/update_manager.gd:9,86-106`, called from `plugin.gd:1066`). Installing only happens when someone clicks **Update** in the dock and confirms (self-update.md:56-61; `plugin.gd:568,873-875`). No MCP tool reaches `start_install`, and headless or export launches never update (self-update.md:143).
- **There is no "disable updates" setting or env var**, and `plugin.cfg` has none either. The only switch that skips the check is dev mode: `check_for_updates()` returns early when `is_dev_checkout()` is true (`update_manager.gd:93`). Force it with Editor Setting `godot_ai/mode_override = "dev"`, or env `GODOT_AI_MODE=dev` (`client_configurator.gd:1621-1651`).
- **Side effects of dev mode.** The dock shows a "Dev (venv)" row. The server command would prefer a `.venv/bin/python` found within 8 parent directories that sits next to `src/godot_ai` (`client_configurator.gd:2015-2061`). Neither worktree has one, so it falls through to the same pinned uvx. Post-update tree verification is also skipped (`plugin.gd:199`), which doesn't matter if we never update. This is an undocumented use of a developer switch, so it may change in later versions.
- **Belt and braces:**
  - Policy: nobody clicks Update.
  - Keep `addons/godot_ai/` tracked, so any swap shows up in `git status`.
  - Keep `.claude/settings.json` denying `client_manage` (and exclude the `client` domain).
- **Verifying it's off:**
  1. `git status addons/` stays clean, and `addons/.godot_ai_update/` never appears (the updater creates `lock.json`, `stage/` and `backup/` there; self-update.md:84-107).
  2. The dock's Install line reads the pinned `v4.2.3`, and `session_manage(op="list")` reports `plugin_version` 4.2.3.
  3. With dev mode set, no connection to `api.github.com` at editor start (check with `nettop -p Godot` or Little Snitch).

## 3. Telemetry

It's **on by default** (TELEMETRY.md:74-75), posting to `https://godot-ai-telemetry-...run.app/events` (`telemetry.py:211`).

**Opt-out knobs** (set all of them):
1. **Env `GODOT_AI_DISABLE_TELEMETRY=true` or `DISABLE_TELEMETRY=true`** (`1`/`yes`/`on` also work) in **Godot's launch environment**. The plugin persists it to the Editor Setting and injects it into servers it spawns (TELEMETRY.md:84-90,129-144). On macOS, launch Godot from a terminal (`~/Applications/godot-4.7.2/Godot.app/Contents/MacOS/Godot`) so it inherits the variable.
2. **Editor Setting `godot_ai/telemetry_enabled = false`**: dock, Clients & Settings, Settings tab, untick Telemetry, then Apply & Restart Server (TELEMETRY.md:77-82).
3. **`--disable-telemetry` on the attach argv.** It covers the bridge and any backend the bridge spawns; the env injection never reaches client-spawned processes (client-configuration.md:60-62).
4. **The `-e` env on the `.mcp.json` entry** (above). Redundant, but harmless.
5. Optional hard stop: `GODOT_AI_TELEMETRY_ENDPOINT=invalid`. An invalid override "disables sending", with no fallback to the default endpoint (TELEMETRY.md:185-191).

**First-connect caveat** (TELEMETRY.md:92-101). When an opted-out editor first connects to an already-running server that was not started opted-out, the single `connected` record (versions, hashed session id, session count) can be enqueued before the WebSocket opt-out latches. Everything after it is suppressed.
Separately, on the very first enable, the plugin spawns a server immediately with the default (on), unless knob 1 was already in the environment. To close both gaps:
- **Set the env before the first-ever editor launch with the plugin enabled.**
- Make sure every spawner is opted out: editor env, Editor Setting, and bridge flag. Then no non-opted-out backend exists to be adopted.

**Verifying it's off:**
- The dock shows the server's `telemetry_enabled` from `/godot-ai/status`, which is a live read of env and latch (TELEMETRY.md:120-123).
- `~/Library/Application Support/godot-ai/` holds no `customer_uuid.txt` or `milestones.json`. Opt-out creates no UUID, worker or files, and deletes old ones at startup (TELEMETRY.md:149-155,193-206). The `capabilities/` subfolder in the same directory is expected.

## 4. Two editors, one server

- **How they connect.** Every editor connects to the one backend on HTTP :8000 and WS :9500. The first process to start it owns it, and later editors and attach bridges adopt it after an authenticated status probe (worktrees.md:24,32; server-lifecycle.md startup steps 1-4).
- **Session IDs** are `<slug-of-project-dir-basename>@<16 random hex>` (`connection.gd:1282-1296`). That gives `project-whiskeyjack@…` for the user's editor and `project-whiskeyjack-agent@…` for the agent's. The hex part is regenerated on reconnect, so look it up with `session_manage(op="list")`.
- **Routing.** Every tool takes a top-level `session_id` (TOOLS.md:372-374; all 19 named tools have the parameter). `session_activate` accepts an exact id or a unique substring (`tools/session.py:48-63`). `"project-whiskeyjack"` is ambiguous and returns an error; `"agent"` resolves.
- **The active session is server-global, not per MCP client.** `SessionRegistry._active_session_id` is set by whichever editor connects **first** (`sessions/registry.py:444-446`) and changed by any client's `session_activate` (`registry.py:227-230`). When the active editor disconnects, the sole survivor is auto-promoted (`registry.py:490-508`). So if the user's editor connects first, **unpinned agent calls go to the user's editor**, and the user's own Claude sessions and the agent can redirect each other.
  Fix: deny `session_activate` and have a hook require `session_id` to start with `project-whiskeyjack-agent@` (§6).
- **Ports.** There are no internal conflicts; both editors share 8000/9500. The only conflicts are foreign processes (port-conflicts.md:1-66). Ports live in the Editor Setting `godot_ai/v4_endpoint_ports` (or legacy `godot_ai/http_port`/`godot_ai/ws_port`), and changing them means regenerating the attach argv.
  Unverified: two editors running games at the same time might collide on Godot's own remote-debug port (editor setting `network/debug/remote_port`, 6007), which the game bridge uses. Test that before relying on it.
- **Does the user's editor need the plugin?** No. Each worktree has its own `project.godot`, so plugin enablement lives on the trial branch only. The user's editor on `main` doesn't load the plugin until merge, and the agent doesn't need it to.
  After a merge, a 4.7 user editor would load it, spawn or adopt the server, and become a routable session, which is why the hook matters. A 4.6 editor refuses with one error and stays inert (AGENTS.md:314-318; server-lifecycle.md:126-132). The committed `_mcp_game_helper` autoload would still run in 4.6 games.
- **Shared Editor Settings.** Editor Settings are per Godot minor version (`editor_settings-4.7.tres`). Both 4.7 editors therefore share `excluded_domains`, telemetry, ports, `mode_override`, vision routing and `run/auto_save/save_before_running`.
- **Server lifetime.** A plugin-owned backend with a live attach lease is detached, not killed, when its editor exits. The idle reaper stops it after the last session and lease end (plugin-architecture.md:218-231).
  `editor_reload_plugin` on a plugin-managed server "kills this server" (`tools/editor.py:258-266`), which drops *both* editors' connections until they recover. Deny it.

## 5. The `_mcp_game_helper` autoload

- **When it's written.** `_ensure_game_helper_autoload()` runs in `_enable_plugin()` and on every non-headless `_enter_tree()` (`plugin.gd:335,1237-1240`). If `autoload/_mcp_game_helper` isn't already `"*res://addons/godot_ai/runtime/game_helper.gd"`, it calls `ProjectSettings.set_setting` then **`ProjectSettings.save()`**, which rewrites `project.godot` (`plugin.gd:1279-1297`). Headless editor launches skip this unless `GODOT_AI_ALLOW_HEADLESS=1` (`plugin.gd:1243-1265`).
- **Removal.** Yes: `_disable_plugin()` clears the key and saves again (`plugin.gd:1271-1276`). A disable in either editor therefore produces a `project.godot` diff.
- **At runtime** (`runtime/game_helper.gd:97-137`). It's a no-op when `Engine.is_editor_hint()`. Otherwise it:
  - sets `process_mode = ALWAYS`;
  - calls `EngineDebugger.register_message_capture("mcp", …)`;
  - adds an `OS.add_logger(GameLogger)`;
  - prints `[godot_ai game_helper] registered mcp capture (debugger active=…, logger=true)`;
  - sends `mcp:hello` only if `EngineDebugger.is_active()`.

  Every frame, `_process` bumps counters and sends log batches only when the debugger is active (`game_helper.gd:139-166`). Captured messages for eval, input and screenshot arrive only over the debugger channel.
- **Our scripted windowed review scenes** (`godot --path . res://scripts/review/*.tscn`, no `--remote-debug`) have no active debugger. The helper is inert, meaning it takes no commands and sends nothing, but it isn't invisible:
  1. One extra stdout line per run.
  2. An extra `/root/_mcp_game_helper` node, appended after AudioManager.
  3. The logger's `_pending` array is **never drained, so it grows without bound** with every print, warning and error (`runtime/game_logger.gd:89-96`; draining happens only in `_process` after the `is_active()` check). That's a small memory leak in long runs.
  4. A per-frame `_process` call.

  None of these touch the RNG, physics or input.
- **Headless `-s` scripts.** Godot 4 instantiates project autoloads when the `-s` main loop is a SceneTree (verify with one run), so the same inert behavior and the extra stdout line apply. A pipeline step that diffs stdout or counts root children would see them.
- **Exports.** `export/mcp_export_plugin.gd:43-69` strips the key in `_export_begin` and restores it in `_export_end`, never saving while stripped. It's registered *before* the headless guard (`plugin.gd:254-257`), so it also works for `--headless --export-*`, but only while the plugin is enabled. As a second guard, add `addons/godot_ai/*` to each export preset's exclude filter. The docs say a missing helper then errors at start (mcp_export_plugin.gd:6-12), and the strip prevents that.

## 6. Tool list and permission classification

- **Count.** 46 tools: 19 named plus 27 `*_manage` rollups (TOOLS.md:3-6). I checked this against `register_manage_tool` calls via AST; the op lists match TOOLS.md:230-259.
- **With the recommended exclusions, Claude Code sees 28 tools.** Every name below is prefixed `mcp__godot-ai__`.
- **`godot://…` resources** (TOOLS.md:376-403) are read-only and go through Claude Code's MCP resource tools, not these names.

**Named tools (exposed)**
| Tool | Class | Note |
|---|---|---|
| `editor_state`, `scene_get_hierarchy`, `node_get_properties`, `node_find`, `logs_read`, `editor_screenshot` | ALLOW | Reads. For the screenshot, keep Vision Routing off (vision-routing.md:9-12). |
| `session_activate` | DENY | Mutates server-global routing (§4); use per-call `session_id`. |
| `project_run` | ASK | Hook forces `autosave=false` (§7). |
| `test_run` | ASK | Executes `res://tests/*.gd` in the editor process. |
| `scene_open` | ASK | `force_reload=true` discards in-memory edits (`tools/scene.py:77-83`). |
| `scene_save` | DENY | No path argument, so it can't be path-guarded. Use `scene_manage save_as` with an explicit path. |
| `node_create`, `node_set_property`, `script_attach`, `script_create`, `script_patch` | ASK + path guard | Script writes go straight to disk and aren't undoable (AGENTS.md:135). |
| `batch_execute` | DENY + excluded | Runs *any* plugin command by internal name, including settings, autoload and file writes. Only 6 subcommands are forbidden (`handlers/batch_handler.gd` FORBIDDEN_SUBCOMMANDS). |
| `editor_reload_plugin` | DENY | Kills the shared plugin-managed server. |
| `animation_create` | DENY + excluded | No per-model keyframing. |

**Exposed rollups, per op**
| Rollup | ALLOW | ASK | DENY |
|---|---|---|---|
| `editor_manage` | state, selection_get, monitors_get | selection_set, logs_clear | **game_eval**, quit |
| `scene_manage` | get_roots | create, save_as (path guard) | |
| `node_manage` | get_children, get_groups | delete, duplicate, rename, move, reparent, add_to_group, remove_from_group | |
| `project_manage` | settings_get | stop | settings_set, set_main_scene |
| `script_manage` | read, find_symbols | detach | |
| `resource_manage` | search, load, inspect, get_info | assign, curve_set_points, physics_shape_autofit, physics_shape_generate | create (can mint non-albedo materials), environment_create, gradient_texture_create, noise_texture_create |
| `signal_manage` | list | connect, disconnect | |
| `game_manage` | get_scene_tree, get_node_info, get_ui_elements, debug_status, input_state | suspend, resume, next_frame, input_key, input_mouse, input_gamepad, input_action, input_sequence | |
| `session_manage` | list | | |
| `test_manage` | results_get | | |
| `api_manage` | get_class | | |

**Excluded domains (all DENY; they're also listed in `deny` as defense in depth)**
| Tool | Ops |
|---|---|
| `filesystem_manage` | read_text, write_text, reimport, scan, search, move, rename, remove. Use Claude's own Read and Grep instead. |
| `autoload_manage` | list, add, remove |
| `input_map_manage` | list, add_action, ensure_action, remove_action, bind_event, ensure_binding |
| `client_manage` | status, configure, remove |
| `material_manage` | all 16, including apply_preset and shaders |
| `particle_manage` | all 7 |
| `animation_manage` | all 15, including preset_* |
| `theme_manage` | all 10 |
| `ui_manage` | all 5, including build_layout and draw_recipe |
| `camera_manage` | all 8, including apply_preset |
| `audio_manage` | all 6 |
| `tilemap_manage`, `tileset_manage`, `gridmap_manage`, `csg_manage` | all ops |
| `navigation_manage` | bake, path_get. path_get would be a harmless read, but bake writes a navmesh. |
| `custom_manage` | list, invoke, plus any promoted `custom_<name>` tools from other addons |

**Mixed rollups.** Permission rules match only the tool name (`op` is a parameter), so a mixed rollup can't be split in `settings.json`.
- Leave the 8 mixed rollups out of every list. They then prompt by default, which is the fail-safe.
- A **PreToolUse hook** inspects `tool_input.op`/`params` and returns `allow`, `ask` or `deny`.
- If the hook errors, Claude Code falls back to normal prompting, so it degrades to ASK and never to allow.
- Tools that are wholly ALLOW or DENY also go in `settings.json`, so they hold without the hook.

```json
{
  "enabledMcpjsonServers": ["godot-ai"],
  "permissions": {
    "allow": ["mcp__godot-ai__editor_state", "mcp__godot-ai__scene_get_hierarchy",
      "mcp__godot-ai__node_get_properties", "mcp__godot-ai__node_find", "mcp__godot-ai__logs_read",
      "mcp__godot-ai__editor_screenshot", "mcp__godot-ai__session_manage",
      "mcp__godot-ai__test_manage", "mcp__godot-ai__api_manage"],
    "ask": ["mcp__godot-ai__project_run", "mcp__godot-ai__test_run", "mcp__godot-ai__scene_open",
      "mcp__godot-ai__node_create", "mcp__godot-ai__node_set_property", "mcp__godot-ai__script_attach",
      "mcp__godot-ai__script_create", "mcp__godot-ai__script_patch"],
    "deny": ["mcp__godot-ai__session_activate", "mcp__godot-ai__scene_save",
      "mcp__godot-ai__batch_execute", "mcp__godot-ai__editor_reload_plugin",
      "mcp__godot-ai__animation_create", "mcp__godot-ai__animation_manage",
      "mcp__godot-ai__filesystem_manage", "mcp__godot-ai__autoload_manage",
      "mcp__godot-ai__input_map_manage", "mcp__godot-ai__client_manage",
      "mcp__godot-ai__material_manage", "mcp__godot-ai__particle_manage",
      "mcp__godot-ai__theme_manage", "mcp__godot-ai__ui_manage", "mcp__godot-ai__camera_manage",
      "mcp__godot-ai__audio_manage", "mcp__godot-ai__tilemap_manage", "mcp__godot-ai__tileset_manage",
      "mcp__godot-ai__gridmap_manage", "mcp__godot-ai__csg_manage",
      "mcp__godot-ai__navigation_manage", "mcp__godot-ai__custom_manage"]
  },
  "hooks": { "PreToolUse": [{ "matcher": "mcp__godot-ai__.*",
    "hooks": [{ "type": "command",
      "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/godot_ai_guard.py\"" }] }] }
}
```
(Merge this with the existing `ask` entries for `tripo` and Blender.)

**Hook design (`.claude/hooks/godot_ai_guard.py`).**
- **Input.** It reads the hook JSON from stdin and uses `tool_name` (strip the `mcp__godot-ai__` prefix) and `tool_input`.
- **Output.** It prints `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow|ask|deny","permissionDecisionReason":"…"}}` and exits 0. On an exception it prints `deny`.

Steps:
1. **Normalize the parameters.**
   - If `tool_input.params` is a string, `json.loads` it, mirroring the server's ParseStringifiedParams.
   - Fold any top-level keys other than `op`, `params` and `session_id` into `params`, mirroring FoldFlatManageParams (TOOLS.md:218-220).
2. **Session gate.** For every tool except `session_manage`, `tool_input.session_id` must match `^project-whiskeyjack-agent@[0-9a-f]{16}$`; otherwise deny, with "call session_manage(op=list) and pass session_id".
3. **Op table.** Look up `(tool, op)` in the tables above to get allow, ask or deny. Deny unknown ops.
4. **Path guard.** Collect `path`, `script_path`, `scene_file`, `scene_path`, `params.path`, `params.resource_path` and `params.scene_file`, then normalize each to `res://`. Deny when a path:
   - matches `^res://(data/animations|data/rigs|assets/meshes)/`, the generated outputs;
   - matches `^res://scenes/props/Held[^/]*\.tscn$`;
   - is under `res://addons/` or `res://.godot/`;
   - is `res://project.godot`.
5. **Require `scene_file`.** For `node_create`, `node_set_property`, `script_attach`, `script_manage.detach`, `signal_manage.connect|disconnect` and `node_manage` write ops, deny if `scene_file` is missing.
   The plugin rejects a write whose `scene_file` doesn't match the edited scene (`tools/node.py:46`), so requiring it makes step 4 reliable even though the hook can't see which scene is open.
6. **`project_run`.** Deny unless `autosave` is explicitly `false`.
7. **`resource_manage.assign`.** Ask, and apply the step 4 path guard to `resource_path`.

## 7. `project_run` autosave

- **The flag is `project_run(autosave=false)`.** The default `true` saves in-memory MCP edits to the scene on disk before playing (TOOLS.md:30; `tools/project.py:52-99`; AGENTS.md:126-133).
- **How it's implemented.** It temporarily sets the **Editor Setting** `run/auto_save/save_before_running=false` and restores it afterwards (`handlers/project_handler.gd:273-300`). A crash in between leaves it off for every 4.7 editor on the machine.
- **Other tools that persist:**
  - `scene_save`, and `scene_manage` create and save_as;
  - `script_create` and `script_patch`, which write to disk directly and aren't undoable;
  - `filesystem_manage` write_text, move, rename and remove (excluded);
  - resource, material, theme, shader and texture creators write `.tres` files through `ResourceSaver` (mostly excluded; `resource_manage.create` denied);
  - `autoload_manage`, `input_map_manage` and `project_manage.settings_set` call `ProjectSettings.save()`;
  - the plugin's own autoload write on enable and start (§5).
- **Also consider:** the user may want to set `save_before_running=false` permanently, so an F5 press can't autosave either.

## 8. Playtest input, screenshots, logs, monitors

- **`input_action`** `{action, pressed=true, strength=1.0}` calls `Input.action_press` or `action_release` directly (`game_helper.gd:715-733`). The action must exist in the game's InputMap. It's applied on whichever frame the round trip lands.
- **`input_sequence`** `{steps:[{at_frame, action, pressed=true, strength=1.0}], settle_frames=0}`:
  - Steps must be in non-decreasing `at_frame` order; two steps on the same frame are allowed.
  - Caps: 256 steps and 600 frames including `settle_frames` (`handlers/game.py:25-26,187-233`).
  - All actions are validated up front, so the run is all-or-nothing.
  - The game applies steps by awaiting `process_frame` (`game_helper.gd:858-900`), then replies once with `completed`, `steps_applied`, `frames_elapsed`, `applied[]` and `actions_pressed_at_end` (TOOLS.md:324-370).
  - It can't run inside `batch_execute`.
- **Determinism limits** (from the code, not the docs):
  - (a) Frames are **process frames, not physics ticks**. `Player._move` runs in `_physics_process`, so "60 frames held" isn't guaranteed to be 60 physics steps.
  - (b) Frame 0 is whenever the message arrives, not a fixed offset from boot.
  - (c) A minimized or App-Napped window stops the main loop, which stalls the sequence and returns stale screenshots (TOOLS.md, `editor_screenshot` doc). "Focus-independent" only means focus doesn't gate delivery.
  - For tighter runs, the user could set `--fixed-fps 60` in Project Settings > Editor > Run > Main Run Args. That's a project-settings change for the user to decide.
- **Our Player won't attack from simulated actions.** Attack, dodge, lock_on and interact are read in `_input(event)` with `event.is_action_pressed(...)` (`scenes/player/Player.gd:94-120`). `Input.action_press` fires no InputEvent (Godot docs), so `input_action` and `input_sequence` **will not trigger `attack_light`**. Movement works because it uses `Input.get_axis`.
  Use `input_key` `{key:"J", pressed}`, which goes through `Input.parse_input_event` and so reaches `_input` (`game_helper.gd:651-662`), or `input_mouse` `{event:"button", button:"left"}`. Those are round-trip-timed, not frame-timed. Always send the matching release.
- **`editor_screenshot(source="game", max_resolution=640|0=full, include_image=true)`:**
  - It only works for runs started by `project_run`; F5 runs are ignored (screenshot-testing.md:52-56).
  - Poll `editor_state` until `game_capture_ready=true` or `game_status.status=="live"`.
  - Waits: up to 6 s for the first frame, 8 s on the editor side, and `stale_frame:true` if the loop has stalled (`game_helper.gd:22-54`).
- **`logs_read(source="game", count=50, offset, since_run_id, include_details)`:**
  - It returns current-run lines from a 2000-line ring; keep the `run_id` to read a run again later.
  - Boot parse errors never appear there; look at `editor_errors_hint` and `source="editor"` (TOOLS.md:73-100).
- **`editor_manage(op="monitors_get", params={monitors:[…]})`** reads the **editor process's** `Performance` (`handlers/editor_handler.gd:915-925`), **not the game's FPS**. Game FPS would need `game_eval` (denied) or the game printing it to the log.
- **`suspend`, `resume` and `next_frame`** go over the native debugger. `next_frame` advances exactly one process tick while suspended, via `path="embed_signal"` or `"direct_session"`. `debug_status` returns the helper's tick counter (TOOLS.md:333-338; `tools/game.py:28-40`).

**Minimal sequence** (every call carries `session_id:"project-whiskeyjack-agent@<hex>"`):
```
1 session_manage {op:"list"}                                   # take the agent's id
2 project_run {mode:"custom", scene:"res://scenes/world/Level1.tscn", autosave:false}
3 editor_state {}  (repeat ~500 ms until game_status.status=="live" && game_capture_ready)
4 game_manage {op:"input_sequence", params:{steps:[
     {at_frame:0,  action:"move_forward", pressed:true},
     {at_frame:60, action:"move_forward", pressed:false}], settle_frames:1}}
5 game_manage {op:"input_key", params:{key:"J", pressed:true}}   # attack_light via _input
  game_manage {op:"input_key", params:{key:"J", pressed:false}}
6 editor_screenshot {source:"game", max_resolution:1280}
7 logs_read {source:"game", count:200, include_details:true}     # keep run_id
8 project_manage {op:"stop"}
```

## 9. Test runner (`test_run`, `McpTestSuite`)

- **What a suite looks like** (testing.md:19-49,236-254):
  - `@tool extends McpTestSuite`, saved as `res://tests/test_*.gd`. Only the top level of that directory is scanned.
  - `suite_name()` plus synchronous `test_*` methods, run alphabetically.
  - Assertions: `assert_eq`, `assert_true`, `assert_gt`, `assert_contains`, `assert_has_key` and so on.
  - Helpers: `track()`, `skip()`, `fail_setup()`.
  - Runs have a 300 s budget, and each phase should stay under about 20 s.
- **Could it host our regression scenarios? Only static ones.** Tests run synchronously on the editor main thread with no `await`. They must not start or stop the game or switch scenes. So it can't host gameplay regressions, which need frames, physics and input.
  It could host instantiate-and-inspect checks, such as scene node names matching `$` references, `SocketMap` validity, or StandardMaterial3D albedo-only asserts.
- **Downsides:**
  - Those checks would depend on a running editor with the plugin enabled.
  - `McpTestSuite` is a plugin global class, so `tests/` fails to parse if the plugin is ever removed, and that includes headless imports.
- **Recommendation:** keep regressions in our headless scripts, and use `test_run` at most as a convenience layer.

## 10. Godot 4.7 notes

- **Floor.** Godot 4.7 or newer is required; 4.5 and 4.6 refuse with one error and stay inert (README.md:26; AGENTS.md:314-330; `plugin.gd:17-19,1431`).
- **Tested versions.** Release qualification is **Godot 4.7.0 on macOS, Windows and Linux, with 4.7.2 tested only on Linux** (packaging-distribution.md:163-177; architecture-simplification-verification-plan.md:70-76,136-142). Our macOS 4.7.2 combination isn't in their matrix.
- **Project changes.** The first save under 4.7 rewrites `config/features` ("4.6" to "4.7") in `project.godot`. Commit that together with the upgrade, separate from the plugin.
- **Settings file.** Editor Settings move to a new per-version file, so existing 4.6 settings don't carry over. Set telemetry and exclusions again for 4.7.
- **Headless launches.** They don't start the plugin's lifecycle (server-lifecycle.md:126-132), so pipeline `--headless` imports stay free of MCP. The export strip still registers (§5).
- **Class names.** There are no `class_name` collisions: all 56 plugin classes are `Mcp*`, and there's no overlap with the project.

## 11. Risks and surprises

1. **Cross-editor routing.** The global active session means the first editor to connect, or anyone's `session_activate`, decides where unpinned calls go. This is the main danger to the user's editor. §6 step 2 is the fix.
2. **Autosave defaults to true**, and the autosave=false path flips a *shared* Editor Setting (§7).
3. **`project.godot` rewrites.** `ProjectSettings.save()` runs on plugin enable, disable and each start if the helper is missing. Expect reformatting diffs.
4. **The game helper runs in every non-export run**, including review and `-s` scripts. It adds a stdout line, an extra root child and an unbounded logger queue. It doesn't change the simulation, but any stdout-diffing regression would notice it.
5. **Input semantics.** `input_action` can't drive `_input`-based actions. Frame timing means process frames, and the start offset is arbitrary (§8).
6. **Self-update can't be disabled by a supported setting.** It checks GitHub on every start, and a human click installs. Dev mode is the only off switch, and it's unsupported (§2).
7. **Dock actions that rewrite state:**
   - Configure and Configure all rewrite client entries in all scopes.
   - Restart, Reload and Apply + Reload can stop the shared server.
   - The Tools tab changes `excluded_domains` for both editors, and a mismatch then makes the bridge refuse the backend.
   - Treat the dock as look, don't touch.
8. **Telemetry** is on by default, and there's a one-record first-connect window (§3).
9. **Supply chain.** The server comes from PyPI at spawn time with no hash pinning. The first cold start is slow (§1.6). The plugin tree itself is signature-verified.
10. **The closed-editor installer triggers a client repin** through `replace_owned_mismatches` (§1.3). Use verify plus unzip instead.
11. **Vision Routing**, if anyone enables it, sends every screenshot to Groq, Gemini or xAI (vision-routing.md:1-35). It's off by default; keep it off.
12. **Unverified items to smoke-test:**
    - Two games running at once from two editors (debugger port).
    - Whether `scene_manage save_as` onto an existing path overwrites (needed for the §6 scene_save replacement).
    - Whether autoloads load under our `-s` scripts.
13. **Unrelated local changes:** the agent worktree already has uncommitted edits to `assets/manifests/{barrow_levy,player,prop_levy_blade,prop_levy_bow}.json`. Don't bundle them into the addon commit.

---

## 12. Update trial: v4.3.0 (2026-10-07)

The update trial in CLAUDE.md → Godot MCP → Updates, on `chore/godot-ai-4.3.0`. Changelog: https://github.com/hi-godot/godot-ai/compare/v4.2.3...v4.3.0 (released 2026-10-03; no security fixes).

- **Identity.** Tag `v4.3.0` = commit `b82b5c519b1b17228f70d8effce1626f391bd1dd`. Archive SHA-256 `dbc3d16e1aa7a5f3ae8038a150bf4191162112f4329c79611aa6f656e3ca4e58`.
- **Signature.** `script/v4-release verify` from the v4.3.0 clone printed "OK: signed v4 release identity, archive, and exact tree verified". As an independent check, the clone's `PUBLIC_KEY_PEM` hashes (`openssl pkey -pubin -outform DER | shasum -a 256`) to the §1 SPKI fingerprint `84ebbd81…d21072`, and `openssl dgst -sha256 -verify` on the manifest prints "Verified OK". The key is unchanged.
- **Install.** §1 steps 2 and 3: unzip into an absent `addons/godot_ai/`, then all 313 inventory entries re-hashed, with no extra files. The file set is the same as 4.2.3's (27 files changed, none added or removed). The PyPI `godot-ai==4.3.0` package matches the tag's `src/godot_ai/` file for file.
- **Tool surface.** The server's `tools/` and `domains.py` are unchanged except a docstring on `node_set_property`. So there are no new tools, ops or parameters, and no changed defaults, and the guard's tables need no change. Behaviour changes inside already-classified ops:
  - `node_set_property` (ask, needs `scene_file`) now assigns Node-typed exports from a node path. The target must be inside the edited scene and match the export's type.
  - `node_manage.reparent` (ask) keeps instanced sub-scenes' owners instead of flattening them.
  - The game helper drops queued log lines when no debugger is attached, and the game logger caps its queue at 4096 lines. This fixes §11 item 4's unbounded queue.
- **Telemetry.** It now batches events and posts every 15 minutes to a new endpoint (`…-telemetry-v2-…`). The opt-out (`--disable-telemetry`, `GODOT_AI_DISABLE_TELEMETRY`) is unchanged, so with our config it still sends nothing.
- **Regression set (4.3.0 vs the pinned 4.2.3).**
  - Guard tests: 36/36.
  - Import, dialogue and load_all: 0 errors and 0 new warnings.
  - Validate: 19/19.
  - gdUnit4: 198 cases, 0 failures (the movement and camera suites included).
  - All 6 replay scenarios are deterministic, and all 37 checks equal their baselines.
  - Motion review of the player library: every clip's `*_metrics.json` is byte-identical under 4.2.3 and 4.3.0.
  - `godot_ai_update.py check --hook` is silent.
- **Not run: the live MCP playtests** (`docs/playtests/brief-*.md`). The shared server on :8000/:9500 was a 4.2.3 one serving the human's open editor. A 4.3.0 agent editor attaching to it would mix versions on one backend, and the guard only admits the `project-whiskeyjack-agent` worktree. They wait for the backlog item `godot-ai-4-3-playtests`.
- **After merge:** restart any open editor so its plugin and the shared server are both 4.3.0. An already-running 4.2.3 server keeps serving until every editor restarts.
