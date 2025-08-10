# Game Controller for 3D Snake
# Manages the global game state, grid system, and snake tracking

extends Node

signal snake_moved
signal snake_ate_food
signal game_over
signal snake_direction_changed(new_direction: Vector3i)
# New signal that conveys full orientation (forward and up) for basis-based turning
signal snake_orientation_changed(new_forward: Vector3i, new_up: Vector3i)
# New pre-move signal to drive smooth animation between grid cells
signal snake_move_started(prev_positions: Array[Vector3], next_positions: Array[Vector3], duration: float)

## Grid dimensions (cells in each direction)
@export var grid_size : Vector3i = Vector3i(30,30,30)
## Size of each grid cell in world units
@export var cell_size : float = 1.0
## World bounds offset from center
@export var world_bounds : Vector3 = Vector3(8, 8, 8)

# Snake data structure
var snake_segments : Array[Vector3i] = []  # Grid positions of snake segments
var snake_directions : Array[Vector3i] = []  # Direction each segment is facing
var snake_head_direction : Vector3i = Vector3i(0, 0, 1)  # Current head direction
var snake_length : int = 2

# Orientation basis for local turning (grid-aligned, orthonormal integer vectors)
var snake_forward: Vector3i = Vector3i(0, 0, 1)
var snake_up: Vector3i = Vector3i(0, 1, 0)
var snake_right: Vector3i = Vector3i(1, 0, 0)

# Game state
var is_game_active : bool = false
var move_timer : float = 0.0
var move_interval : float = 0.3  # Time between moves in seconds

# 3D Grid to track what's in each cell
enum CellType { EMPTY, SNAKE, FOOD, WALL }
var grid : Array[Array] = []  # 3D array [x][y][z]

# Food management
var food_position : Vector3i = Vector3i(-1, -1, -1)
var has_food : bool = false
# Eating radius in cells (Chebyshev distance)
@export var eat_radius_cells: int = 3
# Runtime visual node for food (sphere mesh + cube hitbox)
var food_node: Node3D

# Reference to snake controller for turn animations
var snake_controller : CharacterBody3D

func _ready():
	initialize_grid()
	initialize_snake()
	spawn_food()
	is_game_active = true

func _process(delta):
	if is_game_active:
		move_timer += delta
		if move_timer >= move_interval:
			move_timer = 0.0
			move_snake()

## Initialize the 3D grid array
func initialize_grid():
	grid.clear()
	grid.resize(grid_size.x)
	
	for x in range(grid_size.x):
		grid[x] = []
		grid[x].resize(grid_size.y)
		for y in range(grid_size.y):
			grid[x][y] = []
			grid[x][y].resize(grid_size.z)
			for z in range(grid_size.z):
				grid[x][y][z] = CellType.EMPTY

## Initialize snake at center of grid
func initialize_snake():
	snake_segments.clear()
	snake_directions.clear()
	
	# Reset orientation basis
	snake_forward = Vector3i(0, 0, 1)
	snake_up = Vector3i(0, 1, 0)
	_recompute_right()
	snake_head_direction = snake_forward
	
	var center = Vector3i(grid_size.x / 2, grid_size.y / 2, grid_size.z / 2)
	
	# Create initial snake segments (head + 1 body segment)
	# Head at center
	snake_segments.append(center)
	snake_directions.append(snake_forward)  # Head facing forward
	set_grid_cell(center, CellType.SNAKE)
	
	# Body segment behind the head
	var body_pos = center - snake_forward  # One unit behind along current forward
	snake_segments.append(body_pos)
	snake_directions.append(snake_forward)  # Body also facing forward initially
	set_grid_cell(body_pos, CellType.SNAKE)

## Convert grid coordinates to world coordinates
func grid_to_world(grid_pos: Vector3i) -> Vector3:
	var world_center = Vector3.ZERO
	var grid_center = Vector3(grid_size) * 0.5
	var offset = Vector3(grid_pos) - grid_center + Vector3(0.5, 0.5, 0.5)
	return world_center + offset * cell_size

## Convert world coordinates to grid coordinates
func world_to_grid(world_pos: Vector3) -> Vector3i:
	var world_center = Vector3.ZERO
	var grid_center = Vector3(grid_size) * 0.5
	var offset = (world_pos - world_center) / cell_size + grid_center - Vector3(0.5, 0.5, 0.5)
	return Vector3i(offset.round())

