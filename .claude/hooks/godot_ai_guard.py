#!/usr/bin/env python3
"""PreToolUse guard for the godot-ai MCP server (v4.2.3).

This is the enforcement layer for CLAUDE.md's determinism rules when an agent
drives a live Godot editor: generated outputs (retargeted animation
libraries, rig/socket maps, cleaned meshes, Held* prop wrappers) are only
ever produced by the asset pipeline, never edited by hand through MCP; the
plugin and project.godot are off limits; and the agent may only touch its
own editor (the project-whiskeyjack-agent worktree), never the user's.

The classification tables below mirror sections 6 and 7 of the godot-ai
integration report (godot-ai-report.md, "Tool list and permission
classification" and "Hook design"). Keep them in sync with that report.

Settings rules only match tool names, so this hook is what splits the mixed
`*_manage` rollups by `op`. Every decision fails closed: an unknown tool or
op, a bad session, an unparseable payload or any exception is a deny.
"""
import json
import os
import posixpath
import re
import sys

PREFIX = "mcp__godot-ai__"
WORKTREE = "/Users/zach/Documents/repos/project-whiskeyjack-agent"
SESSION_RE = re.compile(r"^project-whiskeyjack-agent@[0-9a-f]{16}$")
ALLOW, ASK, DENY = "allow", "ask", "deny"

NAMED = {
    **dict.fromkeys(["editor_state", "scene_get_hierarchy", "node_get_properties",
                     "node_find", "logs_read", "editor_screenshot"], ALLOW),
    **dict.fromkeys(["project_run", "test_run", "scene_open", "node_create",
                     "node_set_property", "script_attach", "script_create",
                     "script_patch"], ASK),
    **dict.fromkeys(["session_activate", "scene_save", "batch_execute",
                     "editor_reload_plugin", "animation_create"], DENY),
}


def _ops(allow=(), ask=(), deny=()):
    return {**dict.fromkeys(allow, ALLOW), **dict.fromkeys(ask, ASK), **dict.fromkeys(deny, DENY)}


NODE_WRITES = ("delete", "duplicate", "rename", "move", "reparent",
               "add_to_group", "remove_from_group")
ROLLUPS = {
    "editor_manage": _ops(["state", "selection_get", "monitors_get"],
                          ["selection_set", "logs_clear"], ["game_eval", "quit"]),
    "scene_manage": _ops(["get_roots"], ["create", "save_as"]),
    "node_manage": _ops(["get_children", "get_groups"], NODE_WRITES),
    "project_manage": _ops(["settings_get"], ["stop"], ["settings_set", "set_main_scene"]),
    "script_manage": _ops(["read", "find_symbols"], ["detach"]),
    "resource_manage": _ops(["search", "load", "inspect", "get_info"],
                            ["assign", "curve_set_points", "physics_shape_autofit",
                             "physics_shape_generate"],
                            ["create", "environment_create", "gradient_texture_create",
                             "noise_texture_create"]),
    "signal_manage": _ops(["list"], ["connect", "disconnect"]),
    "game_manage": _ops(["get_scene_tree", "get_node_info", "get_ui_elements",
                         "debug_status", "input_state"],
                        ["suspend", "resume", "next_frame", "input_key", "input_mouse",
                         "input_gamepad", "input_action", "input_sequence"]),
    "session_manage": _ops(["list"]),
    "test_manage": _ops(["results_get"]),
    "api_manage": _ops(["get_class"]),
}
# Domains excluded via --exclude-domains; denied here too as defense in depth.
EXCLUDED = {"filesystem_manage", "autoload_manage", "input_map_manage", "client_manage",
            "material_manage", "particle_manage", "animation_manage", "theme_manage",
            "ui_manage", "camera_manage", "audio_manage", "tilemap_manage",
            "tileset_manage", "gridmap_manage", "csg_manage", "navigation_manage",
            "custom_manage"}

# Writes that must name the scene they edit. (tool, op); op is None for named tools.
NEEDS_SCENE_FILE = {("node_create", None), ("node_set_property", None),
                    ("script_attach", None), ("script_manage", "detach"),
                    ("signal_manage", "connect"), ("signal_manage", "disconnect"),
                    *(("node_manage", op) for op in NODE_WRITES)}
# These plugin signatures have no scene_file parameter (extra="forbid" would
# reject it), so the hook checks it and then strips it before the call.
STRIP_SCENE_FILE = {("script_attach", None), ("script_manage", "detach"),
                    ("signal_manage", "connect"), ("signal_manage", "disconnect")}

# Argument keys that always hold a res:// file path, whatever the tool.
FILE_KEYS = ("scene_file", "scene_path", "script_path", "resource_path")
# Tools/ops whose `path` is a file; everywhere else `path` is a node path.
PATH_IS_FILE = {("scene_open", None), ("script_create", None), ("script_patch", None),
                ("scene_manage", "create"), ("scene_manage", "save_as"),
                ("script_manage", "read"), ("script_manage", "find_symbols"),
                ("resource_manage", "load"), ("project_manage", "set_main_scene")}

# Where a file argument is WRITTEN by the call. Only these get the protected-path deny:
# generated outputs are changed by their generators, but reading, instancing (a GLB in a
# level), attaching or assigning them is ordinary use. Every other file argument is a
# reference and only gets the worktree/scheme/traversal checks in to_res().
PATH_IS_WRITE_TARGET = {("script_create", None), ("script_patch", None),
                        ("scene_manage", "create"), ("scene_manage", "save_as")}

