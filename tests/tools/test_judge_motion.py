#!/usr/bin/env python3
"""Tests for the motion packet's game-path assertions in scripts/judge.py (stdlib unittest).

    python3 tests/tools/test_judge_motion.py

The motion review's game-path pass (scripts/review/game_path.gd) writes a game_path block into each
clip's metrics; the judge asserts the expected clip plays and gates the handover snap against the art
bible's motion_handover_snap_mps. A tolerance marked **proposed** in the art bible is reported as an
advisory, not asserted, until it is adopted.

The clip's own gates (motion_assertions) are per body height (motion-gates-gait-and-scale, user decision
2026-10-02): root travel, foot slide and bind deviation against the art bible's *_bh limits, and in a
locomotion clip the gait check (every foot lifts and swings).
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


REL = {"motion_root_travel_bh": 0.0834, "motion_foot_slide_bhps": 0.2778, "motion_bind_deviation_bh": 1.0,
       "motion_edge_stretch": 1.0, "motion_gait_lift_bh": 0.005, "motion_gait_swing_bh": 0.05}


def clip(kind="in_place", height=1.8, travel=0.03, slide=0.345, dev=1.2, locomotion=True, gait=None):
    gait = gait if gait is not None else {"left": (0.368, 1.164), "right": (0.356, 1.138)}
    mm = {"kind": kind, "body_height_m": height, "root_travel_max_m": travel, "root_travel_final_m": travel,
          "root_travel_max_bh": round(travel / height, 4), "contact_frames": 6, "ground_speed_mps": 5.0,
          "foot_slide_p90_mps": slide, "foot_slide_p90_bhps": round(slide / height, 4),
          "bind_deviation_max_m": dev, "bind_deviation_max_bh": round(dev / height, 4), "bind_deviation_p99_m": dev,
          "edge_stretch_max": 0.2, "edge_stretch_p99": 0.1, "locomotion": locomotion,
          "gait": {side: {"lift_m": lift, "swing_m": swing, "lift_bh": round(lift / height, 4),
                          "swing_bh": round(swing / height, 4)} for side, (lift, swing) in gait.items()}}
    return mm


def assertions(mm):
    packet = {"assertions": []}
    judge.motion_assertions(packet, mm, REL)
    return {a["name"]: a for a in packet["assertions"]}


class SizeRelativeGates(unittest.TestCase):
    def test_humanoid_run_passes_every_gate(self):
        a = assertions(clip())
        self.assertTrue(a and all(x["passed"] for x in a.values()), a)

    def test_slide_is_judged_per_body_height(self):
        # The 1 m Tripo boar's 0.449 m/s passed the old 0.5 m/s; per body height (0.771 m) it fails
        a = assertions(clip(height=0.771, slide=0.449, gait={"l": (0.03, 0.1)}))
        slide = a["planted feet don't slide"]
        self.assertFalse(slide["passed"])
        self.assertEqual(slide["limit"], REL["motion_foot_slide_bhps"])
        self.assertAlmostEqual(slide["value"], 0.449 / 0.771, places=3)

    def test_root_travel_and_bind_deviation_per_body_height(self):
        big = assertions(clip(height=3.526, travel=0.25, dev=2.5, gait={"l": (0.04, 0.7)}))
        self.assertTrue(big["root stays in place (horizontal hips travel)"]["passed"])
        self.assertTrue(big["vertex deviation from bind pose (Hips frame)"]["passed"])
        small = assertions(clip(height=0.771, travel=0.1, dev=0.9, gait={"l": (0.03, 0.1)}))
        self.assertFalse(small["root stays in place (horizontal hips travel)"]["passed"])
        self.assertFalse(small["vertex deviation from bind pose (Hips frame)"]["passed"])

    def test_humanoid_outcomes_match_the_metre_limits(self):
        # At 1.8 m the relative limits are the old 0.15 m, 0.5 m/s and 1.8 m
        for travel, slide, dev, ok in [(0.149, 0.499, 1.79, True), (0.151, 0.501, 1.81, False)]:
            a = assertions(clip(travel=travel, slide=slide, dev=dev))
            for name in ("root stays in place (horizontal hips travel)", "planted feet don't slide",
                         "vertex deviation from bind pose (Hips frame)"):
                self.assertEqual(a[name]["passed"], ok, (name, travel, slide, dev))

    def test_metrics_without_a_body_height_need_a_rerun(self):
        mm = clip()
        del mm["body_height_m"]
        with self.assertRaises(judge.JudgeError):
            assertions(mm)


class GaitCheck(unittest.TestCase):
    def test_a_frozen_foot_fails_lift_and_swing(self):
        # Tripo's quadruped walk: the front feet never move
        gait = {"front_left": (0.0, 0.0), "front_right": (0.0, 0.0), "back_left": (0.033, 0.106), "back_right": (0.02, 0.127)}
        a = assertions(clip(height=0.771, slide=0.29, gait=gait))
        lift, swing = a["every foot lifts (gait)"], a["every foot swings (gait)"]
        self.assertFalse(lift["passed"])
        self.assertFalse(swing["passed"])
        self.assertEqual(lift["limit"], REL["motion_gait_lift_bh"])
        self.assertIn("front_left", lift["detail"])
        self.assertIn("front_right", swing["detail"])
        self.assertNotIn("back_left", lift["detail"].split("failing:")[-1])

    def test_a_shuffling_walk_passes_the_gait(self):
        # The Gobkit walk: small lifts, but every leg moves
        gait = {"front_left": (0.039, 0.696), "front_right": (0.054, 0.895), "back_left": (0.027, 0.324), "back_right": (0.044, 0.494)}
        a = assertions(clip(height=3.526, slide=1.881, gait=gait))
        self.assertTrue(a["every foot lifts (gait)"]["passed"])
        self.assertTrue(a["every foot swings (gait)"]["passed"])
        self.assertFalse(a["planted feet don't slide"]["passed"])

    def test_only_locomotion_clips_get_the_gait_check(self):
        a = assertions(clip(locomotion=False, gait={"left": (0.0, 0.0)}))
        self.assertNotIn("every foot lifts (gait)", a)
        self.assertNotIn("every foot swings (gait)", a)

    def test_the_art_bible_has_the_relative_tolerances(self):
        tol = judge.tolerances()
        for key in REL:
            self.assertIn(key, tol)
        for old in ("motion_root_travel_m", "motion_foot_slide_mps", "motion_bind_deviation_m"):
            self.assertNotIn(old, tol)
        self.assertFalse(set(REL) & judge.proposed_tolerances())


if __name__ == "__main__":
    unittest.main(verbosity=2)