## Check if grid position is valid (within bounds)
func is_valid_grid_position(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < grid_size.x and \
		   pos.y >= 0 and pos.y < grid_size.y and \
		   pos.z >= 0 and pos.z < grid_size.z

## Set what's in a grid cell
func set_grid_cell(pos: Vector3i, cell_type: CellType):
	if is_valid_grid_position(pos):
		grid[pos.x][pos.y][pos.z] = cell_type

## Get what's in a grid cell
func get_grid_cell(pos: Vector3i) -> CellType:
	if is_valid_grid_position(pos):
		return grid[pos.x][pos.y][pos.z]
	return CellType.WALL  # Out of bounds is considered a wall

# Create/position the visual food node (sphere mesh + cube collider)
func _create_or_update_food_visual():
	if not is_instance_valid(food_node):
		food_node = Node3D.new()
		food_node.name = "Food"
		# Parent under the current scene root (Node3D) if possible so transforms work
		var root = get_tree().get_current_scene()
		if root and root is Node3D:
			root.add_child(food_node)
		else:
			add_child(food_node)
		# Cube hitbox
		var collider := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * cell_size
		collider.shape = box
		food_node.add_child(collider)
		# Sphere mesh (orange)
		var mesh_instance := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.4 * cell_size
		sphere.rings = 24
		sphere.radial_segments = 24
		mesh_instance.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.5, 0.0) # orange
		mesh_instance.material_override = mat
		food_node.add_child(mesh_instance)
	# Position it at current food cell center
	food_node.global_position = grid_to_world(food_position)

func _destroy_food_visual():
	if is_instance_valid(food_node):
		food_node.queue_free()
	food_node = null

## Move the snake one step forward
func move_snake():
	if snake_segments.is_empty():
		return
	
	# Cache previous world positions for smooth animation
	var prev_world_positions: Array[Vector3] = get_snake_world_positions()
	
	var head_pos = snake_segments[0]
	# Always advance along current local forward
	snake_head_direction = snake_forward
	var new_head_pos = head_pos + snake_head_direction
	
	# Check collision with walls or self
	var cell_at_new_pos = get_grid_cell(new_head_pos)
	if cell_at_new_pos == CellType.WALL or cell_at_new_pos == CellType.SNAKE:
		game_over.emit()
		is_game_active = false
		return
	
	# Check if snake ate food (within radius in cells around food)
	var ate_food := false
	if has_food:
		var d: Vector3i = new_head_pos - food_position
		var chebyshev: int = max(max(abs(d.x), abs(d.y)), abs(d.z))
		if chebyshev <= eat_radius_cells:
			ate_food = true
	
	if ate_food:
		snake_ate_food.emit()
		# Clear grid cell where the food was (in case head didn't move onto it)
		if is_valid_grid_position(food_position) and get_grid_cell(food_position) == CellType.FOOD:
			set_grid_cell(food_position, CellType.EMPTY)
		# Remove visual
		_destroy_food_visual()
		has_food = false
		snake_length += 1
		spawn_food()
	
	# Prepare next state in temporaries for animation
	var next_segments: Array[Vector3i] = snake_segments.duplicate()
	var next_directions: Array[Vector3i] = snake_directions.duplicate()
	
	# Store the tail position before moving (for removal if not growing)
	var tail_pos: Vector3i = Vector3i.ZERO
	var tail_dir: Vector3i = Vector3i.ZERO
	if next_segments.size() > 0:
		tail_pos = next_segments[-1]
		if next_directions.size() > 0:
			tail_dir = next_directions[-1]
	
	# Move each segment to the position of the segment in front of it
	for i in range(next_segments.size() - 1, 0, -1):
		next_segments[i] = next_segments[i - 1]
		next_directions[i] = next_directions[i - 1]
	
	# Move the head to the new position
	next_segments[0] = new_head_pos
	next_directions[0] = snake_head_direction
	
	# Handle growth in the next state
	if ate_food:
		next_segments.append(tail_pos)
		next_directions.append(tail_dir)
	
	# Ensure we don't exceed target length in the next state
	while next_segments.size() > snake_length:
		next_segments.pop_back()
		next_directions.pop_back()
	
	# Compute next world positions and emit animation signal before committing
	var next_world_positions: Array[Vector3] = []
	for p in next_segments:
		next_world_positions.append(grid_to_world(p))
	
	snake_move_started.emit(prev_world_positions, next_world_positions, move_interval)
	
	# Commit actual state and grid updates
	snake_segments = next_segments
	snake_directions = next_directions
	set_grid_cell(new_head_pos, CellType.SNAKE)
	if ate_food:
		set_grid_cell(tail_pos, CellType.SNAKE)
	else:
		if tail_pos != Vector3i.ZERO:
			set_grid_cell(tail_pos, CellType.EMPTY)
	
	# Safety: ensure grid doesn't keep stale tail cells if any
	while snake_segments.size() > snake_length:
		var excess_tail = snake_segments.pop_back()
		snake_directions.pop_back()
		set_grid_cell(excess_tail, CellType.EMPTY)
	
	snake_moved.emit()

## Old absolute-direction API (kept for compatibility, but not used by input now)
func change_snake_direction(new_direction: Vector3i):
	# Prevent snake from going backwards into itself
	if new_direction == -snake_forward:
		return
	# Update orientation to match an absolute axis request if needed
	if new_direction == snake_forward:
		return
	# Try to align within the plane formed by current basis
	if new_direction != Vector3i.ZERO:
		# Determine which turn achieves this (left/right/up/down). Fallback to closest.
		var target := new_direction
		# Choose best among 4 candidates
		var candidates := [
			{"f": snake_right, "u": snake_up}, # right
			{"f": -snake_right, "u": snake_up}, # left
			{"f": snake_up, "u": -snake_forward}, # up
			{"f": -snake_up, "u": snake_forward} # down
		]
		var best_idx := 0
		var best_dot := -INF
		for i in candidates.size():
			var d := Vector3(candidates[i]["f"]).dot(Vector3(target))
			if d > best_dot:
				best_dot = d
				best_idx = i
		var chosen = candidates[best_idx]
		_snake_set_orientation(chosen["f"], chosen["u"])

