extends GdUnitTestSuite

# DialogueRunner as a wrapper over Dialogue Manager: its signals and public methods are the ones
# DialogueUI and NPC.gd have always used (dialogue_started, line_ready(speaker, text, choices),
# dialogue_ended; start(), advance()). Runs a fresh DialogueRunner whose dialogue expressions see a
# fresh QuestManager (through game_states), so the real autoloads' state is never touched.
# Fixture: tests/fixtures/dialogue/runner_fixture.dialogue. The last tests run the shipped
# Keeper Idrenna conversation (data/dialogues/village_elder.dialogue) through each quest state.

const QUEST := "clear_eastern_road"
const FIXTURES := "res://tests/fixtures/dialogue/"
const MAX_WAIT_FRAMES := 120

var runner: Node
var quests: Node
var events: Array = []


func before_test() -> void:
	events.clear()
	quests = auto_free(load("res://autoloads/QuestManager.gd").new())
	add_child(quests)
	runner = auto_free(load("res://scripts/dialogue/DialogueRunner.gd").new())
	runner.game_states = [{"QuestManager": quests}]
	add_child(runner)
	runner.dialogue_started.connect(func(id: String) -> void: events.append(["started", id]))
	runner.line_ready.connect(
		func(speaker: String, text: String, choices: Array) -> void: events.append(["line", speaker, text, choices])
	)
	runner.dialogue_ended.connect(func() -> void: events.append(["ended"]))


# Waits (a frame at a time) until `count` events have arrived; mutations take a frame each.
func _wait_for_events(count: int) -> void:
	for i in MAX_WAIT_FRAMES:
		if events.size() >= count:
			return
		await get_tree().process_frame


func _start_fixture() -> void:
	runner.dialogue_dir = FIXTURES
	runner.start("runner_fixture")
	await _wait_for_events(2)


func _choice_texts(event: Array) -> Array:
	return event[3].map(func(c: Dictionary) -> String: return c.text)


func test_start_emits_started_then_the_first_line() -> void:
	await _start_fixture()
	assert_array(events).has_size(2)
	assert_array(events[0]).is_equal(["started", "runner_fixture"])
	assert_array(events[1]).is_equal(["line", "Tester", "First line.", []])
	assert_bool(runner.is_active()).is_true()


func test_advance_steps_lines_then_offers_only_allowed_choices() -> void:
	await _start_fixture()
	runner.advance()
	await _wait_for_events(3)
	assert_array(events[2]).is_equal(["line", "Tester", "Second line.", []])
	runner.advance()
	await _wait_for_events(4)
	assert_str(events[3][2]).is_equal("Will you?")
	# The conditional choice is hidden while its condition is false
	assert_array(_choice_texts(events[3])).is_equal(["Yes", "No"])


func test_choice_applies_the_quest_mutation_and_leads_to_its_line() -> void:
	await _start_fixture()
	runner.advance()
	runner.advance()
	await _wait_for_events(4)
	assert_bool(quests.is_quest_active(QUEST)).is_false()
	runner.advance(0)
	await _wait_for_events(5)
	assert_bool(quests.is_quest_active(QUEST)).is_true()
	assert_array(events[4]).is_equal(["line", "Tester", "Good.", []])
	runner.advance()
	await _wait_for_events(6)
	assert_array(events[5]).is_equal(["ended"])
	assert_bool(runner.is_active()).is_false()


func test_other_choice_sets_a_world_flag() -> void:
	await _start_fixture()
	runner.advance()
	runner.advance()
	await _wait_for_events(4)
	runner.advance(1)
	await _wait_for_events(5)
	assert_array(events[4]).is_equal(["line", "Tester", "Fine.", []])
	assert_bool(quests.get_flag("tester_declined")).is_true()
	assert_bool(quests.is_quest_active(QUEST)).is_false()


func test_flag_branches_the_opening() -> void:
	quests.set_flag("tester_declined")
	await _start_fixture()
	assert_array(events[1]).is_equal(["line", "Tester", "Back again?", []])


