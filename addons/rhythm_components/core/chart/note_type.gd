class_name ChartNoteType
extends Resource

@export var action_name: StringName

@export var release_on_beat: bool = false
var on_hold: Callable

# Time (in beats) before the actual hit time to enter
@export var behavior_pre_offset: float
var on_behavior_enter: Callable

var on_hit: Callable

@export var behavior_post_offset: float
var on_behavior_exit: Callable

# which parts of the measure could be entered
@export var enter_measure_parts: Array[float]
