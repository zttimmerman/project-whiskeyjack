extends GdUnitTestSuite
# gdUnit4 signal asserts are coroutines behind an abstract interface, so the analyzer flags their
# required await as redundant
@warning_ignore_start("redundant_await")

# Characterization tests for CharacterStats as it is today (written after the fact, CLAUDE.md →
# Testing). take_damage uses the §6 ratio, max(1, round(damage × 100 / (100 + 10 × defense))); its
# full case table is test_damage_ratio_formula in test_design_targets.gd.

var stats: CharacterStats


func before_test() -> void:
	stats = CharacterStats.new()
	stats.max_hp = 100
	stats.current_hp = 100
	stats.attack = 10
	stats.defense = 5
	stats.level = 1
	stats.experience = 0
	stats.experience_to_next_level = 100


func test_take_damage_applies_the_defense_ratio() -> void:
	var monitor := monitor_signals(stats)
	stats.take_damage(20)  # 20 × 100 / 150 = 13.3
	assert_int(stats.current_hp).is_equal(87)
	await assert_signal(monitor).is_emitted("health_changed", 87, 100)
	await assert_signal(monitor).wait_until(100).is_not_emitted("died")


func test_take_damage_below_defense_still_deals_one() -> void:
	stats.take_damage(1)  # 0.67 rounds to 1; armour never zeroes a hit
	assert_int(stats.current_hp).is_equal(99)


func test_take_damage_to_zero_emits_died_and_clamps() -> void:
	var monitor := monitor_signals(stats)
	stats.take_damage(500)
	assert_int(stats.current_hp).is_equal(0)
	await assert_signal(monitor).is_emitted("health_changed", 0, 100)
	await assert_signal(monitor).is_emitted("died")


func test_heal_clamps_to_max_hp() -> void:
	stats.current_hp = 40
	var monitor := monitor_signals(stats)
	stats.heal(30)
	assert_int(stats.current_hp).is_equal(70)
	await assert_signal(monitor).is_emitted("health_changed", 70, 100)
	stats.heal(1000)
	assert_int(stats.current_hp).is_equal(100)


func test_gain_experience_below_threshold_emits_xp_changed() -> void:
	var monitor := monitor_signals(stats)
	stats.gain_experience(40)
	assert_int(stats.experience).is_equal(40)
	assert_int(stats.level).is_equal(1)
	await assert_signal(monitor).is_emitted("xp_changed", 40, 100)
	await assert_signal(monitor).wait_until(100).is_not_emitted("leveled_up")


# Design bible §6: XP to next level ×1.5; +10 HP, +2 attack, +1 defense per level; full restore
func test_level_up_applies_the_curve() -> void:
	stats.current_hp = 30
	var monitor := monitor_signals(stats)
	stats.level_up()
	assert_int(stats.level).is_equal(2)
	assert_int(stats.max_hp).is_equal(110)
	assert_int(stats.current_hp).is_equal(110)
	assert_int(stats.attack).is_equal(12)
	assert_int(stats.defense).is_equal(6)
	assert_int(stats.experience_to_next_level).is_equal(150)
	await assert_signal(monitor).is_emitted("leveled_up", 2)
	await assert_signal(monitor).is_emitted("health_changed", 110, 110)


func test_gain_experience_carries_over_and_chains_level_ups() -> void:
	# 100 to reach level 2, then 150 to reach level 3: 260 XP leaves 10 carried over
	stats.gain_experience(260)
	assert_int(stats.level).is_equal(3)
	assert_int(stats.experience).is_equal(10)
	assert_int(stats.experience_to_next_level).is_equal(225)
	assert_int(stats.max_hp).is_equal(120)
