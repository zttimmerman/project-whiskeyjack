extends GdUnitTestSuite
# gdUnit4 signal asserts are coroutines behind an abstract interface, so the analyzer flags their
# required await as redundant
@warning_ignore_start("redundant_await")

# NPC quest rewards: the reward fires once, when the NPC's quest completes (dialogue completes it
# with a mutation now), never again on a later talk, including after a save is loaded. Uses the
# QuestManager autoload (NPC.gd calls it directly), snapshotted and restored around each test.

const QUEST := "clear_eastern_road"

var npc: Node
var _snapshot: Array


func before_test() -> void:
	_snapshot = [
		QuestManager._active_quests.duplicate(true),
		QuestManager._completed_quests.duplicate(),
		QuestManager._flags.duplicate(true),
	]
	QuestManager._active_quests.clear()
	QuestManager._completed_quests.clear()
	QuestManager._flags.clear()
	npc = _make_npc()


func after_test() -> void:
	QuestManager._active_quests = _snapshot[0]
	QuestManager._completed_quests.assign(_snapshot[1])
	QuestManager._flags = _snapshot[2]


func _make_npc() -> Node:
	var n: Node = auto_free(load("res://scenes/npcs/NPC.gd").new())
	n.completion_quest_id = QUEST
	n.dialogue_id = ""  # interact() then starts no dialogue
	add_child(n)
	return n


func test_completing_the_quest_gives_the_reward_once() -> void:
	var monitor := monitor_signals(npc)
	QuestManager.start_quest(QUEST)
	QuestManager.complete_quest(QUEST)
	await assert_signal(monitor).is_emitted("quest_reward_given")
	npc.interact()
	await assert_signal(monitor).wait_until(100).is_not_emitted("quest_reward_given")


func test_other_quests_give_no_reward() -> void:
	var monitor := monitor_signals(npc)
	QuestManager.start_quest("no_such_quest")
	QuestManager.complete_quest("no_such_quest")
	await assert_signal(monitor).wait_until(100).is_not_emitted("quest_reward_given")


func test_talking_after_a_load_of_a_completed_quest_gives_no_reward() -> void:
	# A loaded save restores completed quests without signals; the reward is already in the inventory
	QuestManager._completed_quests.append(QUEST)
	var loaded := _make_npc()
	var monitor := monitor_signals(loaded)
	loaded.interact()
	await assert_signal(monitor).wait_until(100).is_not_emitted("quest_reward_given")
