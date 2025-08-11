extends MarginContainer

func _ready() -> void:
	# Ensure the mouse is visible for UI interaction and focus the main button
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var btn: Button = get_node_or_null("VBoxContainer/Button")
	if btn:
		btn.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	# Allow pressing Enter/Space to activate the button
	if event.is_action_pressed("ui_accept"):
		_on_button_pressed()

func _on_button_pressed() -> void:
	print("Game started")
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	pass # Replace with function body.
