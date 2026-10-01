#!/usr/bin/env python3
"""Design-bible numbers from a replay's event log (docs/design-bible.md §9; docs/plans/phase-a/a2b-replay-harness.md).

    python3 scripts/review/replay_metrics.py --scenario tests/scenarios/<name>.json --log <run.jsonl> [--out <metrics.json>]

Reads the JSONL event log written by scripts/debug/EventLog.gd during a replay (scripts/review/replay.tscn)
and evaluates the scenario's "checks". Each check names a target ID and its parameters:

    {"id": "ttk_player_frontfile", "enemy": "EnemyCorridorA", "target": [3, 4], "baseline": 4}

- target:    the design bible's range, [min, max] with null for an open end (a dict of ranges for
             enemy_attackers_max). Missing: the value is only reported.
- pending:   why the target can't be met yet (the feature isn't built). A miss is then reported as
             "pending", not a failure; drop the field in the PR that implements the feature.
- baseline:  today's value (the §9 "Current" column, measured). A different value is "drift" and fails,
             so a change to the numbers is always deliberate: update the baseline with it.
- tolerance: allowed |value - baseline| (default 0; floats compare with 1e-9).

Statuses: pass, fail, pending, drift, unmeasured (no value and pending), info (no target).
Exit code: 0 when nothing failed or drifted, 1 otherwise (and when the log didn't reach scenario_end).
Frames are physics frames at 60 per second (the replay runs with --fixed-fps 60).

    python3 scripts/review/replay_metrics.py --compare <run1.jsonl> <run2.jsonl>

Determinism: two runs of a scenario must log the same events on the same frames. "identical" is
byte for byte; "same_per_frame" tolerates a different order within a frame (Jolt can report
simultaneous overlaps in either order); "different" fails, naming the first frame that differs.
"""
import argparse
import json
import math
import sys

FPS = 60
WINDOW_FRAMES = 2 * FPS  # enemy_attackers_max: attack tokens are counted over 2 s (§3)
DEFAULT_FIGHT_GAP_S = 5.0  # enc_spacing_s: combat events further apart than this start a new fight
PLAYER = "Player"
COMBAT_EVENTS = ("attack_started", "hit", "damage_taken")


def sort_events(events):
    # Stable: events within a frame keep their logged order
    return sorted(events, key=lambda e: e["frame"])


def load_events(path):
    events = []
    with open(path) as f:
        for n, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError as err:
                raise ValueError("%s:%d: not JSON (%s)" % (path, n, err))
    return sort_events(events)


def of(events, name, **fields):
    return [e for e in events if e["event"] == name and all(e.get(k) == v for k, v in fields.items())]


def fights(events, gap_s=DEFAULT_FIGHT_GAP_S):
    """Clusters of combat events, as [first_frame, last_frame] pairs."""
    frames = [e["frame"] for e in events if e["event"] in COMBAT_EVENTS]
    out = []
    for f in frames:
        if out and f - out[-1][1] <= gap_s * FPS:
            out[-1][1] = f
        else:
            out.append([f, f])
    return out


# ── Metrics: each returns {"value": ..., "detail": {...}} ─────────────────────────────────────

def _hits_to_kill(check, events):
    enemy = check.get("enemy")
    if not enemy:
        raise ValueError("%s needs \"enemy\"" % check["id"])
    deaths = of(events, "death", actor=enemy)
    death_frame = deaths[0]["frame"] if deaths else None
    hits = [e for e in of(events, "damage_taken", target=enemy, attacker=PLAYER)
            if death_frame is None or e["frame"] <= death_frame]
    heavy_frames = {e["frame"] for e in of(events, "attack_started", actor=PLAYER, kind="heavy")}
    detail = {"enemy": enemy, "killed": death_frame is not None, "damage": [e.get("amount") for e in hits],
              "heavy_attacks": len(heavy_frames)}
    if death_frame is None:
        detail["note"] = "the enemy wasn't killed"
        return {"value": None, "detail": detail}
    return {"value": len(hits), "detail": detail}


