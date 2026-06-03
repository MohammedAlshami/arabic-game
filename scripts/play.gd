extends Node3D

const MapLoader = preload("res://scripts/map_loader.gd")
const INITIAL_RADIUS = 80
const TRIGGER_DISTANCE = 50
const EXPAND_CHUNK = 30
const GROUND_MARGIN = 10
const SAVE_DEBOUNCE_SECS = 2.0

var gridmap: GridMap
var player: Node3D
var view: Node3D
var day_night: Node = null

var filename: String
var map_data: Dictionary
var id_map: Dictionary
var grass_block_id: int = -1

var bounds_min: Vector3i = Vector3i(999999, 0, 999999)
var bounds_max: Vector3i = Vector3i(-999999, 0, -999999)
var last_player_cell: Vector3i = Vector3i(999999, 0, 999999)
var ground_plane: MeshInstance3D
var ground_body: StaticBody3D
var unsaved_changes: bool = false
var save_timer: float = 0.0
var fog_visible := false

func _ready():
	load_map()

func load_map():
	filename = GameState.map_to_load
	if filename.is_empty():
		return

	var defs = MapLoader.load_definitions()
	if defs.is_empty():
		return

	map_data = MapLoader.load_map(filename)
	if map_data.is_empty():
		return

	var mesh_lib = MapLoader.build_mesh_library(defs)
	gridmap = $GridMap
	gridmap.mesh_library = mesh_lib

	id_map = mesh_lib.get_meta("id_map")
	grass_block_id = id_map.get("block-grass", -1)
	MapLoader.place_cells(gridmap, map_data, id_map)

	for cell_pos in gridmap.get_used_cells():
		bounds_min.x = mini(bounds_min.x, cell_pos.x)
		bounds_min.z = mini(bounds_min.z, cell_pos.z)
		bounds_max.x = maxi(bounds_max.x, cell_pos.x)
		bounds_max.z = maxi(bounds_max.z, cell_pos.z)

	var span = max(bounds_max.x - bounds_min.x, bounds_max.z - bounds_min.z)
	_create_ground_plane()
	if span < INITIAL_RADIUS * 2:
		var spawn_center = Vector3i(0, 0, 0)
		if map_data.has("character"):
			spawn_center = Vector3i(map_data["character"].get("x", 0), 0, map_data["character"].get("z", 0))
		_generate_initial_area(spawn_center)

	day_night = load("res://scripts/day_night.gd").new()
	add_child(day_night)

	var spawn_pos = Vector3(0, 2, 0)
	if map_data.has("character"):
		var ch = map_data["character"]
		spawn_pos = Vector3(ch.get("x", 0), ch.get("y", 0), ch.get("z", 0))
	_spawn_player(spawn_pos)

	var env_node = $WorldEnvironment
	if env_node and env_node.environment:
		env_node.environment.fog_enabled = false

func _create_ground_plane():
	var center = _get_ground_center()
	var size = _get_ground_size()

	ground_plane = MeshInstance3D.new()
	ground_plane.mesh = BoxMesh.new()
	ground_plane.mesh.size = size
	ground_plane.position = Vector3(center.x, -0.5, center.y)
	add_child(ground_plane)

	ground_body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(size.x, 1, size.z)
	ground_body.add_child(col)
	ground_body.position = Vector3(center.x, -0.75, center.y)
	add_child(ground_body)

func _get_ground_center() -> Vector2:
	if bounds_min.x == 999999:
		return Vector2(0, 0)
	return Vector2(
		(bounds_min.x + bounds_max.x) / 2.0,
		(bounds_min.z + bounds_max.z) / 2.0
	)

func _get_ground_size() -> Vector3:
	if bounds_min.x == 999999:
		return Vector3(10, 0.5, 10)
	var sx = (bounds_max.x - bounds_min.x) + 1 + GROUND_MARGIN * 2
	var sz = (bounds_max.z - bounds_min.z) + 1 + GROUND_MARGIN * 2
	return Vector3(sx, 0.5, sz)

func _update_ground_plane():
	var center = _get_ground_center()
	var size = _get_ground_size()
	ground_plane.position = Vector3(center.x, -0.5, center.y)
	ground_plane.mesh.size = size
	ground_body.position = Vector3(center.x, -0.75, center.y)
	ground_body.get_child(0).shape.size = Vector3(size.x, 1, size.z)

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
		if event.keycode == KEY_F1:
			fog_visible = not fog_visible
			var env_node = $WorldEnvironment
			if env_node and env_node.environment:
				env_node.environment.fog_enabled = fog_visible
			return

