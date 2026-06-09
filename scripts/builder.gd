extends Node3D

const MapLoader = preload("res://scripts/map_loader.gd")

const CELL_SIZE := 0.25
const CELL_INV := 4.0

static func snap(v: float) -> float:
	return round(v * CELL_INV) / CELL_INV

static func to_cell(pos: Vector3) -> Vector3i:
	return Vector3i(int(round(pos.x * CELL_INV)), int(round(pos.y * CELL_INV)), int(round(pos.z * CELL_INV)))

static func to_world(cell: Vector3i) -> Vector3:
	return Vector3(cell.x * CELL_SIZE, cell.y * CELL_SIZE, cell.z * CELL_SIZE)

func cell_key(pos: Vector3) -> String:
	var c = to_cell(pos)
	return "%d,%d,%d" % [c.x, c.y, c.z]

@export var structures: Array[Structure] = []

var map:DataMap

var index:int = 0
var y_offset := 0.0
var character_mode := false
var character_marker: Node3D = null
var character_index := 0
var character_indices: Array[int] = []

@export var selector:Node3D
@export var selector_container:Node3D
@export var view_camera:Camera3D
@export var gridmap:GridMap
@export var cash_display:Label

@export var modal:Control
@export var modal_name_input:LineEdit
@export var modal_save_btn:Button
@export var modal_cancel_btn:Button

@export var load_modal:Control
@export var load_map_container:VBoxContainer
@export var load_cancel_btn:Button

@export var structures_btn:Button

var plane:Plane
var struct_modal:Control = null
var categories: Dictionary = {}
var canvas_layer:CanvasLayer = null

var delete_mode := false
var delete_cursor: Control = null
var delete_cursor_tex: Texture2D = null
var delete_marker: MeshInstance3D = null
var delete_marker_mat: Material = null

var position_mode := false
var position_marker: MeshInstance3D = null
var position_marker_mat: Material = null
var position_target_cell: Vector3i
var position_config_data: Dictionary = {}
var position_modal_open := false
var cell_uuids: Dictionary = {}

var character_dim_mat: Material = null

var json_defs: Dictionary = {}
var json_id_map: Dictionary = {}
var current_map_filename := ""
var fog_visible := false
var xray_mode := false
var xray_original_meshes: Dictionary = {}
var xray_cubes: Node3D = null
var barrier_mode := false
var barrier_item_id := -1
var barrier_marker: MeshInstance3D = null
var structure_edit_mode := false
var placed_occupied: Dictionary = {}  # cell_key -> Dictionary of occupied cell keys
var _build_repeat: float = 0.0
var _cycle_repeat: float = 0.0
var _cycle_dir: int = 0
var _manual_placement_active := false
var _manual_placement_pos := Vector3.ZERO
var _last_mouse_pos := Vector2(-1, -1)
const REPEAT_DELAY: float = 0.15

func _ready():
	map = DataMap.new()
	plane = Plane(Vector3.UP, Vector3.ZERO)

	json_defs = MapLoader.load_definitions()
	structures = []
	for sid in json_defs.keys():
		var entry = json_defs[sid]
		var s = Structure.new()
		s.model = load(entry["model"])
		s.price = entry.get("price", 0)
		structures.append(s)

	build_categories()

	character_index = 0
	character_indices = []
	var sid_list = json_defs.keys()
	for i in sid_list.size():
		if sid_list[i] == "character" or sid_list[i].begins_with("character-"):
			character_indices.append(i)

	json_id_map = {}
	var mesh_library = MeshLibrary.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	sid_list = json_defs.keys()
	for i in sid_list.size():
		var sid = sid_list[i]
		var entry = json_defs[sid]
		var id = mesh_library.get_last_unused_item_id()
		mesh_library.create_item(id)
		var mesh = get_mesh(structures[i].model)
		if mesh:
			mesh_library.set_item_mesh(id, mesh)
		else:
			mesh_library.set_item_mesh(id, box)
		var s = entry.get("scale", 1.0)
		if s != 1.0:
			var t = Transform3D()
			t = t.scaled(Vector3(s, s, s))
			mesh_library.set_item_mesh_transform(id, t)
		else:
			mesh_library.set_item_mesh_transform(id, Transform3D())
		json_id_map[sid] = id

	gridmap.mesh_library = mesh_library

	# Add invisible barrier item
	var barrier_id = mesh_library.get_last_unused_item_id()
	mesh_library.create_item(barrier_id)
	mesh_library.set_item_mesh(barrier_id, box)
	var barrier_col = BoxShape3D.new()
	barrier_col.size = Vector3(1, 100, 1)
	mesh_library.set_item_shapes(barrier_id, [barrier_col])
	barrier_item_id = barrier_id
	json_id_map["_barrier"] = barrier_id

	character_marker = MeshInstance3D.new()
	character_marker.mesh = BoxMesh.new()
	character_marker.mesh.size = Vector3(0.5, 1, 0.5)
	character_marker.visible = false
	add_child(character_marker)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.4, 0.6)
	character_marker.set_surface_override_material(0, mat)
	var dim_mat = StandardMaterial3D.new()
	dim_mat.albedo_color = Color(0.2, 0.8, 0.4, 0.2)
	character_dim_mat = dim_mat

	_update_character_preview()

	delete_marker = MeshInstance3D.new()
	delete_marker.visible = false
	add_child(delete_marker)
	delete_marker_mat = StandardMaterial3D.new()
	delete_marker_mat.albedo_color = Color(1, 0.2, 0.2, 0.35)
	delete_marker_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA

	position_marker = MeshInstance3D.new()
	position_marker.visible = false
	add_child(position_marker)
	position_marker_mat = StandardMaterial3D.new()
	position_marker_mat.albedo_color = Color(1, 1, 0.2, 0.35)
	position_marker_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA

	barrier_marker = MeshInstance3D.new()
	barrier_marker.visible = false
	add_child(barrier_marker)
	var barrier_marker_mat = StandardMaterial3D.new()
	barrier_marker_mat.albedo_color = Color(0.8, 0.2, 0.8, 0.4)
	barrier_marker_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	var barrier_mesh = BoxMesh.new()
	barrier_mesh.size = Vector3(1, 100, 1)
	barrier_marker.mesh = barrier_mesh
	barrier_marker.set_surface_override_material(0, barrier_marker_mat)

	canvas_layer = get_node("../CanvasLayer") as CanvasLayer
	structures_btn.visible = false
	_build_delete_cursor()

	update_structure()
	update_cash()

	xray_cubes = Node3D.new()
	xray_cubes.visible = false
	add_child(xray_cubes)

	if view_camera and view_camera.environment:
		view_camera.environment.fog_enabled = false

	if GameState.current_mode == GameState.Mode.STRUCTURE and GameState.structure_to_edit:
		structure_edit_mode = true
		call_deferred("_on_structure_load")
	elif GameState.map_to_load:
		call_deferred("_on_startup_load")

	modal_save_btn.pressed.connect(_on_save_modal_save)

