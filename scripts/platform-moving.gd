extends Node3D

@export var pos_a := Vector3()
@export var pos_b := Vector3()
@export var time : float = 2.0
@export var pause : float = 0.7

func _ready() -> void:
	_move_platform()

func _move_platform():
	var move_tween = create_tween().set_loops().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	
	# Move to B
	move_tween.tween_property(self, "position", pos_b, time) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	move_tween.tween_interval(pause)
	
	# Move back to A
	move_tween.tween_property(self, "position", pos_a, time) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	move_tween.tween_interval(pause)
