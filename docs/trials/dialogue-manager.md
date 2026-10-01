# Trial B4: Dialogue Manager for dialogue and multi-outcome quests

Phase B trial from `docs/tools-review-2026-09.md` (item 8). The question: should Dialogue Manager's `.dialogue` scripts replace our JSON dialogue format?

**Recommendation: keep, with changes** (listed at the end). This branch switches the game over. If the decision is drop, revert the branch's commits from "Vendor Dialogue Manager" on; only this note needs to land.

## What was pinned

| | |
|---|---|
| Addon | Dialogue Manager **v4.1.0** ("for Godot 4.7"), tag `v4.1.0`, commit `a719088aea342572f29b5559fd8726896c9519b2` |
| Source | https://github.com/nathanhoad/godot_dialogue_manager, exported with its own `.gitattributes` (the AssetLib set: `addons/` only; 189 files, 1.2 MB, about 12,300 lines of GDScript) |
| Licence | MIT (`addons/dialogue_manager/LICENSE`; GitHub reports MIT) |
| Godot | Works on 4.7.2: import, `ci/load_all.gd`, gdUnit4, replays and a GUI editor start all run clean, with the patches below |
| Local patches | 4, kept as `docs/trials/dialogue-manager-v4.1.0.patch` and marked `[whiskeyjack patch]` in the code |

### Local patches (why each one)

1. **Headless editors register only the importer and exporter** (`plugin.gd`). The editor UI's code editor `load()`s every global class script in the project for autocomplete. In a headless `--import` that leaks 552 objects at exit, which `ci/check_log.py` fails as `ERROR:` lines. The UI isn't needed headless.
2. **The runtime autoload unregisters its `dm` debugger capture on exit** (`dialogue_manager.gd`). Without it, every debug run (tests, `-d`, editor runs) logs `ERROR: Capture not registered: 'dm'`.
3. **The line data is copied before the resource is attached** (`dialogue_manager.gd`, `get_line`). Upstream writes the resource into its own `lines` dictionary, a reference cycle, so every dialogue that ran is reported as `resources still in use at exit`.
4. **No update check** (`components/update_button.gd`). Every GUI editor start queried the GitHub releases API and offered a one-click update that overwrites `addons/dialogue_manager` in place (dropping these patches). The addon only changes deliberately, like godot-ai and gdUnit4.

Patches 1–3 are upstream bugs worth reporting; each upstream fix shrinks the patch file.

### What the plugin does at editor and import time (audit)

- **Network:** only the update check (patched out). The editor's "help", "Patreon" and example-project buttons open URLs only when clicked. There's no telemetry.
- **Writes inside the project:**
  - the compiled `.dialogue` → `.godot/imported/*.tres`;
  - `project.godot`, when its settings change, and the translation POT list on every editor start. The POT list is turned off here with `dialogue_manager/editor/translations/UPDATE_TRANSLATION_TEMPLATES_AUTOMATICALLY=false`; otherwise opening the editor wrote both `.dialogue` files, the test fixture too, into `project.godot`;
  - dialogue files that import a moved file (path rewrite).
- **Writes outside the project:** `user://dialogue_manager_user_config.json` (recent files, compiler version, the update-check toggle). That's the project's user-data folder, which every checkout on this Mac shares.
- **Processes:** `OS.create_process` only when "open in external editor" is turned on.
- **Autoload:** `DialogueManager` (registered by hand in `project.godot`, next to `DialogueRunner`). It resolves dialogue expressions against every autoload by name, so dialogue can call `QuestManager` directly.
- **Remaining cost:** quitting the GUI editor prints 22 GL texture-leak lines, against 2 without the addon. That's editor-only and cosmetic, and CI never sees it.

## What changed in the game

- **`DialogueRunner` is now a wrapper.** It keeps `dialogue_started(id)`, `line_ready(speaker, text, choices)`, `dialogue_ended`, `start(id)` and `advance(choice)`, and plays `data/dialogues/<id>.dialogue` from `~ start`. `DialogueUI` is unchanged. Choices are `{"text": ...}`, listing only the choices whose conditions allow them. The `next_id` field the JSON had is gone (it was internal).
- **Keeper Idrenna** is one `village_elder.dialogue` instead of two JSON files. It has five openings, one for each quest state, plus a world flag:

  | State | Opening | Outcome |
  |---|---|---|
  | first meeting | "They sent one of you, then. One." | accept → quest started; refuse → `idrenna_turned_down` set |
  | turned down before | "Orders change, soldier?" (new line) | the offer again |
  | quest active | "Still walking, are they? Then so should you." (new line) | none |
  | `return_to_keeper` | "You came back. More than most." | the quest is completed by a mutation, and the reward lands |
  | complete | "Keep your feet dry, soldier." | none |

  Existing lines are kept word for word. The two new lines need the user's OK on tone.
- **World flags** live in `QuestManager` (`set_flag`, `get_flag`, `has_flag`, `flag_changed`) and are saved with the quests. Saves from before flags load as "no flags set", and the format version stays 2.
- **NPC rewards** fire on `QuestManager.quest_completed`, so a dialogue mutation can complete a quest. This also fixes a duplicate reward: after a save was loaded, the next talk gave the shield and 50 XP again. `Level1.tscn` drops `return_stage_id` and `completion_dialogue_id`, though both exports still work.