func _on_structure_load():
	_on_map_selected("res://structures/" + GameState.structure_to_edit)
	GameState.structure_to_edit = ""
	modal_cancel_btn.pressed.connect(_on_save_modal_cancel)
	modal_name_input.text_submitted.connect(_on_save_modal_save)
	load_cancel_btn.pressed.connect(_on_load_modal_cancel)

func _on_startup_load():
	_on_map_selected(GameState.map_to_load)
	GameState.map_to_load = ""
	modal_cancel_btn.pressed.connect(_on_save_modal_cancel)
	modal_name_input.text_submitted.connect(_on_save_modal_save)
	load_cancel_btn.pressed.connect(_on_load_modal_cancel)

func build_categories():
	categories = {
		"Buildings": [],
		"Nature": [],
		"Furniture": [],
		"Blocks": [],
		"Vehicles": [],
		"KayKit": [],
	}

	var sid_list = json_defs.keys()
	for i in sid_list.size():
		var sid = sid_list[i]
		if sid.begins_with("building-") or sid.begins_with("road-") or sid.begins_with("pavement-"):
			categories["Buildings"].append(i)
		elif sid.begins_with("grass-") or sid == "grass":
			categories["Nature"].append(i)
		elif sid.begins_with("furniture-"):
			categories["Furniture"].append(i)
		elif sid.begins_with("block-"):
			categories["Blocks"].append(i)
		elif sid.begins_with("vehicle-"):
			categories["Vehicles"].append(i)
		elif sid.begins_with("kaykit-"):
			categories["KayKit"].append(i)

func build_struct_modal():
	struct_modal = Control.new()
	struct_modal.visible = false
	struct_modal.layout_mode = 3
	struct_modal.anchors_preset = Control.PRESET_FULL_RECT
	struct_modal.anchor_left = 0.0
	struct_modal.anchor_top = 0.0
	struct_modal.anchor_right = 1.0
	struct_modal.anchor_bottom = 1.0
	struct_modal.mouse_filter = Control.MOUSE_FILTER_PASS
	if canvas_layer:
		canvas_layer.add_child(struct_modal)
	else:
		add_child(struct_modal)

	var overlay = ColorRect.new()
	overlay.color = Color(0.796, 0.827, 0.937, 0.8)
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	struct_modal.add_child(overlay)

	var panel = Panel.new()
	panel.layout_mode = 0
	panel.anchors_preset = Control.PRESET_CENTER
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -360
	panel.offset_top = -260
	panel.offset_right = 360
	panel.offset_bottom = 260
	struct_modal.add_child(panel)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.796, 0.827, 0.937, 1)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.6, 0.65, 0.8, 1)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.content_margin_left = 12
	panel_style.content_margin_top = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", panel_style)

	var title_label = Label.new()
	title_label.text = "Select Structure"
	title_label.size = Vector2(696, 36)
	title_label.position = Vector2(12, 12)
	title_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.2, 1))
	var title_font = load("res://fonts/lilita_one_regular.ttf")
	if title_font:
		var ls = LabelSettings.new()
		ls.font = title_font
		ls.font_size = 24
		title_label.label_settings = ls
	panel.add_child(title_label)

	var tabs = TabContainer.new()
	tabs.size = Vector2(696, 420)
	tabs.position = Vector2(12, 54)
	panel.add_child(tabs)

	var white_bg = StyleBoxFlat.new()
	white_bg.bg_color = Color(0.9, 0.92, 0.96, 1)
	white_bg.corner_radius_top_left = 4
	white_bg.corner_radius_top_right = 4
	white_bg.corner_radius_bottom_left = 4
	white_bg.corner_radius_bottom_right = 4

	var preview_size := 180

	var tab_order := ["Buildings", "Nature", "KayKit"]

	for cat_name in tab_order:
		var scroll = ScrollContainer.new()
		scroll.name = cat_name
		tabs.add_child(scroll)
		scroll.add_theme_stylebox_override("panel", white_bg)

		var grid = GridContainer.new()
		grid.columns = 3
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(grid)

		var indices = categories.get(cat_name, [])

		for idx in indices:
			var s = structures[idx]
			var name_str = s.model.resource_path.get_file().trim_suffix(".glb").replace("-", " ").replace("_", " ")
			name_str = name_str.capitalize()

			var item_container = VBoxContainer.new()
			item_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			item_container.custom_minimum_size = Vector2(preview_size, preview_size + 24)

			var preview_path = "res://sprites/animal_previews/" + s.model.resource_path.get_file().trim_suffix(".glb") + ".png"
			var tex = load(preview_path) if ResourceLoader.exists(preview_path) else load("res://sprites/placeholder.png")
			var texture_rect = TextureRect.new()
			texture_rect.texture = tex
			texture_rect.custom_minimum_size = Vector2(140, 140)
			texture_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			texture_rect.expand = true
			texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			texture_rect.mouse_filter = Control.MOUSE_FILTER_STOP

			var name_label = Label.new()
			name_label.text = name_str
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.2, 1))
			name_label.add_theme_font_size_override("font_size", 12)

			var i = idx
			texture_rect.gui_input.connect(_on_item_clicked.bind(i))

			item_container.add_child(texture_rect)
			item_container.add_child(name_label)
			grid.add_child(item_container)

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.size = Vector2(120, 36)
	close_btn.position = Vector2(300, 480)
	close_btn.add_theme_color_override("font_color", Color(0.1, 0.1, 0.2, 1))
	close_btn.add_theme_font_size_override("font_size", 16)
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.6, 0.7, 0.9, 1)
	close_style.border_width_left = 1
	close_style.border_width_top = 1
	close_style.border_width_right = 1
	close_style.border_width_bottom = 1
	close_style.border_color = Color(0.4, 0.5, 0.7, 1)
	close_style.corner_radius_top_left = 6
	close_style.corner_radius_top_right = 6
	close_style.corner_radius_bottom_left = 6
	close_style.corner_radius_bottom_right = 6
	close_btn.add_theme_stylebox_override("normal", close_style)
	panel.add_child(close_btn)
	close_btn.pressed.connect(_close_struct_modal)

	overlay.gui_input.connect(_on_struct_overlay_click)

