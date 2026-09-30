extends GdUnitTestSuite
# gdUnit4 reads do_skip, skip_reason and timeout from the test function's signature
@warning_ignore_start("unused_parameter")

# Runs tests/test_respawn_save.gd as-is, in its own headless Godot process. It drives the real
# death flow (scene reloads through GameManager), which can't run inside the gdUnit4 runner's own
# tree, so it stays a SceneTree script and this suite checks its exit code and output.
# Save isolation: the child gets --save-slot=respawn_test (the arg wins over WHISKEYJACK_SAVE_SLOT),
# and the script itself refuses to run against user://save.json.

const SCRIPT := "res://tests/test_respawn_save.gd"


func test_respawn_restores_the_save(timeout := 120000) -> void:
	var args := [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", SCRIPT, "--", "--save-slot=respawn_test",
	]
	var output := []
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	var text: String = "".join(output)
	assert_int(code).override_failure_message("%s exited %d:\n%s" % [SCRIPT, code, text]).is_equal(0)
	assert_str(text).contains("PASS test_respawn_save")
