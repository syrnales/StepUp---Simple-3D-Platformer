extends Node3D

@export var move_offset := Vector3(12, 0, 0) 
@export var time : float = 5.0
@export var pause : float = 0.7
@export var sync_position: Vector3

var start_pos: Vector3
var end_pos: Vector3

func _enter_tree():
	# Make sure the Host (Peer ID 1) is always in charge of this platform
	set_multiplayer_authority(1)

func _ready() -> void:
	start_pos = global_position
	end_pos = global_position + move_offset
	sync_position = global_position
	
	if is_multiplayer_authority():
		_move_platform()

func _move_platform():
	var move_tween = create_tween().set_loops().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	
	# Notice we are using global_position instead of position to prevent bugs!
	move_tween.tween_property(self, "global_position", end_pos, time) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	move_tween.tween_interval(pause)
	
	move_tween.tween_property(self, "global_position", start_pos, time) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	move_tween.tween_interval(pause)

func _physics_process(delta):
	if is_multiplayer_authority():
		# Host constantly updates the network variable
		sync_position = global_position
	else:
		# Client smoothly glides their platform to perfectly match the Host's platform
		global_position = global_position.lerp(sync_position, delta * 15)