func _build_delete_cursor():
	delete_cursor = Control.new()
	delete_cursor.visible = false
	delete_cursor.mouse_filter = Control.MOUSE_FILTER_PASS
	delete_cursor_tex = load("res://sprites/delete_cursor.png")
	delete_cursor.draw.connect(_on_delete_cursor_draw)

	if canvas_layer:
		canvas_layer.add_child(delete_cursor)
	else:
		add_child(delete_cursor)

func _on_delete_cursor_draw():
	if not delete_cursor_tex:
		return
	var size := 48.0
	var rect = Rect2(-size / 2.0, -size / 2.0, size, size)
	delete_cursor.draw_texture_rect(delete_cursor_tex, rect, false, Color(1, 1, 1, 0.8))

func _set_delete_mode(enabled: bool):
	if enabled:
		_set_position_mode(false)
	delete_mode = enabled
	delete_cursor.visible = enabled
	delete_marker.visible = false
	selector.visible = not enabled and not character_mode and not position_mode
	if enabled:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _set_position_mode(enabled: bool):
	if enabled:
		_set_delete_mode(false)
	position_mode = enabled
	position_marker.visible = false
	selector.visible = not enabled and not delete_mode and not character_mode
	if enabled:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _check_position_hover(gridmap_position: Vector3):
	if position_modal_open:
		return
	var has_building = false
	var found_cell := Vector3i.ZERO
	for y in range(10, -1, -1):
		var check_cell = to_cell(Vector3(gridmap_position.x, y, gridmap_position.z))
		if gridmap.get_cell_item(check_cell) != -1:
			found_cell = check_cell
			has_building = true
			break
	if has_building:
		var item = gridmap.get_cell_item(found_cell)
		if item >= 0:
			var mesh = gridmap.mesh_library.get_item_mesh(item)
			if mesh:
				position_marker.mesh = mesh
				var xform = gridmap.mesh_library.get_item_mesh_transform(item)
				position_marker.scale = xform.basis.get_scale()
				position_marker.position = gridmap.map_to_local(found_cell)
				for s in range(mesh.get_surface_count()):
					position_marker.set_surface_override_material(s, position_marker_mat)
				position_marker.visible = true
				position_target_cell = found_cell
			else:
				position_marker.visible = false
		else:
			position_marker.visible = false
	else:
		position_marker.visible = false
	if has_building and Input.is_action_just_pressed("build"):
		_open_position_modal(found_cell)

