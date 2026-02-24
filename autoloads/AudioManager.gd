extends Node

# AudioManager — global audio control autoload.
# Three buses are created at startup: Music, SFX, UI — all routed to Master.
# Audio files must exist under assets/audio/ before streams can be assigned:
#   assets/audio/music_ambient.ogg  — looping area music
#   assets/audio/sfx_swing.ogg      — sword swing (light + heavy)
#   assets/audio/sfx_impact.ogg     — hit received
#   assets/audio/sfx_footstep.ogg   — footstep tick
#   assets/audio/sting_you_died.ogg — YOU DIED stinger

var _music_player: AudioStreamPlayer
var _ui_player: AudioStreamPlayer


func _ready() -> void:
	_ensure_buses()
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = "UI"
	add_child(_ui_player)


func _ensure_buses() -> void:
	for bus_name: String in ["Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx: int = AudioServer.bus_count
			AudioServer.add_bus()
			AudioServer.set_bus_name(idx, bus_name)


func play_music(stream: AudioStream) -> void:
	if not stream:
		return
	# Enable looping on OGG streams before assigning
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_music_player.stream = stream
	_music_player.play()


func stop_music() -> void:
	_music_player.stop()


func play_ui(stream: AudioStream) -> void:
	if not stream:
		return
	_ui_player.stream = stream
	_ui_player.play()


# Spawns a temporary AudioStreamPlayer3D at world_position; auto-frees when done.
func play_sfx_at(stream: AudioStream, world_position: Vector3) -> void:
	if not stream:
		return
	var scene_root := get_tree().current_scene
	if not scene_root:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "SFX"
	scene_root.add_child(p)
	p.global_position = world_position
	p.play()
	p.finished.connect(p.queue_free)
