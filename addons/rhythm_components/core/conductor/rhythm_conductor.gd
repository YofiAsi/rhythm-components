class_name RhythmConductor extends RhythmComponent

signal beat_update(beat: float)
signal measure_update(measure: int)

var bpm : float = 120.0
var beats_per_measure : float = 4
var beat_unit : float = 4

var beat_duration : float = 0.0
var current_beat : float = 0.0
var current_measure: int = 0

func _ready() -> void:
	super._ready()

func set_song(
	song_bpm: float,
	song_beat_per_mesure: int,
	song_beat_unit: int,
) -> void:
	self.bpm = song_bpm
	self.beats_per_measure = song_beat_per_mesure
	self.beat_unit = song_beat_unit
	self.beat_duration = 60.0 / bpm
	self.current_beat = 0.0
	self.current_measure = 0

func update(song_pos: float = -1) -> void:
	var t := song_pos
	if t <= -1:
		push_error("song time not provided")
		return
	
	var beat: float = _get_beat(t)
	if current_beat == beat:
		return
	current_beat = beat
	beat_update.emit(current_beat)
	
	var mesure: int = _get_mesure(current_beat)
	if current_measure == mesure:
		return
	current_measure = mesure
	measure_update.emit(current_measure)

func _get_beat(time: float) -> float:
	return time / beat_duration

func _get_mesure(beat: float) -> int:
	return int(floor(beat / beats_per_measure))
