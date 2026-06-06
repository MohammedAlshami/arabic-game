extends Node3D

const MapLoader = preload("res://scripts/map_loader.gd")
const CELL_SIZE := 0.25
const CELL_INV := 4.0
const INITIAL_RADIUS = 80 * CELL_INV
const TRIGGER_DISTANCE = 50 * CELL_INV
const EXPAND_CHUNK = 30 * CELL_INV
const GROUND_MARGIN = 10 * CELL_INV
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

var _driving: bool = false
var _driven_vehicle: Node3D = null
var _drive_view: Node3D = null
var _vehicle_cell: Vector3 = Vector3.ZERO
var VEHICLE_IDS: Array = ["vehicle-truck-yellow", "vehicle-truck-red", "vehicle-motorcycle"]

var play_plane: Plane
var hover_marker: MeshInstance3D = null
var char_models: Array = []
var char_index: int = 0
var hover_marker_mat: Material = null
var hovered_cell_key: String = ""
var ray_line: MeshInstance3D = null
var ray_line_mat: Material = null

func _ready():
	play_plane = Plane(Vector3.UP, Vector3.ZERO)
	load_map()
	_build_interaction_popup()
	_build_crosshair()
	_build_hover_marker()
	_build_ray_line()

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
	MapLoader.place_cells(gridmap, map_data, id_map, CELL_SIZE)

	# Add barrier item
	var barrier_id = mesh_lib.get_last_unused_item_id()
	mesh_lib.create_item(barrier_id)
	var barrier_box = BoxMesh.new()
	barrier_box.size = Vector3(0.01, 0.01, 0.01)
	mesh_lib.set_item_mesh(barrier_id, barrier_box)
	var barrier_col = BoxShape3D.new()
	barrier_col.size = Vector3(1, 100, 1)
	mesh_lib.set_item_shapes(barrier_id, [barrier_col])
	id_map["_barrier"] = barrier_id

	# Use exact mesh geometry as collision for each item
	for item_id in mesh_lib.get_item_list():
		if item_id != barrier_id:
			mesh_lib.set_item_shapes(item_id, [])
			var mesh = mesh_lib.get_item_mesh(item_id)
			if mesh:
				var trimesh = mesh.create_trimesh_shape()
				if trimesh:
					mesh_lib.set_item_shapes(item_id, [trimesh])

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

	char_models = [
		"res://models/plat_models/character.glb",
		"res://models/characters/Barbarian.glb",
		"res://models/characters/Knight.glb",
		"res://models/characters/Mage.glb",
		"res://models/characters/Ranger.glb",
		"res://models/characters/Rogue.glb",
		"res://models/characters/Rogue_Hooded.glb",
	]
	char_index = 0

	day_night = load("res://scripts/day_night.gd").new()
	add_child(day_night)

	_spawn_player(Vector3(0, 2, 0))

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

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_anim_player(child)
		if result:
			return result
	return null

func _cycle_character(dir: int):
	if char_models.is_empty() or not player:
		return
	char_index = (char_index + dir + char_models.size()) % char_models.size()
	var path = char_models[char_index]
	var glb = load(path)
	if glb and glb is PackedScene:
		var old = player.get_node_or_null("Character")
		if old:
			player.remove_child(old)
			old.queue_free()
		var inst = glb.instantiate()
		inst.name = "Character"
		if inst is Node3D:
			player.add_child(inst)
			player.move_child(inst, 0)
			player.model = inst
			var embedded_ap = _find_anim_player(inst)
			var ap = embedded_ap
			if not ap:
				ap = AnimationPlayer.new()
				ap.name = "AnimationPlayer"
				inst.add_child(ap)
			if not ap.has_animation_library(""):
				ap.add_animation_library("", AnimationLibrary.new())
			var lib = ap.get_animation_library("")
			if not embedded_ap or embedded_ap.get_animation_list().size() == 0:
				var anim_map = {"Idle_A": "idle", "Walking_A": "walk", "Jump_Full_Long": "jump"}
				for anim_path in ["res://models/characters/Rig_Medium_MovementBasic.glb", "res://models/characters/Rig_Medium_General.glb"]:
					var anim_src = load(anim_path)
					if anim_src and anim_src is PackedScene:
						var src_inst = anim_src.instantiate()
						add_child(src_inst)
						var src_ap = _find_anim_player(src_inst)
						if src_ap:
							for src_name in src_ap.get_animation_list():
								var anim = src_ap.get_animation(src_name)
								if anim:
									var target_name = anim_map.get(src_name, src_name)
									if not lib.has_animation(target_name):
										lib.add_animation(target_name, anim)
						remove_child(src_inst)
						src_inst.queue_free()
			player.animation = ap
			player.animation.play("idle", 0.1)

