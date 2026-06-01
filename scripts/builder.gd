extends Node3D

@export var structures: Array[Structure] = []

var map:DataMap

var index:int = 0
var y_offset := 0
var character_mode := false
var character_marker: Node3D = null
var character_index := -1

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

func _ready():
	map = DataMap.new()
	plane = Plane(Vector3.UP, Vector3.ZERO)

	var extra_paths := [
		"res://structures/character.tres",
		"res://structures/platform_basic.tres",
		"res://structures/platform_medium.tres",
		"res://structures/platform_large.tres",
		"res://structures/coin_collectible.tres",
		"res://structures/flag.tres",
	]
	for p in extra_paths:
		var s = ResourceLoader.load(p)
		if s:
			structures.append(s)

	build_categories()

	var mesh_library = MeshLibrary.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	for i in structures.size():
		var id = mesh_library.get_last_unused_item_id()
		mesh_library.create_item(id)
		var mesh = get_mesh(structures[i].model)
		if i == character_index or not mesh:
			mesh_library.set_item_mesh(id, box)
		else:
			mesh_library.set_item_mesh(id, mesh)
		mesh_library.set_item_mesh_transform(id, Transform3D())

	gridmap.mesh_library = mesh_library

	character_marker = MeshInstance3D.new()
	character_marker.mesh = BoxMesh.new()
	character_marker.mesh.size = Vector3(0.5, 1, 0.5)
	character_marker.visible = false
	add_child(character_marker)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.4, 1)
	character_marker.set_surface_override_material(0, mat)

	canvas_layer = get_node("../CanvasLayer") as CanvasLayer
	build_struct_modal()
	structures_btn.pressed.connect(_open_struct_modal)

	update_structure()
	update_cash()

	modal_save_btn.pressed.connect(_on_save_modal_save)
	modal_cancel_btn.pressed.connect(_on_save_modal_cancel)
	modal_name_input.text_submitted.connect(_on_save_modal_save)
	load_cancel_btn.pressed.connect(_on_load_modal_cancel)

func build_categories():
	categories = {
		"Buildings": [],
		"Nature": [],
		"Platforms": [],
		"Items": [],
		"Animals": [],
		"Tracks": [],
		"Vehicles": [],
	}

	var dirs_to_scan := {
		"Animals": {"path": "res://models/animals", "prefix": "animal-"},
		"Tracks": {"path": "res://models/track", "prefix": ""},
		"Vehicles": {"path": "res://models/vehicles", "prefix": ""},
	}
	for cat_name in dirs_to_scan:
		var info = dirs_to_scan[cat_name]
		var d = DirAccess.open(info.path)
		if d:
			d.list_dir_begin()
			var f = d.get_next()
			while f != "":
				if f.ends_with(".glb"):
					if info.prefix.is_empty() or f.begins_with(info.prefix):
						var path = info.path + "/" + f
						var s = Structure.new()
						s.model = load(path)
						s.price = 0
						structures.append(s)
						categories[cat_name].append(structures.size() - 1)
				f = d.get_next()
			d.list_dir_end()

	for i in structures.size():
		var path = structures[i].model.resource_path
		if "character" in path:
			character_index = i
		elif "building" in path or "garage" in path or "road" in path or "pavement" in path:
			categories["Buildings"].append(i)
		elif "grass" in path or "tree" in path:
			categories["Nature"].append(i)
		elif "platform" in path:
			categories["Platforms"].append(i)
		elif "coin" in path or "flag" in path:
			categories["Items"].append(i)

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

	var tab_order := ["Buildings", "Nature", "Platforms", "Items", "Tracks", "Animals", "Vehicles"]
	if character_index >= 0:
		tab_order.push_front("Character")

	for cat_name in tab_order:
		var scroll = ScrollContainer.new()
		scroll.name = cat_name
		tabs.add_child(scroll)
		scroll.add_theme_stylebox_override("panel", white_bg)

		var grid = GridContainer.new()
		grid.columns = 3
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(grid)

		var indices = []
		if cat_name == "Character" and character_index >= 0:
			indices = [character_index]
		else:
			indices = categories.get(cat_name, [])

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
			texture_rect.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					_select_structure(i))

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

func _open_struct_modal():
	struct_modal.visible = true

func _close_struct_modal():
	struct_modal.visible = false

