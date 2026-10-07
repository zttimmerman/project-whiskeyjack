#!/usr/bin/env python3
"""Tests for scripts/review/replay_metrics.py on fixture event logs (stdlib unittest).

    python3 tests/replay/test_replay_metrics.py
"""
import importlib.util
import json
import os
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FIXTURES = os.path.join(ROOT, "tests", "replay", "fixtures")
METRICS = os.path.join(ROOT, "scripts", "review", "replay_metrics.py")


def _load_metrics():
    spec = importlib.util.spec_from_file_location("replay_metrics", METRICS)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


rm = _load_metrics()


def ev(frame, event, **data):
    return dict({"frame": frame, "event": event}, **data)


def melee_attack(frame, actor, windup=0):
    """An enemy melee attack: optional windup, then attack_started and hitbox_open."""
    out = []
    if windup:
        out.append(ev(frame - windup, "attack_windup", actor=actor))
    out.append(ev(frame, "attack_started", actor=actor, kind="melee"))
    out.append(ev(frame, "hitbox_open", actor=actor, heavy=False, damage=8))
    return out


class FixtureLevy1v1(unittest.TestCase):
    def setUp(self):
        self.events = rm.load_events(os.path.join(FIXTURES, "levy_1v1.jsonl"))

    def test_load_sorts_by_frame(self):
        frames = [e["frame"] for e in self.events]
        self.assertEqual(frames, sorted(frames))
        self.assertEqual(len(self.events), 32)

    def test_ttk_player_frontfile_counts_light_hits_to_kill(self):
        r = rm.compute({"id": "ttk_player_frontfile", "enemy": "EnemyCorridorA"}, self.events)
        self.assertEqual(r["value"], 4)
        self.assertTrue(r["detail"]["killed"])

    def test_ttk_levy_player_projects_from_damage_when_the_player_lives(self):
        r = rm.compute({"id": "ttk_levy_player", "attacker": "EnemyCorridorA"}, self.events)
        self.assertEqual(r["value"], 34)  # ceil(100 / 3)
        self.assertTrue(r["detail"]["projected"])

    def test_enemy_melee_telegraph_is_zero_without_windups(self):
        r = rm.compute({"id": "enemy_melee_telegraph"}, self.events)
        self.assertAlmostEqual(r["value"], 0.0)

    def test_atk_hitbox_sync_against_the_press_without_contact_frames(self):
        r = rm.compute({"id": "atk_hitbox_sync"}, self.events)
        self.assertEqual(r["value"], 0)
        self.assertEqual(r["detail"]["measured_against"], "press")

    def test_atk_hitbox_sync_against_contact_frames(self):
        r = rm.compute({"id": "atk_hitbox_sync", "contact_frames": {"light": 12}}, self.events)
        self.assertEqual(r["value"], 12)  # the worst |open - contact| over the swings
        self.assertEqual(r["detail"]["measured_against"], "contact")

    def test_enc_first_fight_hp_cost(self):
        r = rm.compute({"id": "enc_first_fight_hp_cost"}, self.events)
        self.assertAlmostEqual(r["value"], 0.03)

    def test_one_fight_has_no_spacing(self):
        r = rm.compute({"id": "enc_spacing_s"}, self.events)
        self.assertIsNone(r["value"])


def cam(frame, in_view=True, visible=1.0, inside=False, wall=0.1, target=None, t_in_view=True, t_visible=1.0,
        distance=5.0, occlusion=0.0):
    """A camera sample, as scripts/review/camera_probe.gd logs it; target=None is unlocked."""
    e = ev(frame, "camera", player_in_view=in_view, player_visible=visible, camera_in_player=inside, wall_fill=wall,
           locked=target is not None)
    if target is not None:
        e.update(target=target, target_in_view=t_in_view, target_visible=t_visible, target_distance=distance,
                 melee_occlusion=occlusion)
    return e