def _levy_hits_to_kill_player(check, events):
    attacker = check.get("attacker")
    hits = [e for e in of(events, "damage_taken", target=PLAYER)
            if attacker is None or e.get("attacker") == attacker]
    died = bool(of(events, "death", actor=PLAYER))
    detail = {"attacker": attacker, "hits": len(hits), "damage": [e.get("amount") for e in hits], "projected": not died}
    if died:
        return {"value": len(hits), "detail": detail}
    if not hits:
        detail["note"] = "the player took no hits"
        return {"value": None, "detail": detail}
    # The player lived: project from the damage per hit and max HP
    per_hit = sum(e["amount"] for e in hits) / len(hits)
    max_hp = hits[0]["max_hp"]
    detail.update(per_hit=per_hit, max_hp=max_hp)
    if per_hit <= 0:
        detail["note"] = "hits did no damage"
        return {"value": None, "detail": detail}
    return {"value": math.ceil(max_hp / per_hit), "detail": detail}


def _melee_telegraph(check, events):
    windups = []
    for start in of(events, "attack_started", kind="melee"):
        actor = start["actor"]
        opens = [e for e in of(events, "hitbox_open", actor=actor) if e["frame"] >= start["frame"]]
        if not opens:
            continue
        open_frame = opens[0]["frame"]
        # This attack's windup: the latest one by the actor since its previous hitbox opened
        earlier_opens = [e["frame"] for e in of(events, "hitbox_open", actor=actor) if e["frame"] < start["frame"]]
        since = earlier_opens[-1] if earlier_opens else -1
        tells = [e["frame"] for e in of(events, "attack_windup", actor=actor) if since < e["frame"] <= start["frame"]]
        tell_frame = tells[-1] if tells else start["frame"]
        windups.append({"actor": actor, "frame": start["frame"], "windup_s": (open_frame - tell_frame) / FPS,
                        "has_windup": bool(tells)})
    if not windups:
        return {"value": None, "detail": {"note": "no enemy melee attacks", "attacks": []}}
    return {"value": min(w["windup_s"] for w in windups), "detail": {"attacks": len(windups),
            "with_windup_event": sum(w["has_windup"] for w in windups)}}


def _ranged_telegraph(check, events):
    """Draw start (attack_windup) to release (attack_release), per ranged attack that released."""
    draws = []
    for start in of(events, "attack_started", kind="ranged"):
        actor = start["actor"]
        later_starts = [e["frame"] for e in of(events, "attack_started", actor=actor, kind="ranged")
                        if e["frame"] > start["frame"]]
        until = later_starts[0] if later_starts else math.inf
        releases = [e["frame"] for e in of(events, "attack_release", actor=actor)
                    if start["frame"] <= e["frame"] < until]
        if not releases:
            continue  # cancelled (staggered) before release
        earlier = [e["frame"] for e in of(events, "attack_release", actor=actor) if e["frame"] < start["frame"]]
        since = earlier[-1] if earlier else -1
        tells = [e["frame"] for e in of(events, "attack_windup", actor=actor) if since < e["frame"] <= start["frame"]]
        tell_frame = tells[-1] if tells else start["frame"]
        draws.append({"actor": actor, "frame": start["frame"], "draw_s": (releases[0] - tell_frame) / FPS})
    if not draws:
        return {"value": None, "detail": {"note": "no released ranged attacks", "attacks": 0}}
    return {"value": min(d["draw_s"] for d in draws), "detail": {"attacks": len(draws)}}


