#!/usr/bin/env python3
"""Tests for the sourced-asset licence and provenance rules (scripts/pipeline.py: source_errors,
sources_manifest_errors). Stdlib only, no Godot or Blender:

    python3 ci/test_sources.py
"""

import copy
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import pipeline as P  # noqa: E402

SHA = "0" * 64
BRIEF = {"asset_id": "kit_crate", "source": "download", "pack": "kit", "source_url": "https://example.org/kit.zip",
         "author": "Someone", "license": "CC0-1.0", "source_file": ".downloads/kit/crate.glb"}
ENTRY = {"pack": "kit", "source_url": "https://example.org/kit.zip", "author": "Someone", "license": "CC0-1.0",
         "pack_version": "1.0", "source_file": ".downloads/kit/crate.glb", "source_sha256": SHA}
DERIVED = {"from": "kit_crate_raw", "steps": [{"tool": "tripo", "type": "animate_rig", "task_id": "t1", "credits": 25}]}
SOURCES = {"packs": {"kit": {"license": "CC0-1.0"}}, "assets": {"kit_crate": ENTRY}}


def sources(**entry):
    s = copy.deepcopy(SOURCES)
    s["assets"]["kit_crate"].update(entry)
    return s


class SourceRules(unittest.TestCase):
    def test_cc0_entry_passes(self):
        self.assertEqual(P.source_errors(BRIEF, SOURCES, check_files=False), [])
        self.assertEqual(P.sources_manifest_errors(SOURCES, [BRIEF]), [])

    def test_non_cc0_entry_fails(self):
        errs = P.source_errors({**BRIEF, "license": "CC-BY-4.0"}, sources(license="CC-BY-4.0"), check_files=False)
        self.assertTrue(any("'CC-BY-4.0' is not allowed" in e for e in errs), errs)

    def test_non_cc0_entry_fails_even_if_brief_says_cc0(self):
        errs = P.source_errors(BRIEF, sources(license="CC-BY-NC-4.0"), check_files=False)
        self.assertTrue(any("sources.json entry licence 'CC-BY-NC-4.0' is not allowed" in e for e in errs), errs)

    def test_non_cc0_pack_fails(self):
        s = copy.deepcopy(SOURCES)
        s["packs"]["kit"]["license"] = "CC-BY-3.0"
        self.assertTrue(P.source_errors(BRIEF, s, check_files=False))
        self.assertTrue(any("pack kit" in e for e in P.sources_manifest_errors(s, [BRIEF])))

    def test_missing_entry_fails(self):
        errs = P.source_errors(BRIEF, {"packs": {}, "assets": {}}, check_files=False)
        self.assertTrue(errs and "no entry in assets/sources.json" in errs[0], errs)

    def test_missing_fields_fail(self):
        errs = P.source_errors(BRIEF, sources(source_sha256="", pack_version=None), check_files=False)
        self.assertTrue(any("lacks" in e and "source_sha256" in e and "pack_version" in e for e in errs), errs)

    def test_provenance_mismatch_fails(self):
        errs = P.source_errors({**BRIEF, "author": "Someone Else"}, SOURCES, check_files=False)
        self.assertTrue(any("brief author" in e for e in errs), errs)

    def test_orphan_entry_fails(self):
        self.assertTrue(any("has no sourced brief" in e for e in P.sources_manifest_errors(SOURCES, [])))

    def test_generated_assets_need_no_entry(self):
        self.assertEqual(P.source_errors({"asset_id": "player", "type": "character"}, SOURCES), [])

    # A derived asset (spike-agent-animation): a sourced asset reworked by a vendor (Tripo's rig and
    # retarget of the CC0 Gobkit boar). Its file is in the gitignored .tripo-out/, and its entry records
    # what it came from and each paid step.
    def test_derived_entry_passes(self):
        brief = {**BRIEF, "derived_from": "kit_crate_raw", "source_file": ".tripo-out/kit_crate/model.glb"}
        s = sources(source_file=".tripo-out/kit_crate/model.glb", derived=DERIVED)
        self.assertEqual(P.source_errors(brief, s, check_files=False), [])

    def test_derived_entry_needs_its_record(self):
        brief = {**BRIEF, "derived_from": "kit_crate_raw", "source_file": ".tripo-out/kit_crate/model.glb"}
        errs = P.source_errors(brief, sources(source_file=".tripo-out/kit_crate/model.glb"), check_files=False)
        self.assertTrue(any("derived" in e for e in errs), errs)

    def test_derived_record_must_name_the_brief_source(self):
        brief = {**BRIEF, "derived_from": "kit_crate_raw", "source_file": ".tripo-out/kit_crate/model.glb"}
        s = sources(source_file=".tripo-out/kit_crate/model.glb", derived={**DERIVED, "from": "other"})
        self.assertTrue(any("derived from" in e for e in P.source_errors(brief, s, check_files=False)))

    def test_derived_steps_need_task_and_credits(self):
        brief = {**BRIEF, "derived_from": "kit_crate_raw", "source_file": ".tripo-out/kit_crate/model.glb"}
        s = sources(source_file=".tripo-out/kit_crate/model.glb", derived={**DERIVED, "steps": [{"type": "rig"}]})
        self.assertTrue(any("step" in e for e in P.source_errors(brief, s, check_files=False)))

    def test_source_file_location(self):
        self.assertTrue(P.source_file_ok({"source_file": ".downloads/kit/crate.glb"}))
        self.assertFalse(P.source_file_ok({"source_file": ".tripo-out/kit_crate/model.glb"}))
        self.assertTrue(P.source_file_ok({"source_file": ".tripo-out/kit_crate/model.glb", "derived_from": "kit_crate_raw"}))
        self.assertFalse(P.source_file_ok({"source_file": "assets/meshes/crate.glb", "derived_from": "kit_crate_raw"}))

    def test_committed_manifest_passes(self):
        self.assertEqual(P.sources_manifest_errors(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