func _open_position_modal(cell: Vector3i):
	if position_modal_open:
		return
	position_modal_open = true
	var ck = "%d,%d,%d" % [cell.x, cell.y, cell.z]
	var existing = position_config_data.get(ck, {})
	var sid = _get_sid_at_cell(cell)

	# Build the modal UI
	var modal_control = Control.new()
	modal_control.visible = true
	modal_control.layout_mode = 3
	modal_control.anchors_preset = Control.PRESET_FULL_RECT
	modal_control.mouse_filter = Control.MOUSE_FILTER_STOP
	if canvas_layer:
		canvas_layer.add_child(modal_control)
	else:
		add_child(modal_control)

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			position_modal_open = false
			modal_control.queue_free()
	)
	modal_control.add_child(overlay)

	var panel = Panel.new()
	panel.layout_mode = 3
	panel.anchors_preset = Control.PRESET_CENTER
	panel.offset_left = -200
	panel.offset_top = -200
	panel.offset_right = 200
	panel.offset_bottom = 200
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
	modal_control.add_child(panel)

	var title = Label.new()
	title.text = "Position Options"
	title.position = Vector2(20, 16)
	title.size = Vector2(360, 36)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	title.add_theme_font_size_override("font_size", 22)
	panel.add_child(title)

	var pos_label = Label.new()
	pos_label.text = "Cell: %s" % cell_key
	pos_label.position = Vector2(20, 54)
	pos_label.size = Vector2(360, 20)
	pos_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	pos_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(pos_label)

	var sid_label = Label.new()
	sid_label.text = "Building: %s" % sid
	sid_label.position = Vector2(20, 74)
	sid_label.size = Vector2(360, 20)
	sid_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	sid_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(sid_label)

	var line = ColorRect.new()
	line.color = Color(0.4, 0.4, 0.4, 1)
	line.position = Vector2(20, 100)
	line.size = Vector2(360, 1)
	panel.add_child(line)

	# Interaction options
	var interactions = existing.get("interactions", [])
	var option_rows = []
	var option_keys = ["building", "car", "tree"]
	var option_labels = ["Building", "Car", "Tree"]

	for i in 3:
		var row = VBoxContainer.new()
		row.position = Vector2(20, 112 + i * 60)
		row.size = Vector2(360, 54)
		panel.add_child(row)

		var row_h = HBoxContainer.new()
		row_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(row_h)

		var lbl = Label.new()
		lbl.text = option_labels[i]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		lbl.custom_minimum_size = Vector2(100, 30)
		row_h.add_child(lbl)

		var reward_field = SpinBox.new()
		reward_field.name = "RewardField_%s" % option_keys[i]
		reward_field.min_value = 0
		reward_field.max_value = 9999
		reward_field.step = 1
		reward_field.value = 0
		reward_field.custom_minimum_size = Vector2(80, 30)
		for ei in interactions:
			if ei.get("key", "") == option_keys[i]:
				reward_field.value = ei.get("reward", 0)
				break
		row_h.add_child(reward_field)

		var enable_btn = CheckButton.new()
		enable_btn.name = "EnableBtn_%s" % option_keys[i]
		enable_btn.text = "Enabled"
		enable_btn.button_pressed = false
		for ei in interactions:
			if ei.get("key", "") == option_keys[i]:
				enable_btn.button_pressed = true
				break
		row_h.add_child(enable_btn)

		option_rows.append({"key": option_keys[i], "field": reward_field, "btn": enable_btn})

	var btn_save = Button.new()
	btn_save.text = "Save"
	btn_save.position = Vector2(40, 320)
	btn_save.size = Vector2(140, 36)
	btn_save.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	panel.add_child(btn_save)

	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.position = Vector2(220, 320)
	btn_cancel.size = Vector2(140, 36)
	btn_cancel.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	panel.add_child(btn_cancel)

	btn_save.pressed.connect(func():
		var saved_interactions = []
		for row in option_rows:
			if row["btn"].button_pressed:
				saved_interactions.append({
					"key": row["key"],
					"label": option_labels[option_keys.find(row["key"])],
					"reward": int(row["field"].value)
				})
		var mcell = {
			"interactions": saved_interactions
		}
		position_config_data[ck] = mcell
		_save_position_data_to_cell(cell, saved_interactions)
		position_modal_open = false
		modal_control.queue_free()
	)

	btn_cancel.pressed.connect(func():
		position_modal_open = false
		modal_control.queue_free()
	)

func _get_sid_at_cell(cell: Vector3i) -> String:
	var item = gridmap.get_cell_item(cell)
	if item < 0:
		return ""
	var rev_map = {}
	for key in json_id_map:
		rev_map[json_id_map[key]] = key
	return rev_map.get(item, "")

func _save_position_data_to_cell(cell: Vector3i, interactions: Array):
	var sid = _get_sid_at_cell(cell)
	if sid.is_empty():
		return
	var ck = "%d,%d,%d" % [cell.x, cell.y, cell.z]
	position_config_data[ck] = {"interactions": interactions}
	auto_save()

func _update_character_preview():
	for n in character_marker.get_children():
		if n.name == "CharPreview":
			character_marker.remove_child(n)
			n.queue_free()
			break
	if character_indices.is_empty():
		return
	var idx = character_indices[character_index]
	var char_model = structures[idx].model.instantiate()
	if char_model:
		char_model.name = "CharPreview"
		char_model.position = Vector3(0, 0.5, 0)
		character_marker.add_child(char_model)

func _cycle_character(dir: int):
	if character_indices.is_empty():
		return
	character_index = (character_index + dir + character_indices.size()) % character_indices.size()
	_update_character_preview()

func _set_character_mode(enabled: bool):
	if enabled:
		_set_position_mode(false)
	character_mode = enabled
	character_marker.visible = enabled
	selector.visible = not enabled and not delete_mode and not position_mode
	if enabled:
		_update_character_preview()
		if map.character_position != Vector3.ZERO:
			character_marker.position = map.character_position + Vector3(0, 0.5, 0)
		# Restore full opacity material when actively placing
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.8, 0.4, 0.6)
		character_marker.set_surface_override_material(0, mat)

func _open_struct_modal():
	struct_modal.visible = true

func _close_struct_modal():
	struct_modal.visible = false