func _try_sleep():
	if not gridmap or not player:
		return
	var cell = gridmap.local_to_map(player.global_position)
	var ml = gridmap.mesh_library
	if not ml or not ml.has_meta("id_map"):
		return
	var loaded_id_map = ml.get_meta("id_map")
	var rev_map = {}
	for key in loaded_id_map:
		rev_map[loaded_id_map[key]] = key
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

func _physics_process(delta):
	if day_night and day_night.is_player_asleep() == false and day_night.is_sleeping == false:
		if not player.visible:
			player.set_process(true)
			player.set_physics_process(true)
			player.visible = true
			player.collision_layer = 1
			player.collision_mask = 1

	if player and gridmap:
		var cell = gridmap.local_to_map(player.global_position)
		if cell != last_player_cell:
			last_player_cell = cell
			_generate_if_needed(cell)

	if unsaved_changes:
		save_timer -= delta
		if save_timer <= 0:
			_save_map()

func _generate_initial_area(center: Vector3i):
	if grass_block_id < 0:
		return
	for x in range(center.x - INITIAL_RADIUS, center.x + INITIAL_RADIUS + 1):
		for z in range(center.z - INITIAL_RADIUS, center.z + INITIAL_RADIUS + 1):
			var pos = Vector3i(x, 0, z)
			if gridmap.get_cell_item(pos) < 0:
				gridmap.set_cell_item(pos, grass_block_id)
				bounds_min.x = mini(bounds_min.x, x)
				bounds_min.z = mini(bounds_min.z, z)
				bounds_max.x = maxi(bounds_max.x, x)
				bounds_max.z = maxi(bounds_max.z, z)
	_update_ground_plane()

func _generate_if_needed(player_cell: Vector3i):
	if grass_block_id < 0:
		return
	var changed = false

	if bounds_max.x - player_cell.x < TRIGGER_DISTANCE:
		var new_max = bounds_max.x + EXPAND_CHUNK
		for x in range(bounds_max.x + 1, new_max + 1):
			for z in range(bounds_min.z, bounds_max.z + 1):
				var pos = Vector3i(x, 0, z)
				if gridmap.get_cell_item(pos) < 0:
					gridmap.set_cell_item(pos, grass_block_id)
					changed = true
		bounds_max.x = new_max

	if player_cell.x - bounds_min.x < TRIGGER_DISTANCE:
		var new_min = bounds_min.x - EXPAND_CHUNK
		for x in range(new_min, bounds_min.x):
			for z in range(bounds_min.z, bounds_max.z + 1):
				var pos = Vector3i(x, 0, z)
				if gridmap.get_cell_item(pos) < 0:
					gridmap.set_cell_item(pos, grass_block_id)
					changed = true
		bounds_min.x = new_min

	if bounds_max.z - player_cell.z < TRIGGER_DISTANCE:
		var new_max = bounds_max.z + EXPAND_CHUNK
		for z in range(bounds_max.z + 1, new_max + 1):
			for x in range(bounds_min.x, bounds_max.x + 1):
				var pos = Vector3i(x, 0, z)
				if gridmap.get_cell_item(pos) < 0:
					gridmap.set_cell_item(pos, grass_block_id)
					changed = true
		bounds_max.z = new_max

	if player_cell.z - bounds_min.z < TRIGGER_DISTANCE:
		var new_min = bounds_min.z - EXPAND_CHUNK
		for z in range(new_min, bounds_min.z):
			for x in range(bounds_min.x, bounds_max.x + 1):
				var pos = Vector3i(x, 0, z)
				if gridmap.get_cell_item(pos) < 0:
					gridmap.set_cell_item(pos, grass_block_id)
					changed = true
		bounds_min.z = new_min

	if changed:
		_update_ground_plane()
		_schedule_save()

func _schedule_save():
	save_timer = SAVE_DEBOUNCE_SECS
	unsaved_changes = true

func _save_map():
	if not unsaved_changes:
		return
	var cells = MapLoader.read_cells(gridmap, id_map)
	map_data["cells"] = cells
	MapLoader.save_map(map_data, filename)
	unsaved_changes = false
