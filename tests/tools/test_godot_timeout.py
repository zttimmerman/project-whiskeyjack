#!/usr/bin/env python3
"""Tests for the Godot/Blender call timeouts, both halves (stdlib unittest):
scripts/tools/godot_timeout.sh (bash) and scripts/tools/godot_timeout.py (Python).

    python3 tests/tools/test_godot_timeout.py

The expiry path runs a stand-in that sleeps past a 1 s limit, the way a hung Godot idles at its modal alert.
"""
import importlib.util
import os
import subprocess
import sys
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HELPER_SH = os.path.join(ROOT, "scripts", "tools", "godot_timeout.sh")
_spec = importlib.util.spec_from_file_location("godot_timeout", os.path.join(ROOT, "scripts", "tools", "godot_timeout.py"))
gt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gt)


def bash(script, env=None):
    full = {k: v for k, v in os.environ.items() if k != "TEST_TIMEOUT"}
    full.update(env or {})
    return subprocess.run(["bash", "-c", f'source "{HELPER_SH}"; {script}'], capture_output=True, text=True,
                          env=full, stdin=subprocess.DEVNULL, timeout=60)


class BashHelper(unittest.TestCase):
    def test_expiry_fails_with_124_and_names_the_call_and_limit(self):
        t0 = time.monotonic()
        p = bash('with_timeout TEST_TIMEOUT 1 "sleepy import" sleep 30; echo "status $?"')
        self.assertLess(time.monotonic() - t0, 20)
        self.assertIn("status 124", p.stdout)
        self.assertIn("sleepy import: timed out after 1s", p.stderr)
        self.assertIn("TEST_TIMEOUT=<seconds>", p.stderr)

    def test_env_var_overrides_the_default(self):
        p = bash('with_timeout TEST_TIMEOUT 600 "override" sleep 30; echo "status $?"', {"TEST_TIMEOUT": "1"})
        self.assertIn("status 124", p.stdout)
        self.assertIn("override: timed out after 1s", p.stderr)

    def test_command_status_and_output_pass_through(self):
        p = bash('with_timeout TEST_TIMEOUT 30 "quick" bash -c "echo hello; exit 7"; echo "status $?"')
        self.assertIn("hello", p.stdout)
        self.assertIn("status 7", p.stdout)
        self.assertEqual(p.stderr, "")

    def test_bad_limit_is_refused(self):
        p = bash('with_timeout TEST_TIMEOUT 30 "bad" true; echo "status $?"', {"TEST_TIMEOUT": "soon"})
        self.assertIn("status 2", p.stdout)
        self.assertIn("not a positive whole number", p.stderr)

    def test_runs_as_a_command_too(self):
        p = subprocess.run([HELPER_SH, "TEST_TIMEOUT", "1", "as command", "sleep", "30"], capture_output=True,
                           text=True, stdin=subprocess.DEVNULL, timeout=60, env={k: v for k, v in os.environ.items() if k != "TEST_TIMEOUT"})
        self.assertEqual(p.returncode, 124)
        self.assertIn("as command: timed out after 1s", p.stderr)


class PythonHelper(unittest.TestCase):
    def setUp(self):
        os.environ.pop("TEST_TIMEOUT", None)

    def test_expiry_raises_and_names_the_call_and_limit(self):
        t0 = time.monotonic()
        with self.assertRaises(gt.ToolTimeout) as cm:
            gt.run([sys.executable, "-c", "import time; time.sleep(30)"], "sleepy validate", "TEST_TIMEOUT", 1)
        self.assertLess(time.monotonic() - t0, 20)
        self.assertIn("sleepy validate: timed out after 1s", str(cm.exception))
        self.assertIn("TEST_TIMEOUT=<seconds>", str(cm.exception))

    def test_env_var_overrides_the_default(self):
        os.environ["TEST_TIMEOUT"] = "1"
        try:
            with self.assertRaises(gt.ToolTimeout):
                gt.run([sys.executable, "-c", "import time; time.sleep(30)"], "override", "TEST_TIMEOUT", 600)
        finally:
            del os.environ["TEST_TIMEOUT"]

    def test_result_passes_through(self):
        p = gt.run([sys.executable, "-c", "print('hello'); raise SystemExit(7)"], "quick", "TEST_TIMEOUT", 30,
                   capture_output=True, text=True)
        self.assertEqual(p.returncode, 7)
        self.assertEqual(p.stdout.strip(), "hello")

    def test_bad_limit_is_refused(self):
        os.environ["TEST_TIMEOUT"] = "soon"
        try:
            with self.assertRaises(gt.ToolTimeout):
                gt.run(["true"], "bad", "TEST_TIMEOUT", 30)
        finally:
            del os.environ["TEST_TIMEOUT"]


if __name__ == "__main__":
    unittest.main(verbosity=2)
