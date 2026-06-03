extends Node3D

const MapLoader = preload("res://scripts/map_loader.gd")

var gridmap: GridMap
var player: Node3D
var view: Node3D

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

	# Ground plane (lower it to avoid z-fighting with structures)
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
