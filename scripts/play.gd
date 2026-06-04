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

var interaction_data: Dictionary = {}
var interaction_popup: Control = null
var crosshair: Control = null

var play_plane: Plane
var hover_marker: MeshInstance3D = null
var hover_marker_mat: Material = null
var hovered_cell_key: String = ""

func _ready():
	play_plane = Plane(Vector3.UP, Vector3.ZERO)
	load_map()
	_build_interaction_popup()
	_build_crosshair()
	_build_hover_marker()

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

	# Load interaction data from map cells
	interaction_data = {}
	for cell in map_data.get("cells", []):
		if cell.has("interactions"):
			var ck = "%d,%d,%d" % [cell.get("x", 0), cell.get("y", 0), cell.get("z", 0)]
			interaction_data[ck] = {"interactions": cell["interactions"]}

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
	if event.is_action_pressed("build"):
		_try_interact()
		return
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
		if event.keycode == KEY_F5:
			if view and view.has_method("toggle_view_mode"):
				view.toggle_view_mode()
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

func _build_interaction_popup():
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "InteractionCanvas"
	add_child(canvas_layer)

	interaction_popup = Control.new()
	interaction_popup.visible = false
	interaction_popup.layout_mode = 3
	interaction_popup.anchors_preset = Control.PRESET_FULL_RECT
	interaction_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas_layer.add_child(interaction_popup)

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	interaction_popup.add_child(overlay)

	var panel = Panel.new()
	panel.layout_mode = 3
	panel.anchors_preset = Control.PRESET_CENTER
	panel.offset_left = -150
	panel.offset_top = -120
	panel.offset_right = 150
	panel.offset_bottom = 120
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.12, 0.1, 0.95)
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.35, 0.28, 0.2, 1)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", panel_style)
	interaction_popup.add_child(panel)

	var title = Label.new()
	title.text = "Choose an option:"
	title.position = Vector2(20, 16)
	title.size = Vector2(260, 30)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	title.add_theme_font_size_override("font_size", 18)
	panel.add_child(title)

	interaction_popup.set_meta("panel", panel)
	interaction_popup.set_meta("title", title)

func _build_crosshair():
	var canvas = null
	for c in get_children():
		if c is CanvasLayer:
			canvas = c
			break
	if not canvas:
		return

	crosshair = Control.new()
	crosshair.visible = true
	crosshair.layout_mode = 3
	crosshair.anchors_preset = Control.PRESET_FULL_RECT
	crosshair.mouse_filter = Control.MOUSE_FILTER_PASS
	canvas.add_child(crosshair)

	var size := 24.0
	var thickness := 3.0
	var gap := 6.0
	var half := size / 2.0 + gap / 2.0
	var color = Color(1, 1, 0, 0.9)

	var h_left = ColorRect.new()
	h_left.color = color
	h_left.layout_mode = 0
	h_left.size = Vector2(size, thickness)
	h_left.set_meta("base_pos", Vector2(-half - size, -thickness / 2.0))
	crosshair.add_child(h_left)

	var h_right = ColorRect.new()
	h_right.color = color
	h_right.layout_mode = 0
	h_right.size = Vector2(size, thickness)
	h_right.set_meta("base_pos", Vector2(half, -thickness / 2.0))
	crosshair.add_child(h_right)

	var v_top = ColorRect.new()
	v_top.color = color
	v_top.layout_mode = 0
	v_top.size = Vector2(thickness, size)
	v_top.set_meta("base_pos", Vector2(-thickness / 2.0, -half - size))
	crosshair.add_child(v_top)

	var v_bottom = ColorRect.new()
	v_bottom.color = color
	v_bottom.layout_mode = 0
	v_bottom.size = Vector2(thickness, size)
	v_bottom.set_meta("base_pos", Vector2(-thickness / 2.0, half))
	crosshair.add_child(v_bottom)

	var dot = ColorRect.new()
	dot.color = Color(1, 0, 0, 0.8)
	dot.layout_mode = 0
	dot.size = Vector2(4, 4)
	dot.set_meta("base_pos", Vector2(-2, -2))
	crosshair.add_child(dot)

func _build_hover_marker():
	hover_marker = MeshInstance3D.new()
	hover_marker.visible = false
	add_child(hover_marker)
	hover_marker_mat = StandardMaterial3D.new()
	hover_marker_mat.albedo_color = Color(1, 1, 0.2, 0.35)
	hover_marker_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA

func _process(delta):
	_update_crosshair()
	_raycast_hover()

func _update_crosshair():
	if not crosshair or not get_viewport():
		return
	var mouse_pos = get_viewport().get_mouse_position()
	for c in crosshair.get_children():
		if c is ColorRect:
			var base = c.get_meta("base_pos", Vector2())
			c.position = mouse_pos + base

