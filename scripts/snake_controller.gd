# Snake3D Controller - Camera and Visual Control
# Smooth basis-based turning (preserves local-basis 90° turns, but interpolates like an FPS)

extends CharacterBody3D

## Can we control the camera?
@export var can_control_camera : bool = true

@export_group("Camera Settings")
## Look around rotation speed.
@export var look_speed : float = 0.002
## Duration for smooth camera following.
@export var follow_animation_duration : float = 0.2
## Damped follow speed for first-person to avoid hard snaps
@export var follow_damp_speed: float = 16.0
@export_group("Input Actions")
## Name of Input Action for free look (Ctrl).
@export var input_free_look : String = "free_look"
## Name of Input Action to switch camera view (C).
@export var input_camera_switch : String = "camera_switch"

var mouse_captured : bool = false
var look_rotation : Vector2

# Variables for smooth position following
var is_following : bool = false
var follow_start_position : Vector3
var follow_target_position : Vector3
var follow_progress : float = 0.0
var follow_has_target: bool = false

# Variables for camera control and smooth turning
var free_look_active : bool = false
var prev_free_look_active : bool = false
var is_first_person : bool = true  # Track current camera mode

# Variables for smooth turn animation (basis-based)
var is_turning : bool = false
var turn_start_basis : Basis
var turn_target_basis : Basis
var turn_progress : float = 0.0
# Exported animation config and cooldown for discrete 90° turns
@export var turn_animation_duration : float = 0.3
@export var turn_delay : float = 0.12
var turn_cooldown : float = 0.0

# Head offset smoothing (to avoid snapping when clearing free-look offsets)
var head_start_basis : Basis = Basis.IDENTITY
var head_target_basis : Basis = Basis.IDENTITY

## IMPORTANT REFERENCES
@onready var head: Node3D = $Head
@onready var first_person_camera: Camera3D = $Head/FirstPersonCamera
@onready var third_person_camera: Camera3D = $Head/ThirdPersonCamera
@onready var mesh: MeshInstance3D = $Mesh

# Helper: snap a Vector3 to the closest cardinal axis unit Vector3i
func _nearest_axis(v: Vector3) -> Vector3i:
	var axes = [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(0,0,1), Vector3i(0,0,-1)]
	var best_axis = axes[0]
	var best_dot = -INF
	for a in axes:
		var d = abs(v.dot(Vector3(a)))
		if d > best_dot:
			best_dot = d
			best_axis = a
	return best_axis

func _ready() -> void:
	check_input_mappings()
	
	# Hide the snake controller's own mesh since we use separate visual segments
	if mesh:
		mesh.visible = false
	
	# Initialize transform to face forward (default snake direction is +Z)
	var initial_forward = Vector3(0, 0, 1)  # Forward
	var up = Vector3.UP
	var right = up.cross(initial_forward).normalized()
	transform.basis = Basis(right, up, -initial_forward).orthonormalized()
	
	# Ensure first person camera is active by default
	first_person_camera.current = true
	third_person_camera.current = false

func _unhandled_input(event: InputEvent) -> void:
	if not can_control_camera:
		return
		
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
	# IMPORTANT: remove the "else reset_camera_to_base()" here so we don't clobber head basis during turns
	if mouse_captured and event is InputEventMouseMotion:
		if free_look_active:
			rotate_look(event.relative)
		# else: do nothing here — resetting is handled in _physics_process once, not per mouse motion.

func _physics_process(delta: float) -> void:
	# Tick down turn cooldown
	if turn_cooldown > 0.0:
		turn_cooldown -= delta
		if turn_cooldown < 0.0:
			turn_cooldown = 0.0
	
	# Handle smooth position following animation (third person tween)
	if is_following and not is_first_person:
		follow_progress += delta / follow_animation_duration
		if follow_progress >= 1.0:
			# Finish the follow
			follow_progress = 1.0
			is_following = false
			global_position = follow_target_position
		else:
			# Interpolate position
			global_position = follow_start_position.lerp(follow_target_position, follow_progress)
	
	# Damped per-frame follow for first person to avoid position jumps
	if is_first_person and follow_has_target:
		var to_target := follow_target_position - global_position
		global_position += to_target * clamp(delta * follow_damp_speed, 0.0, 1.0)
		if to_target.length() < 0.001:
			follow_has_target = false
	
	# Smooth turning using eased quaternion slerp for a clear visible rotation
	if is_turning:
		var dur: float = maxf(0.001, turn_animation_duration)
		turn_progress += delta / dur
		var t: float = clampf(turn_progress, 0.0, 1.0)
		# Smoothstep easing for nicer feel
		var s: float = t * t * (3.0 - 2.0 * t)

		# Body orientation interpolation (quaternion slerp from start to target)
		var q_from: Quaternion = Quaternion(turn_start_basis)
		var q_to: Quaternion = Quaternion(turn_target_basis)
		var q_now: Quaternion = q_from.slerp(q_to, s)
		transform.basis = Basis(q_now).orthonormalized()

		# Smoothly reduce any head/free-look offset back to identity *unless* freelook is active
		if not free_look_active:
			var qh_from: Quaternion = Quaternion(head_start_basis)
			var qh_to: Quaternion = Quaternion(head_target_basis) # usually identity
			var qh_now: Quaternion = qh_from.slerp(qh_to, s)
			head.transform.basis = Basis(qh_now).orthonormalized()

		if t >= 1.0:
			# Finish the turn
			is_turning = false
			turn_progress = 1.0
			transform.basis = turn_target_basis.orthonormalized()
			# Ensure head target is applied at the end (if freelook isn't active)
			if not free_look_active:
				head.transform.basis = head_target_basis.orthonormalized()
			# Start a short cooldown before another turn
			turn_cooldown = maxf(0.0, turn_delay)
	else:
		# Only reset the head to base once when freelook was just released (avoid clobbering during slerp)
		if prev_free_look_active and not free_look_active and not is_turning:
			reset_camera_to_base()
		# If not turning and not freelooking, ensure head matches body local orientation (keeps camera steady)
		# (This does not kill any turn interpolation because is_turning is false here)
		if not free_look_active and not is_turning:
			# leave as-is; reset_camera_to_base() already run when freelook changed
			pass

	# save freelook previous state for one-shot actions
	prev_free_look_active = free_look_active

