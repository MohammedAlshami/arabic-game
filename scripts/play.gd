extends Node3D

const MapLoader = preload("res://scripts/map_loader.gd")

var gridmap: GridMap
var player: Node3D
var view: Node3D
var current_vehicle: Node3D = null
var is_driving := false

func _ready():
	load_map()

func load_map():
	var filename = GameState.map_to_load
	if filename.is_empty():
		return

	var defs = MapLoader.load_definitions()
	if defs.is_empty():
		return

	var map_data = MapLoader.load_map(filename)
	if map_data.is_empty():
		return

	var mesh_lib = MapLoader.build_mesh_library(defs)
	var id_map = mesh_lib.get_meta("id_map")

	gridmap = $GridMap
	gridmap.mesh_library = mesh_lib

	MapLoader.place_cells(gridmap, map_data, id_map)

	# Ground plane
	var ground = MeshInstance3D.new()
	ground.mesh = BoxMesh.new()
	ground.mesh.size = Vector3(60, 0.5, 60)
	ground.position = Vector3(0, -0.25, 0)
	add_child(ground)

	var body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(60, 1, 60)
	body.add_child(col)
	body.position = Vector3(0, -0.5, 0)
	add_child(body)

	# Spawn player
	var spawn_pos = Vector3(0, 2, 0)
	if map_data.has("character"):
		var ch = map_data["character"]
		spawn_pos = Vector3(ch.get("x", 0), 0, ch.get("z", 0))
	_spawn_player(spawn_pos)

	# Spawn vehicles
	_spawn_vehicles(map_data, id_map, defs)

func _spawn_player(pos: Vector3):
	player = load("res://scenes/objects/player.tscn").instantiate()
	player.position = pos + Vector3(0, 1, 0)
	view = load("res://scripts/view_platformer.gd").new()
	view.target = player
	player.view = view
	var cam = Camera3D.new()
	cam.name = "Camera"
	cam.current = true
	view.add_child(cam)
	add_child(view)
	view.position = player.position
	add_child(player)

func _spawn_vehicles(map_data: Dictionary, id_map: Dictionary, defs: Dictionary):
	var car_scene = load("res://scenes/objects/car.tscn")
	for cell in map_data.get("cells", []):
		var sid = cell["id"]
		var entry = defs.get(sid)
		if entry and "/vehicles/" in entry["model"]:
			var gpos = Vector3i(cell.get("x", 0), 0, cell.get("z", 0))
			var item = id_map.get(sid, -1)
			if item >= 0:
				gridmap.set_cell_item(gpos, -1)
			var veh = car_scene.instantiate()
			veh.gridmap = gridmap
			var wpos = gridmap.map_to_local(gpos)
			veh.position = wpos + Vector3(0, 0.5, 0)
			add_child(veh)
			current_vehicle = veh

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BACKSPACE:
			get_tree().change_scene_to_file("res://scenes/menu.tscn")
			return
		if event.keycode == KEY_V:
			if is_driving:
				_exit_vehicle()
			elif current_vehicle and player:
				var dist = player.global_position.distance_to(current_vehicle.global_position)
				if dist < 3.0:
					_enter_vehicle()

func _enter_vehicle():
	if not current_vehicle or not player:
		return
	is_driving = true
	player.visible = false
	player.set_process(false)
	player.set_physics_process(false)
	player.collision_layer = 0
	player.collision_mask = 0
	view.target = current_vehicle
	current_vehicle.occupying = true

func _exit_vehicle():
	if not current_vehicle or not player:
		return
	is_driving = false
	current_vehicle.occupying = false
	var exit_pos = current_vehicle.global_position + current_vehicle.global_transform.basis.x * 2
	player.global_position = exit_pos
	player.visible = true
	player.set_process(true)
	player.set_physics_process(true)
	player.collision_layer = 1
	player.collision_mask = 1
	view.target = player
