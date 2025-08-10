# Main Game Entry Point
# Coordinates all game systems and handles the main game loop

extends Node3D

## References to game systems
@onready var game_controller: Node = $GameController
@onready var snake_controller: CharacterBody3D = $SnakeController
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var directional_light: DirectionalLight3D = $DirectionalLight3D

# Visual representation management
var snake_segment_scene: PackedScene
var food_scene: PackedScene
var snake_visual_segments: Array[MeshInstance3D] = []
var food_visual: MeshInstance3D

# Materials for different game objects
var snake_head_material: StandardMaterial3D
var snake_body_material: StandardMaterial3D
var food_material: StandardMaterial3D

# Smooth animation state between ticks
var anim_active: bool = false
var anim_time: float = 0.0
var anim_duration: float = 0.3
var anim_prev_positions: Array[Vector3] = []
var anim_next_positions: Array[Vector3] = []

func _ready():
	setup_materials()
	setup_visual_scenes()
	connect_signals()
	
	# Set snake controller reference in game controller
	game_controller.snake_controller = snake_controller
	
	# Position the snake controller at the initial head position
	update_snake_visuals()
	
	# Initialize snake controller camera with the current snake orientation
	var initial_forward = game_controller.get_snake_head_direction()
	var initial_up = game_controller.get_snake_up_direction() if game_controller.has_method("get_snake_up_direction") else Vector3i(0,1,0)
	snake_controller.on_snake_orientation_changed(initial_forward, initial_up)
	
	# Size and position the world walls to match the GameController's grid in world space
	setup_walls()
	
func _process(delta):
	# Smoothly animate between prev and next positions when a move starts
	if anim_active:
		anim_time += delta
		var t: float = clamp(anim_time / max(0.0001, anim_duration), 0.0, 1.0)
		# Use smoothstep for nicer feel
		var s : float = t * t * (3.0 - 2.0 * t)
		# Ensure we have enough visuals
		while snake_visual_segments.size() < anim_next_positions.size():
			var seg := MeshInstance3D.new()
			var box_mesh := BoxMesh.new(); box_mesh.size = Vector3(0.8, 0.8, 0.8)
			seg.mesh = box_mesh
			add_child(seg)
			snake_visual_segments.append(seg)
		# Interpolate each segment position
		for i in range(min(snake_visual_segments.size(), anim_next_positions.size())):
			var from_p
			if i < anim_prev_positions.size():
				from_p = anim_prev_positions[i]
			else:
				from_p = anim_next_positions[i]
			var to_p = anim_next_positions[i]
			snake_visual_segments[i].global_position = from_p.lerp(to_p, s)
			# Optional: orient towards motion
			var dir = to_p - from_p
			if dir.length() > 0.0001:
				snake_visual_segments[i].look_at(snake_visual_segments[i].global_position + dir, Vector3.UP)
		# Camera/controller follow towards head target continuously
		if anim_next_positions.size() > 0:
			var head_from
			if anim_prev_positions.size() > 0:
				head_from = anim_prev_positions[0]
			else:
				head_from = anim_next_positions[0]
			var head_to := anim_next_positions[0]
			var head_pos = head_from.lerp(head_to, s)
			snake_controller.follow_to_position(head_pos)
		# Finish animation
		if t >= 1.0:
			anim_active = false
			update_snake_visuals()
			update_food_visual()

func _input(event):
	if not game_controller.is_game_active:
		if Input.is_action_just_pressed("ui_accept"):  # Space or Enter to restart
			game_controller.restart_game()
		return
	
	# Local turning controls (no absolute forward/backward)
	if Input.is_action_just_pressed("turn_left"):
		game_controller.turn_left()
		return
	if Input.is_action_just_pressed("turn_right"):
		game_controller.turn_right()
		return
	if Input.is_action_just_pressed("turn_up"):
		game_controller.turn_up()
		return
	if Input.is_action_just_pressed("turn_down"):
		game_controller.turn_down()
		return

## Setup materials for visual elements
func setup_materials():
	# Snake head material (red)
	snake_head_material = StandardMaterial3D.new()
	snake_head_material.albedo_color = Color.RED
	
	# Snake body material (green)
	snake_body_material = StandardMaterial3D.new()
	snake_body_material.albedo_color = Color.GREEN
	
	# Food material (yellow)
	food_material = StandardMaterial3D.new()
	food_material.albedo_color = Color.YELLOW

## Setup visual scene templates
func setup_visual_scenes():
	# Create a simple box scene for snake segments
	snake_segment_scene = create_box_scene(Vector3(0.8, 0.8, 0.8))
	
	# Create food visual
	food_scene = create_box_scene(Vector3(0.6, 0.6, 0.6))