class CameraMetrics(unittest.TestCase):
    def test_player_in_frame_is_the_fraction_of_good_samples(self):
        events = [cam(0), cam(1), cam(2, in_view=False), cam(3)]
        r = rm.compute({"id": "cam_player_in_frame"}, events)
        self.assertAlmostEqual(r["value"], 0.75)
        self.assertEqual(r["detail"]["samples"], 4)

    def test_player_hidden_by_a_wall_or_clipped_is_not_in_frame(self):
        # Fully in frame needs the head and torso mostly unhidden by world geometry, and the camera outside him
        events = [cam(0, visible=0.5), cam(1, inside=True), cam(2, visible=rm.CAM_VISIBLE_MIN), cam(3)]
        r = rm.compute({"id": "cam_player_in_frame"}, events)
        self.assertAlmostEqual(r["value"], 0.5)

    def test_wall_fill_is_the_worst_sample(self):
        events = [cam(0, wall=0.2), cam(1, wall=0.9), cam(2, wall=0.4)]
        r = rm.compute({"id": "cam_wall_fill"}, events)
        self.assertAlmostEqual(r["value"], 0.9)
        self.assertEqual(r["detail"]["worst_frame"], 1)

    def test_melee_occlusion_averages_locked_frames_within_3m(self):
        events = [cam(0, occlusion=1.0),  # not locked: ignored
                  cam(1, target="Levy", distance=2.0, occlusion=0.9),
                  cam(2, target="Levy", distance=3.0, occlusion=0.5),
                  cam(3, target="Levy", distance=3.5, occlusion=1.0)]  # beyond 3 m: ignored
        r = rm.compute({"id": "cam_melee_occlusion"}, events)
        self.assertAlmostEqual(r["value"], 0.7)
        self.assertEqual(r["detail"]["samples"], 2)
        self.assertAlmostEqual(r["detail"]["max"], 0.9)

    def test_melee_occlusion_unmeasured_without_a_close_lock(self):
        r = rm.compute({"id": "cam_melee_occlusion"}, [cam(0), cam(1, target="Levy", distance=6.0)])
        self.assertIsNone(r["value"])

    def test_lock_both_in_frame_counts_locked_frames_with_both_framed(self):
        events = [cam(0, in_view=False),  # not locked: ignored
                  cam(1, target="Levy"), cam(2, target="Levy", t_in_view=False),
                  cam(3, target="Levy", in_view=False), cam(4, target="Levy", t_visible=0.25)]
        r = rm.compute({"id": "cam_lock_both_in_frame"}, events)
        self.assertAlmostEqual(r["value"], 0.25)
        self.assertEqual(r["detail"]["samples"], 4)

    def test_camera_metrics_unmeasured_without_samples(self):
        for check in ("cam_player_in_frame", "cam_wall_fill", "cam_lock_both_in_frame"):
            self.assertIsNone(rm.compute({"id": check}, [ev(0, "hit", target="A")])["value"], check)


