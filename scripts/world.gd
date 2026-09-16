extends Node

@onready var main_menu: Panel = $"CanvasLayer/Main Menu"
@onready var hud: Control = $CanvasLayer/HUD
@onready var health_bar: ProgressBar = $CanvasLayer/HUD/HealthBar
@onready var chat_box: Control = $CanvasLayer/ChatBox
@onready var inbox: RichTextLabel = $CanvasLayer/ChatBox/Inbox
@onready var main_menu_bg: ColorRect = $CanvasLayer/MainMenuBG
@onready var play_options: MarginContainer = $CanvasLayer/PlayOptions
@onready var username_entry: LineEdit = $CanvasLayer/PlayOptions/TextureRect/VBoxContainer/UsernameEntry
@onready var address_entry: LineEdit = $CanvasLayer/PlayOptions/TextureRect/VBoxContainer/AddressEntry
@onready var message_entry: LineEdit = $CanvasLayer/ChatBox/MarginContainer/HBoxContainer/MessageEntry
@onready var send: Button = $CanvasLayer/ChatBox/MarginContainer/HBoxContainer/Send
@onready var matchmaking_screen: Panel = $CanvasLayer/MatchmakingScreen
@onready var roomID: Label = $CanvasLayer/PlayOptions/TextureRect/VBoxContainer/RoomID
@onready var pause_menu: Panel = $CanvasLayer/Paused
@onready var waiting_lobby: Control = $CanvasLayer/WaitingLobby
@export var player_card_scene: PackedScene # You will drag your card scene here in the Inspector
@onready var player_cards_container = $CanvasLayer/WaitingLobby/VBoxContainer/PlayerCards
@onready var player_card_spawner: MultiplayerSpawner = $CanvasLayer/WaitingLobby/VBoxContainer/PlayerCards/PlayerCardSpawner
@onready var resume: Button = $CanvasLayer/Paused/VBoxContainer/Resume
@onready var quit_game: Button = $CanvasLayer/Paused/VBoxContainer/QuitGame

const Player = preload("res://scenes/player.tscn")
var peer = NodeTunnelPeer.new()
var username: String
var game_started: bool = false
var lobby_players: Dictionary = {}

func _ready() -> void:
	peer.authenticated.connect(func(): print("Relay authenticated!"))
	peer.error.connect(func(msg: String): printerr("Relay sent error: ", msg))
	peer.forced_disconnect.connect(func(): print("Disconnected from relay"))

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	peer.connect_to_relay("relay.androodev.com:8080", "srxb50rx6kcwzdk")
	multiplayer.multiplayer_peer = peer
	player_card_spawner.spawned.connect(_on_player_card_spawned)
	
func _unhandled_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("pause"):
		if pause_menu.is_visible_in_tree():
			pause_menu.hide()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			pause_menu.show()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			
	## Toggle chatbox
	if Input.is_action_just_pressed("open_chat"):
		if chat_box.is_visible_in_tree():
			chat_box.hide()
			message_entry.release_focus()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			chat_box.show()
			message_entry.grab_focus()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Hosting & Joining
func _on_host_button_pressed() -> void:
	print("1. Requesting to host...")
	peer.host_room(false, "")
	await peer.room_connected
	print("2. Room connected successfully! ID: ", peer.room_id)

	DisplayServer.clipboard_set(peer.room_id)
	roomID.text = peer.room_id
	
	waiting_lobby.display_room_id(peer.room_id)
	
	waiting_lobby.setup_as_host()
	_switch_to_lobby()

func _on_join_button_pressed() -> void:
	var room_code := address_entry.text.strip_edges()
	if room_code.is_empty():
		print("Room code cannot be empty.")
		return
		
	print("1. Attempting to join room: ", room_code)
	peer.join_room(room_code)
	await peer.room_connected
	print("2. Successfully joined the room!")
	
	roomID.text = peer.room_id
	waiting_lobby.display_room_id(peer.room_id)
	
	_switch_to_lobby()

## Lobby & Game Flow
func _switch_to_lobby() -> void:
	username = username_entry.text.strip_edges() if username_entry.text.strip_edges() != "" else str(multiplayer.get_unique_id())
	main_menu_bg.hide()
	play_options.hide()
	waiting_lobby.show()

	if multiplayer.is_server():
		_register_and_spawn_card(1, username)
	else:
		# Tell the host to register us and spawn our card
		request_spawn_card_rpc.rpc_id(1, multiplayer.get_unique_id(), username)