PROTECTED_DIRS = ("res://data/animations", "res://data/rigs", "res://assets/meshes",
                  "res://addons", "res://.godot")
HELD_PROP_RE = re.compile(r"^res://scenes/props/held[^/]*\.tscn$")


class Deny(Exception):
    pass


def to_res(value):
    """Normalize a path argument to res:// form, or raise Deny."""
    if not isinstance(value, str):
        raise Deny(f"path argument {value!r} is not a string")
    p = value.strip().replace("\\", "/")
    if p.startswith("res://"):
        rest = p[len("res://"):]
    elif p.startswith("/"):
        if not (p == WORKTREE or p.startswith(WORKTREE + "/")):
            raise Deny(f"absolute path {value!r} is outside the agent worktree {WORKTREE}")
        rest = p[len(WORKTREE):]
    elif "://" in p:
        raise Deny(f"path {value!r} uses an unsupported scheme; pass a res:// path")
    else:
        rest = p
    if ".." in rest.split("/"):
        raise Deny(f"path {value!r} contains '..' traversal")
    rest = posixpath.normpath("/" + rest).lstrip("/")
    return "res://" + ("" if rest == "." else rest)


def check_protected(res_path, original):
    low = res_path.lower()  # macOS filesystems are case-insensitive
    if (low == "res://project.godot" or HELD_PROP_RE.match(low)
            or any(low == d or low.startswith(d + "/") for d in PROTECTED_DIRS)):
        raise Deny(f"{original!r} ({res_path}) is a generated or protected path; "
                   "only the asset pipeline (or a human) may write it")


def normalize(tool, tool_input):
    """Return (op, args) with manage params decoded and flat keys folded in."""
    if not isinstance(tool_input, dict):
        raise Deny("tool_input is not an object")
    if not tool.endswith("_manage"):
        return None, {k: v for k, v in tool_input.items() if k != "session_id"}
    op = tool_input.get("op")
    params = tool_input.get("params")
    if isinstance(params, str):
        params = json.loads(params)  # mirrors ParseStringifiedParams
    if params is None:
        params = {}
    if not isinstance(params, dict):
        raise Deny("params must be an object")
    params = dict(params)
    for key, val in tool_input.items():  # mirrors FoldFlatManageParams
        if key in ("op", "params", "session_id"):
            continue
        if key in params and params[key] != val:
            raise Deny(f"param {key!r} given both top-level and in params with different values")
        params[key] = val
    return op, params


def decide(tool, tool_input):
    op, args = normalize(tool, tool_input)
    if tool != "session_manage":
        sid = tool_input.get("session_id")
        if not isinstance(sid, str) or not SESSION_RE.match(sid):
            raise Deny(f"session_id {sid!r} is not the agent editor's session. Call "
                       "session_manage(op=\"list\") and pass the "
                       "project-whiskeyjack-agent@<hex> session_id on every call")
    if tool in EXCLUDED:
        raise Deny(f"{tool} is an excluded domain")
    if tool in NAMED:
        decision = NAMED[tool]
    elif tool in ROLLUPS:
        if op not in ROLLUPS[tool]:
            raise Deny(f"unknown or unclassified op {op!r} for {tool}")
        decision = ROLLUPS[tool][op]
    else:
        raise Deny(f"unknown godot-ai tool {tool!r}")
    if decision == DENY:
        raise Deny(f"{tool}{'.' + op if op else ''} is denied by the godot-ai guard table")

    if tool == "project_run" and args.get("autosave") is not False:
        raise Deny("project_run must pass autosave=false (the default saves in-memory "
                   "MCP edits to disk before playing)")
    key = (tool, op)
    if key in NEEDS_SCENE_FILE and not args.get("scene_file"):
        raise Deny(f"{tool}{'.' + op if op else ''} must pass scene_file (the res:// "
                   "scene being edited) so the path guard can check it")
    for name in FILE_KEYS + (("path",) if key in PATH_IS_FILE else ()):
        if args.get(name):
            res = to_res(args[name])  # every file argument: worktree, scheme, traversal
            written = ((name == "scene_file" and key in NEEDS_SCENE_FILE)
                       or (name == "path" and key in PATH_IS_WRITE_TARGET))
            if written:
                check_protected(res, args[name])

    updated = None
    if key in STRIP_SCENE_FILE:
        args = {k: v for k, v in args.items() if k != "scene_file"}
        base = {"session_id": tool_input["session_id"]}
        updated = {**base, **args} if op is None else {**base, "op": op, "params": args}
    return decision, f"godot-ai guard: {tool}{'.' + op if op else ''} -> {decision}", updated


def emit(decision, reason, updated=None):
    out = {"hookEventName": "PreToolUse", "permissionDecision": decision,
           "permissionDecisionReason": reason}
    if updated is not None:
        out["updatedInput"] = updated
    print(json.dumps({"hookSpecificOutput": out}))


def main():
    try:
        payload = json.loads(sys.stdin.read())
        tool_name = payload.get("tool_name", "")
        if not isinstance(tool_name, str) or not tool_name.startswith(PREFIX):
            return
        emit(*decide(tool_name[len(PREFIX):], payload.get("tool_input") or {}))
    except Deny as exc:
        emit(DENY, f"godot-ai guard: {exc}")
    except Exception as exc:  # fail closed
        emit(DENY, f"godot-ai guard error (fail closed): {type(exc).__name__}: {exc}")


if __name__ == "__main__":
    main()
    sys.exit(0)
