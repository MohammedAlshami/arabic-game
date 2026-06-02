extends Node

# Load the structure definitions from maps/structures.json
static func load_definitions() -> Dictionary:
	var file = FileAccess.open("res://maps/structures.json", FileAccess.READ)
	if not file:
		push_error("Cannot open maps/structures.json")
		return {}
	var text = file.get_as_text()
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		push_error("JSON parse error in structures.json: ", err)
		return {}
	var data = json.data
	var result = {}
	for entry in data:
		result[entry["id"]] = entry
	return result

# Load a map JSON file from res://maps/
static func load_map(filename: String) -> Dictionary:
	var path = "res://maps/" + filename
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Cannot open map: ", path)
		return {}
	var text = file.get_as_text()
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		push_error("JSON parse error in map: ", err)
		return {}
	return json.data

# Save a map dictionary to res://maps/ as JSON
static func save_map(data: Dictionary, filename: String) -> bool:
	var path = "res://maps/" + filename
	var json_str = JSON.new().stringify(data, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Cannot write map: ", path)
		return false
	file.store_string(json_str)
	return true

# Build a MeshLibrary from structure definitions
static func build_mesh_library(defs: Dictionary) -> MeshLibrary:
	var lib = MeshLibrary.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	var id_map = {}
	var next_id = 0
	for key in defs.keys():
		var entry = defs[key]
		var ps = load(entry["model"])
		var mesh = _get_mesh(ps)
		var item_id = lib.get_last_unused_item_id()
		lib.create_item(item_id)
		if mesh:
			lib.set_item_mesh(item_id, mesh)
		else:
			lib.set_item_mesh(item_id, box)
		var s = entry.get("scale", 1.0)
		if s != 1.0:
			var t = Transform3D()
			t = t.scaled(Vector3(s, s, s))
			lib.set_item_mesh_transform(item_id, t)
		else:
			lib.set_item_mesh_transform(item_id, Transform3D())
		id_map[key] = item_id
		next_id += 1
	lib.set_meta("id_map", id_map)
	return lib

# Place cells from map data onto a GridMap using the id_map
static func place_cells(gridmap: GridMap, map_data: Dictionary, id_map: Dictionary):
	for cell in map_data.get("cells", []):
		var sid = cell["id"]
		var item = id_map.get(sid, -1)
		if item >= 0:
			var pos = Vector3i(cell.get("x", 0), 0, cell.get("z", 0))
			var orient = cell.get("orient", 0)
			gridmap.set_cell_item(pos, item, orient)

# Get cells from a GridMap back into map format using reverse id_map
static func read_cells(gridmap: GridMap, id_map: Dictionary) -> Array:
	var rev_map = {}
	for key in id_map:
		rev_map[id_map[key]] = key
	var cells = []
	for cell_pos in gridmap.get_used_cells():
		var item = gridmap.get_cell_item(cell_pos)
		var sid = rev_map.get(item, "")
		if sid != "":
			cells.append({
				"id": sid,
				"x": cell_pos.x,
				"z": cell_pos.z,
				"orient": gridmap.get_cell_item_orientation(cell_pos)
			})
	return cells

static func _get_mesh(packed_scene):
	if not packed_scene:
		return null
	var state = packed_scene.get_state()
	var meshes: Array[Mesh] = []
	for i in range(state.get_node_count()):
		if state.get_node_type(i) == "MeshInstance3D":
			for j in range(state.get_node_property_count(i)):
				if state.get_node_property_name(i, j) == "mesh":
					var v = state.get_node_property_value(i, j)
					if v:
						meshes.append(v.duplicate())
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
			var idx = combined.get_surface_count()
			combined.add_surface_from_arrays(prim, arrays)
			if mat:
				combined.surface_set_material(idx, mat)
	return combined