func _raycast_hover():
	if not gridmap or not get_viewport():
		hover_marker.visible = false
		return
	if interaction_popup and interaction_popup.visible:
		hover_marker.visible = false
		return

	var cam = get_viewport().get_camera_3d()
	if not cam:
		hover_marker.visible = false
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var space = get_world_3d().direct_space_state

	# Try physics raycast first
	var hit_cell = Vector3()
	var found = false
	if space:
		var origin = cam.project_ray_origin(mouse_pos)
		var end = origin + cam.project_ray_normal(mouse_pos) * 200.0
		var query = PhysicsRayQueryParameters3D.create(origin, end)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var result = space.intersect_ray(query)
		if not result.is_empty():
			var hit_pos = result.get("position", Vector3())
			var cell = gridmap.local_to_map(hit_pos)
			hit_cell = Vector3(cell.x, cell.y, cell.z)
			if gridmap.get_cell_item(hit_cell) != -1:
				found = true

	# Fallback: plane projection + broad search
	if not found:
		var origin = cam.project_ray_origin(mouse_pos)
		var normal = cam.project_ray_normal(mouse_pos)
		var plane = Plane(Vector3.UP, Vector3.ZERO)
		var world_pos = plane.intersects_ray(origin, normal)
		if world_pos != null:
			hit_cell = Vector3(round(world_pos.x), 0, round(world_pos.z))
			# Search all Y levels at this XZ
			for y in range(10, -1, -1):
				var check = Vector3(hit_cell.x, y, hit_cell.z)
				if gridmap.get_cell_item(check) != -1:
					hit_cell = check
					found = true
					break

	# Broad search around hit cell if still not found
	if not found:
		var base = Vector3(round(hit_cell.x), 0, round(hit_cell.z)) if hit_cell != Vector3() else Vector3()
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				for dy in range(10, -1, -1):
					var check = Vector3(base.x + dx, dy, base.z + dz)
					if gridmap.get_cell_item(check) != -1:
						hit_cell = check
						found = true
						break
				if found:
					break
			if found:
				break

	var ck = "%d,%d,%d" % [hit_cell.x, hit_cell.y, hit_cell.z]
	if found and interaction_data.has(ck) and interaction_data[ck].get("interactions", []).size() > 0:
		var item = gridmap.get_cell_item(hit_cell)
		if item >= 0:
			var mesh = gridmap.mesh_library.get_item_mesh(item)
			if mesh:
				hover_marker.mesh = mesh
				var xform = gridmap.mesh_library.get_item_mesh_transform(item)
				hover_marker.scale = xform.basis.get_scale()
				hover_marker.position = gridmap.map_to_local(hit_cell)
				for s in range(mesh.get_surface_count()):
					hover_marker.set_surface_override_material(s, hover_marker_mat)
				hover_marker.visible = true
				hovered_cell_key = ck
			else:
				hover_marker.visible = false
				hovered_cell_key = ""
		else:
			hover_marker.visible = false
			hovered_cell_key = ""
	else:
		hover_marker.visible = false
		hovered_cell_key = ""

func _set_interaction_paused(paused: bool):
	if player:
		player.set_process(not paused)
		player.set_physics_process(not paused)
	if view and view.has_method("set_input_paused"):
		view.input_paused = paused
	if paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _show_interaction_popup(interactions: Array):
	if not interaction_popup or interactions.is_empty():
		return
	var panel = interaction_popup.get_meta("panel")
	for child in panel.get_children():
		if child is Button:
			child.queue_free()
	_set_interaction_paused(true)

	var y_start = 56
	for i in range(interactions.size()):
		var data = interactions[i]
		var btn = Button.new()
		btn.text = "%s ($%d)" % [data.get("label", "Option"), data.get("reward", 0)]
		btn.position = Vector2(20, y_start + i * 50)
		btn.size = Vector2(260, 40)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn.pressed.connect(func():
			_give_interaction_reward(data)
		)
		panel.add_child(btn)

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.position = Vector2(100, y_start + interactions.size() * 50 + 10)
	close_btn.size = Vector2(100, 30)
	close_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	close_btn.pressed.connect(func():
		interaction_popup.visible = false
		_set_interaction_paused(false)
	)
	panel.add_child(close_btn)

	interaction_popup.visible = true

func _give_interaction_reward(data: Dictionary):
	var reward = data.get("reward", 0)
	if player and player.has_method("collect_coin"):
		for _i in range(reward):
			player.collect_coin()
	interaction_popup.visible = false
	_set_interaction_paused(false)

func _try_interact():
	if not gridmap or not player:
		return
	if interaction_popup and interaction_popup.visible:
		interaction_popup.visible = false
		return
	if not hovered_cell_key.is_empty() and interaction_data.has(hovered_cell_key):
		var data = interaction_data[hovered_cell_key]
		if data.has("interactions") and not data["interactions"].is_empty():
			_show_interaction_popup(data["interactions"])
			return
