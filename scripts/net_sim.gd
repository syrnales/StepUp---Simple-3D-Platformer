extends Node
## Autoload as "NetSim".
## Degrades the link of the instance it runs on (clients only; the host is never delayed):
##   - client -> server packets are delayed/dropped before sending
##   - server -> client packets are delayed/dropped before the client processes them
## Reliable RPCs (Race, spawning, ...) are NOT touched, only the player input/state streams.

const PRESETS := [
	{"name": "LAN",      "rtt": 0,   "jitter": 0,   "loss": 0.0},
	{"name": "Good",     "rtt": 60,  "jitter": 10,  "loss": 0.0},
	{"name": "Mobile",   "rtt": 150, "jitter": 30,  "loss": 1.0},
	{"name": "Bad",      "rtt": 300, "jitter": 60,  "loss": 5.0},
	{"name": "Terrible", "rtt": 500, "jitter": 100, "loss": 10.0},
]

# --- settings (change with hotkeys) ---
var enabled := true
var rtt_ms := 150.0
var jitter_ms := 30.0
var loss_pct := 0.0
var prediction_enabled := true
var show_ghost := false
var _preset_index := 2
var overlay_visible := false

# --- stats written by the local player ---
var pending_count := 0
var last_error := 0.0
var max_error := 0.0
var snaps := 0

var _label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	if not OS.is_debug_build():
		enabled = false
		prediction_enabled = true
		show_ghost = false
		set_process_unhandled_input(false)
		set_process(false)
	
	_label = Label.new()
	_label.position = Vector2(12, 12)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.visible = overlay_visible
	layer.add_child(_label)
	_apply_preset(_preset_index)

## Pass every simulated packet through here. `fn` runs after the simulated delay (or never, if dropped).
func run(owner: Object, fn: Callable) -> void:
	if multiplayer.is_server() or not enabled:
		fn.call()
		return
	if randf() * 100.0 < loss_pct:
		return
	var one_way := rtt_ms * 0.5 + randf_range(-jitter_ms, jitter_ms) * 0.5
	var delay := maxf(0.0, one_way) / 1000.0
	if delay <= 0.0:
		fn.call()
		return
	get_tree().create_timer(delay).timeout.connect(func():
		if is_instance_valid(owner):
			fn.call())


func reset_stats() -> void:
	last_error = 0.0
	max_error = 0.0
	snaps = 0


func _apply_preset(i: int) -> void:
	_preset_index = i % PRESETS.size()
	var p: Dictionary = PRESETS[_preset_index]
	rtt_ms = p.rtt
	jitter_ms = p.jitter
	loss_pct = p.loss
	reset_stats()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F1:
			prediction_enabled = not prediction_enabled
			reset_stats()
		KEY_F2:
			enabled = not enabled
		KEY_F3:
			_apply_preset(_preset_index + 1)
		KEY_F4:
			show_ghost = not show_ghost
		KEY_F5:
			rtt_ms = maxf(0.0, rtt_ms - 50.0)
		KEY_F6:
			rtt_ms += 50.0
		KEY_F7:
			loss_pct = maxf(0.0, loss_pct - 2.5)
		KEY_F8:
			loss_pct += 2.5
		KEY_F9:
			overlay_visible = not overlay_visible
			_label.visible = overlay_visible
			show_ghost = overlay_visible


func _process(_delta: float) -> void:
	var lines: PackedStringArray = []
	lines.append("PREDICTION: %s   [F1]" % ("ON" if prediction_enabled else "OFF"))
	lines.append("[F9] hide this panel")
	if multiplayer.is_server():
		lines.append("Host: link simulation is inactive here (run it on a client)")
	else:
		lines.append("Link: %s  %d ms RTT, +/-%d ms jitter, %.1f%% loss/direction   [F2 on/off, F3 preset, F5/F6 RTT, F7/F8 loss]"
			% ["SIM ON" if enabled else "SIM OFF", rtt_ms, jitter_ms, loss_pct])
		lines.append("Unacked inputs: %d (~%d ms)   Last correction: %.3f m   Max: %.3f m   Snaps: %d"
			% [pending_count, pending_count * 1000 / maxi(1, Engine.physics_ticks_per_second), last_error, max_error, snaps])
		lines.append("Red ghost = last server position received   [F4]")
	_label.text = "\n".join(lines)
		
