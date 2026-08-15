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


const Player = preload("res://scenes/player.tscn")
const PORT = 9999
var enet_peer = ENetMultiplayerPeer.new()
var username : String
var message : String

func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	
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
	
func _on_host_button_pressed() -> void:
	joined()
	
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)

	add_player(multiplayer.get_unique_id())

func _on_join_button_pressed() -> void:
	joined()

	enet_peer.create_client("localhost", PORT)
	multiplayer.multiplayer_peer = enet_peer

func joined():
	main_menu_bg.hide()
	hud.show()
	play_options.hide()
	username = username_entry.text if username_entry.text != "" else str(multiplayer.get_unique_id())

func add_player(peer_id):
	var player = Player.instantiate()
	player.name = str(peer_id)
	add_child(player)
	if player.is_multiplayer_authority():
		player.health_changed.connect(update_health_bar)
		
func remove_player(peer_id):
	var player = get_node_or_null(str(peer_id))
	if player:
		player.queue_free()
		
func update_health_bar(health_value):
	health_bar.value = health_value

func _on_multiplayer_spawner_spawned(node: Node) -> void:
	if node.is_multiplayer_authority():
		node.health_changed.connect(update_health_bar)

@rpc ("any_peer", "call_local", "reliable")
func message_rpc(sender_username: String, data: String):
	inbox.append_text(str(sender_username, ": ", data, "\n"))

func _on_send_pressed() -> void:
	var text_to_send = message_entry.text.strip_edges()
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
