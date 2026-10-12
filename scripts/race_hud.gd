extends Control

@onready var timer_label: Label = $Timer
@onready var countdown_label: Label = $Countdown
@onready var start_button: Button = $StartButton
@onready var results_label: Label = $Results

var i_finished := false
var showing_results := false

func _ready() -> void:
	countdown_label.hide()
	results_label.hide()
	start_button.pressed.connect(func(): Race.start_race())
	Race.countdown_tick.connect(_on_tick)
	Race.state_changed.connect(_on_state)
	Race.player_finished.connect(_on_finished)
	Race.race_ended.connect(_show_results)

func _process(_delta: float) -> void:
	start_button.visible = multiplayer.is_server() \
		and Race.state == Race.State.LOBBY \
		and not showing_results

	# Timer only runs while racing AND this player hasn't finished
	if Race.state == Race.State.RACING and not i_finished:
		timer_label.text = _fmt(Race.get_elapsed())

func _on_state(s: int) -> void:
	if s == Race.State.COUNTDOWN:
		i_finished = false
		showing_results = false
		results_label.hide()
		results_label.modulate.a = 1.0
		timer_label.text = "0:00.00"
	

func _on_tick(n: int) -> void:
	countdown_label.show()
	countdown_label.text = str(n) if n > 0 else "GO!"
	if n == 0:
		await get_tree().create_timer(0.8).timeout
		countdown_label.hide()

func _on_finished(id: int, time: float, _place: int) -> void:
	if id != multiplayer.get_unique_id():
		return
	i_finished = true
	timer_label.text = _fmt(time)   # frozen at the server-confirmed time
	# No center label here anymore, so it can't overlap "Finished"

const FADE_TIME := 0.5

func _show_results(results: Array) -> void:
	showing_results = true

	# Wait for the "Finished" text to fade out first
	var finished_label = get_tree().current_scene.get_node_or_null("UI/Texts/Finished")
	if finished_label:
		while finished_label.visible:
			await get_tree().process_frame

	var text := "RESULTS\n"
	for r in results:
		text += "%d. Player %s   %s\n" % [r.place, str(r.id).left(4), _fmt(r.time)]
	if results.is_empty():
		text += "Nobody finished!"
	results_label.text = text

	# Fade in
	results_label.modulate.a = 0.0
	results_label.show()
	var fade_in = create_tween()
	fade_in.tween_property(results_label, "modulate:a", 1.0, FADE_TIME)
	await fade_in.finished

	# Stay visible (the fade time is part of the total display time)
	await get_tree().create_timer(Race.RESULTS_DELAY - FADE_TIME * 2.0).timeout

	# Fade out
	var fade_out = create_tween()
	fade_out.tween_property(results_label, "modulate:a", 0.0, FADE_TIME)
	await fade_out.finished

	results_label.hide()
	countdown_label.hide()
	showing_results = false

func _fmt(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]
