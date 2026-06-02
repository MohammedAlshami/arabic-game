extends GdUnitTestSuite

const MAP_FILE = "starter_city.json"

func test_map_loads_and_spawns_player() -> void:
	GameState.map_to_load = MAP_FILE
	GameState.current_mode = GameState.Mode.PLAY
	var scene = load("res://scenes/play.tscn")
	var runner = scene_runner(scene)
	await await_milliseconds(500)
	assert_that(runner.find_child("Player")).is_not_null()
	assert_that(runner.find_child("View")).is_not_null()
	await get_tree().process_frame

func test_vehicle_exists_on_track() -> void:
	GameState.map_to_load = MAP_FILE
	GameState.current_mode = GameState.Mode.PLAY
	var runner = scene_runner(load("res://scenes/play.tscn"))
	await await_milliseconds(500)
	var vehicles = runner.find_child("Vehicle")
	assert_that(vehicles).is_not_null()

func test_player_can_walk() -> void:
	GameState.map_to_load = MAP_FILE
	GameState.current_mode = GameState.Mode.PLAY
	var runner = scene_runner(load("res://scenes/play.tscn"))
	await await_milliseconds(500)
	var player = runner.find_child("Player")
	assert_that(player).is_not_null()
	var start_pos = player.position

	# Simulate pressing W (move_forward) for 1 second
	Input.action_press("move_forward")
	await await_milliseconds(200)
	Input.action_release("move_forward")
	var moved = start_pos.distance_to(player.position)
	assert_that(moved).is_greater_than(0)

func test_player_can_enter_vehicle() -> void:
	GameState.map_to_load = MAP_FILE
	GameState.current_mode = GameState.Mode.PLAY
	var runner = scene_runner(load("res://scenes/play.tscn"))
	await await_milliseconds(1000)
	var player = runner.find_child("Player")
	var vehicle = runner.find_child("Vehicle")
	assert_that(player).is_not_null()
	assert_that(vehicle).is_not_null()

	# Move player near vehicle
	var dir = (vehicle.position - player.position).normalized()
	player.position += dir * 2.0
	await await_milliseconds(200)

	# Press V to enter
	var event = InputEventKey.new()
	event.keycode = KEY_V
	event.pressed = true
	Input.parse_input_event(event)
	await await_milliseconds(100)
	event.pressed = false
	Input.parse_input_event(event)
	await await_milliseconds(200)

	assert_that(vehicle.occupying).is_true()
