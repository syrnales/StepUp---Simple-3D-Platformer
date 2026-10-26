extends Node

const PATH := "user://settings.cfg"

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		set_fullscreen(cfg.get_value("display", "fullscreen", false), false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var enter: bool = event.keycode in [KEY_ENTER, KEY_KP_ENTER]
		if event.keycode == KEY_F11 or (enter and event.alt_pressed):
			toggle()

func is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

func toggle() -> void:
	set_fullscreen(not is_fullscreen())

func set_fullscreen(on: bool, save := true) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	if save:
		var cfg := ConfigFile.new()
		cfg.load(PATH)
		cfg.set_value("display", "fullscreen", on)
		cfg.save(PATH)