func _on_struct_overlay_click(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_struct_modal()

func _select_structure(idx: int):
	if idx == character_index:
		character_mode = true
		character_marker.visible = true
		if map.character_position != Vector3.ZERO:
			character_marker.position = map.character_position + Vector3(0, 0.5, 0)
		selector.visible = false
	else:
		character_mode = false
		character_marker.visible = false
		selector.visible = true
		index = idx
		update_structure()
	_close_struct_modal()

func _process(delta):
	action_y_axis()
	action_save_modal()
	action_load_modal()

	var world_position = plane.intersects_ray(
		view_camera.project_ray_origin(get_viewport().get_mouse_position()),
		view_camera.project_ray_normal(get_viewport().get_mouse_position()))

	var gridmap_position = Vector3(round(world_position.x), y_offset, round(world_position.z))

	if character_mode:
		character_marker.position = lerp(character_marker.position, gridmap_position + Vector3(0, 0.5, 0), min(delta * 40, 1.0))
		action_place_character(gridmap_position)
	else:
		selector.position = lerp(selector.position, gridmap_position, min(delta * 40, 1.0))
		action_build(gridmap_position)

	action_demolish(gridmap_position)

func get_mesh(packed_scene):
	if not packed_scene:
		return null
	var scene_state:SceneState = packed_scene.get_state()
	for i in range(scene_state.get_node_count()):
		if scene_state.get_node_type(i) == "MeshInstance3D":
			for j in range(scene_state.get_node_property_count(i)):
				if scene_state.get_node_property_name(i, j) == "mesh":
					var prop_value = scene_state.get_node_property_value(i, j)
					if prop_value:
						return prop_value.duplicate()
	return null

func action_build(gridmap_position):
	if Input.is_action_just_pressed("build"):
		var previous_tile = gridmap.get_cell_item(gridmap_position)
		gridmap.set_cell_item(gridmap_position, index, gridmap.get_orthogonal_index_from_basis(selector.basis))
		if previous_tile != index:
			map.cash -= structures[index].price
			update_cash()
			Audio.play("sounds/placement-a.ogg, sounds/placement-b.ogg, sounds/placement-c.ogg, sounds/placement-d.ogg", -20)

func action_place_character(gridmap_position):
	if Input.is_action_just_pressed("build"):
		if map.character_position != Vector3.ZERO:
			return
		map.character_position = gridmap_position
		character_marker.position = gridmap_position + Vector3(0, 0.5, 0)
		character_mode = false
		character_marker.visible = false
		selector.visible = true
		Audio.play("sounds/placement-a.ogg, sounds/placement-b.ogg", -20)

func action_demolish(gridmap_position):
	if Input.is_action_just_pressed("demolish"):
		if character_mode and map.character_position.distance_to(gridmap_position) < 1:
			map.character_position = Vector3.ZERO
			character_marker.visible = false
			Audio.play("sounds/removal-a.ogg", -20)
			return
		if gridmap.get_cell_item(gridmap_position) != -1:
			gridmap.set_cell_item(gridmap_position, -1)
			Audio.play("sounds/removal-a.ogg, sounds/removal-b.ogg, sounds/removal-c.ogg, sounds/removal-d.ogg", -20)

func action_y_axis():
	if Input.is_action_just_pressed("y_up"):
		y_offset += 1
	if Input.is_action_just_pressed("y_down"):
		y_offset -= 1
		y_offset = max(0, y_offset)

func update_structure():
	for n in selector_container.get_children():
		selector_container.remove_child(n)
		n.queue_free()
	var _model = structures[index].model.instantiate()
	selector_container.add_child(_model)
	_model.position.y += 0.25

func update_cash():
	cash_display.text = "$" + str(map.cash)

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
	var dir = DirAccess.open("user://")
	if not dir:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var found := false
	while file_name != "":
		if file_name.ends_with(".res") and not file_name.begins_with("."):
			found = true
			var map_name = file_name.trim_suffix(".res").replace("_", " ")
			var btn = Button.new()
			btn.text = map_name
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var file_path = "user://" + file_name
			btn.pressed.connect(_on_map_selected.bind(file_path))
			load_map_container.add_child(btn)
		file_name = dir.get_next()
	dir.list_dir_end()
	if not found:
		var lbl = Label.new()
		lbl.text = "No saved maps found"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		load_map_container.add_child(lbl)

func _on_map_selected(file_path: String):
	var loaded_map = ResourceLoader.load(file_path)
	if not loaded_map:
		return
	gridmap.clear()
	if character_marker:
		character_marker.visible = false
	map = loaded_map
	for cell in map.structures:
		gridmap.set_cell_item(Vector3i(cell.position.x, 0, cell.position.y), cell.structure, cell.orientation)
	if map.character_position != Vector3.ZERO:
		character_marker.position = map.character_position + Vector3(0, 0.5, 0)
		character_marker.visible = true
	character_mode = false
	update_cash()
	Audio.play("sounds/placement-a.ogg, sounds/placement-b.ogg", -20)
	load_modal.hide()

func _on_load_modal_cancel():
	Audio.play("sounds/toggle.ogg", -30)
	load_modal.hide()

func _on_save_modal_save(_text := ""):
	var title_text = modal_name_input.text.strip_edges()
	if title_text.is_empty():
		title_text = "Untitled Map"
	map.title = title_text
	map.structures.clear()
	for cell in gridmap.get_used_cells():
		var item = gridmap.get_cell_item(cell)
		var data_structure:DataStructure = DataStructure.new()
		data_structure.position = Vector2i(cell.x, cell.z)
		data_structure.orientation = gridmap.get_cell_item_orientation(cell)
		data_structure.structure = item
		map.structures.append(data_structure)
	ResourceSaver.save(map, "user://" + title_text.replace(" ", "_") + ".res")
	print("Map saved as: " + title_text)
	Audio.play("sounds/placement-a.ogg, sounds/placement-b.ogg", -20)
	modal.hide()

func _on_save_modal_cancel():
	Audio.play("sounds/toggle.ogg", -30)
	modal.hide()

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if struct_modal and struct_modal.visible:
			_close_struct_modal()
		elif character_mode:
			character_mode = false
			character_marker.visible = false
			selector.visible = true
		elif modal.visible:
			_on_save_modal_cancel()
		elif load_modal.visible:
			_on_load_modal_cancel()
		else:
			get_tree().change_scene_to_file("res://scenes/menu.tscn")
