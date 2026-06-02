extends CharacterBody3D

var speed := 8.0
var rotation_speed := 2.5
var occupying := false
var gridmap: GridMap = null

var driveable_indices := [0, 1, 2, 3, 4, 48, 49, 50, 51, 52]

func _physics_process(delta):
	if not occupying:
		return

	handle_driving(delta)
	enforce_lane()

func handle_driving(delta):
	var forward := Input.get_axis("move_back", "move_forward")
	var turn := Input.get_axis("move_right", "move_left")

	if abs(forward) > 0.1:
		var dir = -global_transform.basis.z * forward
		velocity = dir * speed
		rotation.y += turn * rotation_speed * delta
	else:
		velocity = velocity.lerp(Vector3.ZERO, delta * 5)

	move_and_slide()

func enforce_lane():
	if not gridmap:
		return

	var cell = gridmap.local_to_map(global_position)
	var item = gridmap.get_cell_item(cell)

	if item == -1 or item not in driveable_indices:
		var nearest = _find_nearest_straight(cell)
		if nearest != null:
			global_position.x = gridmap.map_to_local(nearest).x
			velocity.x = 0
		else:
			global_position = gridmap.map_to_local(cell)
			velocity = Vector3.ZERO

func _find_nearest_straight(from: Vector3i) -> Vector3i:
	for x in range(-5, 6):
		var check = Vector3i(from.x + x, 0, from.z)
		var item = gridmap.get_cell_item(check)
		if item in driveable_indices:
			return check
	return from
