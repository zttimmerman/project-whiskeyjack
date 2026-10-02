"""A time limit on every Godot (and Blender) call from Python, the Python half of the one helper
(scripts/tools/godot_timeout.sh is the bash half, and lists the limits and their variables).

On macOS a fatal Godot error opens a modal alert that --headless can't dismiss, so the process idles at
0% CPU forever instead of exiting (the idea is from htdt/godogen, engines/godot.md, "Quirks worth
knowing"; MIT). A limit turns that hang into a failure that names the call.

    import godot_timeout
    proc = godot_timeout.run(cmd, "validate", "GODOT_TIMEOUT_RUN", 600, capture_output=True, text=True)

The limit is the environment variable when it is set, else the default. On expiry the process is killed
and ToolTimeout is raised with "<label>: timed out after <n>s ...". stdin defaults to /dev/null so a
script error never waits at Godot's debugger prompt.
"""
import os
import subprocess


class ToolTimeout(RuntimeError):
    pass


def limit(env_var, default):
    raw = os.environ.get(env_var)
    if raw is None or raw == "":
        return int(default)
    if not raw.isdigit() or int(raw) == 0:
        raise ToolTimeout(f"{env_var}={raw} is not a positive whole number of seconds")
    return int(raw)


def run(cmd, label, env_var, default, **kwargs):
    """subprocess.run under a limit; returns the CompletedProcess, raises ToolTimeout on expiry."""
    seconds = limit(env_var, default)
    kwargs.setdefault("stdin", subprocess.DEVNULL)
    try:
        return subprocess.run([str(c) for c in cmd], timeout=seconds, **kwargs)
    except subprocess.TimeoutExpired:
        raise ToolTimeout(f"{label}: timed out after {seconds}s and was stopped; a hung Godot or Blender, "
                          f"or raise the limit with {env_var}=<seconds>") from None
