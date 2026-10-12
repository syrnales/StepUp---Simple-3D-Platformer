extends Area3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	# Only the server judges the finish
	if multiplayer.is_server() and body is CharacterBody3D:
		Race.report_finish(body.name.to_int())