func _unhandled_input(event):
	if event.is_action_pressed("build"):
		_try_interact()
		return
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
		return
	if event.is_action_pressed("drive"):
		if _driving:
			_exit_vehicle()
		else:
			_try_enter_vehicle()
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
		if event.keycode == KEY_Q:
			_cycle_character(-1)
			return
		if event.keycode == KEY_E:
			_cycle_character(1)
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

	if unsaved_changes:
		save_timer -= delta
		if save_timer <= 0:
			_save_map()

	if _driving and _driven_vehicle and _drive_view:
		var vp = _driven_vehicle.get_vehicle_position()
		_drive_view.position = _drive_view.position.lerp(vp, delta * 4)
		var speed = abs(_driven_vehicle.linear_speed)
		var tz = remap(clamp(speed, 0.0, 1.0), 0.0, 1.0, 10, 20)
		var cam = _drive_view.find_child("Camera", true, false)
		if cam:
			cam.position.z = lerp(cam.position.z, tz, delta * 0.5)

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
	var cells = MapLoader.read_cells(gridmap, id_map, {}, {}, -1, CELL_SIZE)
	map_data["cells"] = cells
	MapLoader.save_map(map_data, filename)
	unsaved_changes = false

func _try_enter_vehicle() -> bool:
	if not gridmap or not player:
		return false
	var cell = gridmap.local_to_map(player.global_position)
	var ml = gridmap.mesh_library
	if not ml or not ml.has_meta("id_map"):
		return false
	var loaded_id_map = ml.get_meta("id_map")
	var rev_map = {}
	for key in loaded_id_map:
		rev_map[loaded_id_map[key]] = key

	for x in range(-2, 3):
		for z in range(-2, 3):
			var check = Vector3i(cell.x + x, 0, cell.z + z)
			var item = gridmap.get_cell_item(check)
			if item < 0:
				continue
			var sid = rev_map.get(item, "")
			if sid in VEHICLE_IDS:
				_enter_vehicle(check)
				return true
	return false

func _enter_vehicle(cell_pos: Vector3i):
	_driving = true
	_vehicle_cell = Vector3(cell_pos)

	var vehicle_scene = load("res://scenes/objects/vehicle.tscn")
	_driven_vehicle = vehicle_scene.instantiate()
	_driven_vehicle.position = gridmap.map_to_local(cell_pos)
	add_child(_driven_vehicle)

	player.set_process(false)
	player.set_physics_process(false)
	player.visible = false
	player.collision_layer = 0
	player.collision_mask = 0

	_drive_view = Node3D.new()
	var cam = Camera3D.new()
	cam.current = true
	cam.position.z = 10
	cam.position.y = 3
	_drive_view.add_child(cam)
	add_child(_drive_view)

func _exit_vehicle():
	if _driven_vehicle:
		_driven_vehicle.queue_free()
		_driven_vehicle = null
	if _drive_view:
		_drive_view.queue_free()
		_drive_view = null

	var exit_pos = gridmap.map_to_local(Vector3i(_vehicle_cell))
	player.position = exit_pos + Vector3(0, 1, 0)
	player.set_process(true)
	player.set_physics_process(true)
	player.visible = true
	player.collision_layer = 1
	player.collision_mask = 1

	if view:
		var view_cam = view.find_child("Camera", true, false)
		if view_cam:
			view_cam.current = true

	_driving = false

