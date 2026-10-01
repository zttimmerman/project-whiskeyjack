extends GdUnitTestSuite

# Enemy attacks (design bible §3 → Enemy tells and fairness, §9): the windup before a melee hitbox
# opens (enemy_melee_telegraph) and the draw before an arrow leaves (enemy_ranged_telegraph), the
# levy committing to its swing, and hits from enemies that have died or been staggered.
# Enemies are stepped by hand (their own physics processing is off), one 60 Hz physics frame at a time.

const BaseEnemy := preload("res://scenes/enemies/BaseEnemy.gd")
const LEVY_SCENE := "res://scenes/enemies/BaseEnemy.tscn"
const ARCHER_SCENE := "res://scenes/enemies/ArcherEnemy.tscn"
const PROJECTILE_SCENE := "res://scenes/enemies/Projectile.tscn"
const FakePlayer := preload("res://tests/doubles/fake_player.gd")
const DT := 1.0 / 60.0
const MELEE_TELEGRAPH_MIN_S := 0.5  # enemy_melee_telegraph
const RANGED_TELEGRAPH_MIN_S := 0.8  # enemy_ranged_telegraph

var _player: CharacterBody3D
var _scene_root: Node3D  # stands in for the level: the archer adds its arrows to the current scene


func before_test() -> void:
	if get_tree().current_scene == null:
		_scene_root = Node3D.new()
		get_tree().root.add_child(_scene_root)
		get_tree().current_scene = _scene_root
	_player = auto_free(FakePlayer.new())
	_player.stats = CharacterStats.new()
	add_child(_player)
	_player.global_position = Vector3.ZERO


func after_test() -> void:
	for proj in _projectiles():
		proj.free()
	if is_instance_valid(_scene_root):
		get_tree().current_scene = null
		_scene_root.free()


# An enemy scene at `at`, in the tree (so its _ready() runs), stepped only by _step(). `attack`
# replaces its stats' attack before _ready() when given.
func _spawn(path: String, at: Vector3, attack: int = -1) -> CharacterBody3D:
	var enemy: CharacterBody3D = auto_free((load(path) as PackedScene).instantiate())
	if attack >= 0:
		enemy.stats = enemy.stats.duplicate()
		enemy.stats.attack = attack
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = at
	return enemy


func _step(enemy: CharacterBody3D, frames: int = 1) -> void:
	for _i in frames:
		enemy._physics_process(DT)


func _hitbox(enemy: Node) -> HitboxComponent:
	return enemy.get_node("HitboxComponent")


# Frames from the attack starting until the melee hitbox opens (-1 if it doesn't within `limit`)
func _frames_until_open(enemy: CharacterBody3D, limit: int = 180) -> int:
	for f in limit:
		if _hitbox(enemy).is_active():
			return f
		_step(enemy)
	return -1


func _projectiles() -> Array[Node]:
	var out: Array[Node] = []
	var scene_root := get_tree().current_scene
	if scene_root:
		for child in scene_root.get_children():
			if child.scene_file_path == PROJECTILE_SCENE and not child.is_queued_for_deletion():
				out.append(child)
	return out


func _facing(enemy: Node3D) -> Vector3:
	return -enemy.global_transform.basis.z


func test_enemy_melee_telegraph() -> void:
	var levy := _spawn(LEVY_SCENE, Vector3(0, 0, -1.2))
	levy._change_state(BaseEnemy.State.ATTACK)
	assert_bool(_hitbox(levy).is_active()).override_failure_message("the hitbox opened as the attack began").is_false()
	var frames := _frames_until_open(levy)
	assert_int(frames).override_failure_message("the hitbox never opened").is_greater(0)
	assert_float(frames * DT).is_greater_equal(MELEE_TELEGRAPH_MIN_S)
	assert_int(levy.state).is_equal(BaseEnemy.State.ATTACK)


# The tell is the attack clip's anticipation pose: the clip is held at its "tell" marker during the
# windup, and released so its "contact" marker plays as the hitbox opens
func test_enemy_melee_telegraph_holds_the_tell_pose() -> void:
	var levy := _spawn(LEVY_SCENE, Vector3(0, 0, -1.2))
	var anim_player: AnimationPlayer = levy.get_node("SkeletonModel/AnimationPlayer")
	var clip := anim_player.get_animation("attack")
	assert_bool(clip.has_marker("tell") and clip.has_marker("contact")).is_true()
	var tell := clip.get_marker_time("tell")
	var contact := clip.get_marker_time("contact")
	levy._change_state(BaseEnemy.State.ATTACK)
	_step(levy, int(MELEE_TELEGRAPH_MIN_S / 2.0 / DT) + 6)
	assert_str(anim_player.assigned_animation).is_equal("attack")  # paused while posed
	assert_float(anim_player.current_animation_position).is_equal_approx(tell, 0.001)
	_frames_until_open(levy)
	# Contact lands with the hitbox, within the ±2 frames atk_hitbox_sync allows the player
	assert_float(anim_player.current_animation_position).is_equal_approx(contact, 2 * DT)


