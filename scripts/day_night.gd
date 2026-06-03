extends Node

enum TimeOfDay { DAY, NIGHT }

var current_time := TimeOfDay.DAY
var sky_material: ProceduralSkyMaterial
var env_node: WorldEnvironment
var sun: DirectionalLight3D
var fade_overlay: ColorRect
var is_sleeping := false
var _sleep_phase := 0

func _ready():
	env_node = get_node("../WorldEnvironment")
	sun = get_node("../DirectionalLight3D")
	if env_node and env_node.environment and env_node.environment.sky:
		sky_material = env_node.environment.sky.sky_material

	fade_overlay = ColorRect.new()
	fade_overlay.color = Color(0, 0, 0, 0)
	fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var canvas = CanvasLayer.new()
	canvas.add_child(fade_overlay)
	add_child(canvas)

func _process(delta):
	if _sleep_phase == 1:
		fade_overlay.color.a = min(fade_overlay.color.a + delta * 1.25, 1.0)
		if fade_overlay.color.a >= 1.0:
			_sleep_phase = 2
	elif _sleep_phase == 2:
		_sleep_phase_timer -= delta
		if _sleep_phase_timer <= 0:
			toggle_time()
			_sleep_phase = 3
	elif _sleep_phase == 3:
		fade_overlay.color.a = max(fade_overlay.color.a - delta * 1.25, 0.0)
		if fade_overlay.color.a <= 0.0:
			_sleep_phase = 0
			is_sleeping = false

var _sleep_phase_timer := 0.0

func sleep():
	if is_sleeping:
		return
	is_sleeping = true
	_sleep_phase = 1
	_sleep_phase_timer = 0.5

func is_player_asleep() -> bool:
	return _sleep_phase > 0

func toggle_time():
	if current_time == TimeOfDay.DAY:
		current_time = TimeOfDay.NIGHT
		_set_night()
	else:
		current_time = TimeOfDay.DAY
		_set_day()

func _set_day():
	if not sky_material or not env_node:
		return
	sky_material.sky_top_color = Color(0.47, 0.69, 1.0)
	sky_material.sky_horizon_color = Color(0.67, 0.68, 0.70)
	sky_material.ground_bottom_color = Color(1, 1, 1)
	sky_material.sun_energy = 1.0
	env_node.environment.ambient_light_color = Color(0.66, 0.69, 0.77)
	env_node.environment.ambient_light_energy = 0.75
	if sun:
		sun.light_energy = 1.0

func _set_night():
	if not sky_material or not env_node:
		return
	sky_material.sky_top_color = Color(0.01, 0.01, 0.05)
	sky_material.sky_horizon_color = Color(0.02, 0.02, 0.08)
	sky_material.ground_bottom_color = Color(0.0, 0.0, 0.02)
	sky_material.sun_energy = 0.0
	env_node.environment.ambient_light_color = Color(0.1, 0.1, 0.2)
	env_node.environment.ambient_light_energy = 0.15
	if sun:
		sun.light_energy = 0.0

func get_bed_ids() -> Array:
	return [
		"furniture-bed_double_A", "furniture-bed_double_B",
		"furniture-bed_single_A", "furniture-bed_single_B"
	]