## Local turning API — use these from input
func turn_left():
	# Block if a turn animation/cooldown is active on the controller
	if is_instance_valid(snake_controller) and snake_controller.has_method("can_accept_turn"):
		if not snake_controller.can_accept_turn():
			return
	# Rotate -90° around local up
	var new_f: Vector3i = -snake_right
	var new_u: Vector3i = snake_up
	_snake_set_orientation(new_f, new_u)

func turn_right():
	# Block if a turn animation/cooldown is active on the controller
	if is_instance_valid(snake_controller) and snake_controller.has_method("can_accept_turn"):
		if not snake_controller.can_accept_turn():
			return
	# Rotate +90° around local up
	var new_f: Vector3i = snake_right
	var new_u: Vector3i = snake_up
	_snake_set_orientation(new_f, new_u)

func turn_up():
	# Block if a turn animation/cooldown is active on the controller
	if is_instance_valid(snake_controller) and snake_controller.has_method("can_accept_turn"):
		if not snake_controller.can_accept_turn():
			return
	# Rotate -90° around local right (pitch up)
	var new_f: Vector3i = snake_up
	var new_u: Vector3i = -snake_forward
	_snake_set_orientation(new_f, new_u)

func turn_down():
	# Block if a turn animation/cooldown is active on the controller
	if is_instance_valid(snake_controller) and snake_controller.has_method("can_accept_turn"):
		if not snake_controller.can_accept_turn():
			return
	# Rotate +90° around local right (pitch down)
	var new_f: Vector3i = -snake_up
	var new_u: Vector3i = snake_forward
	_snake_set_orientation(new_f, new_u)

func _snake_set_orientation(new_forward: Vector3i, new_up: Vector3i):
	# Disallow 180° reversal into self
	if new_forward == -snake_forward:
		return
	snake_forward = _normalize_axis(new_forward)
	snake_up = _normalize_axis(new_up)
	_recompute_right()
	snake_head_direction = snake_forward
	
	# Notify controller first for immediate camera turn
	if is_instance_valid(snake_controller):
		if snake_controller.has_method("on_snake_orientation_changed"):
			snake_controller.on_snake_orientation_changed(snake_forward, snake_up)
		elif snake_controller.has_method("on_snake_direction_changed"):
			snake_controller.on_snake_direction_changed(snake_forward)
	
	# Emit both signals for compatibility
	snake_orientation_changed.emit(snake_forward, snake_up)
	snake_direction_changed.emit(snake_forward)

func _recompute_right():
	var r: Vector3 = Vector3(snake_up).cross(Vector3(snake_forward))
	snake_right = Vector3i(r)
	if snake_right == Vector3i.ZERO:
		# Fallback to a canonical right if up // forward (shouldn't happen with our turns)
		snake_right = Vector3i(1, 0, 0)

func _normalize_axis(v: Vector3i) -> Vector3i:
	# Clamp to unit grid axis (-1,0,1) per component and ensure length is 1
	var c = Vector3i(clamp(v.x, -1, 1), clamp(v.y, -1, 1), clamp(v.z, -1, 1))
	# If zero vector, fallback to current
	if c == Vector3i.ZERO:
		return Vector3i(0, 0, 1)
	return c

## Spawn food at random empty location
func spawn_food():
	if has_food:
		return
	
	var empty_positions : Array[Vector3i] = []
	
	# Find all empty positions
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			for z in range(grid_size.z):
				var pos = Vector3i(x, y, z)
				if get_grid_cell(pos) == CellType.EMPTY:
					empty_positions.append(pos)
	
	if empty_positions.size() > 0:
		food_position = empty_positions[randi() % empty_positions.size()]
		set_grid_cell(food_position, CellType.FOOD)
		has_food = true
		_create_or_update_food_visual()

## Get all snake segment positions in world coordinates
func get_snake_world_positions() -> Array[Vector3]:
	var world_positions : Array[Vector3] = []
	for segment_pos in snake_segments:
		world_positions.append(grid_to_world(segment_pos))
	return world_positions

## Get all snake segment directions
func get_snake_directions() -> Array[Vector3i]:
	return snake_directions.duplicate()

## Get food position in world coordinates
func get_food_world_position() -> Vector3:
	if has_food:
		return grid_to_world(food_position)
	return Vector3.ZERO

## Restart the game
func restart_game():
	initialize_grid()
	initialize_snake()
	_destroy_food_visual()
	spawn_food()
	is_game_active = true
	move_timer = 0.0

## Get current snake length
func get_snake_length() -> int:
	return snake_segments.size()

## Get current snake head direction
func get_snake_head_direction() -> Vector3i:
	return snake_forward

func get_snake_up_direction() -> Vector3i:
	return snake_up
