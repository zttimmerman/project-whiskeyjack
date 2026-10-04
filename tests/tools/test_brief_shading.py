#!/usr/bin/env python3
"""Tests for the brief's `smooth_shading` flag in scripts/pipeline.py (stdlib unittest).

    python3 tests/tools/test_brief_shading.py

Art bible → Shading (adopted 2026-10-02, docs/backlog/decide-art-direction.md): continuous-skin characters
keep the generator's smooth normals (brief `smooth_shading: true`); props, kit pieces and rigid-part
characters stay flat-shaded over 30 degrees. The clean stage reads the flag from the stage params.
"""
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import pipeline  # noqa: E402


class ShadingErrors(unittest.TestCase):
    def test_continuous_skin_character(self):
        self.assertEqual(pipeline.shading_errors({"type": "character", "smooth_shading": True}), [])

    def test_absent_or_false_is_flat(self):
        self.assertEqual(pipeline.shading_errors({"type": "character"}), [])
        self.assertEqual(pipeline.shading_errors({"type": "prop", "smooth_shading": False}), [])

    def test_must_be_bool(self):
        self.assertTrue(pipeline.shading_errors({"type": "character", "smooth_shading": "yes"}))

    def test_characters_only(self):
        # Props and kit pieces keep the 30 degree flat rule (smooth hard surfaces read as inflated plastic)
        self.assertTrue(pipeline.shading_errors({"type": "prop", "smooth_shading": True}))

    def test_not_with_rigid_parts(self):
        # Rigid-part characters keep flat shading (the Barrow-levy's belt read as a tube when smooth)
        self.assertTrue(pipeline.shading_errors({"type": "character", "smooth_shading": True, "rigid_parts": True}))


class ShadingParams(unittest.TestCase):
    def test_stage_params_carry_the_flag(self):
        b = pipeline.parse_brief_yaml("asset_id: x\ntype: character\nsmooth_shading: true\n", "x.yaml")
        self.assertIs(pipeline.stage_params(b)["smooth_shading"], True)

    def test_shipped_briefs(self):
        # The player is continuous skin; the Barrow-levy is rigid parts
        self.assertIs(pipeline.load_brief("player").get("smooth_shading"), True)
        self.assertFalse(pipeline.load_brief("barrow_levy").get("smooth_shading"))


if __name__ == "__main__":
    unittest.main()
