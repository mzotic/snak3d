extends MarginContainer


func _on_button_pressed() -> void:
	print("Game started")
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	pass # Replace with function body.