func _on_struct_overlay_click(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_struct_modal()

func _on_item_clicked(event: InputEvent, idx: int):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_structure(idx)

func _select_structure(idx: int):
	character_mode = false
	character_marker.visible = false
	selector.visible = true
	index = idx
	update_structure()
	_close_struct_modal()

func _process(delta):
	if struct_modal and struct_modal.visible:
		return

	action_y_axis()
	action_save_modal()
	action_load_modal()

	_build_repeat = max(_build_repeat - delta, 0.0)
	_cycle_repeat = max(_cycle_repeat - delta, 0.0)

	if _cycle_dir != 0 and _cycle_repeat <= 0.0:
		if character_mode:
			_cycle_character(_cycle_dir)
		else:
			_cycle_structure(_cycle_dir)
		_cycle_repeat = REPEAT_DELAY
	if not Input.is_key_pressed(KEY_Q) and not Input.is_key_pressed(KEY_E):
		_cycle_dir = 0

	var mouse_pos = get_viewport().get_mouse_position()
	if _manual_placement_active and mouse_pos != _last_mouse_pos:
		_manual_placement_active = false
	_last_mouse_pos = mouse_pos

	var world_position = plane.intersects_ray(
		view_camera.project_ray_origin(mouse_pos),
		view_camera.project_ray_normal(mouse_pos))
	var gridmap_position = Vector3(snap(world_position.x), y_offset, snap(world_position.z))
	if _manual_placement_active:
		gridmap_position = _manual_placement_pos

	if delete_mode:
		delete_cursor.position = mouse_pos
		delete_cursor.queue_redraw()
		var target_pos = Vector3(gridmap_position.x, -1, gridmap_position.z)
		for y in range(10, -1, -1):
			var check_cell = to_cell(Vector3(gridmap_position.x, y, gridmap_position.z))
			if gridmap.get_cell_item(check_cell) != -1:
				target_pos = Vector3(gridmap_position.x, y, gridmap_position.z)
				break
		var has_item = target_pos.y >= 0
		if not has_item:
			for dx in range(-2, 3):
				for dz in range(-2, 3):
					var nearby = Vector3(target_pos.x + dx * CELL_SIZE, target_pos.y, target_pos.z + dz * CELL_SIZE)
					var nearby_cell = to_cell(nearby)
					if gridmap.get_cell_item(nearby_cell) >= 0:
						for y in range(10, -1, -1):
							var check_cell = to_cell(Vector3(nearby.x, y, nearby.z))
							if gridmap.get_cell_item(check_cell) >= 0:
								target_pos = Vector3(nearby.x, y, nearby.z)
								has_item = true
								break
					if has_item:
						break
				if has_item:
					break
		if has_item and not (character_mode and map.character_position.distance_to(target_pos) < 1):
			var target_cell = to_cell(target_pos)
			var item = gridmap.get_cell_item(target_cell)
			if item >= 0:
				var mesh = gridmap.mesh_library.get_item_mesh(item)
				if mesh:
					delete_marker.mesh = mesh
					var xform = gridmap.mesh_library.get_item_mesh_transform(item)
					delete_marker.scale = xform.basis.get_scale() * 1.1
					delete_marker.position = gridmap.map_to_local(target_cell)
					for s in range(mesh.get_surface_count()):
						delete_marker.set_surface_override_material(s, delete_marker_mat)
					delete_marker.visible = true
				else:
					delete_marker.visible = false
			else:
				delete_marker.visible = false
		else:
			delete_marker.visible = false
		if has_item and _build_repeat <= 0.0 and Input.is_action_pressed("build"):
			var dck = cell_key(target_pos)
			var uuid = cell_uuids.get(dck, "")
			var to_delete: Array[String] = [dck]
			if uuid != "":
				for ck in cell_uuids:
					if cell_uuids[ck] == uuid and ck != dck:
						to_delete.append(ck)
			for ck in to_delete:
				cell_uuids.erase(ck)
				position_config_data.erase(ck)
				var parts = ck.split(",")
				if parts.size() == 3:
					gridmap.set_cell_item(Vector3i(int(parts[0]), int(parts[1]), int(parts[2])), -1)
			Audio.play("sounds/removal-a.ogg, sounds/removal-b.ogg, sounds/removal-c.ogg, sounds/removal-d.ogg", -20)
			auto_save()
			_build_repeat = REPEAT_DELAY
	elif barrier_mode:
		barrier_marker.position = lerp(barrier_marker.position, gridmap_position, min(delta * 40, 1.0))
		if _build_repeat <= 0.0 and Input.is_action_pressed("build"):
			var bp = to_cell(gridmap_position)
			if gridmap.get_cell_item(bp) < 0:
				gridmap.set_cell_item(bp, barrier_item_id)
				Audio.play("sounds/placement-a.ogg, sounds/placement-b.ogg, sounds/placement-c.ogg, sounds/placement-d.ogg", -20)
				_build_repeat = REPEAT_DELAY
	elif character_mode:
		character_marker.position = lerp(character_marker.position, gridmap_position + Vector3(0, 0.5, 0), min(delta * 40, 1.0))
		action_place_character(gridmap_position)
	else:
		selector.position = lerp(selector.position, gridmap_position, min(delta * 40, 1.0))
		action_build(gridmap_position)

	if position_mode:
		_check_position_hover(gridmap_position)
	action_demolish(gridmap_position)

func get_mesh(packed_scene):
	if not packed_scene:
		return null
	var scene_state:SceneState = packed_scene.get_state()
	var meshes: Array[Mesh] = []
	var xforms: Array[Transform3D] = []
	for i in range(scene_state.get_node_count()):
		if scene_state.get_node_type(i) != "MeshInstance3D":
			continue
		var mesh_data: Mesh = null
		var node_xform = Transform3D.IDENTITY
		for j in range(scene_state.get_node_property_count(i)):
			var pname = scene_state.get_node_property_name(i, j)
			if pname == "mesh":
				var v = scene_state.get_node_property_value(i, j)
				if v:
					mesh_data = v.duplicate()
			elif pname == "transform":
				node_xform = scene_state.get_node_property_value(i, j)
		if not mesh_data:
			continue

		var baked = ArrayMesh.new()
		for k in range(mesh_data.get_surface_count()):
			var arrays = mesh_data.surface_get_arrays(k)
			var verts = arrays[Mesh.ARRAY_VERTEX]
			if verts:
				for vi in range(verts.size()):
					verts[vi] = node_xform * verts[vi]
				arrays[Mesh.ARRAY_VERTEX] = verts
			var mat = mesh_data.surface_get_material(k)
			var prim = mesh_data.surface_get_primitive_type(k)
			var idx = baked.get_surface_count()
			baked.add_surface_from_arrays(prim, arrays)
			if mat:
				baked.surface_set_material(idx, mat)
		meshes.append(baked)

	if meshes.is_empty():
		return null
	if meshes.size() == 1:
		return meshes[0]
	var combined := ArrayMesh.new()
	for m in meshes:
		for k in range(m.get_surface_count()):
			var arrays = m.surface_get_arrays(k)
			var mat = m.surface_get_material(k)
			var prim = m.surface_get_primitive_type(k)
			var index = combined.get_surface_count()
			combined.add_surface_from_arrays(prim, arrays)
			if mat:
				combined.surface_set_material(index, mat)
	return combined

func _generate_uuid() -> String:
	var hex = "0123456789abcdef"
	var uuid = ""
	for i in range(36):
		if i == 8 or i == 13 or i == 18 or i == 23:
			uuid += "-"
		else:
			uuid += hex[randi() % 16]
	return uuid

func _get_hovered_cell() -> Vector3i:
	var ray = view_camera.get_node_or_null("PickRay") as RayCast3D
	if not ray:
		return Vector3i(-1, -1, -1)
	var mouse_pos = get_viewport().get_mouse_position()
	var origin = view_camera.project_ray_origin(mouse_pos)
	var normal = view_camera.project_ray_normal(mouse_pos)
	ray.global_position = origin
	ray.target_position = normal * 200.0
	ray.force_raycast_update()
	if ray.is_colliding():
		var col_point = ray.get_collision_point()
		var cell = to_cell(col_point)
		if gridmap.get_cell_item(cell) >= 0:
			return cell
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for y in range(10, -1, -1):
					var check = Vector3i(cell.x + dx, y, cell.z + dz)
					if gridmap.get_cell_item(check) >= 0:
						return check
	return Vector3i(-1, -1, -1)

func _get_item_occupied_cells(item_id: int, cell_pos: Vector3) -> Array:
	return [cell_pos]

func action_build(gridmap_position, force := false):
	if _build_repeat <= 0.0 and (force or Input.is_action_pressed("build")):
		var occupy = _get_item_occupied_cells(index, gridmap_position)
		var occupy_set = {}
		for c in occupy:
			var ck = cell_key(c)
			if gridmap.get_cell_item(to_cell(c)) >= 0:
				return
			occupy_set[ck] = true
		for existing_ck in placed_occupied:
			for ck in occupy_set:
				if placed_occupied[existing_ck].has(ck):
					return
		var cp = to_cell(gridmap_position)
		var previous_tile = gridmap.get_cell_item(cp)
		gridmap.set_cell_item(cp, index, gridmap.get_orthogonal_index_from_basis(selector.basis))
		if previous_tile != index:
			var ck = cell_key(gridmap_position)
			placed_occupied[ck] = occupy_set
			if not cell_uuids.has(ck):
				cell_uuids[ck] = _generate_uuid()
			map.cash -= structures[index].price
			update_cash()
			Audio.play("sounds/placement-a.ogg, sounds/placement-b.ogg, sounds/placement-c.ogg, sounds/placement-d.ogg", -20)
			auto_save()
			_build_repeat = REPEAT_DELAY
			if xray_mode:
				_set_xray_mode(false)
				_set_xray_mode(true)

func action_place_character(gridmap_position):
	if _build_repeat <= 0.0 and Input.is_action_pressed("build"):
		map.character_position = gridmap_position
		character_marker.position = gridmap_position + Vector3(0, 0.5, 0)
		character_mode = false
		selector.visible = true
		if character_dim_mat:
			character_marker.set_surface_override_material(0, character_dim_mat)
		Audio.play("sounds/placement-a.ogg, sounds/placement-b.ogg", -20)
		auto_save()
		_build_repeat = REPEAT_DELAY

func action_demolish(gridmap_position):
	if delete_mode:
		return
	if _build_repeat <= 0.0 and Input.is_action_pressed("demolish"):
		if character_mode and map.character_position.distance_to(gridmap_position) < 1:
			map.character_position = Vector3.ZERO
			character_marker.visible = false
			Audio.play("sounds/removal-a.ogg", -20)
			return
		var dp = to_cell(gridmap_position)
		if gridmap.get_cell_item(dp) != -1:
			var dck = cell_key(gridmap_position)
			cell_uuids.erase(dck)
			position_config_data.erase(dck)
			placed_occupied.erase(dck)
			gridmap.set_cell_item(dp, -1)
			Audio.play("sounds/removal-a.ogg, sounds/removal-b.ogg, sounds/removal-c.ogg, sounds/removal-d.ogg", -20)
			auto_save()

func auto_save():
	if current_map_filename.is_empty():
		return
	var map_data = {
		"title": current_map_filename.get_basename().replace("_", " "),
		"cash": map.cash,
		"cells": MapLoader.read_cells(gridmap, json_id_map, position_config_data, cell_uuids, barrier_item_id, CELL_SIZE)
	}
	if map.character_position != Vector3.ZERO:
		map_data["character"] = {"x": map.character_position.x, "y": map.character_position.y, "z": map.character_position.z}
	if not current_map_filename.begins_with("res://"):
		var prefix = "res://structures/" if structure_edit_mode else "res://maps/"
		current_map_filename = prefix + current_map_filename
	MapLoader.save_map(map_data, current_map_filename)

func action_y_axis():
	if Input.is_action_just_pressed("y_up"):
		y_offset += CELL_SIZE
	if Input.is_action_just_pressed("y_down"):
		y_offset -= CELL_SIZE
		y_offset = max(0.0, y_offset)

func _cycle_structure(dir: int):
	for _attempt in range(structures.size()):
		index = (index + dir + structures.size()) % structures.size()
		if character_indices.has(index):
			continue
		if structures[index] and structures[index].model:
			update_structure()
			return

func update_structure():
	for n in selector_container.get_children():
		selector_container.remove_child(n)
		n.queue_free()
	if index < 0 or index >= structures.size():
		return
	var ps = structures[index].model
	if not ps:
		return
	var _model = ps.instantiate()
	if not _model:
		return
	var sid_list = json_defs.keys()
	var sid = sid_list[index]
	var s = json_defs[sid].get("scale", 1.0)
	_model.scale = Vector3(s, s, s)
	selector_container.add_child(_model)
	_model.position.y += 0.25

func update_cash():
	cash_display.text = "$" + str(map.cash)

func _set_xray_mode(enabled: bool):
	xray_mode = enabled
	var lib = gridmap.mesh_library
	if enabled:
		for item_id in lib.get_item_list():
			var mesh = lib.get_item_mesh(item_id)
			if not mesh:
				continue
			xray_original_meshes[item_id] = mesh
			var xray_mesh = mesh.duplicate()
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.3, 0.6, 1.0, 0.3)
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			for s in range(xray_mesh.get_surface_count()):
				xray_mesh.surface_set_material(s, mat)
			lib.set_item_mesh(item_id, xray_mesh)
	else:
		for item_id in xray_original_meshes:
			lib.set_item_mesh(item_id, xray_original_meshes[item_id])
		xray_original_meshes.clear()
		_clear_xray_cubes()

