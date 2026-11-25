extends Node3D
## Tracked vehicle presentation. Gameplay owns traverse, elevation and tread speeds.
@export var missile_muzzle: Node3D
@export var second_muzzle: Node3D
@export var launcher: Node3D
@export var turret: Node3D
@export var barrel: Node3D
@export var muzzle: Node3D
@export var primary_muzzles: Array[Node3D] = []
@export var missile_muzzles: Array[Node3D] = []
@export var _recoil: Node3D
var _paths: Array[PackedVector3Array] = []
var _lengths: Array[float] = []
var _phases: Array[float] = [0.0, 0.0]
var _shoes: Array[Array] = []
var _wheels: Array[Array] = [[], []]
var _materials: Array[StandardMaterial3D] = []
var _colors: Array[Color] = []
var _material_copies: Dictionary[Material, StandardMaterial3D] = {}
var _destroyed: bool = false

@export var left_path: PackedVector3Array
@export var right_path: PackedVector3Array
@export var left_shoes: Array[MeshInstance3D]
@export var right_shoes: Array[MeshInstance3D]
@export var left_wheels: Array[MeshInstance3D]
@export var right_wheels: Array[MeshInstance3D]

func _ready() -> void:
	assert(turret != null and barrel != null and muzzle != null and _recoil != null and launcher != null and missile_muzzle != null and second_muzzle != null, "Vehicle visual requires authored pivots and muzzles.")
	assert(not left_shoes.is_empty() and not right_shoes.is_empty() and left_path.size() > 1 and right_path.size() > 1, "Vehicle visual requires authored tread belts.")
	_paths = [left_path, right_path]
	_shoes = [left_shoes, right_shoes]
	_wheels = [left_wheels, right_wheels]
	for path: PackedVector3Array in _paths:
		var length: float = 0.0
		for i: int in path.size():
			length += path[i].distance_to(path[(i + 1) % path.size()])
		_lengths.append(length)
	_duplicate_materials($Model)

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

func aim_launcher() -> void:
	if launcher != barrel:
		launcher.rotation.x = barrel.rotation.x

func firing_muzzle(missile: bool, shot: int) -> Node3D:
	var muzzles: Array[Node3D] = active_muzzles(missile)
	if muzzles.is_empty():
		return missile_muzzle if missile else muzzle
	return muzzles[posmod(shot, muzzles.size())]

## Returns all distinct physical muzzles belonging to the active primary weapon.
func active_muzzles(missile: bool) -> Array[Node3D]:
	var configured: Array[Node3D] = missile_muzzles if missile else primary_muzzles
	var resolved: Array[Node3D] = []
	for node: Node3D in configured:
		if node != null and node not in resolved:
			resolved.append(node)
	if not resolved.is_empty():
		return resolved
	if missile:
		return [missile_muzzle]
	if second_muzzle != null and second_muzzle != muzzle:
		return [muzzle, second_muzzle]
	return [muzzle]
