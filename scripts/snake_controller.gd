# Snake3D Controller
# Continuous forward movement with WASD directional changes
# No gravity, floating in 3D cube space

extends CharacterBody3D

## Can we move around?
@export var can_move : bool = true
## Can we hold shift to boost speed?
@export var can_boost : bool = true

@export_group("Speeds")
## Look around rotation speed.
@export var look_speed : float = 0.002
## Normal movement speed.
@export var base_speed : float = 7.0
## Boosted speed when holding shift.
@export var boost_speed : float = 12.0
## Rotation speed for directional changes.
@export var turn_speed : float = 2.0
## Duration for smooth turn animation.
@export var turn_animation_duration : float = 0.3	

@export_group("Input Actions")
## Name of Input Action to turn left (A).
@export var input_left : String = "turn_left"
## Name of Input Action to turn right (D).
@export var input_right : String = "turn_right"
## Name of Input Action to turn up (W).
@export var input_up : String = "turn_up"
## Name of Input Action to turn down (S).
@export var input_down : String = "turn_down"
## Name of Input Action to boost speed.
@export var input_boost : String = "boost"
## Name of Input Action for free look (Ctrl).
@export var input_free_look : String = "free_look"
## Name of Input Action to switch camera view (C).
@export var input_camera_switch : String = "camera_switch"

var mouse_captured : bool = false
var look_rotation : Vector2
var move_speed : float = 0.0
var movement_direction : Vector3 = Vector3.FORWARD

# Variables for discrete 90-degree turning
var turn_cooldown : float = 0.0
var turn_delay : float = 0.2  # Minimum time between turns

# Variables for smooth rotation animation
var is_turning : bool = false
var turn_start_rotation : Basis
var turn_target_rotation : Basis
var turn_progress : float = 0.0

# Variables for camera control
var free_look_active : bool = false
var base_look_rotation : Vector2  # Camera rotation when not in free look mode
var is_first_person : bool = true  # Track current camera mode

## IMPORTANT REFERENCES
@onready var head: Node3D = $Head
@onready var first_person_camera: Camera3D = $Head/FirstPersonCamera
@onready var third_person_camera: Camera3D = $Head/ThirdPersonCamera

func _ready() -> void:
	check_input_mappings()
	look_rotation.y = rotation.y
	look_rotation.x = head.rotation.x
	base_look_rotation = look_rotation
	
	# Ensure first person camera is active by default
	first_person_camera.current = true
	third_person_camera.current = false

func _unhandled_input(event: InputEvent) -> void:
	# Mouse capturing
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		capture_mouse()
	if Input.is_key_pressed(KEY_ESCAPE):
		release_mouse()
	
	# Check for camera switch input
	if Input.is_action_just_pressed(input_camera_switch):
		switch_camera()
	
	# Check for free look mode
	free_look_active = Input.is_action_pressed(input_free_look)
	
	# Look around only when in free look mode
	if mouse_captured and event is InputEventMouseMotion:
		if free_look_active:
			rotate_look(event.relative)
		else:
			# Reset to base camera position when not in free look
			reset_camera_to_base()

