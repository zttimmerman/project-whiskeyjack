extends GdUnitTestSuite
# gdUnit4 signal asserts are coroutines behind an abstract interface, so the analyzer flags their
# required await as redundant
@warning_ignore_start("redundant_await")

# Characterization tests for QuestManager, on a fresh instance of the autoload's script so the
# real autoload's state is never touched. Uses data/quests/clear_eastern_road.json (3 stages).

const QUEST := "clear_eastern_road"

var quests: Node


func before_test() -> void:
	quests = auto_free(load("res://autoloads/QuestManager.gd").new())
	add_child(quests)


func test_start_quest_enters_the_first_stage() -> void:
	var monitor := monitor_signals(quests)
	quests.start_quest(QUEST)
	assert_bool(quests.is_quest_active(QUEST)).is_true()
	assert_str(quests.get_quest_stage(QUEST)).is_equal("find_monsters")
	await assert_signal(monitor).is_emitted("quest_started", QUEST)


func test_start_quest_twice_is_ignored() -> void:
	quests.start_quest(QUEST)
	quests.advance_quest(QUEST)
	var monitor := monitor_signals(quests)
	quests.start_quest(QUEST)
	assert_str(quests.get_quest_stage(QUEST)).is_equal("defeat_monsters")
	await assert_signal(monitor).wait_until(100).is_not_emitted("quest_started")


func test_advance_steps_through_stages_then_completes() -> void:
	quests.start_quest(QUEST)
	var monitor := monitor_signals(quests)
	quests.advance_quest(QUEST)
	assert_str(quests.get_quest_stage(QUEST)).is_equal("defeat_monsters")
	await assert_signal(monitor).is_emitted("quest_updated", QUEST, "defeat_monsters")
	quests.advance_quest(QUEST)
	assert_str(quests.get_quest_stage(QUEST)).is_equal("return_to_keeper")
	await assert_signal(monitor).is_emitted("quest_updated", QUEST, "return_to_keeper")
	# Advancing past the last stage completes the quest
	quests.advance_quest(QUEST)
	assert_bool(quests.is_quest_active(QUEST)).is_false()
	assert_bool(quests.is_quest_complete(QUEST)).is_true()
	assert_str(quests.get_quest_stage(QUEST)).is_equal("")
	await assert_signal(monitor).is_emitted("quest_completed", QUEST)


func test_complete_quest_directly() -> void:
	quests.start_quest(QUEST)
	var monitor := monitor_signals(quests)
	quests.complete_quest(QUEST)
	assert_bool(quests.is_quest_complete(QUEST)).is_true()
	await assert_signal(monitor).is_emitted("quest_completed", QUEST)


func test_completed_quest_cannot_restart() -> void:
	quests.start_quest(QUEST)
	quests.complete_quest(QUEST)
	quests.start_quest(QUEST)
	assert_bool(quests.is_quest_active(QUEST)).is_false()


func test_inactive_quest_ignores_advance_and_complete() -> void:
	var monitor := monitor_signals(quests)
	quests.advance_quest(QUEST)
	quests.complete_quest(QUEST)
	assert_bool(quests.is_quest_complete(QUEST)).is_false()
	await assert_signal(monitor).wait_until(100).is_not_emitted("quest_updated")
	await assert_signal(monitor).wait_until(100).is_not_emitted("quest_completed")


func test_quest_without_a_data_file_starts_as_a_stub() -> void:
	quests.start_quest("no_such_quest")
	assert_bool(quests.is_quest_active("no_such_quest")).is_true()
	assert_str(quests.get_quest_stage("no_such_quest")).is_equal("")
	# A stub has no stages, so one advance completes it
	quests.advance_quest("no_such_quest")
	assert_bool(quests.is_quest_complete("no_such_quest")).is_true()