## Move the camera controller to follow a new position smoothly
func follow_to_position(target_pos: Vector3):
	# First-person: damped follow to avoid trailing jitter and hard snaps
	if is_first_person:
		follow_target_position = target_pos
		follow_has_target = true
		return
	# Third-person: subtle smoothing tween
	follow_start_position = global_position
	follow_target_position = target_pos
	follow_progress = 0.0
	is_following = true

# Build a robust target basis from a desired forward and up vectors (grid-aligned), avoiding roll
func _basis_from_forward_up(forward: Vector3, up: Vector3) -> Basis:
	var f := forward.normalized()
	var u := up.normalized()
	if f == Vector3.ZERO:
		f = Vector3(0,0,1)
	# Ensure up is not parallel to forward
	if abs(f.dot(u)) > 0.999:
		u = Vector3(0,1,0) if abs(f.dot(Vector3.UP)) < 0.9 else Vector3(1,0,0)
	var r := u.cross(f).normalized()
	u = f.cross(r).normalized()
	return Basis(r, u, -f).orthonormalized()

## Handle orientation change from grid system (preferred API)
func on_snake_orientation_changed(new_forward: Vector3i, new_up: Vector3i):
	# Gate here too, to be safe (GameController may already gate)
	if not can_accept_turn():
		return
	turn_start_basis = transform.basis
	var f = Vector3(new_forward)
	var u = Vector3(new_up)
	turn_target_basis = _basis_from_forward_up(f, u)
	turn_progress = 0.0
	is_turning = true

	# Smoothly clear any freelook/head offset over the turn duration instead of snapping
	head_start_basis = head.transform.basis
	head_target_basis = Basis.IDENTITY
	# Do NOT instantly set head.transform.basis = Basis.IDENTITY here (that caused snap)


## NEW: request a local-axis turn (keeps your original local-basis rotation semantics)
## Example usage: request_local_turn(transform.basis.y, PI/2)  <-- yaw left/right
func request_local_turn(local_axis: Vector3, angle_radians: float):
	if not can_accept_turn():
		return
	turn_start_basis = transform.basis
	# rotate around the *local* axis (local_axis should be in world coords, e.g. transform.basis.x)
	turn_target_basis = transform.basis.rotated(local_axis.normalized(), angle_radians).orthonormalized()
	turn_progress = 0.0
	is_turning = true

	# Smoothly clear freelook/head offset during the turn
	head_start_basis = head.transform.basis
	head_target_basis = Basis.IDENTITY
	# Do not zero look_rotation instantly — we smoothly interpolate the actual head basis.

## Expose whether we can accept a new turn now
func can_accept_turn() -> bool:
	return (not is_turning) and turn_cooldown <= 0.0

## Handle direction change from grid system (compatibility)
func on_snake_direction_changed(grid_direction: Vector3i):
	var f = Vector3(grid_direction)
	if f == Vector3.ZERO:
		return
	# Use current up (snapped to nearest axis) to define a full orientation
	var current_up_axis: Vector3i = _nearest_axis(transform.basis.y)
	on_snake_orientation_changed(grid_direction, current_up_axis)

## Switch between first person and third person camera views
func switch_camera():
	is_first_person = not is_first_person
	
	if is_first_person:
		first_person_camera.current = true
		third_person_camera.current = false
		# Don't hard snap; keep damp follower target
		follow_has_target = true
		# Sync to head orientation, so first person matches last viewed direction
		# Keep look_rotation as-is (the head basis is used directly)
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
		
		# Apply free look rotation to the head (this *does* set the head basis directly while freelook is active)
		head.transform.basis = Basis()
		head.rotate_y(look_rotation.y)
		head.rotate_x(look_rotation.x)


## Reset camera to follow the snake's body rotation (one-shot)
func reset_camera_to_base():
	# Camera follows snake body orientation directly
	head.transform.basis = Basis.IDENTITY
	look_rotation = Vector2.ZERO


func capture_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true


func release_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false

## Checks if some Input Actions haven't been created.
## Disables functionality accordingly.
func check_input_mappings():
	if not InputMap.has_action(input_free_look):
		push_error("Free look disabled. No InputAction found for input_free_look: " + input_free_look)
		# Note: We don't disable anything here, just warn
	if not InputMap.has_action(input_camera_switch):
		push_error("Camera switch disabled. No InputAction found for input_camera_switch: " + input_camera_switch)
		# Note: We don't disable anything here, just warn
