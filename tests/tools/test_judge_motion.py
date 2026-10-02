#!/usr/bin/env python3
"""Tests for the motion packet's game-path assertions in scripts/judge.py (stdlib unittest).

    python3 tests/tools/test_judge_motion.py

The motion review's game-path pass (scripts/review/game_path.gd) writes a game_path block into each
clip's metrics; the judge asserts the expected clip plays and gates the handover snap against the art
bible's motion_handover_snap_mps. A tolerance marked **proposed** in the art bible is reported as an
advisory, not asserted, until it is adopted.
"""
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import judge  # noqa: E402

KEY = "motion_handover_snap_mps"


def metrics(snap=12.0, wrong=0, errors=False):
    handovers = [{"from": "idle", "to": "attack", "snap_excess_mps": snap, "wrong_clip_frames": wrong, "settle_error_m": 0.0}]
    if errors:
        handovers.append({"from": "attack", "to": "idle", "error": "attack never finished", "snap_excess_mps": -1.0})
    return {"game_path": {"scene": "res://scenes/enemies/BaseEnemy.tscn", "fps": 60.0, "handovers": handovers,
                          "handover_snap_mps": snap, "handover_snap_worst": "idle>attack",
                          "wrong_clip_frames": wrong, "settle_error_max_m": 0.0}}


def run(mm, proposed):
    packet = {"assertions": []}
    judge.game_path_assertions(packet, mm, {KEY: 5.0}, proposed)
    return packet


class GamePathAssertions(unittest.TestCase):
    def test_adopted_tolerance_is_asserted(self):
        p = run(metrics(snap=12.0), set())
        snap = [a for a in p["assertions"] if "snap" in a["name"]]
        self.assertEqual(len(snap), 1)
        self.assertFalse(snap[0]["passed"])
        self.assertEqual(snap[0]["limit"], 5.0)
        self.assertIn("idle>attack", snap[0]["detail"])

    def test_proposed_tolerance_is_an_advisory_only(self):
        p = run(metrics(snap=12.0), {KEY})
        self.assertFalse([a for a in p["assertions"] if "snap" in a["name"]])
        self.assertEqual(len(p["advisories"]), 1)
        self.assertFalse(p["advisories"][0]["passed"])
        self.assertIn("proposed", p["advisories"][0]["detail"])

    def test_the_expected_clip_must_play(self):
        self.assertTrue(run(metrics(wrong=0), {KEY})["assertions"][0]["passed"])
        self.assertFalse(run(metrics(wrong=3), {KEY})["assertions"][0]["passed"])
        self.assertFalse(run(metrics(errors=True), {KEY})["assertions"][0]["passed"])

    def test_metrics_without_a_game_path_add_nothing(self):
        p = {"assertions": []}
        judge.game_path_assertions(p, {}, {KEY: 5.0}, set())
        self.assertEqual(p, {"assertions": []})

    def test_proposed_rows_are_read_from_the_art_bible(self):
        text = ("| `motion_edge_stretch` | 1.0 | every clip | Why. |\n"
                "| `motion_handover_snap_mps` | 5 | every clip, **proposed** | Why. |\n")
        self.assertEqual(judge.proposed_tolerances(text), {KEY})

    def test_the_art_bible_has_the_handover_tolerance(self):
        self.assertIn(KEY, judge.tolerances())

    def test_the_handover_tolerance_is_adopted(self):
        # Adopted by the user on 2026-10-01: the judge fails a clip over it, no longer an advisory
        self.assertNotIn(KEY, judge.proposed_tolerances())


if __name__ == "__main__":
    unittest.main(verbosity=2)
