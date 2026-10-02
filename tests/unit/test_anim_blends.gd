extends GdUnitTestSuite

# Every handover the game makes between a character's clips, played the game's way by the motion
# review's game-path pass (scripts/review/game_path.gd: play() with the scene's own AnimationPlayer blend
# settings, one physics frame at a time), stays under the art bible's motion_handover_snap_mps, with the
# expected clip playing and settled on its own pose once the blend is over. A hard cut (no blend time)
# reads 16-69 m/s on most handovers.

const GamePath := preload("res://scripts/review/game_path.gd")
const ART_BIBLE := "res://docs/art-bible.md"
const FPS := 60.0
const SETTLE_MAX_M := 0.01  # after the blend and three more frames, the clip's own pose (the pass's check)
# Each game scene with the character model its AnimationPlayer drives and the library it plays
const CHARACTERS := {
	"res://scenes/player/Player.tscn": ["res://assets/meshes/player.glb", "res://data/animations/player_library.tres"],
	"res://scenes/enemies/BaseEnemy.tscn":
	["res://assets/meshes/barrow_levy.glb", "res://data/animations/levy_frontfile_library.tres"],
	"res://scenes/enemies/ArcherEnemy.tscn":
	["res://assets/meshes/barrow_levy.glb", "res://data/animations/levy_backfile_library.tres"],
}


# The tolerance's only source is the art bible's Judge tolerances table
func _snap_limit() -> float:
	var re := RegEx.create_from_string("\\| `motion_handover_snap_mps` \\| ([0-9.]+) \\|")
	var m := re.search(FileAccess.get_file_as_string(ART_BIBLE))
	assert_object(m).override_failure_message("no motion_handover_snap_mps row in the art bible").is_not_null()
	return float(m.get_string(1)) if m else 0.0


func _measure(scene: String) -> Array:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)
	var spec: Array = CHARACTERS[scene]
	assert_str(GamePath.scene_for_library(spec[1])).is_equal(scene)
	return GamePath.measure_all(holder, load(spec[0]), load(spec[1]), GamePath.game_settings(scene), FPS)


func _assert_handovers(scene: String) -> void:
	var limit := _snap_limit()
	var results := _measure(scene)
	assert_array(results).is_not_empty()
	for r: Dictionary in results:
		var pair := "%s %s>%s" % [scene.get_file(), r["from"], r["to"]]
		assert_bool(r.has("error")).override_failure_message("%s: %s" % [pair, r.get("error")]).is_false()
		(
			assert_float(r["snap_excess_mps"])
			. override_failure_message(
				(
					"%s snaps %.1f m/s (%s at %.1f vs its own %.1f, blend %.2f s); the limit is %.1f"
					% [
						pair,
						r["snap_excess_mps"],
						r["peak_limb"],
						r["peak_mps"],
						r["own_peak_mps"],
						r["blend_s"],
						limit
					]
				)
			)
			. is_less_equal(limit)
		)
		(
			assert_int(r["wrong_clip_frames"])
			. override_failure_message(
				"%s: %d frames with the wrong clip or a frozen one" % [pair, r["wrong_clip_frames"]]
			)
			. is_equal(0)
		)
		(
			assert_float(r["settle_error_m"])
			. override_failure_message(
				"%s: %.3f m off the clip's own pose after the blend" % [pair, r["settle_error_m"]]
			)
			. is_less(SETTLE_MAX_M)
		)


func test_motion_handover_snap_player() -> void:
	_assert_handovers("res://scenes/player/Player.tscn")


func test_motion_handover_snap_frontfile() -> void:
	_assert_handovers("res://scenes/enemies/BaseEnemy.tscn")


func test_motion_handover_snap_backfile() -> void:
	_assert_handovers("res://scenes/enemies/ArcherEnemy.tscn")
