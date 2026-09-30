# A3: edit-time navmesh bake and a path-clearance check

**Goal:** stop baking navmeshes at runtime (design bible §8; this also removes the "RenderingServer meshes" performance warning), and prove the critical path is clear enough (`lvl_path_clearance_min` ≥ 1.0 m).

**Scope:**
- **A tool** `scripts/tools/bake_navmeshes.gd` (headless `-s`), which, for each level scene (Level1, Level2):
  - bakes each `NavigationRegion3D` (`bake_navigation_mesh(false)`, parsing collision or static geometry, whichever gives the right mesh without the runtime warning);
  - saves the `NavigationMesh` as a `.tres` next to the level (for example `scenes/world/Level1_navmesh.tres`) and points the region at it;
  - is deterministic: running it twice gives identical files.
- **Remove** the runtime bake from `Level1.gd` and `Level2.gd`. Enemies must still path-find, so check headless that a Front-file chases the player around a pillar.
- **Clearance check:**
  - Bake a second, check-only navmesh with agent radius 0.5 m (1.0 m clearance), in memory and never saved.
  - Query `NavigationServer3D.map_get_path` along each level's critical path: waypoints for spawn → Corridor A → Central → Corridor B → Exit in Level 1, and the equivalent in Level 2.
  - Report pass or fail per segment with the path length. Keep the waypoints in a small JSON per level (`tests/critical_paths/level1.json`).
  - Expect the start-room crate snag to show up as a failure or a detour, so report the current state honestly; don't fix level geometry in this PR.
- **The baked `.tres` files are generated:** only the tool writes them. Say so in the tool header, and propose a CLAUDE.md line in the report.
- **CI:** add a job, or a step in A1's workflow, that re-bakes and fails if the result differs from the committed navmesh (stale bake), and that runs the clearance check (report-only until the level fixes land).

**Acceptance:**
- No runtime bake, and the warning is gone from the headless import and run logs.
- Enemies still path-find.
- Two bakes give identical files.
- The clearance report exists for both levels.

**Serves:** §8 of the bible, `lvl_path_clearance_min`.
