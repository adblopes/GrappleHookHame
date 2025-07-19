extends CharacterBody2D

enum GrappleState { IDLE, SHOOTING, ATTACHED, BASHING }

# Nodes
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var raycast: RayCast2D = $RayCast2D
@onready var rope_line: Line2D = $Line2D
@onready var sprite: Sprite2D = $Sprite2D

# Death vars
@export var respawn_position: Vector2
@export var death_bounds := Rect2(Vector2.ZERO, Vector2(720, 480))

# Player movement vars
@export var speed := 200
@export var jump_velocity := -450
@export var gravity := 1300
var air_control := 100.0
var counter_air_control := 2000.0

# Grapple mechanics vars
var grapple_state = GrappleState.IDLE
var grapple_target = Vector2.ZERO
var rope_length = 0.0
var current_rope_length = 0.0
var swing_velocity := 0.0
var swing_angle := 0.0
var swing_frame = 42
var angular_drag = 0.995

# Bash vars
var bash_speed := 1200.0
var bash_direction := Vector2.ZERO
var bash_duration := 0.15
var bash_timer := 0.0
var bash_start_position := Vector2.ZERO

# Coyote time and jump buffering 
var coyote_time := 0.1
var coyote_timer := 0.0
var jump_buffer_time := 0.1
var jump_buffer_timer := 0.0

func _physics_process(delta):
	var direction := Input.get_axis("move_left", "move_right")
	
	# Flip the sprite based on input first
	sprite.flip_h = direction < 0
	
	# If no input, flip based on where it's going 
	if direction == 0:
		sprite.flip_h = velocity.x < 0
	
	# Timers update
	coyote_timer -= delta
	jump_buffer_timer -= delta

	# Refresh coyote timer if grounded
	if is_on_floor():
		coyote_timer = coyote_time

	# If not using grapple
	if grapple_state != GrappleState.ATTACHED:
		velocity.y += gravity * delta

		if is_on_floor():
			velocity.x = direction * speed

			if direction != 0:
				animation_player.play("move_right")
			else:
				animation_player.play("idle")

		else:
			# input in the direction of movement needs to be much weaker than the opposite
			if direction != 0:
				if sign(direction) == sign(velocity.x):
					velocity.x += direction * air_control * delta
				else:
					velocity.x += direction * counter_air_control * delta

		# Check for buffered jump
		if (jump_buffer_timer > 0 and coyote_timer > 0):
			velocity.y = jump_velocity
			jump_buffer_timer = 0
			coyote_timer = 0

	# Grapple movement
	if grapple_state == GrappleState.ATTACHED:
		handle_grapple_movement(delta)
	
	# Bash mechanic
	elif grapple_state == GrappleState.BASHING:
		bash_timer -= delta
		var motion = bash_direction * bash_speed * delta
		var collision = move_and_collide(motion)

		if collision:
			var normal = collision.get_normal()
			# Reflect the direction and reduce speed 
			bash_direction = bash_direction.bounce(normal).normalized()
			velocity = bash_direction * bash_speed * 0.5
			grapple_state = GrappleState.IDLE
		else:
			# No collision, continue moving
			global_position += motion
			if bash_timer <= 0.0:
				velocity = bash_direction * bash_speed
				grapple_state = GrappleState.IDLE
	else:
		move_and_slide()

	# Death check
	if not death_bounds.has_point(global_position):
		die_and_respawn()


func _input(event):
	if event.is_action_pressed("grapple"):
		if grapple_state == GrappleState.IDLE:
			fire_grapple()
		elif grapple_state == GrappleState.ATTACHED:
			bash()

	if event.is_action_pressed("jump"):
		jump_buffer_timer = jump_buffer_time


func _process(_delta):
	if grapple_state == GrappleState.ATTACHED:
		rope_line.points = [to_local(global_position), to_local(grapple_target)]
	else:
		rope_line.points = []


func die_and_respawn():
	global_position = respawn_position
	velocity = Vector2.ZERO
	grapple_state = GrappleState.IDLE
	rope_line.points = []


func fire_grapple():
	# Get cursor position
	var mouse_pos = get_global_mouse_position()
	raycast.global_position = global_position
	raycast.target_position = mouse_pos - global_position
	raycast.force_raycast_update()

	# If cursor vector collides with a wall
	if raycast.is_colliding():
		grapple_target = raycast.get_collision_point()
		grapple_state = GrappleState.ATTACHED
		rope_length = global_position.distance_to(grapple_target)
		current_rope_length = rope_length
		var diff = global_position - grapple_target
		swing_angle = diff.angle() - Vector2.DOWN.angle()
		swing_velocity = 0.0
	else:
		grapple_state = GrappleState.IDLE


func handle_grapple_movement(delta):
	# Apply swing frame
	animation_player.stop()
	sprite.frame = swing_frame
	
	# Cut rope
	if Input.is_action_just_pressed("jump"):
		grapple_state = GrappleState.IDLE
		velocity.y = jump_velocity / 2.0 # small jump
		swing_velocity = 0.0
		return

	# Adjust rope length
	if Input.is_action_pressed("move_up"):
		current_rope_length = max(50.0, current_rope_length - speed * delta)
	elif Input.is_action_pressed("move_down") and not is_on_floor():
		current_rope_length += speed * delta

	# Apply angular force with input
	if Input.is_action_pressed("move_left"):
		swing_velocity += 1.5 * delta
	elif Input.is_action_pressed("move_right"):
		swing_velocity -= 1.5 * delta

	# Apply angular drag
	swing_velocity *= angular_drag
	
	# Gravity as angular acceleration
	swing_velocity += -(gravity / current_rope_length) * sin(swing_angle) * delta

	# Update angle
	swing_angle += swing_velocity * delta

	# Target new position along rope
	var target_pos = grapple_target + Vector2.DOWN.rotated(swing_angle) * current_rope_length
	var move_vector = target_pos - global_position

	# Use move_and_collide to respect collisions
	var collision = move_and_collide(move_vector)

	if collision:
		var bounce = move_vector.bounce(collision.get_normal()) * 0.5 
		var tentative_pos = global_position + bounce

		# Reproject to correct rope length
		var corrected = grapple_target + (tentative_pos - grapple_target).normalized() * current_rope_length
		var corrected_move = corrected - global_position
		move_and_collide(corrected_move)

		# Dampen or reset swing velocity (angular momentum)
		swing_velocity *= -0.5
	else:
		velocity = move_vector / delta

func bash():
	grapple_state = GrappleState.BASHING
	bash_start_position = global_position
	bash_direction = (grapple_target - global_position).normalized()
	bash_timer = bash_duration
