extends Node3D

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _on_vehicle_spawned(vehicle: Node3D):
	var view = preload("res://scripts/view_racing.gd").new()
	view.target = vehicle
	var cam = Camera3D.new()
	cam.current = true
	cam.position.z = 10
	cam.position.y = 3
	view.add_child(cam)
	add_child(view)
