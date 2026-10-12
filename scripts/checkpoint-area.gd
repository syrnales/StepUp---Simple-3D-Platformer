extends Area3D

@export var is_final_checkpoint: bool = false

func _ready() -> void:
	# Remove this line if you already connected body_entered in the editor
	body_entered.connect(_on_body_entered)
	if is_final_checkpoint:
		Race.player_finished.connect(_on_player_finished)

func _on_body_entered(body: Node3D) -> void:
	# Only react to YOUR character
	if not ("spawn_position" in body and body.name == str(multiplayer.get_unique_id())):
		return

	body.spawn_position = global_position + Vector3(0, 2, 0)

	if is_final_checkpoint and Race.state == Race.State.RACING:
		if multiplayer.is_server():
			Race.report_finish(multiplayer.get_unique_id())
		else:
			Race.request_finish.rpc_id(1)

# Runs on every peer when the server confirms someone finished
func _on_player_finished(id: int, _time: float, _place: int) -> void:
	if id == multiplayer.get_unique_id():
		_show_win_text()

func _show_win_text() -> void:
	var win_text = get_tree().current_scene.get_node_or_null("UI/Texts/Finished")
	if win_text:
		win_text.show()
		win_text.scale = Vector2(1, 1)
		win_text.modulate.a = 0.0

		var tween = create_tween()
		tween.tween_property(win_text, "modulate:a", 1.0, 0.5)
		tween.tween_interval(2.0)
		tween.tween_property(win_text, "modulate:a", 0.0, 1.0)
		tween.tween_callback(win_text.hide)
