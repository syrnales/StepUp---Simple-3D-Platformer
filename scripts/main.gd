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


var peer: NodeTunnelPeer

@export var player_scene: PackedScene
@onready var players_container = $Players # We will create this node in the editor

func _ready() -> void:
	main_menu_buttons.show()
	play_options.hide()
	room_id_text.hide()

	# Spawning Signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# 1. Initialize NodeTunnel
	peer = NodeTunnelPeer.new()
	peer.error.connect(func(msg): print("NodeTunnel Error: ", msg))
	
	# 2. Connect to the public relay (change the app ID to something unique to your game)
	peer.connect_to_relay("relay.androodev.com:8080", "58otl66lq7740id")
	multiplayer.multiplayer_peer = peer
	
	print("Authenticating with NodeTunnel...")
	await peer.authenticated
	print("Authenticated!")

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
	main_menu.hide()
	_create_lobby()

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

# Join game
func _on_join_pressed() -> void:
	var room_id = room_id_input.text.strip_edges() 
	
	if room_id.is_empty():
		print("Please enter a Room ID!")
		return
		
	main_menu.hide()
	print("Joining room: ", room_id)
	
	peer.join_room(room_id)
	
	await multiplayer.connected_to_server
	
	print("Successfully connected to the Host!")

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
