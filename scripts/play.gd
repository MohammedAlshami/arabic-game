extends Node3D

const MapLoader = preload("res://scripts/map_loader.gd")

var gridmap: GridMap
var player: Node3D
var view: Node3D
var day_night: Node = null

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
	gridmap = $GridMap
	gridmap.mesh_library = mesh_lib

	MapLoader.place_cells(gridmap, map_data, mesh_lib.get_meta("id_map"))

	# Ground plane
	var ground = MeshInstance3D.new()
	ground.mesh = BoxMesh.new()
	ground.mesh.size = Vector3(60, 0.5, 60)
	ground.position = Vector3(0, -0.5, 0)
	add_child(ground)

	var body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(60, 1, 60)
	body.add_child(col)
	body.position = Vector3(0, -0.75, 0)
	add_child(body)

	# Day/Night manager
	day_night = load("res://scripts/day_night.gd").new()
	add_child(day_night)

	# Spawn player
	var spawn_pos = Vector3(0, 2, 0)
	if map_data.has("character"):
		var ch = map_data["character"]
		spawn_pos = Vector3(ch.get("x", 0), 0, ch.get("z", 0))
	_spawn_player(spawn_pos)

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

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BACKSPACE:
			get_tree().change_scene_to_file("res://scenes/menu.tscn")
			return
		if event.keycode == KEY_V and day_night and not day_night.is_sleeping:
			_try_sleep()

func _try_sleep():
	if not gridmap or not player:
		return
	var cell = gridmap.local_to_map(player.global_position)
	var ml = gridmap.mesh_library
	if not ml or not ml.has_meta("id_map"):
		return
	var id_map = ml.get_meta("id_map")
	var rev_map = {}
	for key in id_map:
		rev_map[id_map[key]] = key
	var bed_ids = day_night.get_bed_ids()
	for x in range(-1, 2):
		for z in range(-1, 2):
			var check = cell + Vector3i(x, 0, z)
			var item = gridmap.get_cell_item(check)
			if item >= 0:
				var sid = rev_map.get(item, "")
				if sid in bed_ids:
					_sleep()
					return

func _sleep():
	if not day_night or day_night.is_sleeping:
		return
	player.set_process(false)
	player.set_physics_process(false)
	player.visible = false
	player.collision_layer = 0
	player.collision_mask = 0
	day_night.sleep()

func _physics_process(_delta):
	if day_night and day_night.is_player_asleep() == false and day_night.is_sleeping == false:
		if not player.visible:
			player.set_process(true)
			player.set_physics_process(true)
			player.visible = true
			player.collision_layer = 1
			player.collision_mask = 1