func _clear_xray_cubes():
	for c in xray_cubes.get_children():
		c.queue_free()
	xray_cubes.visible = false

func _clear_all_cells():
	for cell_pos in gridmap.get_used_cells():
		var ck = "%d,%d,%d" % [cell_pos.x, cell_pos.y, cell_pos.z]
		cell_uuids.erase(ck)
		position_config_data.erase(ck)
		gridmap.set_cell_item(cell_pos, -1)
	placed_occupied.clear()
	map.cash = 10000
	update_cash()
	auto_save()

func action_save_modal():
	if Input.is_action_just_pressed("save_map"):
		if modal.visible:
			modal.hide()
		else:
			modal_name_input.text = map.title
			modal.show()
			modal_name_input.grab_focus()

func action_load_modal():
	if Input.is_action_just_pressed("load_map"):
		if load_modal.visible:
			load_modal.hide()
		else:
			refresh_map_list()
			load_modal.show()

func refresh_map_list():
	for child in load_map_container.get_children():
		child.queue_free()
	var dir = DirAccess.open("res://maps/")
	if not dir:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var found := false
	while file_name != "":
		if file_name.ends_with(".json") and file_name != "structures.json":
			found = true
			var map_name = file_name.get_basename().replace("_", " ")
			var btn = Button.new()
			btn.text = map_name
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.pressed.connect(_on_map_selected.bind(file_name))
			load_map_container.add_child(btn)
		file_name = dir.get_next()
	dir.list_dir_end()
	if not found:
		var lbl = Label.new()
		lbl.text = "No saved maps found"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		load_map_container.add_child(lbl)