func test_completed_quest_branches_the_opening_and_ends() -> void:
	quests.start_quest(QUEST)
	quests.complete_quest(QUEST)
	await _start_fixture()
	assert_array(events[1]).is_equal(["line", "Tester", "Done already.", []])
	runner.advance()
	await _wait_for_events(3)
	assert_array(events[2]).is_equal(["ended"])


# The key that closes a conversation is the player's interact key, which Player polls in the physics
# step; without a block it would reopen the conversation on the frame the dialogue ends.
func test_interact_is_blocked_while_talking_and_on_the_frame_it_ends() -> void:
	assert_bool(runner.accepts_interact()).is_true()
	quests.start_quest(QUEST)
	quests.complete_quest(QUEST)
	await _start_fixture()
	assert_bool(runner.accepts_interact()).is_false()
	var at_end: Array = []
	runner.dialogue_ended.connect(func() -> void: at_end.append(runner.accepts_interact()))
	runner.advance()
	await _wait_for_events(3)
	assert_array(at_end).is_equal([false])
	assert_bool(runner.accepts_interact()).is_false()
	for i in 3:
		await get_tree().physics_frame
	assert_bool(runner.accepts_interact()).is_true()


func test_start_while_active_is_ignored() -> void:
	await _start_fixture()
	runner.start("runner_fixture")
	for i in 5:
		await get_tree().process_frame
	assert_array(events).has_size(2)


func test_advance_while_idle_does_nothing() -> void:
	runner.advance()
	for i in 5:
		await get_tree().process_frame
	assert_array(events).is_empty()


# ── Keeper Idrenna (data/dialogues/village_elder.dialogue) ────────────────────


func _start_elder() -> void:
	runner.start("village_elder")
	await _wait_for_events(2)


func test_elder_offers_the_quest_on_first_meeting() -> void:
	await _start_elder()
	(
		assert_array(events[1])
		. is_equal(
			[
				"line",
				"Idrenna",
				"They sent one of you, then. One.",
				[{"text": "What's the trouble?"}, {"text": "Just on patrol."}],
			]
		)
	)
	runner.advance(0)
	await _wait_for_events(3)
	runner.advance(0)
	await _wait_for_events(4)
	assert_bool(quests.is_quest_active(QUEST)).is_true()
	assert_str(events[3][2]).is_equal("Walk soft past the barrows. They listen.")


func test_elder_remembers_being_turned_down() -> void:
	await _start_elder()
	runner.advance(0)
	await _wait_for_events(3)
	runner.advance(1)
	await _wait_for_events(4)
	assert_bool(quests.get_flag("idrenna_turned_down")).is_true()
	assert_str(events[3][2]).is_equal("Keep your feet dry, soldier.")
	runner.advance()
	await _wait_for_events(5)
	events.clear()
	await _start_elder()
	assert_str(events[1][2]).is_equal("Orders change, soldier?")


func test_elder_report_completes_the_quest() -> void:
	quests.start_quest(QUEST)
	quests.advance_quest(QUEST)
	quests.advance_quest(QUEST)
	assert_str(quests.get_quest_stage(QUEST)).is_equal("return_to_keeper")
	await _start_elder()
	assert_str(events[1][2]).is_equal("You came back. More than most.")
	runner.advance(0)
	await _wait_for_events(3)
	assert_bool(quests.is_quest_complete(QUEST)).is_true()
	assert_str(events[2][2]).starts_with("This was my son's.")


func test_elder_mid_quest_and_after_quest_lines_differ() -> void:
	quests.start_quest(QUEST)
	await _start_elder()
	var mid_quest: String = events[1][2]
	runner.advance()
	await _wait_for_events(3)
	assert_array(events[2]).is_equal(["ended"])
	quests.complete_quest(QUEST)
	events.clear()
	await _start_elder()
	assert_str(events[1][2]).is_not_equal(mid_quest)
	assert_str(events[1][2]).is_equal("Keep your feet dry, soldier.")
