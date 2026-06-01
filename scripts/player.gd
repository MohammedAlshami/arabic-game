extends CharacterBody3D

@export var speed := 8.0
@export var jump_velocity := 10.0
@export var gravity := 25.0
@export var mouse_sensitivity := 0.002

@onready var camera_pivot := $CameraPivot
@onready var camera := $CameraPivot/Camera3D
@onready var mesh_instance := $MeshInstance3D

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -0.5, 1.0)

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	if Input.is_action_just_pressed("move_jump") and is_on_floor():
		velocity.y = jump_velocity

	move_and_slide()

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
