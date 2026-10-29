class_name TankVisualProcedural
extends Node3D
## Original, lightweight field tank. All geometry is authored here; no external assets.
## Vehicle forward = -Z. Root is 0.65 m above ground. Turret/barrel pivots are separate.

var turret: Node3D
var barrel: Node3D
var muzzle: Node3D
var wheel_nodes: Array[Node3D] = []
var left_track: Node3D
var right_track: Node3D
var _slide: Node3D
var _treads: Array = [[], []]
var _phase: Array[float] = [0.0, 0.0]
var _wheel_rest: Array[float] = []
var _armor: StandardMaterial3D
var _dark_armor: StandardMaterial3D
var _track_material: StandardMaterial3D
var _accent: StandardMaterial3D
var _destroyed := false
const TRACK_RADIUS := 0.48
const TRACK_HALF_STRAIGHT := 1.64
const TRACK_LENGTH := 6.56 + TAU * TRACK_RADIUS

func _ready() -> void:
	_build()

func _mat(color: Color, roughness := 0.82, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m

func _build() -> void:
	_armor = _mat(Color("777e50"))
	_dark_armor = _mat(Color("505c3c"))
	_track_material = _mat(Color("292d2b"), 0.95)
	_accent = _mat(Color("d68b48"))
	var wheel_mat := _mat(Color("4d5443"))
	var metal := _mat(Color("444a43"), 0.55, 0.25)
	var black := _mat(Color("171e1b"))
	var pale := _mat(Color("ddd6a6"))
	var glass := _mat(Color("395554"), 0.22, 0.3)
	# Sloped glacis and chamfered rear, rather than a stack of cubes.
	_prism(self, [Vector2(-1.17, -2.13), Vector2(1.17, -2.13), Vector2(1.35, -1.72), Vector2(1.35, 1.72), Vector2(1.07, 2.08), Vector2(-1.07, 2.08), Vector2(-1.35, 1.72), Vector2(-1.35, -1.72)],
		[Vector2(-0.99, -1.55), Vector2(0.99, -1.55), Vector2(1.18, -1.27), Vector2(1.18, 1.58), Vector2(0.96, 1.83), Vector2(-0.96, 1.83), Vector2(-1.18, 1.58), Vector2(-1.18, -1.27)], 0.03, 0.79, _armor)
	_box(self, Vector3(2.5, 0.16, 3.9), Vector3(0, 0.02, 0.0), _dark_armor)
	# Track skirts, mud guards, towing details and orange training recognition panel.
	for side in [-1, 1]:
		_box(self, Vector3(0.72, 0.12, 4.65), Vector3(side * 1.43, 0.43, 0), _dark_armor)
		_box(self, Vector3(0.12, 0.47, 3.16), Vector3(side * 1.79, 0.24, 0.25), _armor)
		for z in [-0.93, 0.1, 1.13]:
			_box(self, Vector3(0.025, 0.34, 0.026), Vector3(side * 1.857, 0.24, z), _dark_armor)
		_box(self, Vector3(0.13, 0.38, 0.30), Vector3(side * 1.796, 0.24, -0.5), _accent)
		_box(self, Vector3(0.38, 0.16, 0.16), Vector3(side * 0.97, 0.51, -1.93), black)
		_box(self, Vector3(0.26, 0.09, 0.022), Vector3(side * 0.97, 0.52, -2.02), pale)
		_box(self, Vector3(0.18, 0.18, 0.24), Vector3(side * 0.8, 0.13, -2.16), metal)
		_box(self, Vector3(0.19, 0.14, 0.28), Vector3(side * 0.83, 0.19, 2.16), metal)
		var track_root := Node3D.new()
		track_root.name = "LeftTrack" if side == -1 else "RightTrack"
		add_child(track_root)
		track_root.position.x = side * 1.44
		if side == -1:
			left_track = track_root
		else:
			right_track = track_root
		_track_belt(track_root)
		for i in range(6):
			var axle := Node3D.new()
			track_root.add_child(axle)
			axle.position = Vector3(0, -0.17, -1.63 + i * 0.652)
			wheel_nodes.append(axle)
			_wheel_rest.append(axle.position.y)
			_cylinder(axle, 0.38, 0.38, 0.55, Vector3.ZERO, wheel_mat, Vector3(0, 0, PI / 2), 12)
			_cylinder(axle, 0.22, 0.22, 0.575, Vector3.ZERO, _armor, Vector3(0, 0, PI / 2), 10)
			_cylinder(axle, 0.075, 0.075, 0.60, Vector3.ZERO, metal, Vector3(0, 0, PI / 2), 8)
			for j in range(3):
				var a := j * TAU / 3.0
				_box(axle, Vector3(0.59, 0.047, 0.047), Vector3(0, sin(a) * 0.14, cos(a) * 0.14), _dark_armor)
		for i in range(40):
			var tread := _box(track_root, Vector3(0.65, 0.065, 0.19), Vector3.ZERO, metal)
			_treads[0 if side == -1 else 1].append(tread)
	# Engine deck with vents and rear exhaust.
	_box(self, Vector3(1.6, 0.045, 0.72), Vector3(0, 0.806, 1.23), _dark_armor)
	for i in range(9):
		_box(self, Vector3(1.41, 0.025, 0.034), Vector3(0, 0.84, 0.94 + i * 0.075), black)
	for x in [-0.9, 0.9]:
		_cylinder(self, 0.13, 0.13, 0.31, Vector3(x, 0.42, 2.04), metal, Vector3(PI / 2, 0, 0), 8)
		_cylinder(self, 0.095, 0.095, 0.015, Vector3(x, 0.42, 2.205), black, Vector3(PI / 2, 0, 0), 8)
	# Separate freely traversing turret.
	turret = Node3D.new()
	turret.name = "Turret"
	add_child(turret)
	turret.position = Vector3(0, 0.93, -0.12)
	_cylinder(turret, 0.91, 0.91, 0.16, Vector3(0, -0.1, 0), metal, Vector3.ZERO, 12)
	_prism(turret, [Vector2(-0.64, -1.19), Vector2(0.64, -1.19), Vector2(1.04, -0.55), Vector2(0.94, 0.94), Vector2(0.61, 1.22), Vector2(-0.61, 1.22), Vector2(-0.94, 0.94), Vector2(-1.04, -0.55)],
		[Vector2(-0.49, -0.82), Vector2(0.49, -0.82), Vector2(0.79, -0.4), Vector2(0.69, 0.76), Vector2(0.49, 0.94), Vector2(-0.49, 0.94), Vector2(-0.69, 0.76), Vector2(-0.79, -0.4)], 0.0, 0.65, _armor)
	for side in [-1, 1]:
		_box(turret, Vector3(0.08, 0.3, 1.0), Vector3(side * 0.94, 0.27, 0.24), _dark_armor)
		_box(turret, Vector3(0.086, 0.3, 0.18), Vector3(side * 0.986, 0.27, 0.01), _accent)
		# Smoke discharger banks.
		for j in range(3):
			_cylinder(turret, 0.07, 0.07, 0.28, Vector3(side * 0.89, 0.21, -0.55 + j * 0.16), metal, Vector3(PI / 3, 0, side * -0.35), 6)
	_cylinder(turret, 0.34, 0.34, 0.10, Vector3(0.35, 0.71, 0.2), _dark_armor, Vector3.ZERO, 12)
	_cylinder(turret, 0.27, 0.27, 0.045, Vector3(0.35, 0.78, 0.2), _armor, Vector3.ZERO, 12)
	_box(turret, Vector3(0.28, 0.16, 0.20), Vector3(-0.35, 0.73, -0.36), _dark_armor)
	_box(turret, Vector3(0.21, 0.07, 0.015), Vector3(-0.35, 0.74, -0.465), glass)
	_box(turret, Vector3(0.17, 0.045, 0.09), Vector3(0.35, 0.82, 0.2), metal)
	_cylinder(turret, 0.018, 0.025, 1.63, Vector3(-0.56, 1.43, 0.70), metal, Vector3(0, 0, -0.07), 5)
	_cylinder(turret, 0.065, 0.09, 0.17, Vector3(-0.5, 0.68, 0.70), black, Vector3.ZERO, 8)
	# Legible turret number, subdued against the armor.
	var number := Label3D.new()
	turret.add_child(number)
	number.text = "07"
	number.font_size = 42
	number.pixel_size = 0.007
	number.modulate = Color("e1d9b2")
	number.outline_size = 0
	number.position = Vector3(0, 0.34, 1.17)
	number.rotation.y = 0
	# Elevation pivot and recoil sled. Positive pitch elevates a -Z barrel.
	barrel = Node3D.new()
	barrel.name = "BarrelElevation"
	turret.add_child(barrel)
	barrel.position = Vector3(0, 0.31, -0.92)
	_box(barrel, Vector3(0.74, 0.48, 0.58), Vector3(0, 0, -0.18), _dark_armor)
	_slide = Node3D.new()
	_slide.name = "RecoilSlide"
	barrel.add_child(_slide)
	_cylinder(_slide, 0.16, 0.18, 1.0, Vector3(0, 0, -0.8), _armor, Vector3(PI / 2, 0, 0), 10)
	_cylinder(_slide, 0.095, 0.115, 2.08, Vector3(0, 0, -2.05), _armor, Vector3(PI / 2, 0, 0), 10)
	_cylinder(_slide, 0.145, 0.145, 0.36, Vector3(0, 0, -1.66), _dark_armor, Vector3(PI / 2, 0, 0), 10)
	_box(_slide, Vector3(0.28, 0.24, 0.4), Vector3(0, 0, -3.15), metal)
	_box(_slide, Vector3(0.17, 0.14, 0.018), Vector3(0, 0, -3.36), black)
	for x in [-0.148, 0.148]:
		_box(_slide, Vector3(0.015, 0.07, 0.19), Vector3(x, 0, -3.15), black)
	muzzle = Node3D.new()
	muzzle.name = "Muzzle"
	_slide.add_child(muzzle)
	muzzle.position = Vector3(0, 0, -3.39)
	animate_tracks(0.0, 0.0, 0.0)

func _box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	parent.add_child(node)
	node.position = pos
	return node

func _cylinder(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3, material: Material, rot: Vector3, segments := 10) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	parent.add_child(node)
	node.position = pos
	node.rotation = rot
	return node

func _prism(parent: Node3D, lower: Array, upper: Array, bottom_y: float, top_y: float, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var n := lower.size()
	for i in range(n):
		var j := (i + 1) % n
		var a := Vector3(lower[i].x, bottom_y, lower[i].y)
		var b := Vector3(lower[j].x, bottom_y, lower[j].y)
		var c := Vector3(upper[j].x, top_y, upper[j].y)
		var d := Vector3(upper[i].x, top_y, upper[i].y)
		_tri(st, a, b, c)
		_tri(st, a, c, d)
		_tri(st, Vector3(0, top_y, 0), d, c)
		_tri(st, Vector3(0, bottom_y, 0), b, a)
	st.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = material
	parent.add_child(node)

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

func _track_belt(parent: Node3D) -> void:
	var outer := [Vector2(-1.65, 0.34), Vector2(1.65, 0.34), Vector2(2.09, 0.08), Vector2(2.09, -0.36), Vector2(1.65, -0.62), Vector2(-1.65, -0.62), Vector2(-2.09, -0.36), Vector2(-2.09, 0.08)]
	var inner := [Vector2(-1.65, 0.22), Vector2(1.65, 0.22), Vector2(1.97, 0.02), Vector2(1.97, -0.30), Vector2(1.65, -0.50), Vector2(-1.65, -0.50), Vector2(-1.97, -0.30), Vector2(-1.97, 0.02)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for i in range(8):
		var j := (i + 1) % 8
		for side in [-1, 1]:
			var a := Vector3(side * 0.29, outer[i].y, outer[i].x)
			var b := Vector3(side * 0.29, outer[j].y, outer[j].x)
			var c := Vector3(side * 0.29, inner[j].y, inner[j].x)
			var d := Vector3(side * 0.29, inner[i].y, inner[i].x)
			if side == 1:
				_tri(st, a, c, b)
				_tri(st, a, d, c)
			else:
				_tri(st, a, b, c)
				_tri(st, a, c, d)
		var a := Vector3(-0.29, outer[i].y, outer[i].x)
		var b := Vector3(-0.29, outer[j].y, outer[j].x)
		var c := Vector3(0.29, outer[j].y, outer[j].x)
		var d := Vector3(0.29, outer[i].y, outer[i].x)
		_tri(st, a, b, c)
		_tri(st, a, c, d)
	st.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = _track_material
	parent.add_child(node)

func _track_point(distance: float) -> Vector3:
	var d := fposmod(distance, TRACK_LENGTH)
	if d < 3.28:
		return Vector3(0, 0.34, -1.64 + d)
	d -= 3.28
	if d < PI * TRACK_RADIUS:
		var angle := d / TRACK_RADIUS
		return Vector3(0, -0.14 + cos(angle) * TRACK_RADIUS, 1.64 + sin(angle) * TRACK_RADIUS)
	d -= PI * TRACK_RADIUS
	if d < 3.28:
		return Vector3(0, -0.62, 1.64 - d)
	d -= 3.28
	var angle := d / TRACK_RADIUS
	return Vector3(0, -0.14 - cos(angle) * TRACK_RADIUS, -1.64 - sin(angle) * TRACK_RADIUS)

func animate_tracks(left_speed: float, right_speed: float, dt: float, ground_offsets: Array = []) -> void:
	if _destroyed:
		return
	for side in range(2):
		var speed := left_speed if side == 0 else right_speed
		_phase[side] = fposmod(_phase[side] + speed * dt, TRACK_LENGTH)
		for i in range(_treads[side].size()):
			var distance: float = _phase[side] + i * TRACK_LENGTH / 40.0
			var point := _track_point(distance)
			var tangent := _track_point(distance + 0.008) - point
			var tread: Node3D = _treads[side][i]
			tread.position = point
			tread.rotation.x = atan2(-tangent.y, tangent.z)
		for i in range(6):
			var index := side * 6 + i
			if index < wheel_nodes.size():
				wheel_nodes[index].rotate_x(speed * dt / 0.38)
				var offset := 0.0
				if ground_offsets.size() == 12:
					offset = clampf(float(ground_offsets[index]), -0.16, 0.16)
				wheel_nodes[index].position.y = lerpf(wheel_nodes[index].position.y, _wheel_rest[index] + offset, minf(dt * 12.0, 1.0))

func set_recoil(amount: float) -> void:
	if is_instance_valid(_slide):
		_slide.position.z = clampf(amount, 0.0, 1.0) * 0.35

func set_destroyed(value: bool) -> void:
	_destroyed = value
	if not is_instance_valid(_armor):
		return
	_armor.albedo_color = Color("343b31") if value else Color("777e50")
	_dark_armor.albedo_color = Color("262c26") if value else Color("505c3c")
	_accent.albedo_color = Color("5f4530") if value else Color("d68b48")
