extends Node

const MapLoader = preload("res://scripts/map_loader.gd")

func _ready():
	print("=== AUTOMATED GAME TESTS ===")
	
	var defs = MapLoader.load_definitions()
	if not defs.is_empty():
		print("PASS: Structures loaded (" + str(defs.size()) + " items)")
	else:
		print("FAIL: Structures not loaded")
	
	GameState.map_to_load = "starter_city.json"
	GameState.current_mode = GameState.Mode.PLAY
	var play = load("res://scenes/play.tscn").instantiate()
	add_child(play)
	
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	
	var gridmap = get_node("Play/GridMap")
	if gridmap and gridmap.get_used_cells().size() > 0:
		print("PASS: GridMap has " + str(gridmap.get_used_cells().size()) + " cells")
	else:
		print("FAIL: GridMap empty or missing")
	
	var player = get_node_or_null("Play/Player")
	if player:
		print("PASS: Player spawned at " + str(player.position))
	else:
		print("FAIL: Player not found")
	
	var vehicle = get_node_or_null("Play/Vehicle")
	if vehicle:
		print("PASS: Vehicle spawned at " + str(vehicle.position))
	else:
		print("FAIL: Vehicle not found")
	
	print("\n=== TESTS COMPLETE ===")
	get_tree().quit()
