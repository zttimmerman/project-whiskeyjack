#!/usr/bin/env python3
"""Tests for scripts/tools/backlog.py (stdlib unittest).

    python3 tests/tools/test_backlog.py
"""
import contextlib
import importlib.util
import io
import json
import os
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_spec = importlib.util.spec_from_file_location("backlog", os.path.join(ROOT, "scripts", "tools", "backlog.py"))
bl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bl)

BIBLE = """# Design Bible

## 9. Targets

| ID | Target | How measured | Current |
|---|---|---|---|
| `atk_hitbox_sync` | ±2 frames | hitbox open vs contact | on the press |
| `enc_spacing_s` | 20–60 s | walking time | 5–10 s |

Prose mentioning `not_a_target_id` outside the table.
"""

BODIES = {
    "work": "\n## Goal\nDo it.\n\n## Scope\n- this\n\n## Acceptance\n- that\n\n## Serves\n- the bible\n",
    "done": "\n## Goal\nDid it.\n\n## Outcome\nShipped.\n",
    "needs-user": "\n## Question\nWhich?\n\n## Options\n1. A\n2. B\n\n## Recommendation\nA.\n",
}


def item_text(item_id, status="ready", kind="feature", targets="[]", after="[]", phase="gameplay-2", pr="null",
              branch="null", title=None, body=None, extra=""):
    if title is None:
        title = '"Item ' + item_id + ': a title"'
    if body is None:
        body = BODIES["done" if status in ("done", "dropped") else "needs-user" if status == "needs-user" else "work"]
    return (
        "---\n"
        f"id: {item_id}\n"
        f"title: {title}\n"
        f"status: {status}\n"
        f"kind: {kind}\n"
        f"targets: {targets}\n"
        f"after: {after}\n"
        f"phase: {phase}\n"
        f"branch: {branch}\n"
        f"pr: {pr}\n"
        f"updated: 2026-10-02\n"
        f"{extra}"
        "---\n" + body
    )


