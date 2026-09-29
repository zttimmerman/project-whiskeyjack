"""Tests for godot_ai_guard.py. Run: python3 .claude/hooks/test_godot_ai_guard.py"""
import json
import os
import subprocess
import sys
import unittest

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "godot_ai_guard.py")
AGENT = "project-whiskeyjack-agent@0123456789abcdef"
USER = "project-whiskeyjack@0123456789abcdef"
LEVEL = "res://scenes/world/Level1.tscn"


def run_raw(stdin):
    proc = subprocess.run([sys.executable, HOOK], input=stdin, capture_output=True,
                          text=True, timeout=10)
    assert proc.returncode == 0, proc.stderr
    return proc.stdout


def run(tool, tool_input):
    out = run_raw(json.dumps({"hook_event_name": "PreToolUse",
                              "tool_name": "mcp__godot-ai__" + tool,
                              "tool_input": tool_input}))
    return json.loads(out)["hookSpecificOutput"]


class GuardTest(unittest.TestCase):
    def assertDecision(self, tool, tool_input, expected, reason_part=None):
        out = run(tool, tool_input)
        self.assertEqual(out["hookEventName"], "PreToolUse")
        self.assertEqual(out["permissionDecision"], expected, out["permissionDecisionReason"])
        if reason_part:
            self.assertIn(reason_part, out["permissionDecisionReason"])
        return out

    # Session gate
    def test_read_with_agent_session_allowed(self):
        self.assertDecision("scene_get_hierarchy", {"session_id": AGENT}, "allow")

    def test_read_with_user_session_denied(self):
        self.assertDecision("scene_get_hierarchy", {"session_id": USER}, "deny",
                            'session_manage(op="list")')

    def test_missing_session_denied(self):
        self.assertDecision("editor_state", {}, "deny", "session_id")

    def test_session_list_without_session_allowed(self):
        self.assertDecision("session_manage", {"op": "list"}, "allow")

    # Op tables
    def test_game_eval_denied(self):
        self.assertDecision("editor_manage", {"op": "game_eval", "params": {"code": "1"},
                                              "session_id": AGENT}, "deny")

    def test_editor_state_op_allowed(self):
        self.assertDecision("editor_manage", {"op": "state", "session_id": AGENT}, "allow")

    def test_input_key_asks(self):
        self.assertDecision("game_manage", {"op": "input_key", "session_id": AGENT,
                                            "params": {"key": "J", "pressed": True}}, "ask")

    def test_unknown_op_denied(self):
        self.assertDecision("node_manage", {"op": "explode", "session_id": AGENT}, "deny",
                            "unknown")

    def test_unknown_tool_denied(self):
        self.assertDecision("frobnicate", {"session_id": AGENT}, "deny", "unknown")

    def test_excluded_domain_denied(self):
        self.assertDecision("filesystem_manage", {"op": "read_text", "session_id": AGENT},
                            "deny", "excluded")

    # project_run autosave
    def test_project_run_without_autosave_denied(self):
        self.assertDecision("project_run", {"mode": "custom", "scene": LEVEL,
                                            "session_id": AGENT}, "deny", "autosave")

    def test_project_run_autosave_true_denied(self):
        self.assertDecision("project_run", {"autosave": True, "session_id": AGENT}, "deny")

    def test_project_run_autosave_false_asks(self):
        self.assertDecision("project_run", {"mode": "custom", "scene": LEVEL,
                                            "autosave": False, "session_id": AGENT}, "ask")

    # scene_file requirement and path guard
    def test_set_property_on_level_asks(self):
        self.assertDecision("node_set_property", {"path": "/Level1/Player", "property": "visible",
                                                  "value": True, "scene_file": LEVEL,
                                                  "session_id": AGENT}, "ask")

    def test_set_property_on_held_prop_denied(self):
        self.assertDecision("node_set_property", {"path": "/HeldLevyBlade", "property": "visible",
                                                  "value": True,
                                                  "scene_file": "res://scenes/props/HeldLevyBlade.tscn",
                                                  "session_id": AGENT}, "deny", "protected")

    def test_set_property_without_scene_file_denied(self):
        self.assertDecision("node_set_property", {"path": "/Level1/Player", "property": "visible",
                                                  "value": True, "session_id": AGENT},
                            "deny", "scene_file")

    def test_script_create_in_rigs_denied(self):
        self.assertDecision("script_create", {"path": "res://data/rigs/x.gd", "content": "",
                                              "session_id": AGENT}, "deny", "protected")

    def test_script_create_case_variant_denied(self):
        self.assertDecision("script_create", {"path": "res://Data/Rigs/x.gd",
                                              "session_id": AGENT}, "deny", "protected")

    def test_worktree_absolute_path_mapped(self):
        self.assertDecision("script_create", {"path": "/Users/zach/Documents/repos/"
                                              "project-whiskeyjack-agent/project.godot",
                                              "session_id": AGENT}, "deny", "res://project.godot")
        self.assertDecision("script_create", {"path": "/Users/zach/Documents/repos/"
                                              "project-whiskeyjack-agent/scripts/tools/x.gd",
                                              "session_id": AGENT}, "ask")

    def test_absolute_path_outside_worktree_denied(self):
        self.assertDecision("script_create", {"path": "/Users/zach/Documents/repos/"
                                              "project-whiskeyjack/scripts/x.gd",
                                              "session_id": AGENT}, "deny", "outside")

    def test_traversal_denied(self):
        self.assertDecision("scene_manage", {"op": "save_as", "session_id": AGENT,
                                             "params": {"path": "res://scenes/../addons/x.tscn"}},
                            "deny", "traversal")

    def test_node_path_is_not_a_file_path(self):
        # node_manage.delete's `path` is a node path like "/Level1/Enemy"; it must not
        # trip the absolute-path check.
        self.assertDecision("node_manage", {"op": "delete", "session_id": AGENT,
                                            "params": {"path": "/Level1/Enemy",
                                                       "scene_file": LEVEL}}, "ask")

    # Generated files may be used (read, instanced, assigned) but never written
    def test_resource_assign_of_generated_mesh_asks(self):
        self.assertDecision("resource_manage", {"op": "assign", "session_id": AGENT, "params": {
            "path": "/Level1/Mesh", "property": "mesh",
            "resource_path": "res://assets/meshes/x.glb"}}, "ask")

    def test_instancing_generated_glb_into_level_asks(self):
        self.assertDecision("node_create", {"session_id": AGENT, "type": "Node3D", "name": "Levy",
                                            "parent_path": "/Level1", "scene_file": LEVEL,
                                            "scene_path": "res://assets/meshes/barrow_levy.glb"}, "ask")

    def test_reference_outside_worktree_still_denied(self):
        self.assertDecision("resource_manage", {"op": "assign", "session_id": AGENT, "params": {
            "path": "/Level1/Mesh", "property": "mesh",
            "resource_path": "/tmp/evil.glb"}}, "deny", "outside")

    def test_saving_into_generated_path_denied(self):
        self.assertDecision("scene_manage", {"op": "save_as", "session_id": AGENT, "params": {
            "path": "res://scenes/props/HeldLevyBlade.tscn"}}, "deny", "protected")

    # Param normalization
    def test_stringified_params(self):
        params = json.dumps({"path": "res://data/animations/player.tres",
                             "scene_file": LEVEL})
        self.assertDecision("scene_manage", {"op": "save_as", "params": params,
                                             "session_id": AGENT}, "deny", "protected")
        self.assertDecision("scene_manage", {"op": "save_as", "session_id": AGENT,
                                             "params": json.dumps({"path": LEVEL})}, "ask")

    def test_flat_params_folded(self):
        self.assertDecision("scene_manage", {"op": "create", "session_id": AGENT,
                                             "path": "res://addons/x.tscn"}, "deny", "protected")

    def test_scene_file_stripped_where_plugin_lacks_it(self):
        out = self.assertDecision("signal_manage", {
            "op": "connect", "session_id": AGENT,
            "params": {"path": "/Level1/Door", "signal": "opened", "target": "/Level1",
                       "method": "_on_door_opened", "scene_file": LEVEL}}, "ask")
        self.assertEqual(out["updatedInput"], {
            "session_id": AGENT, "op": "connect",
            "params": {"path": "/Level1/Door", "signal": "opened", "target": "/Level1",
                       "method": "_on_door_opened"}})

    # Robustness
    def test_malformed_stdin_denied(self):
        out = json.loads(run_raw("{not json"))["hookSpecificOutput"]
        self.assertEqual(out["permissionDecision"], "deny")
        self.assertIn("fail closed", out["permissionDecisionReason"])

    def test_non_godot_tool_no_output(self):
        self.assertEqual(run_raw(json.dumps({"tool_name": "Bash",
                                             "tool_input": {"command": "ls"}})), "")


if __name__ == "__main__":
    unittest.main()
