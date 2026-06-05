extends Node3D

@export_group("Properties")
@export var target: Node

@export_group("Zoom")
@export var zoom_minimum = 8
@export var zoom_maximum = 2
@export var zoom_speed = 10

@export_group("Rotation")
@export var rotation_speed = 120

var camera_rotation_x := -20.0
var camera_rotation_y := 0.0
var zoom = 3

var first_person := false
var head_height := 1.2
var input_paused := false

@onready var camera = $Camera

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func toggle_view_mode():
	first_person = not first_person
	if first_person:
		zoom = 0.5
		camera_rotation_x = 0
	else:
		zoom = 3
		camera_rotation_x = -20

func _physics_process(delta):
	if not target:
		return

	self.position = self.position.lerp(target.position, delta * 4)
	rotation_degrees = Vector3(camera_rotation_x, camera_rotation_y, 0)
	var cam_pos = Vector3(0, head_height if first_person else 0, zoom)
	camera.position = camera.position.lerp(cam_pos, 8 * delta)

	if not input_paused:
		var yaw = Input.get_axis("camera_right", "camera_left")
		var pitch = Input.get_axis("camera_up", "camera_down")

		var move_x = Input.get_axis("move_left", "move_right")
		var move_z = Input.get_axis("move_forward", "move_back")
		var moving = Vector2(move_x, move_z)
		if moving.length() > 0.1 and abs(yaw) < 0.3:
			var move_angle = atan2(move_x, -move_z)
			camera_rotation_y += rad_to_deg(-move_angle) * 2.0 * delta

		camera_rotation_y += yaw * rotation_speed * delta
		camera_rotation_x -= pitch * rotation_speed * delta
		if first_person:
			camera_rotation_x = clamp(camera_rotation_x, -80, 80)
		else:
			camera_rotation_x = clamp(camera_rotation_x, -80, -10)
