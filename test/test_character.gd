extends Node

const MapLoader = preload("res://scripts/map_loader.gd")

func _ready():
	print("=== CHARACTER PLACEMENT TEST (Z key) ===")
	
	GameState.map_to_load = "my_map.json"
	GameState.current_mode = GameState.Mode.EDIT
	var editor = load("res://scenes/main.tscn").instantiate()
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	
	var builder = get_node("Main/Builder")
	if not builder:
		print("FAIL: Builder not found"); get_tree().quit(); return
	print("PASS: Editor loaded")
	
	# 1. Press Z to toggle character mode
	var event = InputEventKey.new()
	event.keycode = KEY_Z
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame
	
	if builder.character_mode:
		print("PASS: Z key toggled character_mode = true")
	else:
		print("FAIL: character_mode not set after Z"); get_tree().quit(); return
	
	# 2. Check character_position before placement
	if builder.map.character_position == Vector3.ZERO:
		print("PASS: character_position starts at zero")
	else:
		print("INFO: character_position already = ", builder.map.character_position)
	
	# 3. Simulate clicking to place
	Input.action_press("build")
	await get_tree().process_frame
	Input.action_release("build")
	await get_tree().process_frame
	await get_tree().process_frame
	
	# 4. Verify placement
	if not builder.character_mode:
		print("PASS: character_mode = false after placement")
	else:
		print("FAIL: character_mode still true")
	
	if builder.map.character_position != Vector3.ZERO:
		print("PASS: Character placed at ", builder.map.character_position)
	else:
		print("FAIL: character_position still zero")
	
	# 5. Verify JSON saved
	var saved = MapLoader.load_map("my_map.json")
	if saved.has("character"):
		var ch = saved["character"]
		print("PASS: JSON has character at (", ch.get("x"), ", ", ch.get("z"), ")")
	else:
		print("FAIL: JSON missing character field")
	
	print("\n=== ALL TESTS COMPLETE ===")
	get_tree().quit()
