extends Control

const HOME_JSON = "res://maps/home.json"
const MAP_JSON = "res://maps/structures.json"

var home_data: Dictionary = {}

@onready var map_container := $MapModal/Panel/Scroll/MapContainer
@onready var map_modal := $MapModal
@onready var modal_title := $MapModal/Panel/Title

func _ready():
	var file = FileAccess.open(HOME_JSON, FileAccess.READ)
	if file:
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			home_data = json.data
			apply_style()
	_connect_buttons()

func apply_style():
	var bg = $Bg
	var ground = $Ground
	var ground_overlay = $Ground/GroundOverlay
	var title_label = $Title
	var subtitle_bg = $SubtitleBg
	var subtitle_label = $SubtitleBg/Subtitle

	if home_data.has("bg"):
		var bg_data = home_data["bg"]
		if bg_data.has("ground_color"):
			ground.color = _hex(bg_data["ground_color"])
		if bg_data.has("ground_overlay"):
			ground_overlay.color = _hex(bg_data["ground_overlay"])

	if home_data.has("title"):
		var t = home_data["title"]
		title_label.text = t.get("text", "CITY BUILDER")
		var ls = LabelSettings.new()
		ls.font = load("res://fonts/lilita_one_regular.ttf")
		ls.font_size = t.get("font_size", 72)
		ls.outline_color = _hex(t.get("outline_color", "#000000"))
		ls.outline_size = t.get("outline_size", 6)
		title_label.label_settings = ls

	if home_data.has("subtitle"):
		var s = home_data["subtitle"]
		subtitle_label.text = s.get("text", "")
		var sls = LabelSettings.new()
		sls.font = load("res://fonts/lilita_one_regular.ttf")
		sls.font_size = s.get("font_size", 22)
		subtitle_label.label_settings = sls
		subtitle_label.add_theme_color_override("font_color", _hex(s.get("color", "#e28a55")))
		var ss = StyleBoxFlat.new()
		ss.bg_color = _hex(s.get("bg_color", "#fff3e5"))
		ss.border_color = Color(0.118, 0.106, 0.161)
		ss.border_width_left = 4
		ss.border_width_top = 4
		ss.border_width_right = 4
		ss.border_width_bottom = 4
		ss.corner_radius_top_left = 40
		ss.corner_radius_top_right = 40
		ss.corner_radius_bottom_left = 40
		ss.corner_radius_bottom_right = 40
		subtitle_bg.add_theme_stylebox_override("panel", ss)

	var buttons_data = home_data.get("buttons", [])
	for btn_data in buttons_data:
		var btn_id = btn_data.get("id", "")
		var name = btn_id.capitalize() + "Btn"
		var btn = get_node_or_null(name)
		if btn:
			btn.text = btn_data.get("text", btn.text)
			var bs = StyleBoxFlat.new()
			bs.bg_color = _hex(btn_data.get("color", "#aaaaaa"))
			bs.border_color = Color(0.118, 0.106, 0.161)
			bs.border_width_left = 4
			bs.border_width_top = 4
			bs.border_width_right = 4
			bs.border_width_bottom = 8
			bs.corner_radius_top_left = 16
			bs.corner_radius_top_right = 16
			bs.corner_radius_bottom_left = 16
			bs.corner_radius_bottom_right = 16
			btn.add_theme_stylebox_override("normal", bs)
			btn.add_theme_color_override("font_color", Color(1, 1, 1))
			btn.add_theme_font_size_override("font_size", btn_data.get("font_size", 28))

func _hex(h: String) -> Color:
	return Color(h.replace("#", ""))

func _connect_buttons():
	var buttons_data = home_data.get("buttons", [])
	for btn_data in buttons_data:
		var btn_id = btn_data.get("id", "")
		var btn = find_child(btn_id.capitalize() + "Btn", true, false)
		if btn:
			var action = btn_data.get("action", "")
			if action == "play":
				btn.pressed.connect(_on_play)
			elif action == "edit":
				btn.pressed.connect(_on_edit)

func _on_play():
	modal_title.text = home_data.get("modal", {}).get("play_title", "Select Map")
	refresh_map_list(false)
	map_modal.show()

func _on_edit():
	modal_title.text = home_data.get("modal", {}).get("edit_title", "Edit Map")
	refresh_map_list(true)
	map_modal.show()

func refresh_map_list(is_edit: bool):
	for child in map_container.get_children():
		child.queue_free()

	var dir = DirAccess.open("res://maps/")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		var found := false
		while file_name != "":
			if file_name.ends_with(".json") and file_name != "structures.json" and file_name != "home.json":
				found = true
				var map_name = file_name.get_basename().replace("_", " ")
				var btn = Button.new()
				btn.text = map_name
				btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				btn.pressed.connect(_on_map_selected.bind(file_name, is_edit))
				map_container.add_child(btn)
			file_name = dir.get_next()
		dir.list_dir_end()
		if not found:
			var lbl = Label.new()
			lbl.text = home_data.get("no_maps_text", "No maps found")
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.custom_minimum_size = Vector2(300, 0)
			map_container.add_child(lbl)
	else:
		var lbl = Label.new()
		lbl.text = home_data.get("no_maps_text", "No maps found")
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(300, 0)
		map_container.add_child(lbl)

func _on_map_selected(filename: String, is_edit: bool):
	GameState.map_to_load = filename
	if is_edit:
		GameState.current_mode = GameState.Mode.EDIT
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		GameState.current_mode = GameState.Mode.PLAY
		get_tree().change_scene_to_file("res://scenes/play.tscn")

func _on_map_back():
	map_modal.hide()

func _input(event):
	if map_modal.visible and event.is_action_pressed("ui_cancel"):
		map_modal.hide()