def _hitbox_sync(check, events):
    contact_frames = check.get("contact_frames") or {}
    swings = []
    for start in of(events, "attack_started", actor=PLAYER):
        opens = [e for e in of(events, "hitbox_open", actor=PLAYER) if e["frame"] >= start["frame"]]
        if not opens:
            continue
        swing = {"kind": start.get("kind"), "press": start["frame"], "open": opens[0]["frame"]}
        if "contact_frame" in start:
            swing["contact"] = start["contact_frame"]
        elif start.get("kind") in contact_frames:
            swing["contact"] = start["frame"] + int(contact_frames[start["kind"]])
        swings.append(swing)
    if not swings:
        return {"value": None, "detail": {"note": "no player attacks", "swings": 0}}
    against_contact = [s for s in swings if "contact" in s]
    if against_contact:
        return {"value": max(abs(s["open"] - s["contact"]) for s in against_contact),
                "detail": {"measured_against": "contact", "swings": len(against_contact),
                           "unmarked": len(swings) - len(against_contact)}}
    # No clip contact frames are marked yet: report the open frame against the press, not the target
    return {"value": max(s["open"] - s["press"] for s in swings), "measurable": False,
            "detail": {"measured_against": "press", "swings": len(swings),
                       "note": "no contact frames marked; value is hitbox open minus press, in frames"}}


def _hp_cost(check, events):
    spans = fights(events, check.get("gap_s", DEFAULT_FIGHT_GAP_S))
    taken = of(events, "damage_taken", target=PLAYER)
    if not spans:
        return {"value": None, "detail": {"note": "no fight"}}
    first = spans[0]
    in_fight = [e for e in taken if first[0] <= e["frame"] <= first[1]]
    max_hp = in_fight[0]["max_hp"] if in_fight else None
    if not in_fight:
        return {"value": 0.0, "detail": {"hits": 0}}
    lost = sum(e["amount"] for e in in_fight)
    return {"value": round(lost / max_hp, 4), "detail": {"hits": len(in_fight), "hp_lost": lost, "max_hp": max_hp,
                                                         "fight_frames": first}}


def _attackers_max(check, events):
    def max_distinct(kind):
        starts = of(events, "attack_started", kind=kind)
        best = 0
        for s in starts:
            actors = {e["actor"] for e in starts if s["frame"] - WINDOW_FRAMES < e["frame"] <= s["frame"]}
            best = max(best, len(actors))
        return best
    return {"value": {"melee": max_distinct("melee"), "ranged": max_distinct("ranged")},
            "detail": {"window_s": WINDOW_FRAMES / FPS}}


def _spacing(check, events):
    spans = fights(events, check.get("gap_s", DEFAULT_FIGHT_GAP_S))
    gaps = [(b[0] - a[1]) / FPS for a, b in zip(spans, spans[1:])]
    detail = {"fights": len(spans), "gaps_s": gaps}
    if not gaps:
        detail["note"] = "fewer than two fights in this run"
        return {"value": None, "detail": detail}
    return {"value": min(gaps), "detail": detail}


def _group_size(check, events):
    actors = sorted({e["actor"] for e in of(events, "detected")})
    return {"value": len(actors), "detail": {"engaged": actors}}


def _through_walls(check, events):
    blind = sorted({e["actor"] for e in of(events, "detected") if e.get("line_of_sight") is False})
    return {"value": len(blind), "detail": {"actors": blind}}


# Camera checks (design bible §2, §9) read the per-frame "camera" samples (scripts/review/camera_probe.gd)
CAM_VISIBLE_MIN = 0.75  # a body counts as in frame when this much of it is unhidden by world geometry
CAM_MELEE_RANGE = 3.0  # cam_melee_occlusion: locked frames with the target this close (metres)


def _camera_samples(events, locked=None):
    samples = of(events, "camera")
    if locked is not None:
        samples = [e for e in samples if bool(e.get("locked")) == locked]
    return samples


def _player_framed(e):
    return (bool(e.get("player_in_view")) and not e.get("camera_in_player")
            and e.get("player_visible", 0.0) >= CAM_VISIBLE_MIN)


def _target_framed(e):
    return bool(e.get("target_in_view")) and e.get("target_visible", 0.0) >= CAM_VISIBLE_MIN


def _frames_where(samples, bad):
    return [e["frame"] for e in samples if bad(e)]