## Create a simple box mesh scene
func create_box_scene(size: Vector3) -> PackedScene:
	var scene = PackedScene.new()
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	
	# Pack the scene
	var root = Node3D.new()
	root.add_child(mesh_instance)
	scene.pack(root)
	
	return scene

## Connect signals from game controller
func connect_signals():
	if game_controller:
		game_controller.snake_moved.connect(_on_snake_moved)
		game_controller.snake_ate_food.connect(_on_snake_ate_food)
		game_controller.game_over.connect(_on_game_over)
		# Prefer orientation change for controller
		if game_controller.has_signal("snake_orientation_changed"):
			game_controller.snake_orientation_changed.connect(_on_snake_orientation_changed)
		else:
			game_controller.snake_direction_changed.connect(_on_snake_direction_changed)
		# Smooth animation hook
		if game_controller.has_signal("snake_move_started"):
			game_controller.snake_move_started.connect(_on_snake_move_started)

# Configure the CSG walls (Floor, Roof, Left, Right, Front, Back)
# to enclose the playable grid volume defined by GameController.
func setup_walls():
	var combiner := $CSGCombiner3D
	if combiner == null:
		return
	# Ensure the wall root is centered at world origin to match grid_to_world()
	combiner.position = Vector3.ZERO
	
	# Read grid dimensions in world units
	var gs: Vector3i = game_controller.grid_size
	var cs: float = game_controller.cell_size
	var width: float = float(gs.x) * cs
	var height: float = float(gs.y) * cs
	var depth: float = float(gs.z) * cs
	var t: float = max(0.1, cs) # wall thickness
	
	var half_w: float = width * 0.5
	var half_h: float = height * 0.5
	var half_d: float = depth * 0.5
	
	# Get child CSG boxes
	var floor: CSGBox3D = combiner.get_node_or_null("Floor")
	var roof: CSGBox3D = combiner.get_node_or_null("Roof")
	var right: CSGBox3D = combiner.get_node_or_null("Right")
	var left: CSGBox3D = combiner.get_node_or_null("Left")
	var back: CSGBox3D = combiner.get_node_or_null("Back")
	var front: CSGBox3D = combiner.get_node_or_null("Front")
	
	# Reset orientations to identity so sizes align with axes
	for wall in [floor, roof, right, left, back, front]:
		if wall:
			wall.transform = Transform3D.IDENTITY
	
	# Floor and roof span width x depth and sit just outside the grid volume
	if floor:
		floor.size = Vector3(width, t, depth)
		floor.position = Vector3(0, -half_h - t * 0.5, 0)
	if roof:
		roof.size = Vector3(width, t, depth)
		roof.position = Vector3(0, half_h + t * 0.5, 0)
	
	# Left/Right walls span height x depth, thin along X
	if left:
		left.size = Vector3(t, height, depth)
		left.position = Vector3(-half_w - t * 0.5, 0, 0)
	if right:
		right.size = Vector3(t, height, depth)
		right.position = Vector3(half_w + t * 0.5, 0, 0)
	
	# Front/Back walls span width x height, thin along Z
	if back:
		back.size = Vector3(width, height, t)
		back.position = Vector3(0, 0, -half_d - t * 0.5)
	if front:
		front.size = Vector3(width, height, t)
		front.position = Vector3(0, 0, half_d + t * 0.5)
	
	# Assign distinct colors to each wall for visualization
	var mat_floor := StandardMaterial3D.new(); mat_floor.albedo_color = Color.from_hsv(0.0, 0.0, 0.35) # dark gray
	var mat_roof := StandardMaterial3D.new(); mat_roof.albedo_color = Color.from_hsv(0.58, 0.35, 0.85) # light blue
	var mat_left := StandardMaterial3D.new(); mat_left.albedo_color = Color(0.95, 0.25, 0.25) # red
	var mat_right := StandardMaterial3D.new(); mat_right.albedo_color = Color(0.25, 0.9, 0.35) # green
	var mat_back := StandardMaterial3D.new(); mat_back.albedo_color = Color(0.25, 0.35, 0.95) # blue
	var mat_front := StandardMaterial3D.new(); mat_front.albedo_color = Color(0.95, 0.85, 0.25) # yellow
	
	if floor: floor.material = mat_floor
	if roof: roof.material = mat_roof
	if left: left.material = mat_left
	if right: right.material = mat_right
	if back: back.material = mat_back
	if front: front.material = mat_front

