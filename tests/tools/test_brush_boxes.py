#!/usr/bin/env python3
"""Tests for scripts/tools/brush_boxes.py (stdlib unittest).

    python3 tests/tools/test_brush_boxes.py
"""
import importlib.util
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_spec = importlib.util.spec_from_file_location("brush_boxes", os.path.join(ROOT, "scripts", "tools", "brush_boxes.py"))
bb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bb)

PLANE = re.compile(r"\( (-?\d+) (-?\d+) (-?\d+) \) \( (-?\d+) (-?\d+) (-?\d+) \) \( (-?\d+) (-?\d+) (-?\d+) \) (\S+)")


def parse(line):
    g = PLANE.match(line).groups()
    pts = [tuple(int(v) for v in g[i : i + 3]) for i in (0, 3, 6)]
    return pts, g[9]


def outward(lines, centre_q):
    for line in lines:
        (p0, p1, p2), _ = parse(line)
        n = bb.quake_normal(p0, p1, p2)
        if bb._dot(n, bb._sub(centre_q, p0)) >= 0:
            return False
    return True


class BrushBoxes(unittest.TestCase):
    def test_godot_to_quake_axes(self):
        # Godot (x, y, z) = Quake (y, z, x) / 32
        self.assertEqual(bb.to_quake((1, 2, 3)), (96, 32, 64))

    def test_box_normals_point_out(self):
        lines = bb.box_planes((-1, 0, -2), (1, 3, 2), "t")
        self.assertEqual(len(lines), 6)
        self.assertTrue(outward(lines, bb.to_quake((0, 1.5, 0))))

    def test_outside_faces_get_skip_on_the_right_side(self):
        lines = bb.box_planes((0, -1, 0), (1, 0, 1), "floor", bb.outside("-y"))
        skipped = [parse(l) for l in lines if l.endswith("skip 0 0 0 1 1")]
        self.assertEqual(len(skipped), 1)
        (p0, p1, p2), _ = skipped[0]
        self.assertEqual(bb.quake_normal(p0, p1, p2)[2] < 0, True)  # Quake -z is Godot -y
        with self.assertRaises(ValueError):
            bb.outside("down")

    def test_hull_is_rewound_to_face_out(self):
        ramp = [
            [(-2, 0, -6), (2, 0, -6), (2, 0, -8)],
            [(-2, 0, -8), (2, 0, -8), (2, 1, -8)],
            [(-2, 0, -6), (-2, 0, -8), (-2, 1, -8)],
            [(2, 0, -6), (2, 1, -8), (2, 0, -8)],
            [(-2, 0, -6), (2, 0, -6), (2, 1, -8)],
        ]
        self.assertTrue(outward(bb.hull_planes(ramp, (0, 0.3, -7.5), "clip"), bb.to_quake((0, 0.3, -7.5))))

    def test_flat_box_is_refused(self):
        with self.assertRaises(ValueError):
            bb.box_planes((0, 0, 0), (1, 0.01, 1), "t")

    def test_committed_maps_match_their_layouts(self):
        self.assertEqual(bb.main(["--check"]), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
