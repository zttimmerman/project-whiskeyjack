#!/usr/bin/env python3
"""Check the pinned godot-ai version against the latest release. Never updates anything.

    python3 scripts/tools/godot_ai_update.py check [--force]   # human-readable report
    python3 scripts/tools/godot_ai_update.py check --hook      # SessionStart hook: one line, only when there's news

The pin lives in two places that must agree: addons/godot_ai/plugin.cfg (the addon) and .mcp.json
(`godot-ai==X`, the server). Updating is a deliberate trial on its own branch (CLAUDE.md -> Godot MCP ->
Updates): verify the signed release, swap the addon and the pin, diff the tool surface against the guard's
table, re-run the regression set and the saved playtest scenarios, and open a PR.

Network checks are cached for CHECK_EVERY_DAYS in .godot/ (gitignored). In --hook mode every failure is
silent, so a session never breaks because GitHub is unreachable.
Env overrides for tests: GODOT_AI_UPDATE_LATEST=<json list of {tag, name, published}>, GODOT_AI_UPDATE_CACHE=<path>.
"""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPO = "hi-godot/godot-ai"
CHECK_EVERY_DAYS = 7
PLUGIN_CFG = ROOT / "addons" / "godot_ai" / "plugin.cfg"
MCP_JSON = ROOT / ".mcp.json"


def version_key(v):
    return tuple(int(x) for x in re.findall(r"\d+", v)[:3])


def pinned():
    """(addon version, server version) as pinned in the repo; None where not found."""
    addon = server = None
    if PLUGIN_CFG.exists():
        m = re.search(r'^version="([^"]+)"', PLUGIN_CFG.read_text(), re.M)
        addon = m and m.group(1)
    if MCP_JSON.exists():
        m = re.search(r"godot-ai==([0-9][0-9.]*)", MCP_JSON.read_text())
        server = m and m.group(1)
    return addon, server


def fetch_releases():
    """Stable releases, newest first, as [{tag, name, published}]."""
    if "GODOT_AI_UPDATE_LATEST" in os.environ:
        return json.loads(os.environ["GODOT_AI_UPDATE_LATEST"])
    fields = '.[] | select(.draft|not) | select(.prerelease|not) | {tag: .tag_name, name, published: .published_at}'
    try:
        out = subprocess.run(["gh", "api", f"repos/{REPO}/releases?per_page=30", "--jq", fields],
                             capture_output=True, text=True, timeout=8, check=True).stdout
        return [json.loads(line) for line in out.splitlines() if line.strip()]
    except (OSError, subprocess.SubprocessError, ValueError):
        pass  # no gh or not logged in: fall back to the unauthenticated API
    req = urllib.request.Request(f"https://api.github.com/repos/{REPO}/releases?per_page=30",
                                 headers={"Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=8) as resp:
        data = json.load(resp)
    return [{"tag": r["tag_name"], "name": r.get("name"), "published": r.get("published_at")}
            for r in data if not r.get("draft") and not r.get("prerelease")]


def cache_path():
    return Path(os.environ.get("GODOT_AI_UPDATE_CACHE", ROOT / ".godot" / "godot-ai-update-check.json"))


def releases(force):
    """Releases from the cache when it's younger than CHECK_EVERY_DAYS, else from GitHub (then cached)."""
    now = datetime.datetime.now(datetime.timezone.utc)
    cp = cache_path()
    if not force and cp.exists():
        try:
            cached = json.loads(cp.read_text())
            age = now - datetime.datetime.fromisoformat(cached["checked_at"])
            if age < datetime.timedelta(days=CHECK_EVERY_DAYS):
                return cached["releases"], cached["checked_at"]
        except (ValueError, KeyError):
            pass
    rel = fetch_releases()
    try:
        cp.parent.mkdir(parents=True, exist_ok=True)
        cp.write_text(json.dumps({"checked_at": now.isoformat(timespec="seconds"), "releases": rel}, indent=1))
    except OSError:
        pass
    return rel, now.isoformat(timespec="seconds")


def report(force):
    """(news: list of lines worth surfacing, details: lines for the human report)."""
    addon, server = pinned()
    news, details = [], [f"pinned: addon {addon or '?'}, server {server or '?'}"]
    if addon != server:
        news.append(f"godot-ai pins disagree: addon {addon} (plugin.cfg) vs server {server} (.mcp.json)")
    rel, checked = releases(force)
    details.append(f"releases checked {checked}")
    pin = addon or server
    newer = [r for r in rel if pin and version_key(r["tag"]) > version_key(pin)]
    if newer:
        newest = max(newer, key=lambda r: version_key(r["tag"]))
        news.append(f"godot-ai {newest['tag'].lstrip('v')} is available (pinned {pin}; {len(newer)} newer "
                    f"release{'s' if len(newer) > 1 else ''}). Don't update in place: it's a trial on its own "
                    "branch (CLAUDE.md -> Godot MCP -> Updates). Mention it to the user.")
        details += [f"  newer: {r['tag']} ({(r.get('published') or '')[:10]}) {r.get('name') or ''}"
                    for r in sorted(newer, key=lambda r: version_key(r["tag"]), reverse=True)]
        details.append(f"  changelog: https://github.com/{REPO}/blob/{newest['tag']}/CHANGELOG.md")
    else:
        details.append("up to date")
    return news, details


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["check"])
    ap.add_argument("--force", action="store_true", help="ignore the cache and ask GitHub now")
    ap.add_argument("--hook", action="store_true", help="SessionStart hook output: silent unless there's news")
    args = ap.parse_args()
    if args.hook:
        try:
            news, _ = report(args.force)
        except Exception:  # never break a session over a version check
            return 0
        if news:
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                                     "additionalContext": " ".join(news)}}))
        return 0
    news, details = report(args.force)
    print("\n".join(details + (["", *news] if news else [])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
