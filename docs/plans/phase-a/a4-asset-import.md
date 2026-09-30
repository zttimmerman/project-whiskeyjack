# A4: the downloaded-asset import path

**Goal:** CC0 kits (KayKit, Quaternius, Kenney) go through the same clean stage as generated assets (facing and pivot, flat shading, albedo-only, palette correction, the triangle budget) and land in the same colour space and shading standard. This unlocks Phase C. The principle is in the art bible: generate what carries identity, download the rest.

**Scope:**
- **Briefs for sourced assets:** `assets/briefs/<id>.yaml` gains `source: download` plus `source_url`, `author`, `license` (CC0 only unless the user decides otherwise; anything else fails validation) and `source_file` (the path of the downloaded file inside a gitignored `.downloads/<pack>/` folder, keeping the original zip and its SHA-256).
  - Budgets still come from the art bible. Add a "Sourced props" budget line to the art bible **only as a proposal in your report**, since budgets are the user's call.
- **`pipeline.py`:** sourced assets skip concept, multiview, model and rig, and run clean and validate. There's no approved concept, so colour correction uses the palette fallback that already exists.
  - Kits often share one atlas across many pieces. Handle one GLB per piece, with the shared atlas downscaled to the brief's `texture_size` and corrected once, and palette correction deterministic per atlas. Explain the approach.
  - Kits come as FBX, glTF or OBJ. Support glTF and OBJ; FBX optionally, if Blender's importer handles it headless.
- **A sources manifest** `assets/sources.json`, committed: one entry per imported asset with URL, author, licence, pack version and SHA-256 of the source file. Validate fails if an asset lacks an entry or has a non-CC0 licence.
- **A pack helper** `scripts/tools/import_pack.py`: given a downloaded pack folder and a list of piece names (or a glob), it writes the briefs and runs the pipeline for each. It's idempotent, and reports triangle counts and budget failures per piece.
- **The judge:** sourced assets are judged at the mesh stage as usual (`judge.py packet --stage mesh`), and the packet notes "sourced, no concept". Check that it works; don't change the judge's rules.
- **Test:** import a small CC0 set end to end (for example 5–10 pieces from KayKit Dungeon Remastered: a wall, floor, door, crate, barrel, stairs), all passing clean and validate, with judge packets built.
  - Downloads are free CC0: download them with curl from the official URLs in `docs/tools-review-2026-09.md`, never with the Blender MCP tools. If a download needs a browser login, stop and report.
- **Docs:** update the asset-pipeline skill (Adding an asset → sourced assets), and propose CLAUDE.md and art-bible text in your report.

**Acceptance:**
- 5 or more CC0 pieces imported, cleaned, validated and judged.
- The sources manifest is complete.
- A non-CC0 licence entry fails validation (shown).
- Existing generated assets are unaffected: `pipeline.py <id> --stage validate` passes for all four.

**Serves:** Phase C, `lvl_dressing_density`, and the art bible's sourcing principle.