func _on_map_selected(filename: String):
	if filename.is_empty():
		return
	var map_data = MapLoader.load_map(filename)
	if map_data.is_empty():
		return
	gridmap.clear()
	if character_marker:
		character_marker.visible = false
	current_map_filename = filename
	position_config_data = {}
	cell_uuids = {}
	placed_occupied = {}
	map = DataMap.new()
	MapLoader.place_cells(gridmap, map_data, json_id_map, CELL_SIZE)
	for cell in map_data.get("cells", []):
		var ck = cell_key(Vector3(cell.get("x", 0), cell.get("y", 0), cell.get("z", 0)))
		if cell.has("interactions"):
			position_config_data[ck] = {"interactions": cell["interactions"]}
		if cell.has("uuid"):
			cell_uuids[ck] = cell["uuid"]
	for cell_coord in gridmap.get_used_cells():
		var item = gridmap.get_cell_item(cell_coord)
		if item >= 0:
			var wpos = to_world(cell_coord)
			var occ = _get_item_occupied_cells(item, wpos)
			var occ_set = {}
			for o in occ:
				occ_set[cell_key(o)] = true
			placed_occupied[cell_key(wpos)] = occ_set
	if map_data.has("character"):
		var ch = map_data["character"]
		map.character_position = Vector3(ch.get("x", 0), ch.get("y", 0), ch.get("z", 0))
		map.cash = map_data.get("cash", 10000)
		character_mode = false
		update_cash()
		Audio.play("sounds/placement-a.ogg, sounds/placement-b.ogg", -20)
		load_modal.hide()

	var cells = map_data.get("cells", [])
	if cells.size() > 0:
		var min_pos = Vector3(cells[0]["x"], cells[0]["y"], cells[0]["z"])
		var max_pos = min_pos
		for c in cells:
			var p = Vector3(c["x"], c["y"], c["z"])
			min_pos = Vector3(min(min_pos.x, p.x), min(min_pos.y, p.y), min(min_pos.z, p.z))
			max_pos = Vector3(max(max_pos.x, p.x), max(max_pos.y, p.y), max(max_pos.z, p.z))
		var center = (min_pos + max_pos) / 2.0
		var view = get_node("../View")
		if view:
			view.camera_position = center

func _on_load_modal_cancel():
	Audio.play("sounds/toggle.ogg", -30)
	load_modal.hide()

func _on_save_modal_save(_text := ""):
	var title_text = modal_name_input.text.strip_edges()
	if title_text.is_empty():
		title_text = "Untitled Map"
	var filename = title_text.replace(" ", "_") + ".json"
	var map_data = {
		"title": title_text,
		"cash": map.cash,
		"cells": MapLoader.read_cells(gridmap, json_id_map, position_config_data, cell_uuids, barrier_item_id, CELL_SIZE)
	}
	if map.character_position != Vector3.ZERO:
		map_data["character"] = {"x": map.character_position.x, "y": map.character_position.y, "z": map.character_position.z}
	var save_path = ("res://structures/" if structure_edit_mode else "res://maps/") + filename
	MapLoader.save_map(map_data, save_path)
	current_map_filename = save_path
	print("Map saved as: " + save_path)
	Audio.play("sounds/placement-a.ogg, sounds/placement-b.ogg", -20)
	modal.hide()

