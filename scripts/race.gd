extends Node

signal state_changed(state: int)
signal countdown_tick(n: int)        # 3, 2, 1, 0 (0 = GO)
signal player_finished(id: int, time: float, place: int)
signal race_ended(results: Array)

enum State { LOBBY, COUNTDOWN, RACING }

const COUNTDOWN_SECONDS := 3
const TIME_LIMIT := 180.0
const RESULTS_DELAY := 8.0

var state := State.LOBBY
var race_start_ms := 0
var results: Array = []              # [{id, time, place}]  (server-authoritative)

func get_elapsed() -> float:
	if state != State.RACING:
		return 0.0
	return (Time.get_ticks_msec() - race_start_ms) / 1000.0

func _players() -> Node:
	return get_tree().current_scene.get_node("Players")

func _start_pos() -> Vector3:
	var marker = get_tree().current_scene.get_node_or_null("World/StartLine")
	if marker == null:
		push_error("Race: couldn't find World/StartLine under the main scene")
		return Vector3.ZERO
	return marker.global_position	

func _my_player() -> Node:
	return _players().get_node_or_null(str(multiplayer.get_unique_id()))

# ---------- Server entry point (call from the Start button) ----------
func start_race() -> void:
	if not multiplayer.is_server() or state != State.LOBBY:
		return
	results.clear()

	# Assign each player a grid slot
	var spawns: Dictionary = {}
	var i := 0
	var start_pos: Vector3 = _start_pos()
	for p in _players().get_children():
		var offset := Vector3((i % 4) * 1.5 - 2.25, 0, (i / 4) * 1.5)
		spawns[p.name.to_int()] = start_pos + offset
		i += 1

	_begin_countdown.rpc(spawns)

@rpc("authority", "call_local", "reliable")
func _begin_countdown(spawns: Dictionary) -> void:
	_set_state(State.COUNTDOWN)

	# Each peer teleports and freezes only its own player (it owns it)
	var me = _my_player()
	if me:
		me.reset_for_race(spawns.get(multiplayer.get_unique_id(), me.global_position))
		me.can_move = false

	for n in range(COUNTDOWN_SECONDS, 0, -1):
		countdown_tick.emit(n)
		await get_tree().create_timer(1.0).timeout

	countdown_tick.emit(0)  # GO!
	race_start_ms = Time.get_ticks_msec()
	if me:
		me.can_move = true
	_set_state(State.RACING)

	if multiplayer.is_server():
		_watch_time_limit()

func _watch_time_limit() -> void:
	await get_tree().create_timer(TIME_LIMIT).timeout
	if state == State.RACING:
		_finish_race()

# ---------- Called by the finish line (server only) ----------
func report_finish(id: int) -> void:
	if not multiplayer.is_server() or state != State.RACING:
		return
	for r in results:
		if r.id == id:
			return  # already finished
	var t := get_elapsed()
	var place := results.size() + 1
	results.append({"id": id, "time": t, "place": place})
	_announce_finish.rpc(id, t, place)

	if results.size() >= _players().get_child_count():
		_finish_race()

@rpc("authority", "call_local", "reliable")
func _announce_finish(id: int, time: float, place: int) -> void:
	player_finished.emit(id, time, place)

func _finish_race() -> void:
	if state != State.RACING:
		return
	_end_race.rpc(results)
	await get_tree().create_timer(RESULTS_DELAY).timeout
	_back_to_lobby.rpc()

@rpc("authority", "call_local", "reliable")
func _end_race(final_results: Array) -> void:
	results = final_results
	_set_state(State.LOBBY)  # lets players free-roam again
	race_ended.emit(final_results)

@rpc("authority", "call_local", "reliable")
func _back_to_lobby() -> void:
	var me = _my_player()
	if me:
		me.reset_for_race(_start_pos())
		me.can_move = true

@rpc("any_peer", "call_remote", "reliable")
func request_finish() -> void:
	if multiplayer.is_server():
		report_finish(multiplayer.get_remote_sender_id())

func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)