func _auto_test_vehicle():
	push_error("=== AUTO TEST VEHICLE ===")
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

func _build_ray_line():
	ray_line = MeshInstance3D.new()
	ray_line.visible = true
	ray_line_mat = StandardMaterial3D.new()
	ray_line_mat.albedo_color = Color(1, 1, 0, 0.3)
	ray_line_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	add_child(ray_line)

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
		ray_line.visible = false
		return
	if interaction_popup and interaction_popup.visible:
		hover_marker.visible = false
		ray_line.visible = false
		return

	var cam = get_viewport().get_camera_3d()
	if not cam:
		hover_marker.visible = false
		ray_line.visible = false
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var origin = cam.project_ray_origin(mouse_pos)
	var normal = cam.project_ray_normal(mouse_pos)

	var hit_cell = Vector3()
	var found = false
	var hit_world_pos = origin + normal * 200.0

	# Use AABB intersection for precise cell detection
	var best_dist = INF
	var best_cell = Vector3()
	var best_hit = Vector3()

	# First narrow down using plane projection
	var plane = Plane(Vector3.UP, Vector3.ZERO)
	var plane_hit = plane.intersects_ray(origin, normal)
	var search_center = Vector3.ZERO
	if plane_hit != null:
		var scx = round(plane_hit.x * CELL_INV)
		var scz = round(plane_hit.z * CELL_INV)
		search_center = Vector3(scx, 0, scz)

	for cell_pos in gridmap.get_used_cells():
		# Quick XZ distance check to skip far cells
		var dx = abs(cell_pos.x - search_center.x)
		var dz = abs(cell_pos.z - search_center.z)
		if dx > 5 or dz > 5:
			continue

		var item = gridmap.get_cell_item(cell_pos)
		if item < 0:
			continue
		var mesh = gridmap.mesh_library.get_item_mesh(item)
		if not mesh:
			continue

		var world_pos = gridmap.map_to_local(cell_pos)
		var xform = gridmap.mesh_library.get_item_mesh_transform(item)
		var aabb = mesh.get_aabb()
		var taabb = xform * aabb
		taabb.position += world_pos

		var hit = taabb.intersects_ray(origin, normal)
		if hit != null:
			var d = origin.distance_squared_to(hit)
			if d < best_dist:
				best_dist = d
				best_cell = cell_pos
				best_hit = hit

	if best_dist != INF:
		hit_cell = best_cell
		hit_world_pos = best_hit
		found = true

	# Also check physics raycast as fallback
	if not found:
		var space = get_world_3d().direct_space_state
		if space:
			var end = origin + normal * 200.0
			var query = PhysicsRayQueryParameters3D.create(origin, end)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			var result = space.intersect_ray(query)
			if not result.is_empty():
				var rpos = result.get("position", Vector3())
				hit_world_pos = rpos
				var cell = gridmap.local_to_map(rpos)
				hit_cell = Vector3(cell.x, cell.y, cell.z)
				if gridmap.get_cell_item(hit_cell) != -1:
					var ck = "%d,%d,%d" % [hit_cell.x, hit_cell.y, hit_cell.z]
					if interaction_data.has(ck) and not interaction_data[ck].get("interactions", []).is_empty():
						found = true

	var ck = "%d,%d,%d" % [hit_cell.x, hit_cell.y, hit_cell.z]
	if found:
		var target_cell = hit_cell
		var target_item = gridmap.get_cell_item(target_cell)
		if target_item < 0:
			var search_radius = 3
			var found_owner = false
			for dx in range(-search_radius, search_radius + 1):
				if found_owner:
					break
				for dz in range(-search_radius, search_radius + 1):
					if found_owner:
						break
					var nearby = Vector3(hit_cell.x + dx, hit_cell.y, hit_cell.z + dz)
					var ni = gridmap.get_cell_item(nearby)
					if ni < 0:
						continue
					for y in range(10, -1, -1):
						var check = Vector3(nearby.x, y, nearby.z)
						if gridmap.get_cell_item(check) == ni:
							var occ = _get_item_occupied_cells(ni, check)
							for o in occ:
								if Vector3(o.x, o.y, o.z) == hit_cell:
									target_cell = check
									target_item = ni
									found_owner = true
									break
						if found_owner:
							break
		if target_item >= 0:
			_draw_ray_line(origin, hit_world_pos)
			ray_line.visible = true
			var mesh = gridmap.mesh_library.get_item_mesh(target_item)
			if mesh:
				hover_marker.mesh = mesh
				var xform = gridmap.mesh_library.get_item_mesh_transform(target_item)
				hover_marker.scale = xform.basis.get_scale() * 1.1
				hover_marker.position = gridmap.map_to_local(target_cell)
				for s in range(mesh.get_surface_count()):
					hover_marker.set_surface_override_material(s, hover_marker_mat)
				hover_marker.visible = true
				hovered_cell_key = "%d,%d,%d" % [target_cell.x, target_cell.y, target_cell.z]
	else:
		hover_marker.visible = false
		hovered_cell_key = ""
		ray_line.visible = false

