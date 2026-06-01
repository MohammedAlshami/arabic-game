extends Node3D

@onready var player_spawn := $PlayerSpawn

func _ready():
	load_map()

func load_map():
	if GameState.map_to_load.is_empty():
		return

	var map_data = ResourceLoader.load(GameState.map_to_load)
	if not map_data:
		return

	var structures_path = "res://structures/"
	var dir = DirAccess.open(structures_path)
	if not dir:
		return

	var structure_resources: Array[Structure] = []
	dir.list_dir_begin()
	var f = dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			var res = ResourceLoader.load(structures_path + f)
			if res is Structure:
				structure_resources.append(res)
		f = dir.get_next()
	dir.list_dir_end()

	var mesh_library = MeshLibrary.new()
	for s in structure_resources:
		var id = mesh_library.get_last_unused_item_id()
		mesh_library.create_item(id)
		mesh_library.set_item_mesh(id, get_mesh_from_scene(s.model))
		mesh_library.set_item_mesh_transform(id, Transform3D())

	var gridmap = $GridMap
	gridmap.mesh_library = mesh_library

	for cell in map_data.structures:
		gridmap.set_cell_item(Vector3i(cell.position.x, 0, cell.position.y), cell.structure, cell.orientation)

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

	if map_data.character_position != Vector3.ZERO:
		var player = load("res://scenes/objects/player.tscn").instantiate()
		player.position = map_data.character_position + Vector3(0, 1, 0)
		var view = load("res://scripts/view_platformer.gd").new()
		view.target = player
		player.view = view
		add_child(view)
		view.position = player.position
		add_child(player)
	else:
		var player = load("res://scenes/objects/player.tscn").instantiate()
		player.position = Vector3(0, 2, 0)
		var view = load("res://scripts/view_platformer.gd").new()
		view.target = player
		player.view = view
		add_child(view)
		view.position = player.position
		add_child(player)

func get_mesh_from_scene(packed_scene):
	if not packed_scene:
		return null
	var state = packed_scene.get_state()
	for i in range(state.get_node_count()):
		if state.get_node_type(i) == "MeshInstance3D":
			for j in range(state.get_node_property_count(i)):
				if state.get_node_property_name(i, j) == "mesh":
					return state.get_node_property_value(i, j).duplicate()
	return null

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
