# FoodController
# Manages food spawning on the grid. Collision and growth remain managed by GameController.
# This controller delegates spawning to GameController's existing API to avoid duplication.

class_name FoodController
extends Node

@export var game_controller: Node

func _ready():
	# Auto-discover GameController if not set
	if not is_instance_valid(game_controller):
		var gc := get_parent()
		if is_instance_valid(gc) and gc.has_node("GameController"):
			game_controller = gc.get_node("GameController")

	# Optionally ensure one food exists at start (GameController already spawns in _ready)
	# If you want FoodController to be the authority, disable GC's auto-spawn and uncomment:
	# spawn_food_random()

# Spawns a food item at a random empty cell using GameController's grid
func spawn_food_random():
	if not is_instance_valid(game_controller):
		push_warning("FoodController: game_controller is not set; cannot spawn food")
		return
	if not game_controller.has_method("spawn_food"):
		push_warning("FoodController: game_controller has no spawn_food(); cannot spawn")
		return
	game_controller.spawn_food()

# Returns the food world position, if available (delegates to GameController)
func get_food_world_position() -> Vector3:
	if is_instance_valid(game_controller) and game_controller.has_method("get_food_world_position"):
		return game_controller.get_food_world_position()
	return Vector3.ZERO

# Convenience: does food exist?
func has_food() -> bool:
	if not is_instance_valid(game_controller):
		return false
	# GameController exposes has_food as a property
	return game_controller.has_food
