extends Node3D
## M1 Abrams presentation. Gameplay owns traverse, elevation and tread speeds.
var turret: Node3D
var barrel: Node3D
var muzzle: Node3D
var _recoil: Node3D
var _paths: Array[PackedVector3Array] = []
var _lengths: Array[float] = []
var _phases: Array[float] = [0.0, 0.0]
var _shoes: Array[Array] = []
var _wheels: Array[Array] = [[], []]
var _materials: Array[StandardMaterial3D] = []
var _colors: Array[Color] = []
var _material_copies: Dictionary[Material, StandardMaterial3D] = {}
var _destroyed: bool = false

func _ready() -> void:
	var model: Node3D = $Model/M1Abrams
	turret = model.get_node("TurretPivot")
	barrel = turret.get_node("BarrelPivot")
	_recoil = barrel.get_node("Recoil")
	muzzle = _recoil.get_node("Muzzle")
	var data: Array = JSON.parse_string(FileAccess.get_file_as_string("res://games/minigame/godot_party_default_tank_range/assets/m1_abrams/track_paths.json"))
	for side: int in 2:
		var path: PackedVector3Array = []
		for point: Array in data[side]:
			path.append(Vector3(point[0], point[1], point[2]))
		_paths.append(path)
		var length: float = 0.0
		for i: int in path.size():
			length += path[i].distance_to(path[(i + 1) % path.size()])
		_lengths.append(length)
		var source: MeshInstance3D = model.get_node("TrackShoeL" if side == 0 else "TrackShoeR")
		var shoes: Array[MeshInstance3D] = [source]
		for i: int in range(1, roundi(length / 0.128)):
			var shoe: MeshInstance3D = source.duplicate()
			model.add_child(shoe)
			shoes.append(shoe)
		_shoes.append(shoes)
		for wheel: Node in model.find_children("WheelL*" if side == 0 else "WheelR*", "MeshInstance3D", false, false):
			_wheels[side].append(wheel)
	_duplicate_materials(model)
	animate_tracks(0.0, 0.0, 0.0)

func _duplicate_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node
		for surface: int in instance.mesh.get_surface_count():
			var source: Material = instance.get_active_material(surface)
			if not _material_copies.has(source):
				var material: StandardMaterial3D = source.duplicate()
				_material_copies[source] = material
				_materials.append(material)
				_colors.append(material.albedo_color)
			instance.set_surface_override_material(surface, _material_copies[source])
	for child: Node in node.get_children():
		_duplicate_materials(child)

func animate_tracks(left_speed: float, right_speed: float, delta: float, _ground_offsets: Array[float] = []) -> void:
	if _destroyed:
		return
	for side: int in 2:
		var speed: float = left_speed if side == 0 else right_speed
		_phases[side] = fposmod(_phases[side] + speed * delta, _lengths[side])
		var path: PackedVector3Array = _paths[side]
		for i: int in _shoes[side].size():
			var distance: float = fposmod(_phases[side] + i * _lengths[side] / _shoes[side].size(), _lengths[side])
			for segment: int in path.size():
				var a: Vector3 = path[segment]
				var b: Vector3 = path[(segment + 1) % path.size()]
				var length: float = a.distance_to(b)
				if distance <= length:
					var shoe: MeshInstance3D = _shoes[side][i]
					shoe.position = a.lerp(b, distance / length)
					# Belt tangent lies in YZ. X stays on the wheel axle even at the ends.
					var z_axis: Vector3 = (b - a).normalized()
					shoe.basis = Basis(Vector3.RIGHT, z_axis.cross(Vector3.RIGHT), z_axis)
					break
				distance -= length
		for wheel: Node3D in _wheels[side]:
			wheel.rotate_x(-speed * delta / 0.26)

func set_recoil(amount: float) -> void:
	_recoil.position.z = clampf(amount, 0.0, 1.0) * 0.22

func set_destroyed(value: bool) -> void:
	if value == _destroyed:
		return
	_destroyed = value
	for i: int in _materials.size():
		_materials[i].albedo_color = _colors[i].darkened(0.65) if value else _colors[i]
