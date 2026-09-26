extends Node3D

@export var respawn_time: float = 1.5

var falling := false
var fall_velocity := 0.0
var start_position: Vector3

func _ready():
	start_position = global_position
	add_to_group("falling_platforms")

func _physics_process(delta):
	scale = scale.lerp(Vector3(1, 1, 1), delta * 10)
	
	if falling:
		fall_velocity += 8.0 * delta
		global_position.y -= fall_velocity * delta
	else:
		fall_velocity = 0.0
	
	if global_position.y < start_position.y - 15:
		hide()
		set_physics_process(false)
		_trigger_respawn()

func _on_body_entered(_body):
	if !falling:
		Audio.play("res://resources/sounds/fall.ogg")
		scale = Vector3(1.25, 1, 1.25)
		falling = true

func _trigger_respawn():
	await get_tree().create_timer(respawn_time).timeout
	reset_platform()

func reset_platform():
	global_position = start_position
	falling = false
	fall_velocity = 0.0
	
	scale = Vector3.ZERO 
	
	show()
	set_physics_process(true)