func _get_item_occupied_cells(item_id: int, cell_pos: Vector3) -> Array:
	var mesh = gridmap.mesh_library.get_item_mesh(item_id)
	if not mesh:
		return [cell_pos]
	var xform = gridmap.mesh_library.get_item_mesh_transform(item_id)
	var aabb = xform * mesh.get_aabb()
	var min_x = int(ceil(aabb.position.x))
	var max_x = int(floor(aabb.position.x + aabb.size.x))
	var min_y = int(ceil(aabb.position.y))
	var max_y = int(floor(aabb.position.y + aabb.size.y))
	var min_z = int(ceil(aabb.position.z))
	var max_z = int(floor(aabb.position.z + aabb.size.z))
	var cells: Array = []
	for ox in range(min_x, max_x + 1):
		for oy in range(min_y, max_y + 1):
			for oz in range(min_z, max_z + 1):
				cells.append(Vector3(cell_pos.x + ox, cell_pos.y + oy, cell_pos.z + oz))
	return cells

func _draw_ray_line(from: Vector3, to: Vector3):
	if not ray_line:
		return
	var dir = to - from
	var dist = dir.length()
	if dist < 0.01:
		ray_line.visible = false
		return
	dir = dir.normalized()
	var mid = (from + to) / 2.0
	var box = BoxMesh.new()
	box.size = Vector3(0.04, dist, 0.04)
	box.material = ray_line_mat
	ray_line.mesh = box
	ray_line.position = mid
	ray_line.look_at(from, Vector3.UP)

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
		btn.pressed.connect(_give_interaction_reward.bind(data))
		panel.add_child(btn)

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.position = Vector2(100, y_start + interactions.size() * 50 + 10)
	close_btn.size = Vector2(100, 30)
	close_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	close_btn.pressed.connect(_close_interaction_popup)
	panel.add_child(close_btn)

	interaction_popup.visible = true

func _close_interaction_popup():
	if interaction_popup:
		interaction_popup.visible = false
	_set_interaction_paused(false)

func _give_interaction_reward(data: Dictionary):
	var reward = data.get("reward", 0)
	if player and player.has_method("collect_coin"):
		for _i in range(reward):
			player.collect_coin()
	_close_interaction_popup()

func _try_interact():
	if not gridmap or not player:
		return
	if interaction_popup and interaction_popup.visible:
		return
	if not hovered_cell_key.is_empty() and interaction_data.has(hovered_cell_key):
		var data = interaction_data[hovered_cell_key]
		if data.has("interactions") and not data["interactions"].is_empty():
			_show_interaction_popup(data["interactions"])
			return
