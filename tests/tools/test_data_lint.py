#!/usr/bin/env python3
"""Tests for the QuestManager member check in ci/data_lint.py (stdlib unittest).

    python3 tests/tools/test_data_lint.py

Dialogue Manager evaluates `QuestManager.<name>(...)` in a .dialogue condition or mutation only at
runtime, so a typo in the method name would otherwise ship (backlog dialogue-questmanager-lint).
The lint requires every `QuestManager.<name>` to be a func, var, const or signal of the autoload.
"""
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "ci"))
import data_lint  # noqa: E402

QUESTS = {"clear_eastern_road": {"talk_to_elder", "clear_road"}}


def lint(text):
    with tempfile.TemporaryDirectory(dir=ROOT) as tmp:
        path = Path(tmp) / "probe.dialogue"
        path.write_text(text)
        errors, limits = [], []
        data_lint.lint_dialogue_script(path, QUESTS, {"met_elder"}, errors, limits)
        return errors


class QuestManagerMembers(unittest.TestCase):
    def test_reads_the_autoload_script(self):
        members = data_lint.quest_manager_members()
        for name in ("start_quest", "advance_quest", "complete_quest", "get_flag", "set_flag", "quest_started"):
            self.assertIn(name, members)
        self.assertNotIn("start_quets", members)

    def test_known_method_passes(self):
        self.assertEqual(lint('~ start\ndo QuestManager.set_flag("met_elder")\n=> END\n'), [])

    def test_typo_in_mutation_fails(self):
        errors = lint('~ start\ndo QuestManager.start_quets("clear_eastern_road")\n=> END\n')
        self.assertEqual(len(errors), 1)
        self.assertIn("probe.dialogue:2", errors[0])
        self.assertIn("start_quets", errors[0])

    def test_typo_in_condition_fails(self):
        errors = lint('~ start\nif QuestManager.is_quest_actve("clear_eastern_road"):\n\tElder: Hello.\n=> END\n')
        self.assertTrue(any("is_quest_actve" in e for e in errors))

    def test_typo_inside_inline_markup_fails(self):
        errors = lint('~ start\nElder: Hi. [if QuestManager.get_flg("met_elder")]Again.[/if]\n=> END\n')
        self.assertTrue(any("get_flg" in e for e in errors))

    def test_comment_is_ignored(self):
        self.assertEqual(lint('~ start\n# QuestManager.not_a_method()\n=> END\n'), [])


if __name__ == "__main__":
    unittest.main()
