extends Node3D

@export var pos_a := Vector3()
@export var pos_b := Vector3()
@export var time : float = 2.0
@export var pause : float = 0.7

@onready var static_body: StaticBody3D = $"platform-medium2#StaticBody3D"

var previous_position: Vector3

func _ready() -> void:
	previous_position = global_position
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

func _physics_process(delta):
	var current_velocity = (global_position - previous_position) / delta
	
	if static_body:
		static_body.constant_linear_velocity = current_velocity

	previous_position = global_position
