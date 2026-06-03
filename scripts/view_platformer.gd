extends Node3D

@export_group("Properties")
@export var target: Node

@export_group("Zoom")
@export var zoom_minimum = 8
@export var zoom_maximum = 2
@export var zoom_speed = 10

@export_group("Rotation")
@export var rotation_speed = 0.3

var camera_rotation_x := -20.0
var camera_rotation_y := 0.0
var zoom = 3

@onready var camera = $Camera

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta):
	if not target:
		return

	self.position = self.position.lerp(target.position, delta * 4)
	rotation_degrees = Vector3(camera_rotation_x, camera_rotation_y, 0)
	camera.position = camera.position.lerp(Vector3(0, 0, zoom), 8 * delta)

func _input(event):
	if event is InputEventMouseMotion:
		camera_rotation_y -= event.relative.x * rotation_speed * 0.1
		camera_rotation_x -= event.relative.y * rotation_speed * 0.1
		camera_rotation_x = clamp(camera_rotation_x, -80, -10)
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom -= zoom_speed * 0.1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom += zoom_speed * 0.1
		zoom = clamp(zoom, zoom_maximum, zoom_minimum)
	
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
