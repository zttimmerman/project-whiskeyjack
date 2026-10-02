#!/usr/bin/env python3
"""Tests for the brief's `parts` schema in scripts/pipeline.py (stdlib unittest).

    python3 tests/tools/test_brief_parts.py

A character built from separate shells (a body plus garment shells, e.g. Tripo P2) lists each shell
in `parts`, one inline mapping per line:

    parts:
      - {select: rank 1, bind: transfer, offset_mm: 0}
      - {select: rank 3-4, bind: transfer, offset_mm: 4}
      - {select: rank 6-9, bind: rigid:Head}

`select` picks welded shells by size rank (1 = most triangles), `bind` is `keep` (the rig's own
weights stay, and the shell is the weight source), `transfer` (weights copied from the source: the
keep shells, or with none a continuous voxel proxy of the transfer shells; CLAUDE.md's fourth
animation exception) or `rigid:<bone>` (weight 1.0 on that bone), `offset_mm` (garments only, 0-10) pushes the shell out along its normals, and `skirt: true`
marks the shells `skirt_reweight` may grade (without it, a flared boot cuff above the knee counts as skirt).
"""
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import pipeline  # noqa: E402

BRIEF = """asset_id: x
parts:
  - {select: rank 1, bind: transfer, offset_mm: 0}
  - {select: rank 3-4, bind: transfer, offset_mm: 4}
  - {select: rank 6-9, bind: rigid:Head}
skirt_reweight: true
"""


class PartsParsing(unittest.TestCase):
    def test_inline_mappings_parse(self):
        b = pipeline.parse_brief_yaml(BRIEF, "x.yaml")
        self.assertEqual(b["parts"][0], {"select": "rank 1", "bind": "transfer", "offset_mm": 0})
        self.assertEqual(b["parts"][1]["offset_mm"], 4)
        self.assertEqual(b["parts"][2], {"select": "rank 6-9", "bind": "rigid:Head"})
        self.assertIs(b["skirt_reweight"], True)

    def test_plain_lists_still_parse(self):
        b = pipeline.parse_brief_yaml("animations:\n  - idle\n  - run\n", "x.yaml")
        self.assertEqual(b["animations"], ["idle", "run"])

    def test_unclosed_mapping_fails(self):
        with self.assertRaises(pipeline.PipelineError):
            pipeline.parse_brief_yaml("parts:\n  - {select: rank 1, bind: transfer\n", "x.yaml")


class PartsSelect(unittest.TestCase):
    def test_ranks(self):
        self.assertEqual(pipeline.part_ranks("rank 1"), [1])
        self.assertEqual(pipeline.part_ranks("rank 3-4"), [3, 4])
        self.assertEqual(pipeline.part_ranks("rank 2,5"), [2, 5])
        self.assertEqual(pipeline.part_ranks("rank 6-9"), [6, 7, 8, 9])

    def test_bad_select(self):
        for bad in ("largest", "rank 0", "rank 4-3", "rank x"):
            with self.assertRaises(pipeline.PipelineError, msg=bad):
                pipeline.part_ranks(bad)


class PartsErrors(unittest.TestCase):
    def errors(self, parts, **brief):
        return pipeline.parts_errors({"type": "character", "parts": parts, **brief})

    def test_valid(self):
        self.assertEqual(self.errors(pipeline.parse_brief_yaml(BRIEF, "x.yaml")["parts"]), [])

    def test_keep_is_a_bind(self):
        self.assertEqual(self.errors([{"select": "rank 1", "bind": "keep"}, {"select": "rank 2", "bind": "transfer"}]), [])

    def test_bad_bind(self):
        self.assertTrue(self.errors([{"select": "rank 1", "bind": "glue"}]))

    def test_rigid_needs_bone(self):
        self.assertTrue(self.errors([{"select": "rank 1", "bind": "rigid:"}]))

    def test_rank_listed_twice(self):
        self.assertTrue(self.errors([{"select": "rank 1-2", "bind": "transfer"}, {"select": "rank 2", "bind": "transfer"}]))

    def test_offset_range(self):
        self.assertTrue(self.errors([{"select": "rank 1", "bind": "transfer", "offset_mm": 12}]))
        self.assertTrue(self.errors([{"select": "rank 1", "bind": "transfer", "offset_mm": -1}]))

    def test_skirt_needs_skirt_reweight(self):
        part = {"select": "rank 1", "bind": "transfer", "skirt": True}
        self.assertTrue(self.errors([part]))
        self.assertEqual(self.errors([part], skirt_reweight=True), [])

    def test_unknown_key(self):
        self.assertTrue(self.errors([{"select": "rank 1", "bind": "transfer", "weld": True}]))

    def test_needs_a_transfer_part(self):
        # The proxy is built from the transfer shells; with none there's nothing to copy weights from
        self.assertTrue(self.errors([{"select": "rank 1", "bind": "rigid:Head"}]))

    def test_not_with_rigid_parts(self):
        self.assertTrue(self.errors([{"select": "rank 1", "bind": "transfer"}], rigid_parts=True))

    def test_characters_only(self):
        self.assertTrue(pipeline.parts_errors({"type": "prop", "parts": [{"select": "rank 1", "bind": "transfer"}]}))


if __name__ == "__main__":
    unittest.main()