# The levy commits to the swing (§3): no re-aiming or moving between the windup and the swing's end
func test_enemy_melee_attack_commits() -> void:
	var levy := _spawn(LEVY_SCENE, Vector3(0, 0, -1.2))
	levy._change_state(BaseEnemy.State.ATTACK)
	var facing := _facing(levy)
	var start := levy.global_position
	_player.global_position = Vector3(3, 0, -1.2)  # sidestep well clear
	for _f in 50:
		_step(levy)
		if levy.state != BaseEnemy.State.ATTACK:
			break
		assert_vector(_facing(levy)).is_equal_approx(facing, Vector3.ONE * 0.001)
		assert_float(Vector2(levy.velocity.x, levy.velocity.z).length()).is_equal_approx(0.0, 0.001)
	var moved := Vector2(levy.global_position.x - start.x, levy.global_position.z - start.z).length()
	assert_float(moved).is_less(0.01)


# A stagger cancels the attack during its windup; its hitbox never opens
func test_stagger_cancels_the_windup() -> void:
	var levy := _spawn(LEVY_SCENE, Vector3(0, 0, -1.2))
	levy._change_state(BaseEnemy.State.ATTACK)
	_step(levy, 10)
	var blade: HitboxComponent = auto_free(HitboxComponent.new())
	levy._on_hurtbox_hit(blade)
	assert_int(levy.state).is_equal(BaseEnemy.State.STAGGER)
	for _f in 90:
		_step(levy)
		assert_bool(_hitbox(levy).is_active()).is_false()


func test_enemy_ranged_telegraph() -> void:
	var archer := _spawn(ARCHER_SCENE, Vector3(0, 0, -7))
	archer._change_state(BaseEnemy.State.ATTACK)
	var frames := -1
	for f in 180:
		if not _projectiles().is_empty():
			frames = f
			break
		_step(archer)
	assert_int(frames).override_failure_message("the arrow was never released").is_greater(0)
	assert_float(frames * DT).is_greater_equal(RANGED_TELEGRAPH_MIN_S)
	assert_int(_projectiles().size()).is_equal(1)


func test_stagger_cancels_the_draw() -> void:
	var archer := _spawn(ARCHER_SCENE, Vector3(0, 0, -7))
	archer._change_state(BaseEnemy.State.ATTACK)
	_step(archer, 20)
	var blade: HitboxComponent = auto_free(HitboxComponent.new())
	archer._on_hurtbox_hit(blade)
	_step(archer, 90)
	assert_int(_projectiles().size()).is_equal(0)


# Enemy hitbox damage is the enemy's attack stat, not a scene value kept equal to it by hand
func test_enemy_hitbox_damage_is_the_attack_stat() -> void:
	var levy := _spawn(LEVY_SCENE, Vector3(0, 0, -1.2))
	assert_int(_hitbox(levy).damage).is_equal(levy.stats.attack)
	var strong := _spawn(LEVY_SCENE, Vector3(5, 0, -1.2), 21)
	assert_int(_hitbox(strong).damage).is_equal(21)


func test_archer_arrow_damage_is_the_attack_stat() -> void:
	var archer := _spawn(ARCHER_SCENE, Vector3(0, 0, -7), 19)
	archer._change_state(BaseEnemy.State.ATTACK)
	_step(archer, 120)
	var arrows := _projectiles()
	assert_int(arrows.size()).is_equal(1)
	if arrows.size() == 1:
		assert_int((arrows[0].get_node("HitboxComponent") as HitboxComponent).damage).is_equal(19)


# Found in play: a levy's hit still landed on the frame it died, because hitbox deactivation is
# deferred to the end of the frame. A closed hitbox (dead, staggered or between swings) never hits.
func test_dead_enemy_lands_no_hit() -> void:
	var levy := _spawn(LEVY_SCENE, Vector3(0, 0, -1.2))
	levy._change_state(BaseEnemy.State.ATTACK)
	_frames_until_open(levy)
	assert_bool(_hitbox(levy).is_active()).is_true()
	levy.stats.take_damage(levy.stats.max_hp * 10)  # dies through stats.died, as from a player hit
	assert_bool(levy.is_dead()).is_true()
	assert_bool(_hitbox(levy).is_active()).is_false()

	var player_hurtbox: HurtboxComponent = auto_free(HurtboxComponent.new())
	player_hurtbox.stats = CharacterStats.new()
	var hp := player_hurtbox.stats.current_hp
	var hits := []
	_hitbox(levy).hit.connect(func(target, damage): hits.append([target, damage]))
	# The overlap the physics step reports in that same frame, in either order
	_hitbox(levy)._on_area_entered(player_hurtbox)
	player_hurtbox._on_hitbox_entered(_hitbox(levy))
	assert_array(hits).is_empty()
	assert_int(player_hurtbox.stats.current_hp).is_equal(hp)
