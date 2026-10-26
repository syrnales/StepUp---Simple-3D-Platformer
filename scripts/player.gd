extends CharacterBody3D
## Server-authoritative movement with client-side prediction.
##
## Roles (all decided from the node name = owner's peer id; authority stays with the server):
##   HOST'S OWN PLAYER : samples input and simulates directly, broadcasts state.
##   REMOTE PLAYER ON HOST : server pops queued commands from that client and simulates them.
##   LOCAL PLAYER ON CLIENT : samples input -> pending queue -> (predict) -> send to server;
##                            when server state arrives: rewind, replay pending, smooth the error.
##   OTHER PLAYERS ON CLIENT : just follow the latest server state.

# ---- Gameplay tunables (must be identical on every peer) ----
@export var move_speed := 4.2
@export var jump_strength := 7.0
@export var gravity := 25.0
@export var max_jumps := 2

# ---- Netcode tunables ----
const REDUNDANCY := 6            # unacked commands re-sent in every packet (covers packet loss)
const MAX_PENDING := 120         # client safety cap
const MAX_SERVER_BACKLOG := 4    # server processes 2 cmds/tick above this to catch up
const STATE_EVERY := 2           # server sends state every N physics ticks (30 Hz at 60 tps)
const SNAP_DISTANCE := 2.0       # error above this teleports instead of smoothing
const SMOOTH_RATE := 12.0        # how fast the visual error fades (higher = faster)
const GHOST_OFFSET := Vector3(0, 0.8, 0)

var view: Node3D
var spawn_position: Vector3      # last checkpoint (also set by checkpoint_area.gd on every peer)
var can_move := true             # set by Race (only affects input sampling)
var epoch := 0                   # bumped on every race reset so stale packets are ignored
var lobby_position: Vector3

var owner_id := 0
var is_local := false
var dt := 1.0 / 60.0

# --- simulation state (this is what the server snapshots) ---
var jumps_left := 0
var sim_on_floor := false

# --- client side ---
var seq := 0
var pending: Array = []          # commands sent but not yet acknowledged by the server
var latest_state: Dictionary = {}
var got_first_state := false
var _fresh_state := false
var visual_offset := Vector3.ZERO
var model_base_pos := Vector3.ZERO
var ghost: MeshInstance3D

# --- server side ---
var queue: Array = []            # input queue: commands received from the owning client
var last_queued_seq := 0
var last_seq := 0                # last command actually simulated
var server_tick := 0

# --- visuals ---
var rotation_direction := 0.0
var previously_floored := false
var _fall_vy := 0.0

@onready var particles_trail = $ParticlesTrail
@onready var sound_footsteps = $SoundFootsteps
@onready var model = $Character
@onready var animation = $Character/AnimationPlayer


func _ready() -> void:
	owner_id = name.to_int()
	is_local = owner_id == multiplayer.get_unique_id()
	dt = 1.0 / Engine.physics_ticks_per_second
	spawn_position = global_position
	lobby_position = global_position
	jumps_left = max_jumps
	model_base_pos = model.position

	if is_local:
		view = get_tree().current_scene.get_node_or_null("View")
		if view:
			view.target = self
			var cam = view.get_node_or_null("Camera")
			if cam:
				cam.current = true
		if not multiplayer.is_server():
			_make_ghost()


func _make_ghost() -> void:
	ghost = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.4
	mesh.height = 1.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.2, 0.2, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	ghost.mesh = mesh
	ghost.top_level = true
	add_child(ghost)


# =====================================================================
#  Main loop
# =====================================================================

func _physics_process(_delta: float) -> void:
	_fall_vy = velocity.y

	if multiplayer.is_server():
		_server_tick()
	elif is_local:
		_client_tick()
	else:
		_follow_state(15.0)

	if Vector2(velocity.x, velocity.z).length() > 0.1:
		rotation_direction = Vector2(-velocity.z, -velocity.x).angle()
	rotation.y = lerp_angle(rotation.y, rotation_direction, dt * 10.0)

	handle_visuals(dt)
	handle_effects()


