class_name RhythmComposer
extends RhythmComponent


signal note_behavior_enter(note)
signal note_hit_window_open(note)
signal note_hit(note)
signal note_hit_window_close(note)
signal note_behavior_exit(note)
signal note_signal(note: NoteSignal)

signal sequence_started(sequence: NoteSequence)
signal sequence_ended(sequence: NoteSequence)

const EPS := 0.0001

var _actions: Array[Dictionary] = []
var _chart: NoteChart
var _hit_window: float
var _cur_index: int
var _prev_beat: float

func _ready() -> void:
	super._ready()

func set_hit_window(v: float) -> void:
	_hit_window = v

func update(curr_beat: float):
	while _cur_index < len(_actions):
		var action := _actions[_cur_index]

		if action["reported"]:
			_cur_index += 1
			continue

		if action["time"] <= curr_beat:
			action["reported"] = true
			_report_action(action)
			_cur_index += 1
		else:
			break
	
	_prev_beat = curr_beat

func _compile_chart(chart: NoteChart) -> void:
	_actions = []
	if not chart:
		return

	for part in chart.chart:
		if part is Note:
			add_note(part)
		if part is NoteSequence:
			add_sequence(part)
		if part is NoteSignal:
			add_note_signal(part)

	_actions.sort_custom(func(a, b):
		return a["time"] < b["time"]
	)

func set_chart(chart: NoteChart) -> void:
	_cur_index = 0
	_prev_beat = 0.0
	_chart = chart
	_compile_chart(_chart)

func _report_action(action: Dictionary) -> void:
	match action["type"]:
		"behavior_enter":
			emit_signal("note_behavior_enter", action["note"])

		"hit_window_open":
			emit_signal("note_hit_window_open", action["note"])

		"hit_window_close":
			emit_signal("note_hit_window_close", action["note"])

		"behavior_exit":
			emit_signal("note_behavior_exit", action["note"])

		"sequence_start":
			emit_signal("sequence_started", action["sequence"])

		"sequence_end":
			emit_signal("sequence_ended", action["sequence"])

		"hit":
			emit_signal("note_hit", action["note"])
		
		"signal":
			note_signal.emit(action["note"])

func _insert_action_sorted(action: Dictionary) -> void:
	var idx := _actions.bsearch_custom(action, func(a, b): return a["time"] < b["time"])
	_actions.insert(idx, action)

#region Note API
func add_note(note: Note) -> void:
	var pre_t  = note.hit_time - note.type.behavior_pre_offset
	var hw_open = note.hit_time - _hit_window
	var hw_close = note.hit_time + _hit_window
	var post_t = note.hit_time + note.type.behavior_post_offset

	if pre_t <= _prev_beat:
		push_warning("Cannot insert note: first action occurs in the past.")
		return

	_insert_action_sorted({
		"time": pre_t,
		"type": "behavior_enter",
		"note": note,
		"reported": false,
	})
	
	_insert_action_sorted({
		"time": note.hit_time,
		"type": "hit",
		"note": note,
		"reported": false,
	})

	_insert_action_sorted({
		"time": hw_open,
		"type": "hit_window_open",
		"note": note,
		"reported": false,
	})

	_insert_action_sorted({
		"time": hw_close,
		"type": "hit_window_close",
		"note": note,
		"reported": false,
	})

	_insert_action_sorted({
		"time": post_t,
		"type": "behavior_exit",
		"note": note,
		"reported": false,
	})

func _quantize(time: float, note_type: NoteType) -> float:
	return _quantize_to_measure_parts(time, note_type.enter_measure_parts)

func _quantize_to_measure_parts(time: float, parts: Array[float]) -> float:
	if parts.is_empty():
		return ceil(time)

	var beats_per_measure := orchestrator.beats_per_measure
	var current_measure := orchestrator.measure

	parts.sort()

	# Try current measure
	for part in parts:
		var candidate := current_measure * beats_per_measure \
			+ part * beats_per_measure

		if candidate >= time:
			return candidate

	# Fallback: next measure
	var next_measure := current_measure + 1
	return next_measure * beats_per_measure \
		+ parts[0] * beats_per_measure

func add_note_auto(note: Note) -> float:
	# Compute the earliest possible hit time such that
	# all derived action times are still in the future.
	var needed_enter_time := orchestrator.beat + EPS
	
	var enter_time := _quantize_to_measure_parts(
		needed_enter_time,
		note.type.enter_measure_parts
	)
	
	var hit_time := enter_time + note.type.behavior_pre_offset
	note.hit_time = hit_time

	add_note(note)
	return hit_time

func add_note_signal(note_signal: NoteSignal) -> void:
	_insert_action_sorted({
		"time": note_signal.start_time,
		"type": "signal",
		"reported": false,
	})
#endregion

#region Sequence API
func _resolve_sequence_enter_time(sequence: NoteSequence) -> float:
	if sequence.start_time > 0.0:
		return sequence.start_time

	var needed_enter_time := orchestrator.beat + EPS

	return _quantize_to_measure_parts(
		needed_enter_time,
		sequence.enter_measure_parts
	)

func _compute_sequence_end_time(sequence: NoteSequence) -> float:
	var max_time := 0.0

	for note in sequence.notes:
		var note_end := note.hit_time + note.type.behavior_post_offset
		if note_end > max_time:
			max_time = note_end

	return sequence.start_time + max_time

func _add_sequence_start(sequence: NoteSequence) -> void:
	_insert_action_sorted({
		"time": sequence.start_time,
		"type": "sequence_start",
		"sequence": sequence,
		"reported": false,
	})

func _add_sequence_end(sequence: NoteSequence) -> void:
	var end_time := _compute_sequence_end_time(sequence)

	_insert_action_sorted({
		"time": end_time,
		"type": "sequence_end",
		"sequence": sequence,
		"reported": false,
	})

func add_sequence(sequence: NoteSequence) -> float:
	_add_sequence_start(sequence)
	for note in sequence.notes:
		var note_copy: Note = note.duplicate()
		var original_hit := note_copy.hit_time
		note_copy.hit_time = sequence.start_time + original_hit
		add_note(note_copy)

	_add_sequence_end(sequence)

	return sequence.start_time

func add_sequence_auto(sequence: NoteSequence) -> float:
	var sequence_copy: NoteSequence = sequence.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	sequence_copy.start_time = 0.0
	var enter_time := _resolve_sequence_enter_time(sequence_copy)
	sequence_copy.start_time = enter_time

	if enter_time <= orchestrator.beat:
		push_warning("Cannot insert sequence: start_time is in the past.")
		return enter_time
	
	_add_sequence_start(sequence_copy)

	for note in sequence_copy.notes:
		var original_hit := note.hit_time
		note.hit_time = sequence_copy.start_time + original_hit
		print(note.type.action_name, " - ", note.hit_time)
		add_note(note)

	_add_sequence_end(sequence_copy)

	return sequence_copy.start_time
#endregion
