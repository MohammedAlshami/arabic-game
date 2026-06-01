extends Node3D

@export var player_scene: PackedScene
@export var tree_scene: PackedScene
@export var coin_scene: PackedScene

var world_size := 20
var mountain_radius := 6
var mountain_height := 7

var grass_mat: Material
var snow_mat: Material
var dirt_mat: Material

func _ready():
	create_materials()
	generate_ground()
	generate_mountain()
	spawn_player()
	spawn_decorations()
	spawn_coins()

func create_materials():
	grass_mat = StandardMaterial3D.new()
	grass_mat.albedo_color = Color(0.2, 0.6, 0.15)
	grass_mat.metallic = 0.0
	grass_mat.roughness = 0.9

	snow_mat = StandardMaterial3D.new()
	snow_mat.albedo_color = Color(0.95, 0.95, 0.98)
	snow_mat.metallic = 0.0
	snow_mat.roughness = 0.7

	dirt_mat = StandardMaterial3D.new()
	dirt_mat.albedo_color = Color(0.4, 0.25, 0.1)
	dirt_mat.metallic = 0.0
	dirt_mat.roughness = 0.95

func generate_ground():
	var ground = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(100, 0.5, 100)
	mesh.material = grass_mat
	ground.mesh = mesh
	ground.position = Vector3(0, -0.25, 0)
	add_child(ground)

	var body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	col.shape = shape
	body.add_child(col)
	body.position = Vector3(0, -0.5, 0)
	add_child(body)

func generate_mountain():
	for x in range(-mountain_radius, mountain_radius + 1):
		for z in range(-mountain_radius, mountain_radius + 1):
			var dist := Vector2(x, z).length()
			if dist > mountain_radius:
				continue
			var height := int(mountain_height * (1.0 - dist / mountain_radius)) + 1
			for y in range(1, height):
				var block = MeshInstance3D.new()
				block.mesh = BoxMesh.new()
				block.mesh.size = Vector3(2, 2, 2)
				if y >= mountain_height - 2:
					block.mesh.material = snow_mat
				elif y <= 1:
					block.mesh.material = dirt_mat
				else:
					block.mesh.material = grass_mat
				block.position = Vector3(x * 2, y * 2 - 0.5, z * 2)
				add_child(block)

				var body = StaticBody3D.new()
				var col = CollisionShape3D.new()
				var box = BoxShape3D.new()
				box.size = Vector3(2, 2, 2)
				col.shape = box
				body.add_child(col)
				body.position = block.position
				add_child(body)

	var slope_mat = StandardMaterial3D.new()
	slope_mat.albedo_color = Color(0.15, 0.5, 0.1)
	slope_mat.roughness = 0.9

	for x in range(-mountain_radius - 1, mountain_radius + 2):
		for z in range(-mountain_radius - 1, mountain_radius + 2):
			var dist := Vector2(x, z).length()
			if dist < mountain_radius - 1 or dist > mountain_radius + 0.5:
				continue
			var h := int(mountain_height * (1.0 - mountain_radius / mountain_radius)) if dist <= mountain_radius else 0
			h = max(h, 1)
			var block = MeshInstance3D.new()
			block.mesh = BoxMesh.new()
			block.mesh.size = Vector3(2, 1, 2)
			block.mesh.material = grass_mat
			block.position = Vector3(x * 2, -0.5, z * 2)
			add_child(block)

func spawn_player():
	var player = player_scene.instantiate()
	player.position = Vector3(15, 2, 15)
	add_child(player)

func spawn_decorations():
	var positions := [
		Vector3(-16, 0, -14), Vector3(18, 0, -10), Vector3(-14, 0, 18),
		Vector3(20, 0, 8), Vector3(-18, 0, -20), Vector3(10, 0, -18),
		Vector3(-20, 0, 12), Vector3(8, 0, 20), Vector3(-10, 0, -8),
		Vector3(22, 0, -14), Vector3(-22, 0, -12), Vector3(-12, 0, -22),
	]
	for pos in positions:
		var tree = tree_scene.instantiate()
		tree.position = pos
		add_child(tree)

func spawn_coins():
	for i in 20:
		var coin = coin_scene.instantiate()
		var x := (randi() % 36 - 18)
		var z := (randi() % 36 - 18)
		coin.position = Vector3(x, 3, z)
		add_child(coin)

func _process(_delta):
	if Input.is_action_just_pressed("ui_accept"):
		Globals.reset()