## Handle snake direction change (compatibility)
func _on_snake_direction_changed(new_direction: Vector3i):
	# Forward the direction change to the snake controller for camera rotation
	snake_controller.on_snake_direction_changed(new_direction)

## Handle snake orientation change (preferred)
func _on_snake_orientation_changed(new_forward: Vector3i, new_up: Vector3i):
	snake_controller.on_snake_orientation_changed(new_forward, new_up)

## Smooth move started: set up interpolation state
func _on_snake_move_started(prev_positions: Array[Vector3], next_positions: Array[Vector3], duration: float):
	anim_prev_positions = prev_positions
	anim_next_positions = next_positions
	anim_duration = duration
	anim_time = 0.0
	anim_active = true
	# Ensure visuals exist and are colored properly
	ensure_snake_visuals(anim_next_positions.size())
	apply_snake_materials()
	# Prime visuals to previous positions immediately to avoid any 1-frame pops
	for i in range(min(snake_visual_segments.size(), anim_prev_positions.size())):
		snake_visual_segments[i].global_position = anim_prev_positions[i]
	# Also move camera immediately towards new path start to avoid lag
	if anim_next_positions.size() > 0:
		snake_controller.follow_to_position(anim_prev_positions[0])

## Handle snake movement (end of tick fallback)
func _on_snake_moved():
	# During active interpolation, do not rebuild the snake visuals yet to avoid a 1-frame flash.
	if anim_active:
		# It's safe to refresh food immediately (e.g., after eating) without touching snake visuals.
		update_food_visual()
		return
	# Rebuild at end to snap to exact grid in case of drift and to update growth
	update_snake_visuals()
	update_food_visual()
	# Update controller to exact head pos
	var snake_positions = game_controller.get_snake_world_positions()
	if snake_positions.size() > 0:
		snake_controller.follow_to_position(snake_positions[0])

## Handle food consumption
func _on_snake_ate_food():
	print("Snake ate food! Length: ", game_controller.get_snake_length())

## Handle game over
func _on_game_over():
	print("Game Over! Press Space/Enter to restart")
	anim_active = false

## Ensure snake visuals array has the correct number of segments
func ensure_snake_visuals(count: int):
	# Remove extras
	while snake_visual_segments.size() > count:
		var seg = snake_visual_segments.pop_back()
		if is_instance_valid(seg): seg.queue_free()
	# Add missing
	while snake_visual_segments.size() < count:
		var segment_visual = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(0.8, 0.8, 0.8)
		segment_visual.mesh = box_mesh
		add_child(segment_visual)
		snake_visual_segments.append(segment_visual)

func apply_snake_materials():
	for i in range(snake_visual_segments.size()):
		if i == 0:
			snake_visual_segments[i].material_override = snake_head_material
		else:
			snake_visual_segments[i].material_override = snake_body_material

## Update visual representation of the snake
func update_snake_visuals():
	# Clear existing visual segments
	for segment in snake_visual_segments:
		if is_instance_valid(segment):
			segment.queue_free()
	snake_visual_segments.clear()
	
	# Create new visual segments
	var snake_positions = game_controller.get_snake_world_positions()
	var snake_directions = game_controller.get_snake_directions()
	
	for i in range(snake_positions.size()):
		var segment_visual = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(0.8, 0.8, 0.8)
		segment_visual.mesh = box_mesh
		
		# Apply material (head vs body)
		if i == 0:
			segment_visual.material_override = snake_head_material
		else:
			segment_visual.material_override = snake_body_material
		
		# Position the segment
		segment_visual.global_position = snake_positions[i]
		
		# Rotate segment based on direction
		if i < snake_directions.size():
			var direction = snake_directions[i]
			if direction != Vector3i.ZERO:
				segment_visual.look_at(
					segment_visual.global_position + Vector3(direction),
					Vector3.UP
				)
		
		add_child(segment_visual)
		snake_visual_segments.append(segment_visual)

## Update visual representation of food
func update_food_visual():
	# Remove existing food visual
	if food_visual and is_instance_valid(food_visual):
		food_visual.queue_free()
		food_visual = null
	
	# Create new food visual if food exists
	if game_controller.has_food:
		food_visual = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(0.6, 0.6, 0.6)
		food_visual.mesh = box_mesh
		food_visual.material_override = food_material
		food_visual.global_position = game_controller.get_food_world_position()
		add_child(food_visual)

func _exit_tree():
	# Clean up visual elements
	for segment in snake_visual_segments:
		if is_instance_valid(segment):
			segment.queue_free()
	
	if food_visual and is_instance_valid(food_visual):
		food_visual.queue_free()