func _physics_process(delta: float) -> void:
	# Update turn cooldown
	if turn_cooldown > 0:
		turn_cooldown -= delta
	
	# Handle smooth rotation animation
	if is_turning:
		turn_progress += delta / turn_animation_duration
		if turn_progress >= 1.0:
			# Finish the turn
			turn_progress = 1.0
			is_turning = false
			transform.basis = turn_target_rotation
		else:
			# Interpolate rotation
			transform.basis = turn_start_rotation.slerp(turn_target_rotation, turn_progress)
	
	# Determine movement speed based on boost input
	if can_boost and Input.is_action_pressed(input_boost):
		move_speed = boost_speed
	else:
		move_speed = base_speed

	# Handle directional input for snake turning (90-degree discrete turns)
	if can_move and turn_cooldown <= 0 and not is_turning:
		var turn_requested = false
		# Start with the current basis (orientation)
		var new_basis = transform.basis

		if Input.is_action_just_pressed(input_up):  # Pitch up
			new_basis = new_basis.rotated(new_basis.x, PI/2)
			turn_requested = true
		elif Input.is_action_just_pressed(input_down):  # Pitch down
			new_basis = new_basis.rotated(new_basis.x, -PI/2)
			turn_requested = true
		elif Input.is_action_just_pressed(input_left):  # Yaw left
			new_basis = new_basis.rotated(new_basis.y, PI/2)
			turn_requested = true
		elif Input.is_action_just_pressed(input_right):  # Yaw right
			new_basis = new_basis.rotated(new_basis.y, -PI/2)
			turn_requested = true

		if turn_requested:
			turn_start_rotation = transform.basis
			turn_target_rotation = new_basis.orthonormalized()
			turn_progress = 0.0
			is_turning = true
			turn_cooldown = turn_delay
	
	# Always move forward in the current facing direction (independent of mouse look)
	movement_direction = -transform.basis.z  # Forward direction based on snake's orientation
	velocity = movement_direction * move_speed
	
	# Use velocity to actually move
	move_and_slide()
	
	# Update camera if not in free look mode
	if not free_look_active:
		reset_camera_to_base()


## Switch between first person and third person camera views
func switch_camera():
	is_first_person = not is_first_person
	
	if is_first_person:
		first_person_camera.current = true
		third_person_camera.current = false
		# Sync to head orientation, so first person matches last viewed direction
		base_look_rotation.y = head.rotation.y
		base_look_rotation.x = head.rotation.x
		look_rotation = base_look_rotation
	else:
		first_person_camera.current = false
		third_person_camera.current = true
		# When switching to third person, keep the current look rotation fixed


## Rotate camera/head to look around (free look - only when Ctrl is held).
## This is purely visual and doesn't change the snake's movement direction.
func rotate_look(rot_input : Vector2):
	if free_look_active:
		look_rotation.x -= rot_input.y * look_speed
		look_rotation.x = clamp(look_rotation.x, deg_to_rad(-85), deg_to_rad(85))
		look_rotation.y -= rot_input.x * look_speed
		
		# Apply free look rotation to the head
		head.transform.basis = Basis()
		head.rotate_y(look_rotation.y)
		head.rotate_x(look_rotation.x)


## Reset camera to follow the snake's body rotation
func reset_camera_to_base():
	# Smoothly return camera to base position (faster interpolation for responsive turning)
	look_rotation = look_rotation.lerp(base_look_rotation, 0.3)
	
	# Apply the base camera rotation
	head.transform.basis = Basis()
	head.rotate_y(look_rotation.y)
	head.rotate_x(look_rotation.x)


func capture_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true


func release_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false

## Checks if some Input Actions haven't been created.
## Disables functionality accordingly.
func check_input_mappings():
	if can_move and not InputMap.has_action(input_left):
		push_error("Movement disabled. No InputAction found for input_left: " + input_left)
		can_move = false
	if can_move and not InputMap.has_action(input_right):
		push_error("Movement disabled. No InputAction found for input_right: " + input_right)
		can_move = false
	if can_move and not InputMap.has_action(input_up):
		push_error("Movement disabled. No InputAction found for input_up: " + input_up)
		can_move = false
	if can_move and not InputMap.has_action(input_down):
		push_error("Movement disabled. No InputAction found for input_down: " + input_down)
		can_move = false
	if can_boost and not InputMap.has_action(input_boost):
		push_error("Boost disabled. No InputAction found for input_boost: " + input_boost)
		can_boost = false
	if not InputMap.has_action(input_free_look):
		push_error("Free look disabled. No InputAction found for input_free_look: " + input_free_look)
		# Note: We don't disable anything here, just warn
	if not InputMap.has_action(input_camera_switch):
		push_error("Camera switch disabled. No InputAction found for input_camera_switch: " + input_camera_switch)
		# Note: We don't disable anything here, just warn
		
