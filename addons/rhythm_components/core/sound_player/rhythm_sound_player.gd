class_name RhythmSoundPlayer extends RhythmSoundPlayerInterface

signal song_finished()

var main_song_player: AudioStreamPlayer
var sfx_players: Dictionary[String, AudioStreamPlayer] = {}

var song_position: float = 0.0
var latency_offset: float = 0.0

# --- Latency cache ---
var _cached_output_latency: float = 0.0
var _last_latency_update_ms: int = 0
const LATENCY_REFRESH_MS := 1000

func _ready() -> void:
	main_song_player = AudioStreamPlayer.new()
	main_song_player.finished.connect(song_finished.emit)
	add_child(main_song_player)

	_refresh_output_latency()

func add_sfx(stream: AudioStream, action_name: String) -> void:
	if not sfx_players.has(action_name):
		var player := AudioStreamPlayer.new()
		add_child(player)
		sfx_players[action_name] = player

	sfx_players[action_name].stream = stream

func set_song(stream: AudioStream) -> void:
	main_song_player.stream = stream

func play_main_song() -> void:
	main_song_player.play()

func update() -> void:
	if not main_song_player.playing:
		return

	_refresh_output_latency_if_needed()

	song_position = main_song_player.get_playback_position()
	song_position += AudioServer.get_time_since_last_mix()
	song_position -= _cached_output_latency
	song_position += latency_offset

	song_position_updated.emit(song_position)

func set_manual_latency_offset(val: float) -> void:
	latency_offset = val

func stop() -> void:
	main_song_player.stop()

func on_sfx_play(action_name: StringName) -> void:
	var sfx_player: AudioStreamPlayer = sfx_players.get(str(action_name))
	if is_instance_valid(sfx_player):
		sfx_player.play()

func _refresh_output_latency_if_needed() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_latency_update_ms >= LATENCY_REFRESH_MS:
		_refresh_output_latency()

func _refresh_output_latency() -> void:
	_cached_output_latency = AudioServer.get_output_latency()
	_last_latency_update_ms = Time.get_ticks_msec()
