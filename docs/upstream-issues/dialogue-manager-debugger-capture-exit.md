# Dialogue Manager: "Capture not registered: 'dm'" at exit in debug runs

- **Repo:** nathanhoad/godot_dialogue_manager
- **Action:** new issue (our local patch 2, `dialogue_manager.gd`)
- **Duplicate search (2026-10-08):** `Capture not registered`, `capture`, `debugger capture`, `EngineDebugger`. No match.
- **Still present on `main`** (8ffe461f2a): `_ready()` calls `EngineDebugger.register_message_capture("dm", _capture)` and nothing unregisters it.
- **Reproduced 2026-10-08** in a fresh project with unpatched v4.1.0: the error appears on every `-d` run, and adding the `_exit_tree` below removes it.

## Title

`ERROR: Capture not registered: 'dm'` on exit of every debug run

## Body

~~~markdown
**Describe the bug**
Whenever the game runs with the debugger active (from the editor, or `godot -d`), quitting prints:

```
ERROR: Capture not registered: 'dm'.
   at: unregister_message_capture (core/debugger/engine_debugger.cpp:62)
```

The `DialogueManager` autoload registers the `dm` message capture in `_ready()` when `EngineDebugger.is_active()`, but never unregisters it, and the engine then reports the error during shutdown. It's harmless, but it's an `ERROR:` line in every debug run, which fails test runners and CI log checks.

**Affected version**

- Dialogue Manager version: 4.1.0 (tag `v4.1.0`); the same code is on `main` at 8ffe461
- Godot version: 4.7.2.stable.official (ed1daf0bf), macOS 26, Apple Silicon

**To Reproduce**

1. New project with Dialogue Manager 4.1.0 enabled (so the `DialogueManager` autoload exists) and a main scene whose script calls `get_tree().quit()`.
2. Run it with the debugger active: `godot --headless -d --path <project>`.
3. See the error above at exit.

**Expected behavior**
No error at exit. Unregistering the capture when the autoload leaves the tree fixes it for us:

```gdscript
# dialogue_manager.gd
func _exit_tree() -> void:
	if EngineDebugger.has_capture("dm"):
		EngineDebugger.unregister_message_capture("dm")
```

Happy to open a PR with this.
~~~
