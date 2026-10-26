extends Node3D

@onready var main_menu: Control = $UI/MainMenu
@onready var play: Button = $UI/MainMenu/Buttons/VBoxContainer/Play
@onready var quit: Button = $UI/MainMenu/Buttons/VBoxContainer/Quit
@onready var play_options: MarginContainer = $UI/MainMenu/PlayOptions
@onready var main_menu_buttons: MarginContainer = $UI/MainMenu/MainMenuButtons
@onready var title: Label = $UI/MainMenu/Title
@onready var title_2: Label = $UI/MainMenu/Title2
@onready var room_id_input: LineEdit = $UI/MainMenu/PlayOptions/VBoxContainer/RoomID
@onready var room_id_text: Label = $"UI/RoomID-text"
@onready var race_hud: Control = $UI/RaceHUD
@onready var resume: Button = $UI/InGameMenu/VBoxContainer/Resume
@onready var quit_game: Button = $UI/InGameMenu/VBoxContainer/Quit
@onready var in_game_menu: Control = $UI/InGameMenu

const MENU_MUSIC = "res://resources/music/Bubble World by Mace Dev - 1) Main Menu.wav"
const LOBBY_PLAYLIST := [
	"res://resources/music/inside my world.mp3",
	"res://resources/music/DOS-88 - Far away.mp3",
	"res://resources/music/Race to Mars.mp3",
	"res://resources/music/Smooth Sailing.mp3"
	# add more music here
]

var peer: NodeTunnelPeer

@export var player_scene: PackedScene
@onready var players_container = $Players # We will create this node in the editor

func _ready() -> void:
	if Transition.is_covered:
		Transition.reveal()
	
	main_menu_buttons.show()
	play_options.hide()
	room_id_text.hide()
	Audio.play_menu_music(MENU_MUSIC)

	# Spawning Signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(func():
		await Transition.cover("diamond", 0.8)
		get_tree().reload_current_scene())

	# 1. Initialize NodeTunnel
	peer = NodeTunnelPeer.new()
	peer.error.connect(func(msg): print("NodeTunnel Error: ", msg))
	
	# 2. Connect to the public relay (change the app ID to something unique to your game)
	peer.connect_to_relay("relay.androodev.com:8080", "58otl66lq7740id")
	multiplayer.multiplayer_peer = peer
	
	print("Authenticating with NodeTunnel...")
	await peer.authenticated
	print("Authenticated!")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if in_game_menu.visible:
			in_game_menu.hide()          # closing is always allowed
		elif _is_in_game():
			in_game_menu.show()

func _is_in_game() -> bool:
	if main_menu.is_visible_in_tree():
		return false
	# Menu is hidden, but make sure there's really a player (not mid-connection)
	return players_container.has_node(str(multiplayer.get_unique_id()))

func _on_play_pressed() -> void:
	_hide_main_menu()
	play_options.show()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _hide_main_menu():
	main_menu_buttons.hide()
	title.hide()
	title_2.hide()

func _show_main_menu():
	main_menu_buttons.show()
	title.show()
	title_2.show()
	
## Play Options

# Hosting
func _on_host_pressed() -> void:
	await Transition.cover("diamond", 0.8)
	main_menu.hide()
	await _create_lobby()
	race_hud.show()
	Transition.reveal()

func _create_lobby() -> void:
	print("Hosting room...")
	peer.host_room(true, "My Game Room")
	
	await peer.room_connected
	
	var room_id = peer.room_id
	print("ROOM CREATED! Share this ID with friends: ", room_id)
	room_id_text.text = str(room_id)
	room_id_text.show()
	
	
	# Spawn the host's own player character
	_add_player(multiplayer.get_unique_id())
	
	# play another music when in lobby
	Audio.play_playlist(LOBBY_PLAYLIST)

# Join game
func _on_join_pressed() -> void:
	var room_id = room_id_input.text.strip_edges()
	if room_id.is_empty():
		print("Please enter a Room ID!")
		return

	await Transition.cover("diamond", 0.8)
	main_menu.hide()
	print("Joining room: ", room_id)
	peer.join_room(room_id)
	await multiplayer.connected_to_server
	print("Successfully connected to the Host!")
	Transition.reveal("diamond", 0.8)
	
# Back to Main Menu
func _on_back_pressed() -> void:
	_show_main_menu()
	play_options.hide()
	
func _mouse_hidden() -> void:
	if main_menu.is_visible_in_tree():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		print("Mouse pointer visible!")

# --- Multiplayer Spawning Logic ---

func _on_peer_connected(id: int) -> void:
	print("Player connected: ", id)
	if multiplayer.is_server():
		_add_player(id)

func _on_peer_disconnected(id: int) -> void:
	print("Player disconnected: ", id)
	if multiplayer.is_server():
		var player_to_remove = players_container.get_node_or_null(str(id))
		if player_to_remove:
			player_to_remove.queue_free()

func _add_player(id: int) -> void:
	var player = player_scene.instantiate()
	player.name = str(id)
	players_container.add_child(player)

func _on_resume_pressed() -> void:
	in_game_menu.hide()

func _on_quit_game_pressed() -> void:
	await Transition.cover("clock", 0.8)
	var p = multiplayer.multiplayer_peer
	if p:
		p.close()
	multiplayer.multiplayer_peer = null
	Race._set_state(Race.State.LOBBY)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()