def _cam_player_in_frame(check, events):
    samples = _camera_samples(events)
    if not samples:
        return {"value": None, "detail": {"note": "no camera samples", "samples": 0}}
    out = _frames_where(samples, lambda e: not _player_framed(e))
    return {"value": round(1.0 - len(out) / len(samples), 4),
            "detail": {"samples": len(samples), "out_of_frame": len(out), "first_out": out[:10],
                       "camera_in_player": sum(1 for e in samples if e.get("camera_in_player")),
                       "camera_in_world": sum(1 for e in samples if e.get("camera_in_world"))}}


def _cam_wall_fill(check, events):
    samples = _camera_samples(events)
    if not samples:
        return {"value": None, "detail": {"note": "no camera samples", "samples": 0}}
    worst = max(samples, key=lambda e: e.get("wall_fill", 0.0))
    over = [e["frame"] for e in samples if e.get("wall_fill", 0.0) > 0.6]
    return {"value": worst.get("wall_fill", 0.0),
            "detail": {"samples": len(samples), "worst_frame": worst["frame"], "frames_over_0.6": len(over)}}


def _cam_melee_occlusion(check, events):
    rng = check.get("range_m", CAM_MELEE_RANGE)
    samples = [e for e in _camera_samples(events, locked=True) if e.get("target_distance", math.inf) <= rng]
    if not samples:
        return {"value": None, "detail": {"note": "no locked frames with the target within %g m" % rng,
                                          "samples": 0}}
    values = sorted(e.get("melee_occlusion", 0.0) for e in samples)
    return {"value": round(sum(values) / len(values), 4),
            "detail": {"samples": len(values), "aggregate": "mean", "max": values[-1],
                       "p90": values[min(len(values) - 1, int(0.9 * len(values)))]}}


def _cam_lock_both_in_frame(check, events):
    samples = _camera_samples(events, locked=True)
    if not samples:
        return {"value": None, "detail": {"note": "never locked on", "samples": 0}}
    out = _frames_where(samples, lambda e: not (_player_framed(e) and _target_framed(e)))
    return {"value": round(1.0 - len(out) / len(samples), 4),
            "detail": {"samples": len(samples), "out_of_frame": len(out), "first_out": out[:10]}}


METRICS = {
    "ttk_player_frontfile": _hits_to_kill,
    "ttk_player_backfile": _hits_to_kill,
    "ttk_levy_player": _levy_hits_to_kill_player,
    "enemy_melee_telegraph": _melee_telegraph,
    "enemy_ranged_telegraph": _ranged_telegraph,
    "atk_hitbox_sync": _hitbox_sync,
    "enc_first_fight_hp_cost": _hp_cost,
    "enemy_attackers_max": _attackers_max,
    "enc_spacing_s": _spacing,
    "enc_group_max_first_area": _group_size,
    # Not a §9 target ID: §3's rule that detection needs line of sight, as detections without it
    "detect_through_walls": _through_walls,
    "cam_player_in_frame": _cam_player_in_frame,
    "cam_wall_fill": _cam_wall_fill,
    "cam_melee_occlusion": _cam_melee_occlusion,
    "cam_lock_both_in_frame": _cam_lock_both_in_frame,
}


def compute(check, events):
    fn = METRICS.get(check.get("id"))
    if fn is None:
        raise KeyError("unknown check id %r" % check.get("id"))
    return fn(check, events)


# ── Evaluation ─────────────────────────────────────────────────────────────────────────────────

def _in_range(value, rng):
    lo, hi = rng
    return (lo is None or value >= lo) and (hi is None or value <= hi)


def _meets(value, target):
    if isinstance(target, dict):
        return all(_in_range(value.get(k), rng) for k, rng in target.items())
    return _in_range(value, target)


def _same(value, baseline, tolerance):
    if isinstance(baseline, dict):
        return isinstance(value, dict) and all(_same(value.get(k), b, tolerance) for k, b in baseline.items())
    if value is None or baseline is None:
        return value is baseline
    return abs(value - baseline) <= max(tolerance, 1e-9)