class SyntheticLogs(unittest.TestCase):
    def test_telegraph_measures_windup_to_hitbox_open(self):
        events = melee_attack(100, "Levy", windup=30) + melee_attack(300, "Levy", windup=36)
        r = rm.compute({"id": "enemy_melee_telegraph"}, rm.sort_events(events))
        self.assertAlmostEqual(r["value"], 0.5)  # the shortest windup, 30 frames at 60 fps

    def test_telegraph_counts_a_windup_logged_with_the_attack_start(self):
        # BaseEnemy logs attack_windup and attack_started on the frame the windup begins
        events = [ev(100, "attack_windup", actor="Levy"), ev(100, "attack_started", actor="Levy", kind="melee"),
                  ev(136, "hitbox_open", actor="Levy", heavy=False, damage=14)]
        r = rm.compute({"id": "enemy_melee_telegraph"}, rm.sort_events(events))
        self.assertAlmostEqual(r["value"], 0.6)
        self.assertEqual(r["detail"]["with_windup_event"], 1)

    def test_ranged_telegraph_measures_draw_to_release(self):
        events = []
        for start, draw in ((100, 54), (400, 60)):
            events += [ev(start, "attack_windup", actor="Archer"),
                       ev(start, "attack_started", actor="Archer", kind="ranged"),
                       ev(start + draw, "attack_release", actor="Archer", kind="ranged")]
        r = rm.compute({"id": "enemy_ranged_telegraph"}, rm.sort_events(events))
        self.assertAlmostEqual(r["value"], 0.9)  # the shortest draw, 54 frames
        self.assertEqual(r["detail"]["attacks"], 2)

    def test_ranged_telegraph_without_a_windup_is_zero(self):
        events = [ev(100, "attack_started", actor="Archer", kind="ranged"),
                  ev(100, "attack_release", actor="Archer", kind="ranged")]
        r = rm.compute({"id": "enemy_ranged_telegraph"}, rm.sort_events(events))
        self.assertAlmostEqual(r["value"], 0.0)

    def test_ranged_telegraph_ignores_a_cancelled_draw(self):
        # A draw staggered before release has no release; the next draw is measured on its own
        events = [ev(100, "attack_windup", actor="Archer"), ev(100, "attack_started", actor="Archer", kind="ranged"),
                  ev(120, "stagger", actor="Archer", interrupted_attack=True),
                  ev(300, "attack_windup", actor="Archer"), ev(300, "attack_started", actor="Archer", kind="ranged"),
                  ev(354, "attack_release", actor="Archer", kind="ranged")]
        r = rm.compute({"id": "enemy_ranged_telegraph"}, rm.sort_events(events))
        self.assertAlmostEqual(r["value"], 0.9)
        self.assertEqual(r["detail"]["attacks"], 1)

    def test_ranged_telegraph_unmeasured_without_shots(self):
        r = rm.compute({"id": "enemy_ranged_telegraph"}, [])
        self.assertIsNone(r["value"])

    def test_attackers_max_counts_distinct_melee_in_a_2s_window(self):
        events = (melee_attack(100, "A") + melee_attack(130, "B") + melee_attack(200, "C")
                  + melee_attack(600, "A"))
        events.append(ev(150, "attack_started", actor="Archer1", kind="ranged"))
        events.append(ev(170, "attack_started", actor="Archer2", kind="ranged"))
        r = rm.compute({"id": "enemy_attackers_max"}, rm.sort_events(events))
        self.assertEqual(r["value"], {"melee": 3, "ranged": 2})

    def test_spacing_between_fights(self):
        events = [ev(100, "hit", attacker="Player", target="A"), ev(160, "hit", attacker="Player", target="A"),
                  ev(160 + 20 * 60, "hit", attacker="Player", target="B")]
        r = rm.compute({"id": "enc_spacing_s"}, rm.sort_events(events))
        self.assertAlmostEqual(r["value"], 20.0)

    def test_group_size_and_through_walls_detection(self):
        events = [ev(10, "detected", actor="A", distance=9.0, line_of_sight=True),
                  ev(12, "detected", actor="B", distance=9.5, line_of_sight=False),
                  ev(40, "detected", actor="A", distance=9.0, line_of_sight=True)]
        events = rm.sort_events(events)
        self.assertEqual(rm.compute({"id": "enc_group_max_first_area"}, events)["value"], 2)
        r = rm.compute({"id": "detect_through_walls"}, events)
        self.assertEqual(r["value"], 1)
        self.assertEqual(r["detail"]["actors"], ["B"])

    def test_ttk_player_backfile_uses_the_named_archer(self):
        events = [ev(1, "damage_taken", target="Archer", attacker="Player", amount=9, hp=11, max_hp=20),
                  ev(2, "damage_taken", target="Archer", attacker="Player", amount=9, hp=2, max_hp=20),
                  ev(3, "damage_taken", target="Archer", attacker="Player", amount=9, hp=0, max_hp=20),
                  ev(3, "death", actor="Archer")]
        r = rm.compute({"id": "ttk_player_backfile", "enemy": "Archer"}, rm.sort_events(events))
        self.assertEqual(r["value"], 3)

    def test_reach_distance_is_the_end_position_to_the_point(self):
        events = [ev(0, "scenario_start", scenario="walk"),
                  ev(300, "scenario_end", player_position=[0.0, 1.9, -8.0], player_hp=100)]
        r = rm.compute({"id": "reach_distance_m", "point": [0, 1.9, -9]}, events)
        self.assertAlmostEqual(r["value"], 1.0)
        self.assertEqual(r["detail"]["end_position"], [0.0, 1.9, -8.0])

    def test_frame_stamps_count_probes_off_their_tick(self):
        check = {"id": "replay_frame_stamps"}
        good = [ev(-2, "probe", tick=-1), ev(-1, "probe", tick=0), ev(0, "probe", tick=1)]
        self.assertEqual(rm.compute(check, good)["value"], 0)
        # The warm-up frame stamped from origin 0, as before the fix: an absolute frame count
        stale = [ev(0, "probe", tick=-1), ev(1, "probe", tick=0), ev(0, "probe", tick=1)]
        self.assertEqual(rm.compute(check, stale)["value"], 2)
        self.assertIsNone(rm.compute(check, [])["value"])

    def test_reach_distance_needs_a_point(self):
        events = [ev(300, "scenario_end", player_position=[0.0, 0.0, 0.0])]
        with self.assertRaises(ValueError):
            rm.compute({"id": "reach_distance_m"}, events)


