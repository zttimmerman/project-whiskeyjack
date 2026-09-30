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


class SyntheticLogs(unittest.TestCase):
    def test_telegraph_measures_windup_to_hitbox_open(self):
        events = melee_attack(100, "Levy", windup=30) + melee_attack(300, "Levy", windup=36)
        r = rm.compute({"id": "enemy_melee_telegraph"}, rm.sort_events(events))
        self.assertAlmostEqual(r["value"], 0.5)  # the shortest windup, 30 frames at 60 fps

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