def evaluate_check(check, events):
    result = {"id": check.get("id"), "target": check.get("target"), "pending": check.get("pending")}
    if "baseline" in check:
        result["baseline"] = check["baseline"]
    try:
        measured = compute(check, events)
    except (KeyError, ValueError) as err:
        result.update(status="fail", value=None, detail={"error": str(err)})
        return result
    value = measured["value"]
    result.update(value=value, detail=measured["detail"])
    measurable = measured.get("measurable", True) and value is not None
    if "baseline" in check and not _same(value, check["baseline"], check.get("tolerance", 0)):
        result["status"] = "drift"
    elif not measurable:
        result["status"] = "unmeasured" if check.get("pending") else "fail"
    elif check.get("target") is None:
        result["status"] = "info"
    elif _meets(value, check["target"]):
        result["status"] = "pass"
    else:
        result["status"] = "pending" if check.get("pending") else "fail"
    return result


def evaluate(scenario, events):
    return [evaluate_check(c, events) for c in scenario.get("checks", [])]


def _canonical(events):
    by_frame = {}
    for e in events:
        by_frame.setdefault(e["frame"], []).append(json.dumps(e, sort_keys=True))
    return {f: sorted(lines) for f, lines in by_frame.items()}


def compare_logs(path_a, path_b):
    with open(path_a) as f:
        raw_a = f.read()
    with open(path_b) as f:
        raw_b = f.read()
    if raw_a == raw_b:
        return {"result": "identical", "events": raw_a.count("\n")}
    a, b = _canonical(load_events(path_a)), _canonical(load_events(path_b))
    if a == b:
        return {"result": "same_per_frame", "events": sum(len(v) for v in a.values())}
    first = min(f for f in set(a) | set(b) if a.get(f) != b.get(f))
    return {"result": "different", "first_frame": first, "a": a.get(first, []), "b": b.get(first, [])}


def _fmt(v):
    if isinstance(v, float):
        return ("%.3f" % v).rstrip("0").rstrip(".")
    return json.dumps(v)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--scenario")
    ap.add_argument("--log")
    ap.add_argument("--compare", nargs=2, metavar=("LOG1", "LOG2"), help="check two runs' logs match")
    ap.add_argument("--out", help="write the report as JSON here")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)
    if args.compare:
        r = compare_logs(*args.compare)
        if not args.quiet:
            print("compare %s %s: %s" % (args.compare[0], args.compare[1], r["result"]))
            if r["result"] == "different":
                print("  first difference at frame %d\n  run 1: %s\n  run 2: %s" % (r["first_frame"], r["a"], r["b"]))
        return 1 if r["result"] == "different" else 0
    if not args.scenario or not args.log:
        ap.error("--scenario and --log are required (or --compare LOG1 LOG2)")

    with open(args.scenario) as f:
        scenario = json.load(f)
    events = load_events(args.log)
    finished = bool(of(events, "scenario_end"))
    results = evaluate(scenario, events)
    passed = finished and not any(r["status"] in ("fail", "drift") for r in results)
    report = {"scenario": scenario.get("name"), "log": args.log, "finished": finished, "passed": passed,
              "frames": events[-1]["frame"] if events else 0, "results": results}
    if args.out:
        with open(args.out, "w") as f:
            json.dump(report, f, indent=2)
            f.write("\n")
    if not args.quiet:
        print("%s (%s)" % (scenario.get("name"), args.log))
        if not finished:
            print("  ERROR: the log has no scenario_end; the run didn't finish")
        for r in results:
            line = "  %-10s %-26s value=%s" % (r["status"].upper(), r["id"], _fmt(r["value"]))
            if r.get("target") is not None:
                line += " target=%s" % _fmt(r["target"])
            if "baseline" in r:
                line += " baseline=%s" % _fmt(r["baseline"])
            if r.get("pending") and r["status"] in ("pending", "unmeasured"):
                line += "  (pending: %s)" % r["pending"]
            print(line)
        print("  %s" % ("PASS" if passed else "FAIL"))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
