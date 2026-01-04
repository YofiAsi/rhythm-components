class_name RhythmInputListener
extends RhythmComponent

signal player_input_event(
	action_name: StringName,
	event: InputEvent
)

var actions: Array[StringName] = []
var enabled: bool = true

func _ready() -> void:
	super._ready()

func set_enabled(v: bool) -> void:
	enabled = v

func is_enabled() -> bool:
	return enabled

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if not event.is_action_type():
		return
	for action in actions:
		if event.is_action(action):
			_handle_action_event(action, event)

func _handle_action_event(action: StringName, event: InputEvent) -> void:
	player_input_event.emit(action, event)

func set_actions(_actions: Array[StringName]) -> void:
	actions = _actions
