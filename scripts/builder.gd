extends Node3D

const MapLoader = preload("res://scripts/map_loader.gd")

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

var delete_mode := false
var delete_cursor: Control = null
var delete_cursor_tex: Texture2D = null
var delete_marker: MeshInstance3D = null
var character_dim_mat: Material = null

var json_defs: Dictionary = {}
var json_id_map: Dictionary = {}
var current_map_filename := ""

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

	character_index = -1
	var sid_list = json_defs.keys()
	for i in sid_list.size():
		if sid_list[i] == "character":
			character_index = i
			break

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

	# Also create a visible character model child for the marker
	if character_index >= 0 and character_index < structures.size():
		var char_model = structures[character_index].model.instantiate()
		if char_model:
			char_model.name = "CharPreview"
			char_model.position = Vector3(0, 0.5, 0)
			character_marker.add_child(char_model)

	delete_marker = MeshInstance3D.new()
	delete_marker.mesh = BoxMesh.new()
	delete_marker.mesh.size = Vector3(0.5, 0.5, 0.5)
	delete_marker.visible = false
	add_child(delete_marker)
	var del_mat = StandardMaterial3D.new()
	del_mat.albedo_color = Color(1, 0.2, 0.2, 0.5)
	del_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	delete_marker.set_surface_override_material(0, del_mat)

	canvas_layer = get_node("../CanvasLayer") as CanvasLayer
	structures_btn.visible = false
	_build_delete_cursor()

	update_structure()
	update_cash()

	if GameState.map_to_load:
		call_deferred("_on_startup_load")

	modal_save_btn.pressed.connect(_on_save_modal_save)

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

	var tab_order := ["Buildings", "Nature"]

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
	delete_mode = enabled
	delete_cursor.visible = enabled
	delete_marker.visible = false
	selector.visible = not enabled and not character_mode
	if enabled:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _set_character_mode(enabled: bool):
	character_mode = enabled
	character_marker.visible = enabled
	selector.visible = not enabled and not delete_mode
	if enabled:
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

	var mouse_pos = get_viewport().get_mouse_position()
	var world_position = plane.intersects_ray(
		view_camera.project_ray_origin(mouse_pos),
		view_camera.project_ray_normal(mouse_pos))

	var gridmap_position = Vector3(round(world_position.x), y_offset, round(world_position.z))

	if delete_mode:
		delete_cursor.position = mouse_pos
		delete_cursor.queue_redraw()
		var has_item = gridmap.get_cell_item(gridmap_position) != -1
		if has_item and not (character_mode and map.character_position.distance_to(gridmap_position) < 1):
			delete_marker.position = gridmap_position + Vector3(0, 0.5, 0)
			delete_marker.visible = true
		else:
			delete_marker.visible = false
		if Input.is_action_just_pressed("build"):
			gridmap.set_cell_item(gridmap_position, -1)
			Audio.play("sounds/removal-a.ogg, sounds/removal-b.ogg, sounds/removal-c.ogg, sounds/removal-d.ogg", -20)
			auto_save()
	elif character_mode:
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
	var meshes: Array[Mesh] = []
	for i in range(scene_state.get_node_count()):
		if scene_state.get_node_type(i) == "MeshInstance3D":
			for j in range(scene_state.get_node_property_count(i)):
				if scene_state.get_node_property_name(i, j) == "mesh":
					var prop_value = scene_state.get_node_property_value(i, j)
					if prop_value:
						meshes.append(prop_value.duplicate())
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

func action_build(gridmap_position):
	if Input.is_action_just_pressed("build"):
		var previous_tile = gridmap.get_cell_item(gridmap_position)
		gridmap.set_cell_item(gridmap_position, index, gridmap.get_orthogonal_index_from_basis(selector.basis))
		if previous_tile != index:
			map.cash -= structures[index].price
			update_cash()
			Audio.play("sounds/placement-a.ogg, sounds/placement-b.ogg, sounds/placement-c.ogg, sounds/placement-d.ogg", -20)
			auto_save()

func action_place_character(gridmap_position):
	if Input.is_action_just_pressed("build"):
		map.character_position = gridmap_position
		character_marker.position = gridmap_position + Vector3(0, 0.5, 0)
		character_mode = false
		selector.visible = true
		if character_dim_mat:
			character_marker.set_surface_override_material(0, character_dim_mat)
		Audio.play("sounds/placement-a.ogg, sounds/placement-b.ogg", -20)
		auto_save()

func action_demolish(gridmap_position):
	if delete_mode:
		return
	if Input.is_action_just_pressed("demolish"):
		if character_mode and map.character_position.distance_to(gridmap_position) < 1:
			map.character_position = Vector3.ZERO
			character_marker.visible = false
			Audio.play("sounds/removal-a.ogg", -20)
			return
		if gridmap.get_cell_item(gridmap_position) != -1:
			gridmap.set_cell_item(gridmap_position, -1)
			Audio.play("sounds/removal-a.ogg, sounds/removal-b.ogg, sounds/removal-c.ogg, sounds/removal-d.ogg", -20)
			auto_save()

func auto_save():
	if current_map_filename.is_empty():
		return
	var map_data = {
		"title": current_map_filename.get_basename().replace("_", " "),
		"cash": map.cash,
		"cells": MapLoader.read_cells(gridmap, json_id_map)
	}
	if map.character_position != Vector3.ZERO:
		map_data["character"] = {"x": map.character_position.x, "z": map.character_position.z}
	MapLoader.save_map(map_data, current_map_filename)

func action_y_axis():
	if Input.is_action_just_pressed("y_up"):
		y_offset += 1
	if Input.is_action_just_pressed("y_down"):
		y_offset -= 1
		y_offset = max(0, y_offset)

func _cycle_structure(dir: int):
	for _attempt in range(structures.size()):
		index = (index + dir + structures.size()) % structures.size()
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
	map = DataMap.new()
	MapLoader.place_cells(gridmap, map_data, json_id_map)
	if map_data.has("character"):
		var ch = map_data["character"]
		map.character_position = Vector3(ch.get("x", 0), 0, ch.get("z", 0))
	map.cash = map_data.get("cash", 10000)
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
	var filename = title_text.replace(" ", "_") + ".json"
	var map_data = {
		"title": title_text,
		"cash": map.cash,
		"cells": MapLoader.read_cells(gridmap, json_id_map)
	}
	if map.character_position != Vector3.ZERO:
		map_data["character"] = {"x": map.character_position.x, "z": map.character_position.z}
	MapLoader.save_map(map_data, filename)
	current_map_filename = filename
	print("Map saved as: " + filename)
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
		if event.keycode == KEY_BACKSPACE:
			get_tree().change_scene_to_file("res://scenes/menu.tscn")
			return
		if event.keycode == KEY_Q and not character_mode and not delete_mode:
			_cycle_structure(-1)
			return
		if event.keycode == KEY_E and not character_mode and not delete_mode:
			_cycle_structure(1)
			return
		if event.keycode == KEY_Z:
			if struct_modal and struct_modal.visible:
				return
			if character_mode:
				_set_character_mode(false)
			else:
				delete_mode = false
				delete_cursor.visible = false
				delete_marker.visible = false
				_set_character_mode(true)
			return
		if event.keycode == KEY_R:
			if not character_mode and not delete_mode:
				selector.basis = selector.basis.rotated(Vector3.UP, deg_to_rad(90))
			return

	if event.is_action_pressed("ui_cancel"):
		if struct_modal and struct_modal.visible:
			_close_struct_modal()
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
