extends SceneTree

# CI: compile every .dialogue file outside addons/ with Dialogue Manager's own compiler, and print
# each syntax error with its line. The importer reports a broken file only as "N errors found in
# <path>" and imports nothing, so this step is what names the line.
#   godot --headless --path . -s ci/check_dialogue.gd
# Exit code: 0 when every file compiles, 1 otherwise.

const SKIP_DIRS := ["res://addons", "res://.godot", "res://.tripo-out", "res://.claude", "res://reports"]


func _initialize() -> void:
	var paths: Array[String] = []
	_collect("res://", paths)
	paths.sort()
	var broken := 0
	for path in paths:
		var result: DMCompilerResult = DMCompiler.compile_string(FileAccess.get_file_as_string(path), path)
		if result.errors.is_empty():
			continue
		broken += 1
		for error: DMError in result.errors:
			printerr("ERROR: %s:%d: %s" % [path, error.line_number, DMConstants.get_error_message(error.error)])
	print("check_dialogue: compiled %d files, %d with errors" % [paths.size(), broken])
	quit(0 if broken == 0 else 1)


func _collect(dir_path: String, out: Array[String]) -> void:
	if dir_path.trim_suffix("/") in SKIP_DIRS:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for file in dir.get_files():
		if file.get_extension() == "dialogue":
			out.append(dir_path.path_join(file))