class SearchMetrics(unittest.TestCase):
    A = "ArcherCorridorB"

    def search(self, start, look_at, end_at, return_at, actor=A):
        return [ev(start, "lost_sight", actor=actor, distance=10.0),
                ev(look_at, "search_look", actor=actor, distance=0.4, reached=True),
                ev(end_at, "search_end", actor=actor, outcome="gave_up"),
                ev(return_at, "search_return", actor=actor, distance=0.3, reached=True)]

    def test_search_look_s_runs_from_the_last_seen_spot_to_giving_up(self):
        r = rm.compute({"id": "search_look_s", "enemy": self.A}, self.search(10, 100, 310, 500))
        self.assertAlmostEqual(r["value"], 3.5)
        self.assertEqual(r["detail"]["frames"]["search_return"], 500)

    def test_search_legs_report_how_far_off_the_enemy_stopped(self):
        events = self.search(10, 100, 310, 500)
        self.assertEqual(rm.compute({"id": "search_last_seen_m", "enemy": self.A}, events)["value"], 0.4)
        self.assertEqual(rm.compute({"id": "search_post_m", "enemy": self.A}, events)["value"], 0.3)

    def test_a_regained_search_is_skipped_for_the_next_full_one(self):
        events = [ev(5, "lost_sight", actor=self.A, distance=9.0),
                  ev(40, "search_look", actor=self.A, distance=0.2, reached=True),
                  ev(60, "search_end", actor=self.A, outcome="regained")]
        events += self.search(100, 200, 410, 600)
        r = rm.compute({"id": "search_look_s", "enemy": self.A}, events)
        self.assertEqual(r["detail"]["frames"]["lost_sight"], 100)

    def test_other_enemies_and_unfinished_searches_measure_nothing(self):
        events = self.search(10, 100, 310, 500, actor="EnemyCentral1") + self.search(10, 100, 310, 500)[:3]
        r = rm.compute({"id": "search_post_m", "enemy": self.A}, events)
        self.assertIsNone(r["value"])

    def test_search_checks_need_an_enemy(self):
        with self.assertRaises(ValueError):
            rm.compute({"id": "search_look_s"}, [])


