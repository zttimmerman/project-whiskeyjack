extends SceneTree

# CI: load every project script, scene and resource outside addons/, so parse errors and broken
# scenes show up in the log even when nothing else references them.
#   godot --headless --path . -s ci/load_all.gd
# Exit code: 0 when everything loaded, 1 otherwise. The log is checked by ci/check_log.py.

const SKIP_DIRS := ["res://addons", "res://.godot", "res://.tripo-out", "res://.claude"]
const EXTENSIONS := ["gd", "tscn", "tres"]


func _initialize() -> void:
	var paths: Array[String] = []
	_collect("res://", paths)
	paths.sort()
	var failed: Array[String] = []
	for path in paths:
		var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if res == null:
			failed.append(path)
		elif res is GDScript and not (res as GDScript).can_instantiate():
			failed.append(path)
	print("load_all: loaded %d files, %d failed" % [paths.size(), failed.size()])
	for path in failed:
		printerr("ERROR: load_all: failed to load %s" % path)
	quit(0 if failed.is_empty() else 1)


func _collect(dir_path: String, out: Array[String]) -> void:
	if dir_path.trim_suffix("/") in SKIP_DIRS:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for file in dir.get_files():
		if file.get_extension() in EXTENSIONS:
			out.append(dir_path.path_join(file))
