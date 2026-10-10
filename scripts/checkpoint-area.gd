extends Area3D

@export var is_final_checkpoint: bool = false
var has_triggered_win: bool = false

func _on_body_entered(body: Node3D) -> void:
	# 1. Use get_unique_id() to absolutely guarantee this block ONLY runs when YOUR character touches it.
	if "spawn_position" in body and body.name == str(multiplayer.get_unique_id()):
		body.spawn_position = global_position + Vector3(0, 2, 0)
		print("Checkpoint")
		
		# 2. Check if this is the final checkpoint and nobody has won yet
		if is_final_checkpoint and not has_triggered_win:
			# 3. Tell the OTHER player over the network to lock their checkpoint!
			rpc("lock_checkpoint_for_losers")
			
			has_triggered_win = true
			_show_win_text()

# This RPC (Remote Procedure Call) executes on the OTHER player's computer over the internet
@rpc("any_peer", "call_remote", "reliable")
func lock_checkpoint_for_losers():
	has_triggered_win = true

func _show_win_text():
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