class Evaluate(unittest.TestCase):
    def setUp(self):
        self.events = rm.load_events(os.path.join(FIXTURES, "levy_1v1.jsonl"))

    def status(self, check):
        return rm.evaluate_check(check, self.events)["status"]

    def test_in_target_passes(self):
        self.assertEqual(self.status({"id": "ttk_player_frontfile", "enemy": "EnemyCorridorA", "target": [3, 4]}), "pass")

    def test_out_of_target_fails(self):
        self.assertEqual(self.status({"id": "ttk_levy_player", "attacker": "EnemyCorridorA", "target": [10, 14]}), "fail")

    def test_pending_target_miss_is_reported_not_failed(self):
        self.assertEqual(self.status({"id": "enemy_melee_telegraph", "target": [0.5, None], "pending": "no windups yet"}),
                         "pending")

    def test_baseline_drift_fails_even_when_pending(self):
        self.assertEqual(self.status({"id": "ttk_levy_player", "attacker": "EnemyCorridorA", "target": [10, 14],
                                      "pending": "retune", "baseline": 30}), "drift")

    def test_baseline_within_tolerance_holds(self):
        self.assertEqual(self.status({"id": "enc_first_fight_hp_cost", "target": [0.10, 0.15], "pending": "telegraphs",
                                      "baseline": 0.04, "tolerance": 0.015}), "pending")

    def test_unmeasured_fails_unless_pending(self):
        self.assertEqual(self.status({"id": "enc_spacing_s", "target": [20, 60]}), "fail")
        self.assertEqual(self.status({"id": "enc_spacing_s", "target": [20, 60], "pending": "one fight"}), "unmeasured")

    def test_dict_targets(self):
        events = rm.sort_events(melee_attack(100, "A") + melee_attack(110, "B") + melee_attack(120, "C"))
        check = {"id": "enemy_attackers_max", "target": {"melee": [None, 2], "ranged": [None, 1]}}
        self.assertEqual(rm.evaluate_check(check, events)["status"], "fail")
        check["baseline"] = {"melee": 3, "ranged": 0}
        check["pending"] = "attack tokens"
        self.assertEqual(rm.evaluate_check(check, events)["status"], "pending")

    def test_unknown_check_id_fails(self):
        self.assertEqual(self.status({"id": "no_such_target"}), "fail")

    def test_main_exit_codes_and_report(self):
        with tempfile.TemporaryDirectory() as tmp:
            scenario = os.path.join(tmp, "s.json")
            out = os.path.join(tmp, "m.json")
            log = os.path.join(FIXTURES, "levy_1v1.jsonl")
            passing = {"name": "fixture", "checks": [
                {"id": "ttk_player_frontfile", "enemy": "EnemyCorridorA", "target": [3, 4], "baseline": 4},
                {"id": "enemy_melee_telegraph", "target": [0.5, None], "pending": "no windups", "baseline": 0.0}]}
            with open(scenario, "w") as f:
                json.dump(passing, f)
            self.assertEqual(rm.main(["--scenario", scenario, "--log", log, "--out", out, "--quiet"]), 0)
            with open(out) as f:
                report = json.load(f)
            self.assertTrue(report["passed"])
            self.assertEqual([r["status"] for r in report["results"]], ["pass", "pending"])

            failing = dict(passing, checks=passing["checks"] + [
                {"id": "ttk_levy_player", "attacker": "EnemyCorridorA", "target": [10, 14]}])
            with open(scenario, "w") as f:
                json.dump(failing, f)
            self.assertEqual(rm.main(["--scenario", scenario, "--log", log, "--out", out, "--quiet"]), 1)

    def test_missing_scenario_end_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            scenario = os.path.join(tmp, "s.json")
            log = os.path.join(tmp, "cut.jsonl")
            with open(os.path.join(FIXTURES, "levy_1v1.jsonl")) as src, open(log, "w") as dst:
                dst.writelines(src.readlines()[:-1])  # the run died before its end
            with open(scenario, "w") as f:
                json.dump({"name": "fixture", "checks": []}, f)
            self.assertEqual(rm.main(["--scenario", scenario, "--log", log, "--quiet"]), 1)


class CompareLogs(unittest.TestCase):
    """Determinism: two runs of one scenario must log the same events on the same frames."""

    def write(self, tmp, name, events):
        path = os.path.join(tmp, name)
        with open(path, "w") as f:
            f.writelines(json.dumps(e) + "\n" for e in events)
        return path

    def test_identical_logs(self):
        with tempfile.TemporaryDirectory() as tmp:
            a = self.write(tmp, "a.jsonl", [ev(1, "hit", target="A"), ev(2, "death", actor="A")])
            b = self.write(tmp, "b.jsonl", [ev(1, "hit", target="A"), ev(2, "death", actor="A")])
            self.assertEqual(rm.compare_logs(a, b)["result"], "identical")

    def test_reordered_within_a_frame_is_tolerated(self):
        with tempfile.TemporaryDirectory() as tmp:
            a = self.write(tmp, "a.jsonl", [ev(1, "hit", target="A"), ev(1, "hit", target="Player")])
            b = self.write(tmp, "b.jsonl", [ev(1, "hit", target="Player"), ev(1, "hit", target="A")])
            self.assertEqual(rm.compare_logs(a, b)["result"], "same_per_frame")

    def test_different_logs_report_the_first_frame(self):
        with tempfile.TemporaryDirectory() as tmp:
            a = self.write(tmp, "a.jsonl", [ev(1, "hit", target="A"), ev(5, "death", actor="A")])
            b = self.write(tmp, "b.jsonl", [ev(1, "hit", target="A"), ev(6, "death", actor="A")])
            r = rm.compare_logs(a, b)
            self.assertEqual(r["result"], "different")
            self.assertEqual(r["first_frame"], 5)
            self.assertEqual(rm.main(["--compare", a, b, "--quiet"]), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