class Fixture:
    def __init__(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = os.path.join(self.tmp.name, "backlog")
        os.makedirs(self.dir)
        self.bible = os.path.join(self.tmp.name, "design-bible.md")
        with open(self.bible, "w", encoding="utf-8") as f:
            f.write(BIBLE)
        with open(os.path.join(self.dir, "README.md"), "w", encoding="utf-8") as f:
            f.write("# Backlog\n\nNot an item.\n")

    def add(self, item_id, filename=None, **kw):
        with open(os.path.join(self.dir, (filename or item_id) + ".md"), "w", encoding="utf-8") as f:
            f.write(item_text(item_id, **kw))

    def run(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = bl.main(["--dir", self.dir, "--bible", self.bible, *argv])
        return code, out.getvalue()

    def lint(self):
        items, errors = bl.load_items(self.dir)
        return errors + bl.lint(items, bl.bible_targets(self.bible))

    def close(self):
        self.tmp.cleanup()


class FrontMatterTest(unittest.TestCase):
    def test_parses_scalars_lists_and_body(self):
        meta, body = bl.parse_front_matter(item_text("a-b", targets="[atk_hitbox_sync, enc_spacing_s]", pr="14",
                                                     title='"Colon: kept"'))
        self.assertEqual(meta["id"], "a-b")
        self.assertEqual(meta["title"], "Colon: kept")
        self.assertEqual(meta["targets"], ["atk_hitbox_sync", "enc_spacing_s"])
        self.assertEqual(meta["after"], [])
        self.assertEqual(meta["pr"], 14)
        self.assertIsNone(meta["branch"])
        self.assertEqual(meta["updated"], "2026-10-02")
        self.assertIn("## Goal", body)

    def test_unquoted_title_with_colon(self):
        meta, _ = bl.parse_front_matter(item_text("a", title="Trial B1: the camera"))
        self.assertEqual(meta["title"], "Trial B1: the camera")

    def test_missing_front_matter_raises(self):
        with self.assertRaises(ValueError):
            bl.parse_front_matter("# no front matter\n")

    def test_bad_line_raises(self):
        with self.assertRaises(ValueError):
            bl.parse_front_matter("---\nid: a\nthis line has no key\n---\n")


class BibleTargetsTest(unittest.TestCase):
    def test_reads_only_the_table_ids(self):
        fx = Fixture()
        try:
            self.assertEqual(bl.bible_targets(fx.bible), {"atk_hitbox_sync", "enc_spacing_s"})
        finally:
            fx.close()

    def test_real_bible_has_the_known_ids(self):
        ids = bl.bible_targets(os.path.join(ROOT, "docs", "design-bible.md"))
        for known in ("atk_hitbox_sync", "cam_melee_occlusion", "enc_first_fight_hp_cost", "perf_fps_min"):
            self.assertIn(known, ids)


class LintTest(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()

    def tearDown(self):
        self.fx.close()

    def assertLintMentions(self, *fragments):
        errors = self.fx.lint()
        joined = "\n".join(errors)
        for fragment in fragments:
            self.assertIn(fragment, joined, msg=joined)

    def test_clean_backlog_passes(self):
        self.fx.add("one", status="done", pr="12", targets="[atk_hitbox_sync]")
        self.fx.add("two", after="[one]")
        self.fx.add("three", status="needs-user", kind="decision")
        self.assertEqual(self.fx.lint(), [])

    def test_unknown_status_kind_and_phase(self):
        self.fx.add("one", status="blocked", kind="epic", phase="Z")
        self.assertLintMentions("unknown status 'blocked'", "unknown kind 'epic'", "unknown phase 'Z'")

    def test_missing_and_unknown_keys(self):
        with open(os.path.join(self.fx.dir, "one.md"), "w", encoding="utf-8") as f:
            f.write(item_text("one", extra="owner: me\n").replace("kind: feature\n", ""))
        self.assertLintMentions("missing key 'kind'", "unknown key 'owner'")

    def test_id_must_be_kebab_case_and_match_the_file(self):
        self.fx.add("Bad_Id")
        self.fx.add("good", filename="other")
        self.assertLintMentions("not kebab-case", "does not match the file name")

    def test_after_must_exist(self):
        self.fx.add("one", after="[ghost]")
        self.assertLintMentions("'ghost'")

    def test_after_cycle(self):
        self.fx.add("one", after="[two]")
        self.fx.add("two", after="[three]")
        self.fx.add("three", after="[one]")
        self.assertLintMentions("cycle")

    def test_self_dependency_is_a_cycle(self):
        self.fx.add("one", after="[one]")
        self.assertLintMentions("cycle")

    def test_unknown_target(self):
        self.fx.add("one", targets="[not_a_target_id]")
        self.assertLintMentions("unknown design-bible target 'not_a_target_id'")

    def test_done_and_in_review_need_a_pr(self):
        self.fx.add("one", status="done")
        self.fx.add("two", status="in-review", branch="feature/two")
        self.assertLintMentions("one", "two", "needs a pr")

    def test_decision_and_docs_kinds_may_finish_without_a_pr(self):
        self.fx.add("one", status="done", kind="decision")
        self.fx.add("two", status="done", kind="docs")
        self.assertEqual(self.fx.lint(), [])

    def test_pr_must_be_a_number(self):
        self.fx.add("one", status="done", pr="soon")
        self.assertLintMentions("pr must be")

    def test_updated_must_be_a_date(self):
        with open(os.path.join(self.fx.dir, "one.md"), "w", encoding="utf-8") as f:
            f.write(item_text("one").replace("updated: 2026-10-02", "updated: yesterday"))
        self.assertLintMentions("updated")

    def test_body_sections_follow_the_status(self):
        self.fx.add("one", body="\n## Goal\nOnly a goal.\n")
        self.fx.add("two", status="needs-user", body="\n## Question\nWhich?\n")
        self.assertLintMentions("one: body lacks '## Scope'", "two: body lacks '## Options'")

    def test_after_a_dropped_item_is_flagged(self):
        self.fx.add("one", status="dropped", pr="3")
        self.fx.add("two", after="[one]")
        self.assertLintMentions("dropped")

    def test_unparseable_file_is_reported(self):
        with open(os.path.join(self.fx.dir, "broken.md"), "w", encoding="utf-8") as f:
            f.write("no front matter here\n")
        self.assertLintMentions("broken.md")

    def test_lint_exit_code_and_json(self):
        self.fx.add("one", status="blocked")
        code, out = self.fx.run("lint", "--json")
        self.assertEqual(code, 1)
        self.assertTrue(any("blocked" in e for e in json.loads(out)["errors"]))
        self.fx.add("one")
        code, out = self.fx.run("lint", "--json")
        self.assertEqual((code, json.loads(out)["errors"]), (0, []))


class NextTest(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()

    def tearDown(self):
        self.fx.close()

    def test_ready_items_with_satisfied_after(self):
        self.fx.add("dep-done", status="done", pr="1")
        self.fx.add("dep-review", status="in-review", pr="2", branch="chore/x")
        self.fx.add("dep-open")
        self.fx.add("dep-proposed", status="proposed")
        self.fx.add("b-free", phase="C")
        self.fx.add("a-unblocked", after="[dep-done, dep-review]", phase="C")
        self.fx.add("blocked", after="[dep-proposed]")
        self.fx.add("early", phase="A")
        self.fx.add("not-ready", status="proposed")
        code, out = self.fx.run("next", "--json")
        self.assertEqual(code, 0)
        ids = [i["id"] for i in json.loads(out)]
        # Sorted by phase order (A, gameplay-2, C), then id.
        self.assertEqual(ids, ["early", "dep-open", "a-unblocked", "b-free"])

    def test_next_text_lists_ids(self):
        self.fx.add("solo")
        code, out = self.fx.run("next")
        self.assertEqual(code, 0)
        self.assertIn("solo", out)


class StatusAndShowTest(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()
        self.fx.add("one", status="done", pr="7", title='"Shipped one"')
        self.fx.add("two")
        self.fx.add("three", status="needs-user", kind="decision")

    def tearDown(self):
        self.fx.close()

    def test_status_counts_json(self):
        code, out = self.fx.run("status", "--json")
        data = json.loads(out)
        self.assertEqual(code, 0)
        self.assertEqual(data["counts"]["done"], 1)
        self.assertEqual(data["counts"]["ready"], 1)
        self.assertEqual(data["counts"]["needs-user"], 1)
        self.assertEqual(data["counts"]["proposed"], 0)
        self.assertEqual([i["id"] for i in data["items"]["ready"]], ["two"])

    def test_status_text_has_a_table_per_status(self):
        code, out = self.fx.run("status")
        self.assertEqual(code, 0)
        self.assertIn("### done (1)", out)
        self.assertIn("| one |", out)
        self.assertIn("#7", out)

    def test_show(self):
        code, out = self.fx.run("show", "one", "--json")
        self.assertEqual(code, 0)
        data = json.loads(out)
        self.assertEqual((data["id"], data["pr"]), ("one", 7))
        self.assertIn("## Outcome", data["body"])
        code, out = self.fx.run("show", "one")
        self.assertIn("Shipped one", out)

    def test_show_unknown_id_fails(self):
        code, _ = self.fx.run("show", "ghost")
        self.assertEqual(code, 1)


class RepoBacklogTest(unittest.TestCase):
    def test_committed_backlog_lints_clean(self):
        directory = os.path.join(ROOT, "docs", "backlog")
        items, errors = bl.load_items(directory)
        errors += bl.lint(items, bl.bible_targets(os.path.join(ROOT, "docs", "design-bible.md")))
        self.assertEqual(errors, [])
        self.assertGreater(len(items), 0)


if __name__ == "__main__":
    unittest.main()