## CI coverage

| Check | JSON (before) | `.dialogue` (now) |
|---|---|---|
| Syntax | `json.loads` in data-lint | Dialogue Manager's compiler at import. The importer's "N errors found in …" now fails `ci/check_log.py`, and `ci/check_dialogue.gd` (import job) prints each error with its line |
| Start point | `start` node | `~ start` cue |
| Links | every `next_id` exists | every `=> cue` exists (also a compile error) |
| Reachability | every node reachable from `start` | every cue jumped to |
| Quest ids | `set_quest` names a quest | every `QuestManager.*("id")` call names a quest, and `get_quest_stage("q") == "s"` names a real stage |
| Flags | none | a flag read (`get_flag`/`has_flag`) must be `set_flag`'d in some dialogue or script |
| Tone limits | ≤ 2 sentences per node, baselined | ≤ 2 sentences per spoken line, baselined (the same one known violation moved over). Objectives stay in the quest JSON, ≤ 12 words |
| Behaviour | none | gdUnit4 runs every Idrenna branch (`tests/unit/test_dialogue_runner.gd`) |

**Not covered:** a typo in a method or property name inside an expression (`QuestManager.start_quets(...)`). The compiler doesn't check state names, so it fails only at runtime. The gdUnit4 branch tests catch it for Idrenna; a lint of `QuestManager.<name>` against the script's methods would catch it everywhere (a follow-up).

**The syntax gate, demonstrated:** a throwaway commit removed a closing parenthesis in `village_elder.dialogue`. The pre-push hook, which runs the same import and `check_log.py` as CI's import job, refused the push with `::error::…import.log: 1 errors found in res://data/dialogues/village_elder.dialogue`. `ci/check_dialogue.gd` printed `ERROR: res://data/dialogues/village_elder.dialogue:4: Missing closing bracket.` and exited 1.

Pushing it to CI would have meant `--no-verify`, which the project rules forbid, so the commit was dropped unpushed. The CI import job runs the same two commands.

## Comparison with today's JSON

| | JSON | Dialogue Manager |
|---|---|---|
| Authoring (agent) | Each node needs an id, and every link is a `next_id` string to keep in sync. Idrenna was 20 lines in 2 files, plus 3 scene exports and NPC code to choose between them | Write the conversation top to bottom; nesting is a branch. Idrenna is 34 content lines in 1 file covering 5 states. It compiled and passed its tests on the first run |
| Diffability | One node per line, but a new branch touches ids in several nodes | One spoken line per line. A new branch is a contiguous block (the turned-down branch is 4 lines) |
| Branching | Choices, plus `set_quest` (start only). Quest-state branching needs NPC code per case | `if`/`elif`/`match` on any state, conditional choices, mutations (start, advance or complete quests; flags; any autoload method or signal), jumps, random lines, inline conditions |
| Multi-outcome quests (design bible §6: "at least two resolutions") | Needs a format extension and an evaluator | Built in |
| Runtime | Synchronous, 90 lines | Async (each mutation takes at least a frame; works while paused). A 87-line wrapper over a 12k-line addon |
| Maintenance | Ours, tiny | 4 local patches to reapply on each update. Upstream ships often (5 releases from 2026-08-15 to 2026-09-04) |
| Godot-upgrade risk | None | Each Dialogue Manager major tracks a Godot minor (v3.x for 4.3–4.6, v4 for 4.6+, with 4.7 support from 3.10.5). A Godot upgrade usually means a Dialogue Manager bump, with syntax changes at majors (v3→v4 renamed titles to cues). Its `COMPILER_VERSION` change reimports every `.dialogue` |
| Editor | Any text editor | A dialogue tab with syntax highlighting, error gutter and a test-run scene. Plain text otherwise |

## Recommendation: keep, with changes

Keep it. The design bible needs multi-outcome quests with persistent flags, and the JSON format can't express them without growing its own condition language and evaluator. That would be a home-made Dialogue Manager with weaker checks. The wrapper keeps the addon behind `DialogueRunner`, so dropping it later means rewriting `DialogueRunner` and porting the `.dialogue` files, not touching the UI or NPCs.

Changes that come with keeping it:

1. **Pin it like gdUnit4 and godot-ai.** Never use the in-editor updater (patched out). An update is a `chore/dialogue-manager-<version>` branch:
   1. export the new tag;
   2. check the commit SHA and the MIT licence;
   3. `git apply docs/trials/dialogue-manager-<old>.patch`, dropping any hunk fixed upstream, and save the patch for the new version;
   4. rerun the import with `ci/check_log.py`, `ci/check_dialogue.gd`, `tests/run.sh`, `ci/data_lint.py` and the replays.
2. **Report patches 1–3 upstream**, so the patch file shrinks.
3. **Follow-up lint:** `QuestManager.<method>` names in `.dialogue` must exist on `QuestManager`.
4. **CLAUDE.md's Dialogue System section** describes `.dialogue` instead of the JSON format (proposed text in the PR).
5. **Before a Godot upgrade,** check that a Dialogue Manager release exists for the target version.
