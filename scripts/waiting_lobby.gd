extends Control

signal started_game

@onready var start_button: Button = $VBoxContainer/Controls/Start
@onready var quit_button: Button = $VBoxContainer/Controls/Quit
@onready var room_id_label: Label = $VBoxContainer/RoomIDLabel

func _ready() -> void:
	start_button.hide()

func setup_as_host() -> void:
	start_button.show()

func _on_start_pressed() -> void:
	if multiplayer.is_server():
		start_match_rpc.rpc()

@rpc("any_peer", "call_local", "reliable")
func start_match_rpc() -> void:
	started_game.emit()

func _on_quit_pressed() -> void:
	get_tree().quit()

func display_room_id(id: String) -> void:
	room_id_label.text = "Room ID: " + id
