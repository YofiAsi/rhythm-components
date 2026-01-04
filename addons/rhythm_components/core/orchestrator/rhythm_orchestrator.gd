class_name RhythmOrchestrator
extends RhythmComponent

# Conductor Signals
signal beat_update(beat: float)
signal measure_update(measure: int)

# Judge Signals
signal note_missed(note_key: StringName)
signal note_succeed(note_key: StringName, error_beats: float)
signal blank_hit(note_key: StringName)

# Composer Signals
signal note_enter_behavior(note: Note)
signal note_exit_behavior(note: Note)
signal note_hit(note: Note)
signal note_signal(note_signal: NoteSignal)
signal sequence_started(sequence: NoteSequence)
signal sequence_ended(sequence: NoteSequence)

# Input Signals
signal player_input_entered(action_name: StringName, event: InputEvent)

# Calibration Signals
signal calibration_sample(error_beats: float)
signal calibration_updated(avg_error_beats: float, offset_ms: float)
signal calibration_finished()

@onready var sound_player: RhythmSoundPlayer = $SoundPlayer
@onready var conductor: RhythmConductor = $Conductor
@onready var composer: RhythmComposer = $Composer
@onready var player_input: RhythmInputListener = $PlayerInput
@onready var judge: RhythmJudge = $Judge
@onready var calibration: RhythmCalibration = $Calibration

@export var auto_start: bool = false
@export var song_stream: AudioStream
@export var bpm: float = 120.0
@export var beats_per_measure: float = 4
@export var beat_unit: float = 4
@export var hit_window_seconds: float = 0.1
@export var note_chart: NoteChart
@export var note_keys: NoteKeys
@export var hit_sfx: Dictionary[StringName, AudioStream]

var song_position: float
var beat: float
var measure: int
var active: bool = false

# --- Calibration state ---
var _calibrating: bool = false
var _prev_bpm_save: float
# -------------------------

func _update() -> void:
	sound_player.update()
	conductor.update(song_position)
	composer.update(beat)

func _process(_delta: float) -> void:
	if not active:
		return
	_update()

func _ready() -> void:
	super._ready()
	_prepare()
	_connects_signals()
	if auto_start:
		self.start()

#region Preperation
func _connects_signals() -> void:
	sound_player.song_position_updated.connect(
		func(value: float):
			song_position = value
	)

	conductor.beat_update.connect(
		func(value: float):
			beat = value
			beat_update.emit(value)
	)
	conductor.measure_update.connect(
		func(value: int):
			measure = value
			measure_update.emit(value)
	)
	
	sound_player.song_finished.connect(_on_sound_player_finished)

	composer.note_behavior_enter.connect(_on_composer_behavior_enter)
	composer.note_hit_window_open.connect(_on_composer_hit_window_open)
	composer.note_hit_window_close.connect(_on_composer_hit_window_close)
	composer.note_behavior_exit.connect(_on_composer_behavior_exit)
	composer.sequence_started.connect(_on_composer_sequence_started)
	composer.sequence_ended.connect(_on_composer_sequence_ended)
	composer.note_hit.connect(_on_composer_note_hit)
	composer.note_signal.connect(_on_composer_note_signal)

	player_input.player_input_event.connect(_on_player_input_event)

	judge.note_succeed.connect(_on_note_succeed)
	judge.note_missed.connect(_on_note_missed)
	judge.note_blank_hit.connect(_on_note_blank_hit)
	
	calibration.calibration_finished.connect(_on_calibration_finished)
	calibration.update_latency_offset.connect(_on_calibration_update)

func _prepare() -> void:
	song_position = 0.0
	beat = 0.0
	measure = 0

	_prepare_sound_player()
	_prepare_conductor()
	_prepare_composer()
	_prepare_player_input()
	_prepare_judge()

func _prepare_sound_player() -> void:
	sound_player.set_song(song_stream)

func _prepare_conductor() -> void:
	conductor.set_song(bpm, beats_per_measure, beat_unit)

func _prepare_composer() -> void:
	var beat_duration := 60.0 / bpm
	var hit_window_beats := hit_window_seconds / beat_duration
	composer.set_hit_window(hit_window_beats)
	composer.set_chart(note_chart)

