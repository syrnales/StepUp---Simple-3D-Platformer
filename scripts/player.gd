extends CharacterBody3D

@export_subgroup("Components")
var view: Node3D 

@export_subgroup("Properties")
@export var movement_speed = 250
@export var jump_strength = 7
@export var camera_sens = 0.003
@export var cameraLimitDeg = 40
@export var sync_position: Vector3
@export var sync_rotation: float
@export var sync_velocity: Vector3

var spawn_position: Vector3
var movement_velocity: Vector3
var rotation_direction: float
var gravity = 0
var previously_floored = false
var jump_single = true
var jump_double = true
var coins = 0


@onready var particles_trail = $ParticlesTrail
@onready var sound_footsteps = $SoundFootsteps
@onready var model = $Character
@onready var animation = $Character/AnimationPlayer

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	spawn_position = global_position
	sync_position = global_position
	sync_rotation = rotation.y
	
	if is_multiplayer_authority():
		view = get_tree().current_scene.get_node_or_null("View")
		if view:
			view.target = self
			var cam = view.get_node_or_null("Camera")
			if cam:
				cam.current = true

func _physics_process(delta):
	if is_multiplayer_authority():
		# 1. THIS IS YOU: Handle movement naturally
		handle_controls(delta)
		handle_gravity(delta)
		
		velocity.x = lerp(velocity.x, movement_velocity.x, delta * 10)
		velocity.z = lerp(velocity.z, movement_velocity.z, delta * 10)

		move_and_slide()

		if Vector2(velocity.z, velocity.x).length() > 0.1:
			rotation_direction = Vector2(-velocity.z, -velocity.x).angle()

		rotation.y = lerp_angle(rotation.y, rotation_direction, delta * 10)

		# Broadcast exact physical status to clients
		sync_position = global_position
		sync_rotation = rotation.y
		sync_velocity = velocity

		# Falling/respawning
		if position.y < spawn_position.y - 15:
			global_position = spawn_position
			get_tree().call_group("falling_platforms", "reset_platform")
			
	else:
		# 2. THIS IS A REMOTE PLAYER: Apply their exact network velocity
		velocity = sync_velocity
		
		# Make sure they feel gravity locally so the physics engine knows they are touching the floor
		if not is_on_floor():
			velocity.y -= 25 * delta
		elif velocity.y < 0:
			velocity.y = -2.0
			
		# Crucial: Using move_and_slide() allows Godot to automatically push them along moving platforms!
		move_and_slide()
		
		rotation.y = lerp_angle(rotation.y, sync_rotation, delta * 15)
		
		# Network Safeguard: Only force-snap their position if they drift way too far out of sync
		if global_position.distance_to(sync_position) > 1.0:
			global_position = sync_position

	# Visuals run for ALL players
	handle_visuals(delta)
	handle_effects(delta)

func handle_visuals(delta):
	model.scale = model.scale.lerp(Vector3(1, 1, 1), delta * 10)

	if is_on_floor() and gravity > 2 and !previously_floored:
		model.scale = Vector3(1.25, 0.75, 1.25)

	previously_floored = is_on_floor()

func handle_effects(delta):
	particles_trail.emitting = false
	sound_footsteps.stream_paused = true

	if is_on_floor():
		var horizontal_velocity = Vector2(velocity.x, velocity.z)
		var speed_factor = horizontal_velocity.length() / movement_speed / delta
		if speed_factor > 0.05:
			if animation.current_animation != "walk":
				animation.play("walk", 0.1)

			if speed_factor > 0.3:
				sound_footsteps.stream_paused = false
				sound_footsteps.pitch_scale = speed_factor

			if speed_factor > 0.75:
				particles_trail.emitting = true

		elif animation.current_animation != "idle":
			animation.play("idle", 0.1)
			
		if animation.current_animation == "walk":
			animation.speed_scale = speed_factor
		else:
			animation.speed_scale = 1.0
			
	elif animation.current_animation != "jump":
		animation.play("jump", 0.1)
		

func handle_controls(delta):
	var input := Vector3.ZERO

	input.x = Input.get_axis("move_left", "move_right")
	input.z = Input.get_axis("move_forward", "move_back")
	
	if view:
		input = input.rotated(Vector3.UP, view.rotation.y)

	if input.length() > 1:
		input = input.normalized()

	movement_velocity = input * movement_speed * delta

	if Input.is_action_just_pressed("jump"):
		if jump_single or jump_double:
			jump()

func handle_gravity(delta):
	# Apply gravity directly to the native velocity.y property
	if not is_on_floor():
		velocity.y -= 25 * delta
	else:
		jump_single = true
		
		# Keep a tiny bit of downward pressure to stick to moving platforms
		if velocity.y < -2.0:
			velocity.y = -2.0

func jump():
	Audio.play("res://resources/sounds/jump.ogg")
	
	velocity.y = jump_strength
	model.scale = Vector3(0.5, 1.5, 0.5)

	if jump_single:
		jump_single = false
		jump_double = true
	else:
		jump_double = false