func _on_save_modal_cancel():
	Audio.play("sounds/toggle.ogg", -30)
	modal.hide()

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_DELETE:
			_set_delete_mode(not delete_mode)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_B:
			_set_position_mode(not position_mode)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_BACKSPACE:
			get_tree().change_scene_to_file("res://scenes/menu.tscn")
			return
		if event.keycode == KEY_Q and not delete_mode:
			_cycle_dir = -1
			_cycle_repeat = 0.0
			return
		if event.keycode == KEY_E and not delete_mode:
			_cycle_dir = 1
			_cycle_repeat = 0.0
			return
		if event.keycode == KEY_Z and not structure_edit_mode:
			if struct_modal and struct_modal.visible:
				return
			if character_mode:
				_set_character_mode(false)
			elif not character_indices.is_empty():
				delete_mode = false
				delete_cursor.visible = false
				delete_marker.visible = false
				_set_character_mode(true)
			return
		if event.keycode == KEY_R:
			if not character_mode and not delete_mode:
				selector.basis = selector.basis.rotated(Vector3.UP, deg_to_rad(90))
			return
		if event.keycode == KEY_F1:
			fog_visible = not fog_visible
			if view_camera and view_camera.environment:
				view_camera.environment.fog_enabled = fog_visible
			return
		if event.keycode == KEY_X and event.ctrl_pressed:
			_clear_all_cells()
			return
		if event.keycode == KEY_Y and event.ctrl_pressed:
			_set_xray_mode(not xray_mode)
			return
		if event.keycode == KEY_M and not structure_edit_mode:
			barrier_mode = not barrier_mode
			barrier_marker.visible = barrier_mode
			if barrier_mode:
				delete_mode = false
				delete_cursor.visible = false
				delete_marker.visible = false
				character_mode = false
				_set_character_mode(false)
			return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			if not delete_mode and not barrier_mode and not character_mode:
				var pos: Vector3
				if _manual_placement_active:
					pos = _manual_placement_pos
				else:
					var hc = _get_hovered_cell()
					if hc.x >= 0:
						pos = to_world(hc)
						pos.y = y_offset
					else:
						var mp = get_viewport().get_mouse_position()
						var wp = plane.intersects_ray(view_camera.project_ray_origin(mp), view_camera.project_ray_normal(mp))
						pos = Vector3(snap(wp.x), y_offset, snap(wp.z))
				action_build(pos, true)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_LEFT and not delete_mode and not barrier_mode and not character_mode:
			_manual_placement_active = true
			if _manual_placement_pos == Vector3.ZERO:
				var hc = _get_hovered_cell()
				if hc.x >= 0:
					_manual_placement_pos = to_world(hc)
				else:
					var mp = get_viewport().get_mouse_position()
					var wp = plane.intersects_ray(view_camera.project_ray_origin(mp), view_camera.project_ray_normal(mp))
					_manual_placement_pos = Vector3(snap(wp.x), y_offset, snap(wp.z))
				_manual_placement_pos.y = y_offset
			_manual_placement_pos.x -= CELL_SIZE
			_manual_placement_pos.x = snap(_manual_placement_pos.x)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_RIGHT and not delete_mode and not barrier_mode and not character_mode:
			_manual_placement_active = true
			if _manual_placement_pos == Vector3.ZERO:
				var hc = _get_hovered_cell()
				if hc.x >= 0:
					_manual_placement_pos = to_world(hc)
				else:
					var mp = get_viewport().get_mouse_position()
					var wp = plane.intersects_ray(view_camera.project_ray_origin(mp), view_camera.project_ray_normal(mp))
					_manual_placement_pos = Vector3(snap(wp.x), y_offset, snap(wp.z))
				_manual_placement_pos.y = y_offset
			_manual_placement_pos.x += CELL_SIZE
			_manual_placement_pos.x = snap(_manual_placement_pos.x)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_UP and not delete_mode and not barrier_mode and not character_mode:
			_manual_placement_active = true
			if _manual_placement_pos == Vector3.ZERO:
				var hc = _get_hovered_cell()
				if hc.x >= 0:
					_manual_placement_pos = to_world(hc)
				else:
					var mp = get_viewport().get_mouse_position()
					var wp = plane.intersects_ray(view_camera.project_ray_origin(mp), view_camera.project_ray_normal(mp))
					_manual_placement_pos = Vector3(snap(wp.x), y_offset, snap(wp.z))
				_manual_placement_pos.y = y_offset
			_manual_placement_pos.z -= CELL_SIZE
			_manual_placement_pos.z = snap(_manual_placement_pos.z)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_DOWN and not delete_mode and not barrier_mode and not character_mode:
			_manual_placement_active = true
			if _manual_placement_pos == Vector3.ZERO:
				var hc = _get_hovered_cell()
				if hc.x >= 0:
					_manual_placement_pos = to_world(hc)
				else:
					var mp = get_viewport().get_mouse_position()
					var wp = plane.intersects_ray(view_camera.project_ray_origin(mp), view_camera.project_ray_normal(mp))
					_manual_placement_pos = Vector3(snap(wp.x), y_offset, snap(wp.z))
				_manual_placement_pos.y = y_offset
			_manual_placement_pos.z += CELL_SIZE
			_manual_placement_pos.z = snap(_manual_placement_pos.z)
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("ui_cancel"):
		if struct_modal and struct_modal.visible:
			_close_struct_modal()
		elif position_mode:
			_set_position_mode(false)
		elif delete_mode:
			_set_delete_mode(false)
		elif character_mode:
			_set_character_mode(false)
		elif modal.visible:
			_on_save_modal_cancel()
		elif load_modal.visible:
			_on_load_modal_cancel()
		else:
			get_tree().change_scene_to_file("res://scenes/menu.tscn")
