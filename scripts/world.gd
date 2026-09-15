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


const Player = preload("res://scenes/player.tscn")
# const PORT = 9999
var peer = NodeTunnelPeer.new( )
var username : String
var message : String

func _ready() -> void:
	peer.authenticated.connect(func():
		print("Relay authenticated!")
	)
	peer.error.connect(func(msg: String):
		printerr("Relay sent error: ", msg)
	)
	peer.forced_disconnect.connect(func():
		print("Disconnected from relay")
	)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	peer.connect_to_relay("relay.androodev.com:8080", "srxb50rx6kcwzdk")

	multiplayer.multiplayer_peer = peer
	
func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("pause"):
		pause_menu.show()
		
	
	# Open Chat Box
	if Input.is_action_just_pressed("open_chat"):
		chat_box.show()
		message_entry.grab_focus()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	elif Input.is_action_just_pressed("hide_chat"):
		if chat_box.is_visible_in_tree():
			chat_box.hide()
			message_entry.release_focus()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
## Hosting a room
func _on_host_button_pressed() -> void:
	print("1. Requesting to host...")
	peer.host_room(false, "")
	
	await peer.room_connected
	print("2. Room connected successfully! ID: ", peer.room_id)

	DisplayServer.clipboard_set(peer.room_id)
	roomID.text = peer.room_id

	joined()
	main_menu_bg.hide()
	play_options.hide()
	
	add_player(multiplayer.get_unique_id())

func _on_join_button_pressed() -> void:
	var room_code := address_entry.text.strip_edges()
	if room_code.is_empty():
		print("Room code cannot be empty.")
		return
		
	print("1. Attempting to join room: ", room_code)
	
	peer.join_room(room_code)
	await peer.room_connected

	main_menu_bg.hide()
	play_options.hide()
	
	print("2. Successfully joined the room!")

	main_menu_bg.hide()
	play_options.hide()
	roomID.text = peer.room_id
	joined()

## Joining a room
func joined():
	hud.show()
	matchmaking_screen.hide()
	username = username_entry.text.strip_edges() if username_entry.text.strip_edges() != "" else str(multiplayer.get_unique_id())

func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		add_player(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
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

## Main Menu Buttons
func _on_play_pressed() -> void:
	main_menu.hide()
	play_options.show()
func _on_quit_pressed() -> void:
	get_tree().quit()