func _process(delta: float) -> void:
	# Smoothly fade out the prediction error: the BODY is already correct,
	# only the model is drawn offset so nothing visibly snaps.
	visual_offset = visual_offset.lerp(Vector3.ZERO, 1.0 - exp(-SMOOTH_RATE * delta))
	model.global_position = to_global(model_base_pos) + visual_offset

	if ghost:
		ghost.visible = NetSim.show_ghost and not latest_state.is_empty()
		if ghost.visible:
			ghost.global_position = latest_state.pos + GHOST_OFFSET


# =====================================================================
#  The deterministic simulation step (runs identically on client & server)
# =====================================================================

func _simulate(cmd: Dictionary, replay: bool) -> void:
	velocity.x = lerp(velocity.x, cmd.mx * move_speed, dt * 10.0)
	velocity.z = lerp(velocity.z, cmd.mz * move_speed, dt * 10.0)

	if sim_on_floor:
		jumps_left = max_jumps
		if velocity.y < 0.0:
			velocity.y = -2.0   # stick to the floor
	else:
		velocity.y -= gravity * dt
		jumps_left = mini(jumps_left, max_jumps - 1)  # walking off a ledge costs the ground jump

	var did_jump := false
	if cmd.jump and jumps_left > 0:
		velocity.y = jump_strength
		jumps_left -= 1
		did_jump = true

	move_and_slide()
	sim_on_floor = is_on_floor()

	if global_position.y < spawn_position.y - 15.0:
		global_position = spawn_position
		velocity = Vector3.ZERO
		if not replay and is_local:
			get_tree().call_group("falling_platforms", "reset_platform")

	# Side effects only on real (non-replayed) steps
	if did_jump and not replay and is_local:
		Audio.play("res://resources/sounds/jump.ogg")
		model.scale = Vector3(0.5, 1.5, 0.5)


func _sample_input() -> Dictionary:
	var mx := 0.0
	var mz := 0.0
	var jump := false
	if can_move:
		var input := Vector3(
			Input.get_axis("move_left", "move_right"), 0.0,
			Input.get_axis("move_forward", "move_back"))
		if view:
			input = input.rotated(Vector3.UP, view.rotation.y)
		input = input.limit_length(1.0)
		mx = input.x
		mz = input.z
		jump = Input.is_action_just_pressed("jump")
	seq += 1
	# Movement is stored in WORLD space, so the server never needs the camera.
	return {"seq": seq, "epoch": epoch, "mx": mx, "mz": mz, "jump": jump}


# =====================================================================
#  Server
# =====================================================================

func _server_tick() -> void:
	server_tick += 1

	if is_local:
		# Host's own character: no network in between.
		var cmd := _sample_input()
		_simulate(cmd, false)
		last_seq = cmd.seq
	else:
		var steps := 2 if queue.size() > MAX_SERVER_BACKLOG else 1
		for i in steps:
			if queue.is_empty():
				break   # starved: wait for the next packet
			var cmd: Dictionary = queue.pop_front()
			_simulate(cmd, false)
			last_seq = cmd.seq

	if server_tick % STATE_EVERY == 0:
		_broadcast_state()


func _broadcast_state() -> void:
	var s := {
		"tick": server_tick, "epoch": epoch, "seq": last_seq,
		"pos": global_position, "vel": velocity,
		"jumps": jumps_left, "floor": sim_on_floor,
	}
	for peer in multiplayer.get_peers():
		_rpc_state.rpc_id(peer, s)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_cmds(batch: Array) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner_id:
		return   # you can only drive your own character
	for c in batch:
		if c.epoch != epoch or c.seq <= last_queued_seq:
			continue   # stale race epoch, or duplicate from the redundancy window
		last_queued_seq = c.seq
		queue.append(c)


# =====================================================================
#  Client
# =====================================================================

@rpc("authority", "call_remote", "unreliable")
func _rpc_state(s: Dictionary) -> void:
	# Pass the packet through the simulated bad connection
	NetSim.run(self, func(): _on_state(s))