@rpc("any_peer", "reliable")
func request_spawn_card_rpc(peer_id: int, p_username: String) -> void:
	if multiplayer.is_server():
		_register_and_spawn_card(peer_id, p_username)

func _register_and_spawn_card(peer_id: int, p_username: String) -> void:
	# 1. Update the host's dictionary and sync it to all clients
	lobby_players[peer_id] = p_username
	sync_lobby_players_rpc.rpc(lobby_players)

	# 2. Host instantiates the UI card
	var card = player_card_scene.instantiate()
	card.name = str(peer_id)
	player_cards_container.add_child(card)

	# 3. Update the host's own UI card immediately
	_update_card_ui(card, peer_id)

@rpc("authority", "reliable")
func sync_lobby_players_rpc(synced_dict: Dictionary) -> void:
	lobby_players = synced_dict
	
	# Update any existing cards to match the new dictionary
	for child in player_cards_container.get_children():
		# MultiplayerSpawner nodes might be in here, so ensure it's a card
		if child.name.is_valid_int(): 
			_update_card_ui(child, child.name.to_int())

func _on_player_card_spawned(card: Node) -> void:
	# This triggers automatically on clients when the spawner replicates a card.
	_update_card_ui(card, card.name.to_int())

func _update_card_ui(card: Node, peer_id: int) -> void:
	if lobby_players.has(peer_id):
		# CHANGE "NameLabel" TO THE ACTUAL NAME OF THE LABEL INSIDE YOUR CARD SCENE
		var label = card.get_node_or_null("Nametag")
		if label:
			label.text = lobby_players[peer_id]

func _on_waiting_lobby_started_game() -> void:
	game_started = true
	waiting_lobby.hide()
	hud.show()
	
	# Only the host is responsible for spawning the players
	if multiplayer.is_server():
		_spawn_players()

func _spawn_players() -> void:
	# 1. Spawn the host's character
	add_player(multiplayer.get_unique_id())
	
	# 2. Spawn a character for every client currently in the lobby
	for peer_id in multiplayer.get_peers():
		add_player(peer_id)

## Network Callbacks
func _on_peer_connected(peer_id: int) -> void:
	# If a player joins late (after the game started), spawn them immediately.
	# If they join during the lobby phase, wait.
	if multiplayer.is_server() and game_started:
		add_player(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		# Clean up the lobby UI if they leave during the waiting phase
		if lobby_players.has(peer_id):
			lobby_players.erase(peer_id)
			sync_lobby_players_rpc.rpc(lobby_players)
			
		var card = player_cards_container.get_node_or_null(str(peer_id))
		if card:
			card.queue_free()
			
		remove_player(peer_id)

func add_player(peer_id: int) -> void:
	var player = Player.instantiate()
	player.name = str(peer_id)
	add_child(player)
	if player.is_multiplayer_authority():
		player.health_changed.connect(update_health_bar)

func remove_player(peer_id: int) -> void:
	var player = get_node_or_null(str(peer_id))
	if player:
		player.queue_free()

func update_health_bar(health_value: float) -> void:
	health_bar.value = health_value

func _on_multiplayer_spawner_spawned(node: Node) -> void:
	if node.is_multiplayer_authority():
		node.health_changed.connect(update_health_bar)

## Chat & Lobby
@rpc("any_peer", "call_local", "reliable")
func message_rpc(sender_username: String, data: String) -> void:
	inbox.append_text(str(sender_username, ": ", data, "\n"))

func _on_send_pressed() -> void:
	var text_to_send := message_entry.text.strip_edges()
	if text_to_send.is_empty():
		return
	message_rpc.rpc(username, text_to_send)
	message_entry.text = ""
	message_entry.release_focus()

func _on_play_pressed() -> void:
	main_menu.hide()
	play_options.show()

func _on_quit_pressed() -> void:
	get_tree().quit()

## Pause menu controls
func _on_resume_pressed() -> void:
	pause_menu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_quit_game_pressed() -> void:
	multiplayer.multiplayer_peer = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	get_tree().paused = false 
	get_tree().reload_current_scene()
