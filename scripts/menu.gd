extends Control

@onready var map_container := $MapModal/Panel/Scroll/MapContainer
@onready var map_modal := $MapModal
@onready var modal_title := $MapModal/Panel/Title
@onready var play_btn := $PlayBtn
@onready var edit_btn := $EditBtn

func _ready():
	play_btn.pressed.connect(_on_play)
	edit_btn.pressed.connect(_on_edit)

func _on_play():
	modal_title.text = "Select Map"
	refresh_map_list("play")
	map_modal.show()

func _on_edit():
	modal_title.text = "Edit Map"
	refresh_map_list("edit")
	map_modal.show()

func refresh_map_list(mode: String):
	for child in map_container.get_children():
		child.queue_free()

	var dir = DirAccess.open("res://maps/")
	if dir:
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
				var is_edit = mode == "edit"
				btn.pressed.connect(_on_map_selected.bind(file_name, is_edit))
				map_container.add_child(btn)
			file_name = dir.get_next()
		dir.list_dir_end()
		if not found:
			var lbl = Label.new()
			lbl.text = "No maps yet. Ask the AI to create one for you!"
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.custom_minimum_size = Vector2(300, 0)
			map_container.add_child(lbl)
	else:
		var lbl = Label.new()
		lbl.text = "No maps yet. Ask the AI to create one for you!"
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
