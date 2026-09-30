extends Node

# Review tool: runs Level 1 with its real gameplay code, puts the player a few metres from an enemy
# (camera facing it), presses a light attack and a dodge, and saves frames from the player camera.
# Windowed run:
#   godot --path . res://scripts/review/level1_play_capture.tscn -- --enemy EnemyCentral1 --out <dir>
#       [--kill-at <seconds>] [--duration <seconds>]   kill the enemy (checks the death clip and fade)

const CAPTURE_EVERY := 0.25
const DURATION := 5.5
const INPUTS := {1.9: "attack_light", 3.0: "dodge"}  # seconds -> action pressed for one frame
const START_DISTANCE := 7.0


func _ready() -> void:
	# Vsync off: with another window in front (the human's editor), macOS throttles a covered
	# window's buffer swaps and a vsynced capture crawls (one clip took minutes, not seconds)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var args := {}
	var argv := OS.get_cmdline_user_args()
	for i in range(0, argv.size() - 1, 2):
		args[argv[i].trim_prefix("--")] = argv[i + 1]
	get_window().size = Vector2i(1280, 720)
	var level: Node = load("res://scenes/world/Level1.tscn").instantiate()
	add_child(level)
	for i in 5:
		await get_tree().process_frame
	var player: CharacterBody3D = get_tree().get_first_node_in_group("player")
	var enemy: Node3D = level.get_node(args.get("enemy", "EnemyCentral1"))
	var dir := (player.global_position - enemy.global_position)
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.BACK
	player.global_position = enemy.global_position + dir * START_DISTANCE + Vector3.UP * 0.1
	# Camera behind the player, looking at the enemy (the rig looks down its -Z)
	var to_enemy := -dir
	player.set("_cam_yaw", atan2(-to_enemy.x, -to_enemy.z))
	var t := 0.0
	var shot := 0
	var pressed := {}
	var duration := float(args.get("duration", DURATION))
	var killed := false
	while t < duration:
		if args.has("kill-at") and not killed and t >= float(args["kill-at"]):
			killed = true
			# Kill the enemy nearest the player, so the death is in view
			var nearest: Node3D = null
			for body in level.find_children("*", "CharacterBody3D", true, false):
				if body != player and body.has_method("die") and (nearest == null or
						body.global_position.distance_to(player.global_position) < nearest.global_position.distance_to(player.global_position)):
					nearest = body
			enemy = nearest
			enemy.call("die")
		await get_tree().process_frame
		t += get_process_delta_time()
		for at in INPUTS:
			if t >= at and not pressed.has(at):
				pressed[at] = true
				# The player reads actions from input events (_input), so send real events
				for pressed_state in [true, false]:
					var ev := InputEventAction.new()
					ev.action = INPUTS[at]
					ev.pressed = pressed_state
					Input.parse_input_event(ev)
					await get_tree().physics_frame
		if t >= shot * CAPTURE_EVERY:
			await RenderingServer.frame_post_draw
			var anim := ""
			if not is_instance_valid(enemy):
				print("SAVED (enemy freed) t=%.1f" % t)
				shot += 1
				continue
			var ep = enemy.get_node_or_null("SkeletonModel/AnimationPlayer")
			var fade := 0.0
			for m in enemy.find_children("*", "MeshInstance3D", true, false):
				var ov = (m as MeshInstance3D).get_surface_override_material(0)
				if ov is BaseMaterial3D:
					fade = maxf(fade, 1.0 - (ov as BaseMaterial3D).albedo_color.a)
			var pp = player.get_node_or_null("PlayerModel/AnimationPlayer")
			anim = "player=%s enemy=%s" % [pp.current_animation if pp else "-", ep.current_animation if ep else "-"]
			var path: String = args["out"].path_join("level1_play_%02d.png" % shot)
			get_viewport().get_texture().get_image().save_png(path)
			print("SAVED ", path, " t=%.1f " % t, anim, " fade=%.2f" % fade)
			shot += 1
	get_tree().quit()
