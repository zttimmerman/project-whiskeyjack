# A2a: gdUnit4 and the first unit tests

**Goal:** a GDScript test framework in CI, with tests for the systems the design bible changes next.

**Scope:**
- **Vendor gdUnit4 v6.2.1** (MIT, https://github.com/godot-gdunit-labs/gdUnit4) into `addons/gdUnit4`, pinned; record the tag and commit in the PR.
  - Enable it in `project.godot`.
  - Confirm it works on 4.7.2; its README lists up to 4.7.1.
  - Check it doesn't disturb headless runs or the godot-ai plugin, and that the motion review still gives identical metrics (for example the `idle` clip).
- **Move** `tests/test_respawn_save.gd` into gdUnit4's form, or run it as-is from a test. Keep its save-slot isolation.
- **Unit tests** under `tests/`:
  - `CharacterStats`: take_damage, heal, level_up and signals;
  - `Inventory`: add, remove, equip and unequip, with modifiers applied once;
  - `QuestManager`: start, advance, complete and signals;
  - `SaveManager`: a save/load round-trip on a temporary slot; a foreign-scene save ignored; the version check.
- **Pending tests** for the settled design-bible decisions, marked skipped or pending until implemented:
  - the damage ratio `max(1, round(dmg × 100 / (100 + 10 × def)))`;
  - enemy damage at 8–10% of player HP at equal level;
  - level-band scaling `base × (1 + 0.12 × (level − 1))`.

  These document the targets and flip on in the PR that implements them.
- **CI:** add a gdUnit4 job to `.github/workflows/ci.yml`, using `godot-gdunit-labs/gdUnit4-action` or the CLI, with JUnit output uploaded as an artifact.
- **Document** in the report how to run the tests locally (one command).

**Acceptance:** the tests pass locally and in CI; a deliberately failing assertion fails CI (shown, then dropped); the motion review is unchanged.

**Serves:** `ttk_*`, §6 (damage and level bands), save integrity.
