extends Area3D

@onready var checkpoint_reached: Label = $"../../../UI/Texts/CheckpointReached"

func _on_body_entered(body: Node3D) -> void:
	if "spawn_position" in body and body.is_multiplayer_authority():
		body.spawn_position = global_position + Vector3(0, 2, 0)
		print("Checkpoint")
		
