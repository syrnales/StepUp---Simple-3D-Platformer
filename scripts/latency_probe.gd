extends Node
## Autoload as "LatencyProbe". Run it in the CLIENT window.
## F10 = print a summary to the Output panel and clear the samples.
##
## M1 Input response time: ms from "move key pressed while standing still"
##    to "the drawn model has visibly moved MOVE_THRESHOLD metres".
## M3 Steady-run smoothness: coefficient of variation (stdev / mean) of the
##    drawn horizontal speed per frame while a move key is held steadily.

const MOVE_THRESHOLD := 0.01   # metres of drawn movement that counts as "responded"
const STEADY_AFTER := 1.0      # seconds of held input before smoothness sampling starts

var response_ms: Array[float] = []
var frame_speeds: Array[float] = []

var _waiting := false
var _armed := true
var _t_press := 0
var _start_pos := Vector3.ZERO
var _last_pos := Vector3.ZERO
var _held := 0.0


func _player() -> Node:
	return get_tree().current_scene.get_node_or_null("Players/%d" % multiplayer.get_unique_id())


func _process(delta: float) -> void:
	var p = _player()
	if p == null:
		return

	var drawn: Vector3 = p.model.global_position
	var pressing := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.1
	var still: bool = p.velocity.length() < 0.2

	# --- M1: input response time ---
	if pressing and _armed and still and not _waiting:
		_waiting = true
		_armed = false
		_t_press = Time.get_ticks_usec()
		_start_pos = drawn
	elif _waiting:
		if not pressing:
			_waiting = false     # released before any movement: discard
		elif drawn.distance_to(_start_pos) > MOVE_THRESHOLD:
			response_ms.append((Time.get_ticks_usec() - _t_press) / 1000.0)
			_waiting = false
	if not pressing and still:
		_armed = true            # ready for the next standstill-to-move sample

	# --- M3: smoothness while running steadily ---
	_held = _held + delta if pressing else 0.0
	if _held > STEADY_AFTER and delta > 0.0:
		var step := Vector2(drawn.x - _last_pos.x, drawn.z - _last_pos.z).length()
		frame_speeds.append(step / delta)
	_last_pos = drawn


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		_print_summary()
		response_ms.clear()
		frame_speeds.clear()


func _print_summary() -> void:
	print("=== LatencyProbe ===")
	print("Prediction: %s | Sim: %s | RTT %d ms | jitter %d ms | loss %.1f%%" % [
		"ON" if NetSim.prediction_enabled else "OFF",
		"ON" if NetSim.enabled else "OFF",
		NetSim.rtt_ms, NetSim.jitter_ms, NetSim.loss_pct])
	print("M1 input response (ms): ", _stats(response_ms))
	var mean := _mean(frame_speeds)
	var cv := 0.0
	if mean > 0.0:
		cv = _sd(frame_speeds, mean) / mean
	print("M3 steady-run frames: n=%d  mean speed=%.2f m/s  CV=%.3f" % [frame_speeds.size(), mean, cv])
	print("M4 last correction %.3f m | max %.3f m | snaps %d | unacked inputs %d" % [
		NetSim.last_error, NetSim.max_error, NetSim.snaps, NetSim.pending_count])


func _mean(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += v
	return t / a.size()


func _sd(a: Array[float], mean: float) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += (v - mean) * (v - mean)
	return sqrt(t / a.size())


func _stats(a: Array[float]) -> String:
	if a.is_empty():
		return "no samples"
	var s: Array[float] = a.duplicate()
	s.sort()
	var mean := _mean(s)
	return "n=%d mean=%.1f median=%.1f p95=%.1f min=%.1f max=%.1f sd=%.2f" % [
		s.size(), mean, s[int(s.size() * 0.5)], s[mini(s.size() - 1, int(s.size() * 0.95))],
		s[0], s[s.size() - 1], _sd(s, mean)]
