extends CharacterBody3D

signal coin_collected

@export_subgroup("Components")
@export var view: Node3D

@export_subgroup("Properties")
@export var movement_speed = 250
@export var jump_strength = 7

var movement_velocity: Vector3
var rotation_direction: float
var gravity = 0

var previously_floored = false
var peak_y: float = 0.0
var falling_hard: bool = false
var falling_sound_played: bool = false
var crash_sound_played: bool = false
var fall_audio: AudioStreamPlayer
var crash_audio: AudioStreamPlayer

var coins = 0

@onready var particles_trail = $ParticlesTrail
@onready var sound_footsteps = $SoundFootsteps
@onready var model = $Character
@onready var animation = $Character/AnimationPlayer
var falling_snd: AudioStreamPlayer
var crash_snd: AudioStreamPlayer

# Functions

func _ready():
	falling_snd = AudioStreamPlayer.new()
	crash_snd = AudioStreamPlayer.new()
	add_child(falling_snd)
	add_child(crash_snd)

func _physics_process(delta):

	# Handle functions

	handle_controls(delta)
	handle_gravity(delta)

	handle_effects(delta)

	# Movement

	var applied_velocity: Vector3

	applied_velocity = velocity.lerp(movement_velocity, delta * 10)
	applied_velocity.y = -gravity

	velocity = applied_velocity
	move_and_slide()

	# Rotation

	if Vector2(velocity.z, velocity.x).length() > 0:
		rotation_direction = Vector2(velocity.z, velocity.x).angle()

	rotation.y = lerp_angle(rotation.y, rotation_direction, delta * 10)

	# Falling/respawning

	if position.y < -10:
		get_tree().reload_current_scene()

	# Track falling state BEFORE landing logic
	var was_falling_hard = falling_hard
	var just_landed = is_on_floor() and not previously_floored
	var fall_dist = peak_y - position.y

	# Track peak height for falling pose

	if velocity.y > 0:
		peak_y = max(peak_y, position.y)
		falling_hard = false
	elif velocity.y < 0 and not is_on_floor():
		if fall_dist > 6:
			falling_hard = true

	# Animation for scale (jumping and landing)

	model.scale = model.scale.lerp(Vector3(1, 1, 1), delta * 10)

	# Falling pose (head down)

	if falling_hard:
		model.rotation.x = lerp_angle(model.rotation.x, deg_to_rad(90), delta * 5)
	elif not is_on_floor():
		model.rotation.x = lerp_angle(model.rotation.x, deg_to_rad(0), delta * 5)

	# Falling sound
	if velocity.y < -1 and fall_dist > 8 and not falling_sound_played and not is_on_floor():
		falling_sound_played = true
		var s = load("res://sounds/falling.mp3")
		if s:
			falling_snd.stream = s
			falling_snd.volume_db = -8
			falling_snd.play()

	# Crash sound — play just before impact
	if falling_hard and not crash_sound_played:
		var space = get_world_3d().direct_space_state
		if space:
			var from = position
			var to = position + Vector3(0, -4, 0)
			var query = PhysicsRayQueryParameters3D.create(from, to)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			var result = space.intersect_ray(query)
			if not result.is_empty():
				var dist = position.y - result["position"].y
				if dist < 2.5:
					crash_sound_played = true
					var s = load("res://sounds/crash.mp3")
					if s:
						crash_snd.stream = s
						crash_snd.volume_db = -5
						crash_snd.play()

	# Animation when landing

	if is_on_floor():
		model.rotation.x = lerp_angle(model.rotation.x, deg_to_rad(0), delta * 10)
		peak_y = position.y
		falling_hard = false
		falling_sound_played = false
		crash_sound_played = false
		if just_landed and gravity > 2:
			model.scale = Vector3(1.25, 0.75, 1.25)
			if not was_falling_hard:
				Audio.play("res://sounds/land.ogg")

	previously_floored = is_on_floor()

# Handle animation(s)

func handle_effects(delta):

	particles_trail.emitting = false
	sound_footsteps.stream_paused = true

	if is_on_floor():
		var horizontal_velocity = Vector2(velocity.x, velocity.z)
		var speed_factor = horizontal_velocity.length() / movement_speed / delta
		if speed_factor > 0.05:
			if animation.current_animation != "walk":
				animation.play("walk", 0.1)

			if speed_factor > 0.3:
				sound_footsteps.stream_paused = false
				sound_footsteps.pitch_scale = speed_factor

			if speed_factor > 0.75:
				particles_trail.emitting = true

		elif animation.current_animation != "idle":
			animation.play("idle", 0.1)
			
		if animation.current_animation == "walk":
			animation.speed_scale = speed_factor
		else:
			animation.speed_scale = 1.0
			
	elif animation.current_animation != "jump":
		animation.play("jump", 0.1)

# Handle movement input

func handle_controls(delta):

	# Movement

	var input := Vector3.ZERO

	input.x = Input.get_axis("move_left", "move_right")
	input.z = Input.get_axis("move_forward", "move_back")

	input = input.rotated(Vector3.UP, view.rotation.y)

	if input.length() > 1:
		input = input.normalized()

	var speed_mult = 2.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	movement_velocity = input * movement_speed * speed_mult * delta

	# Jumping

	if Input.is_action_just_pressed("jump"):
		jump()

# Handle gravity

func handle_gravity(delta):

	gravity += 25 * delta

	if gravity > 0 and is_on_floor():
		gravity = 0

# Jumping

func jump():

	Audio.play("res://sounds/jump.ogg")

	gravity = -jump_strength

	model.scale = Vector3(0.5, 1.5, 0.5)

# Collecting coins

func collect_coin():

	coins += 1

	coin_collected.emit(coins)