func _prepare_player_input() -> void:
	if note_keys:
		player_input.set_actions(note_keys.keys)

func _prepare_judge() -> void:
	if note_keys:
		judge.set_note_keys(note_keys.keys)

#endregion

#region Sound Player Callbacks
func _on_sound_player_finished() -> void:
	active = false
	
	if _calibrating:
		stop_calibration()
		return
#endregion

#region Composer Callbacks
func _on_composer_behavior_enter(note: Note) -> void:
	note_enter_behavior.emit(note)

func _on_composer_hit_window_open(note: Note) -> void:
	judge.on_hit_window_opened(note)

func _on_composer_hit_window_close(note: Note) -> void:
	judge.on_hit_window_closed(note, beat)

func _on_composer_behavior_exit(note: Note) -> void:
	note_exit_behavior.emit(note)

func _on_composer_sequence_started(sequence: NoteSequence) -> void:
	if not _calibrating:
		sequence_started.emit(sequence)

func _on_composer_sequence_ended(sequence: NoteSequence) -> void:
	sequence_ended.emit(sequence)

func _on_composer_note_hit(note: Note) -> void:
	note_hit.emit(note)

	if _calibrating:
		return

	var res := judge.on_note_hit_time(note)
	if res["emit"]:
		_on_note_succeed(note.type.action_name, res["error_beats"])

func _on_composer_note_signal(note_signal: NoteSignal) -> void:
	note_signal.emit(note_signal)

#endregion

#region Input / Judge callbacks
func _on_player_input_event(
	action_name: StringName,
	event: InputEvent,
	emulate: bool = false
) -> void:
	player_input_entered.emit(action_name, event)
	if not _calibrating:
		judge.on_input_event(action_name, event, beat, !emulate)

func _on_note_succeed(note_key: StringName, error_beats: float) -> void:
	note_succeed.emit(note_key, error_beats)
	print("succeed - ", error_beats)

func _on_note_missed(note_key: StringName) -> void:
	note_missed.emit(note_key)

func _on_note_blank_hit(note_key: StringName) -> void:
	blank_hit.emit(note_key)
#endregion

#region Calibration API
func _on_calibration_finished() -> void:
	_calibrating = false
	var _calibration_mode: RhythmCalibration.CALIBRATION_MODE = calibration.get_mode()
	if _calibration_mode == RhythmCalibration.CALIBRATION_MODE.STREAM:
		active = false
		bpm = _prev_bpm_save
		sound_player.stop()
		_prepare_sound_player()
	if _calibration_mode == RhythmCalibration.CALIBRATION_MODE.TIME:
		pass
	
	calibration_finished.emit()

func _on_calibration_update(val: float) -> void:
	print_debug("calibration offset = ", val)
	sound_player.set_manual_latency_offset(val/3)

func _init_calibration() -> void:
	_calibrating = true
	active = true
	
func start_calibration_by_time(desired_time: float) -> void:
	_init_calibration()
	sound_player.play_main_song()
	calibration.start_calibration(RhythmCalibration.CALIBRATION_MODE.TIME, -1, desired_time)

func start_calibration_by_stream(calibration_stream: AudioStream, calibration_bpm: float) -> void:
	_prev_bpm_save = bpm
	bpm = calibration_bpm
	
	sound_player.set_song(calibration_stream)
	sound_player.play_main_song()
	_init_calibration()
	calibration.start_calibration(RhythmCalibration.CALIBRATION_MODE.STREAM, -1, -1)
	
func stop_calibration() -> void:
	calibration.stop_calibration()

#endregion

#region Public control
func start() -> void:
	_prepare()
	active = true
	sound_player.play_main_song()

func stop() -> void:
	active = false

func add_note(note: Note) -> float:
	var hit_time: float
	if note.hit_time <= 0:
		hit_time = composer.add_note_auto(note)
	else:
		hit_time = note.hit_time
		composer.add_note(note)
	return hit_time

func add_sequence_auto(sequence: NoteSequence) -> float:
	return composer.add_sequence_auto(sequence)

func emulate_player_action(action_name: StringName, event: InputEvent) -> void:
	_on_player_input_event(action_name, event, true)
#endregion