func _on_state(s: Dictionary) -> void:
	if not got_first_state:
		got_first_state = true
		epoch = s.epoch          # late joiners adopt the server's epoch
		global_position = s.pos
	if s.epoch != epoch:
		return                   # packet from before a race reset
	if not latest_state.is_empty() and s.tick <= latest_state.tick:
		return                   # reordered / old packet
	latest_state = s
	_fresh_state = true          # applied at the start of the next PHYSICS tick (see below)


func _client_tick() -> void:
	# 1) Apply the newest authoritative state. This must happen inside the physics
	#    tick, because move_and_slide() only uses the fixed delta there.
	if _fresh_state:
		_fresh_state = false
		_acknowledge(latest_state)
		if NetSim.prediction_enabled:
			_reconcile(latest_state)

	# 2) Sample input and put it in the pending queue
	var cmd := _sample_input()
	pending.append(cmd)
	if pending.size() > MAX_PENDING:
		pending.pop_front()
	NetSim.pending_count = pending.size()

	# 3) Predict, or wait for the server
	if NetSim.prediction_enabled:
		_simulate(cmd, false)
	else:
		_follow_state(20.0)

	# 4) Send the last few unacked commands (redundancy covers lost packets)
	var n := mini(pending.size(), REDUNDANCY)
	var batch := pending.slice(pending.size() - n)
	NetSim.run(self, func(): _rpc_cmds.rpc_id(1, batch))


func _acknowledge(s: Dictionary) -> void:
	while not pending.is_empty() and pending[0].seq <= s.seq:
		pending.pop_front()


func _reconcile(s: Dictionary) -> void:
	var before := global_position

	# Rewind to the server's truth...
	global_position = s.pos
	velocity = s.vel
	jumps_left = s.jumps
	sim_on_floor = s.floor

	# ...and replay every command the server hasn't processed yet.
	for c in pending:
		_simulate(c, true)

	# Where we are now vs. where we were drawing the player = the prediction error.
	var err := before - global_position
	var mag := err.length()
	NetSim.last_error = mag
	NetSim.max_error = maxf(NetSim.max_error, mag)

	if mag > SNAP_DISTANCE:
		visual_offset = Vector3.ZERO     # too far off (respawn, teleport): just snap
		NetSim.snaps += 1
	else:
		# Keep the picture where it was, then let _process() fade the offset out.
		visual_offset = (visual_offset + err).limit_length(SNAP_DISTANCE)


## Used by remote players, and by the local player when prediction is OFF.
func _follow_state(rate: float) -> void:
	if latest_state.is_empty():
		return
	global_position = global_position.lerp(latest_state.pos, 1.0 - exp(-rate * dt))
	velocity = latest_state.vel
	sim_on_floor = latest_state.floor


# =====================================================================
#  Race hook (call on EVERY peer for EVERY player, see race.gd changes)
# =====================================================================

func reset_for_race(pos: Vector3) -> void:
	epoch += 1
	global_position = pos
	spawn_position = pos
	velocity = Vector3.ZERO
	jumps_left = max_jumps
	pending.clear()
	queue.clear()
	latest_state = {}
	_fresh_state = false
	visual_offset = Vector3.ZERO


# =====================================================================
#  Visuals / effects (same behaviour as before)
# =====================================================================

func handle_visuals(delta: float) -> void:
	model.scale = model.scale.lerp(Vector3.ONE, delta * 10.0)

	if sim_on_floor and not previously_floored and _fall_vy < -6.0:
		model.scale = Vector3(1.25, 0.75, 1.25)

	previously_floored = sim_on_floor


func handle_effects() -> void:
	particles_trail.emitting = false
	sound_footsteps.stream_paused = true

	if sim_on_floor:
		var speed_factor := Vector2(velocity.x, velocity.z).length() / move_speed
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

		animation.speed_scale = speed_factor if animation.current_animation == "walk" else 1.0
	elif animation.current_animation != "jump":
		animation.play("jump", 0.1)
