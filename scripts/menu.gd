extends Control

@onready var map_container := $MapModal/Panel/Scroll/MapContainer
@onready var map_modal := $MapModal
@onready var play_btn := $PlayBtn
@onready var edit_btn := $EditBtn

func _ready():
	play_btn.pressed.connect(_on_play)
	edit_btn.pressed.connect(_on_edit)

func _on_play():
	refresh_map_list()
	map_modal.show()

func _on_edit():
	GameState.current_mode = GameState.Mode.EDIT
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func refresh_map_list():
	for child in map_container.get_children():
		child.queue_free()

	var dir = DirAccess.open("user://")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		var found := false

		while file_name != "":
			if file_name.ends_with(".res"):
				found = true
				var map_name = file_name.trim_suffix(".res").replace("_", " ")
				var btn = Button.new()
				btn.text = map_name
				btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var path = "user://" + file_name
				btn.pressed.connect(_start_play.bind(path))
				map_container.add_child(btn)
			file_name = dir.get_next()

		dir.list_dir_end()

		if not found:
			var lbl = Label.new()
			lbl.text = "No saved maps found"
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			map_container.add_child(lbl)
	else:
		var lbl = Label.new()
		lbl.text = "No saved maps found"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		map_container.add_child(lbl)

func _start_play(path: String):
	GameState.map_to_load = path
	GameState.current_mode = GameState.Mode.PLAY
	get_tree().change_scene_to_file("res://scenes/play.tscn")

func _on_map_back():
	map_modal.hide()

func _input(event):
	if map_modal.visible and event.is_action_pressed("ui_cancel"):
		map_modal.hide()
