extends GdUnitTestSuite
# gdUnit4 reads do_skip, skip_reason and timeout from the test function's signature
@warning_ignore_start("unused_parameter")

# Design-bible targets (docs/design-bible.md §6, §9, §11), named after their target IDs.
# Settled decisions that aren't implemented yet are skipped (do_skip) with the reason; each one
# flips on (delete do_skip and skip_reason) in the PR that implements it, which must make it pass.
# The ttk_player_* tests check today's stats and combo against the target ranges, so a stat or
# formula change that breaks a target fails here.

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const LEVY_SCENE := "res://scenes/enemies/BaseEnemy.tscn"  # front-file levy (melee)
const ARCHER_SCENE := "res://scenes/enemies/ArcherEnemy.tscn"  # back-file levy (archer)
const STARTING_WEAPON := "res://data/items/sword_iron.tres"


# The stats resource a scene ships with, copied, without running the scene's _ready()
func _scene_stats(path: String) -> CharacterStats:
	var node: Node = (load(path) as PackedScene).instantiate()
	var stats: CharacterStats = (node.get("stats") as CharacterStats).duplicate()
	node.free()
	return stats


func _scene_hitbox_damage(path: String) -> int:
	var node: Node = (load(path) as PackedScene).instantiate()
	var damage: int = node.get_node("HitboxComponent").damage
	node.free()
	return damage


# Damage the target actually takes from one hit of `amount`, through CharacterStats.take_damage
func _damage_taken(target: CharacterStats, amount: int) -> int:
	var probe: CharacterStats = target.duplicate()
	probe.max_hp = 1000000
	probe.current_hp = probe.max_hp
	probe.take_damage(amount)
	return probe.max_hp - probe.current_hp


func _light_hits_to_kill(attacker: CharacterStats, target: CharacterStats) -> int:
	var hp := target.max_hp
	var hits := 0
	while hp > 0 and hits < 100:
		# Player.gd _attack_light(): hits 1 and 2 deal base attack, the finisher base + base / 2
		var base := attacker.attack
		var damage: int = base if hits % 3 < 2 else base + floori(base / 2.0)
		hp -= _damage_taken(target, damage)
		hits += 1
	return hits


# §6 and §11.1: damage = max(1, round(damage × 100 / (100 + 10 × defense)))
func test_damage_ratio_formula(
	do_skip := true, skip_reason := "pending: the §6 damage ratio replaces damage − defense (design bible §11.1)"
) -> void:
	# [incoming damage, defense, expected]
	var cases := [
		[10, 0, 10],
		[20, 5, 13],  # 13.3
		[8, 5, 5],  # 5.3: the levy's hit on the starting player
		[15, 2, 13],  # 12.5 rounds away from zero
		[100, 10, 50],
		[1, 50, 1],  # rounds to 0; the minimum is 1, so armour never zeroes damage
		[3, 200, 1],
	]
	for c in cases:
		var target := CharacterStats.new()
		target.defense = c[1]
		(
			assert_int(_damage_taken(target, c[0]))
			. override_failure_message("damage %d vs defense %d: expected %d" % c)
			. is_equal(c[2])
		)


# §11.5: an enemy hit takes about 8–10% of the player's HP at equal level
func test_enemy_damage_share(
	do_skip := true, skip_reason := "pending: enemy damage retune after the damage ratio (design bible §11.5)"
) -> void:
	var player := _equipped_player_stats()
	var levy := _scene_stats(LEVY_SCENE)
	assert_int(levy.level).is_equal(player.level)
	var share := float(_damage_taken(player, _scene_hitbox_damage(LEVY_SCENE))) / player.max_hp
	assert_float(share).is_between(0.08, 0.10)


# ttk_levy_player: 10–14 levy hits kill the player, equal level, starting gear equipped
func test_ttk_levy_player(
	do_skip := true,
	skip_reason := "pending: today about 34 hits; needs the damage ratio and enemy retune (design bible §11.1, §11.5)"
) -> void:
	var player := _equipped_player_stats()
	var per_hit := _damage_taken(player, _scene_hitbox_damage(LEVY_SCENE))
	assert_int(per_hit).is_greater(0)
	assert_int(ceili(float(player.max_hp) / per_hit)).is_between(10, 14)


# §6: enemy stats are base × (1 + 0.12 × (level − 1)). The API name is a proposal: a static
# CharacterStats.level_scale(level) -> float multiplier (called dynamically so this file parses today).
func test_level_band_scaling(
	do_skip := true, skip_reason := "pending: level-band scaling isn't implemented (design bible §6)"
) -> void:
	assert_bool(CharacterStats.new().has_method("level_scale")).is_true()
	var expected := {1: 1.0, 2: 1.12, 3: 1.24, 5: 1.48}
	for level in expected:
		var scale: float = (CharacterStats as GDScript).call("level_scale", level)
		assert_float(scale).is_equal_approx(expected[level], 0.0001)
	# The first area's band is 1–3: a 30 HP levy at level 3 has about 37 HP
	assert_float(30.0 * float((CharacterStats as GDScript).call("level_scale", 3))).is_equal_approx(37.2, 0.001)


# ttk_player_frontfile: 3–4 light hits kill a front-file levy at equal level (current: 4)
func test_ttk_player_frontfile() -> void:
	var player := _scene_stats(PLAYER_SCENE)
	var levy := _scene_stats(LEVY_SCENE)
	assert_int(levy.level).is_equal(player.level)
	assert_int(_light_hits_to_kill(player, levy)).is_between(3, 4)


# ttk_player_backfile: 2–3 light hits kill a back-file levy (archer) at equal level (current: 3)
func test_ttk_player_backfile() -> void:
	var player := _scene_stats(PLAYER_SCENE)
	var archer := _scene_stats(ARCHER_SCENE)
	assert_int(archer.level).is_equal(player.level)
	assert_int(_light_hits_to_kill(player, archer)).is_between(2, 3)


func _equipped_player_stats() -> CharacterStats:
	var stats := _scene_stats(PLAYER_SCENE)
	var inventory := Inventory.new()
	var weapon: Item = load(STARTING_WEAPON)
	inventory.add_item(weapon)
	inventory.equip_item(weapon, stats)
	return stats
