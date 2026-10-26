extends Node

var num_players = 12
var bus = "master"

var available = []  # The available players.
var queue = []  # The queue of sounds to play.

var music_player: AudioStreamPlayer
var music_volume_db := -12.0
var music_mode := ""            # "", "menu" or "playlist"
var menu_track := ""
var playlist: Array = []
var playlist_index := 0
var _fade_tween: Tween
var _switching := false

func _ready():
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Master"
	music_player.volume_db = -80.0
	add_child(music_player)
	music_player.finished.connect(_on_music_finished)

	for i in num_players:
		var p = AudioStreamPlayer.new()
		add_child(p)
		
		available.append(p)
		
		p.volume_db = -10
		p.finished.connect(_on_stream_finished.bind(p))
		p.bus = bus


func _on_stream_finished(stream): available.append(stream)

func play(sound_path, randomize_pitch := true):
	queue.append({"path": sound_path, "random": randomize_pitch})

func _process(_delta):
	if not queue.is_empty() and not available.is_empty():
		var item = queue.pop_front()
		var p = available.pop_front()
		p.stream = load(item.path)
		p.pitch_scale = randf_range(0.9, 1.1) if item.random else 1.0
		p.play()

func play_menu_music(path: String, fade := 1.0) -> void:
	if music_mode == "menu" and menu_track == path:
		return
	music_mode = "menu"
	menu_track = path
	_switch_track(path, fade)

func play_playlist(paths: Array, shuffle := true, fade := 1.5) -> void:
	if music_mode == "playlist" or paths.is_empty():
		return
	music_mode = "playlist"
	playlist = paths.duplicate()
	if shuffle:
		playlist.shuffle()
	playlist_index = 0
	_switch_track(playlist[0], fade)

func stop_music(fade := 1.0) -> void:
	music_mode = ""
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(music_player, "volume_db", -80.0, fade)
	_fade_tween.tween_callback(music_player.stop)

# Fades the current track out, swaps the stream, fades the new one in.
func _switch_track(path: String, fade: float) -> void:
	_switching = true
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	if music_player.playing:
		_fade_tween.tween_property(music_player, "volume_db", -80.0, fade)
	_fade_tween.tween_callback(func():
		music_player.stream = load(path)
		music_player.volume_db = -80.0
		music_player.play()
		_switching = false)
	_fade_tween.tween_property(music_player, "volume_db", music_volume_db, fade)

func _on_music_finished() -> void:
	if _switching:
		return
	match music_mode:
		"menu":
			music_player.play()   # repeat the menu track
		"playlist":
			playlist_index = (playlist_index + 1) % playlist.size()
			music_player.stream = load(playlist[playlist_index])
			music_player.play()
