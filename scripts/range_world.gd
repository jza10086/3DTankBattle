class_name RangeWorld
extends Node3D
## Original, deterministic low-poly proving ground. All obstacles use layer 1.
## Ramp test: drive north at x=-43 from z=12; 1:6 ascent to y=4 at z=-16.

const TARGETS: Array[Vector3] = [
	Vector3(0, 0.06, -35), Vector3(24, 0.06, -61),
	Vector3(-24, 0.06, -82), Vector3(-67, 0.06, -18),
	Vector3(60, 0.06, 25), Vector3(12, 0.06, 65)]

var sand: StandardMaterial3D
var stone: StandardMaterial3D
var concrete: StandardMaterial3D
var dark: StandardMaterial3D
var white: StandardMaterial3D
var amber: StandardMaterial3D
var olive: StandardMaterial3D
var rng := RandomNumberGenerator.new()

func get_target_positions() -> Array[Vector3]:
	return TARGETS.duplicate()

func _ready() -> void:
	rng.seed = 429018
	sand = _mat(Color("bda074"))
	stone = _mat(Color("ad7950"))
	concrete = _mat(Color("b4afa0"))
	dark = _mat(Color("303d38"))
	white = _mat(Color("e7ddbf"))
	amber = _mat(Color("d19c3d"))
	olive = _mat(Color("65715a"))
	_build_floor()
	_build_course()
	_build_ramps()
	_build_range()
	_build_base()
	_build_landscape()

func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	return material

func _box(at: Vector3, size: Vector3, material: Material, solid: bool = false, angle: float = 0.0) -> Node3D:
	var root: Node3D
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		root = body
	else:
		root = Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	root.add_child(mesh)
	root.position = at
	root.rotation.y = angle
	add_child(root)
	return root

func _cylinder(at: Vector3, bottom: float, top: float, height: float, material: Material, sides: int = 8, solid: bool = false) -> Node3D:
	var root: Node3D
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CylinderShape3D.new()
		shape.radius = maxf(bottom, top)
		shape.height = height
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		root = body
	else:
		root = Node3D.new()
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.bottom_radius = bottom
	cylinder.top_radius = top
	cylinder.height = height
	cylinder.radial_segments = sides
	cylinder.rings = 1
	mesh.mesh = cylinder
	mesh.material_override = material
	root.add_child(mesh)
	root.position = at
	add_child(root)
	return root

func _label(text_value: String, at: Vector3, size: int = 64, tint: Color = Color("e7ddbf"), angle: float = 0.0) -> Label3D:
	var label := Label3D.new()
	label.text = text_value
	label.font_size = size
	label.pixel_size = 0.018
	label.modulate = tint
	label.outline_size = 0
	label.no_depth_test = false
	label.position = at
	label.rotation.y = angle
	add_child(label)
	return label

func _build_floor() -> void:
	_box(Vector3(0, -0.6, 0), Vector3(260, 1.2, 260), sand, true)
	# Large flat color fields break the ground up without noisy textures.
	for i in range(40):
		var patch_color := Color("c4a979") if i % 2 == 0 else Color("b4986a")
		var patch := _cylinder(Vector3(rng.randf_range(-100, 100), 0.006 + i * 0.00015, rng.randf_range(-100, 100)), rng.randf_range(5, 16), 0.0, 0.012, _mat(patch_color), 7)
		patch.scale = Vector3(rng.randf_range(0.9, 1.7), 1, rng.randf_range(0.7, 1.3))
		patch.rotation.y = rng.randf_range(0, TAU)
	# Far perimeter keeps an overturned or distracted driver inside the arena.
	for side in [-1, 1]:
		_box(Vector3(side * 129, 2, 0), Vector3(2, 5, 260), stone, true)
		_box(Vector3(0, 2, side * 129), Vector3(260, 5, 2), stone, true)

func _build_course() -> void:
	# Elliptical 13 m wide dirt test circuit, with sparse pale kerb markers.
	var track := _mat(Color("958c6e"))
	var shoulder := _mat(Color("a89774"))
	_ring(46, 66, 15, 0.02, shoulder)
	_ring(46, 66, 11.6, 0.025, track)
	for i in range(56):
		var a := TAU * float(i) / 56.0
		var at := Vector3(sin(a) * 46, 0.038, cos(a) * 66)
		var tangent := Vector3(cos(a) * 46, 0, -sin(a) * 66).normalized()
		var angle := atan2(tangent.x, tangent.z)
		_box(at, Vector3(0.18, 0.018, 1.2), white, false, angle)
	# Straight practice strip ends well before target 01.
	_box(Vector3(0, 0.026, 4), Vector3(13, 0.04, 47), track)
	for z in range(-18, 29, 6):
		for x in [-6.1, 6.1]:
			_box(Vector3(x, 0.055, z), Vector3(0.15, 0.018, 2.5), white)
	for x in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		_box(Vector3(x, 0.052, 24), Vector3(1, 0.018, 1.2), white)
	_label("START", Vector3(-8.3, 1.3, 23), 44, Color("303d38"))
	for z in [-10, 12]:
		_flag(Vector3(8.4, 0, z), Color("cb9c4e"), 3.6)

func _ring(rx: float, rz: float, width: float, y: float, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(96):
		var a := TAU * float(i) / 96.0
		var b := TAU * float(i + 1) / 96.0
		var points := [Vector3(sin(a) * (rx - width * 0.5), y, cos(a) * (rz - width * 0.5)),
			Vector3(sin(a) * (rx + width * 0.5), y, cos(a) * (rz + width * 0.5)),
			Vector3(sin(b) * (rx + width * 0.5), y, cos(b) * (rz + width * 0.5)),
			Vector3(sin(b) * (rx - width * 0.5), y, cos(b) * (rz - width * 0.5))]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.UP)
			st.add_vertex(points[idx])
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = material
	add_child(mesh)

func _build_ramps() -> void:
	_box(Vector3(-43, 2, -28), Vector3(16, 4, 24), concrete, true)
	_ramp(Vector3(-43, 0, -4), 16, 24, 4, false)
	_ramp(Vector3(-43, 0, -52), 16, 24, 4, true)
	# Narrow edge stripes are painted, not barriers: safe to exit or fall off.
	for x in [-50.8, -35.2]:
		_box(Vector3(x, 4.025, -28), Vector3(0.25, 0.025, 24), amber)
	_flag(Vector3(-53, 0, 7), Color("d49f46"), 4.5)
	_label("CLIMB\n16% GRADE", Vector3(-53, 2, 5), 35, Color("e7ddbf"))
	_box(Vector3(-53, 2, 4.9), Vector3(4.2, 2.5, 0.15), dark)
	# Compact undulating log/beam strip beside the main course.
	for i in range(6):
		_box(Vector3(27, 0.09 + float(i % 2) * 0.03, 4 - i * 2.5), Vector3(10, 0.24, 0.65), concrete, true)
	_label("SUSPENSION", Vector3(35, 1.1, 6), 28, Color("303d38"))

func _ramp(at: Vector3, width: float, length: float, height: float, reversed: bool) -> void:
	var hw := width * 0.5
	var hl := length * 0.5
	var points := PackedVector3Array([
		Vector3(-hw, 0, -hl), Vector3(hw, 0, -hl), Vector3(hw, 0, hl), Vector3(-hw, 0, hl),
		Vector3(-hw, height, -hl), Vector3(hw, height, -hl)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for idx in [4, 5, 2, 4, 2, 3, 0, 1, 5, 0, 5, 4, 0, 4, 3, 1, 2, 5, 0, 3, 2, 0, 2, 1]:
		st.add_vertex(points[idx])
	st.generate_normals()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at
	if reversed:
		body.rotation.y = PI
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = concrete
	body.add_child(mesh)
	var collider := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	collider.shape = shape
	body.add_child(collider)
	add_child(body)

func _build_range() -> void:
	for i in range(TARGETS.size()):
		var p := TARGETS[i]
		_cylinder(Vector3(p.x, 0.031, p.z), 6, 6, 0.06, _mat(Color("a58a62")), 24)
		var sign := p + Vector3(-4.6, 1.15, 1.8)
		_box(sign + Vector3(0, -0.4, 0), Vector3(0.12, 1.6, 0.12), dark)
		_box(sign + Vector3(0, 0.45, 0), Vector3(1.3, 0.8, 0.12), dark)
		_label("0%d" % (i + 1), sign + Vector3(0, 0.45, 0.075), 40)
		_flag(p + Vector3(4.7, -0.06, 1.7), Color("cf8b4c"), 3.8)
	# Staggered low cover: leaves central start lane unobstructed.
	for p in [Vector3(-14, 0.7, -23), Vector3(14, 0.7, -43), Vector3(39, 0.7, 33), Vector3(-61, 0.7, 39)]:
		var angle := -0.2 if p.x > 0 else 0.24
		_box(p, Vector3(6, 1.4, 1.3), concrete, true, angle)
		for x in [-2.0, 0.0, 2.0]:
			_box(p + Vector3(x, 0.74, 0), Vector3(0.65, 0.08, 1.34), amber, false, angle)
	# Firing line end markers.
	_box(Vector3(0, 0.04, -20), Vector3(13, 0.02, 0.25), amber)

func _flag(at: Vector3, color: Color, height: float) -> void:
	_cylinder(at + Vector3(0, height * 0.5, 0), 0.045, 0.045, height, dark, 6)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := at + Vector3(0, height - 0.08, 0)
	var b := a + Vector3(1.5, -0.3, 0.15)
	var c := a + Vector3(0, -0.85, 0)
	for p in [a, b, c, c, b, a]:
		st.add_vertex(p)
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = _mat(color)
	add_child(mesh)

func _build_base() -> void:
	# Sage maintenance sheds and a shaded veranda give the site a human scale.
	for i in range(2):
		var x := -82.0 + i * 18
		_box(Vector3(x, 3.8, 57), Vector3(15, 7.6, 15), olive, true)
		_box(Vector3(x, 7.65, 57), Vector3(16, 0.45, 16), dark)
		_box(Vector3(x, 2.4, 49.43), Vector3(9.8, 4.8, 0.08), dark)
		_box(Vector3(x, 5.7, 49.3), Vector3(4, 0.65, 0.15), amber)
		_label("SERVICE 0%d" % (i + 1), Vector3(x, 6.6, 49.25), 34, Color("e7ddbf"), PI)
		for z in [49.8, 53, 56.2, 59.4, 62.6]:
			_box(Vector3(x, 7.92, z), Vector3(15.8, 0.07, 0.18), concrete)
	# Watchtower sits off the drivable circuit, looking over the range.
	var tower := Vector3(76, 0, -54)
	for x in [-2.2, 2.2]:
		for z in [-2.2, 2.2]:
			_box(tower + Vector3(x, 4.4, z), Vector3(0.5, 8.8, 0.5), dark, true)
	_box(tower + Vector3(0, 8.6, 0), Vector3(5.5, 0.45, 5.5), concrete)
	_box(tower + Vector3(0, 9.7, 0.5), Vector3(5, 2.2, 4), olive)
	_box(tower + Vector3(0, 11, 0.2), Vector3(6.1, 0.4, 5.8), dark)
	_box(tower + Vector3(0, 9.9, 2.54), Vector3(4.5, 0.75, 0.04), _mat(Color("698889")))
	_label("RANGE CONTROL", tower + Vector3(0, 8.7, 3), 32)
	# Main destination sign, offset from the first target's sightline.
	_box(Vector3(-17, 3.5, -51), Vector3(13, 3.6, 0.4), dark, true)
	for x in [-21, -13]:
		_box(Vector3(x, 1.4, -51), Vector3(0.35, 2.8, 0.35), dark, true)
	_label("IRON RANGE", Vector3(-17, 3.95, -50.75), 70)
	_label("DRIVE   /   AIM   /   FIRE", Vector3(-17, 2.65, -50.74), 27, Color("d19c3d"))
	for i in range(8):
		var p := Vector3(-87 + i % 4 * 3.6, 0.7, 42 + int(i / 4) * 3)
		_box(p, Vector3(2.8, 1.4, 2), olive if i % 2 == 0 else concrete, true, rng.randf_range(-0.12, 0.12))

func _build_landscape() -> void:
	# Hand-shaped silhouette of layered mesas: flat crowns, eroded slopes.
	for i in range(30):
		var angle := TAU * float(i) / 30.0
		var r := rng.randf_range(112, 136)
		var p := Vector3(sin(angle) * r, 0, cos(angle) * r)
		var height := rng.randf_range(13, 29)
		var radius := rng.randf_range(12, 21)
		_mesa(p, radius, height, rng.randf_range(0, TAU))
	# Sparse rocks and scrub beyond the driving envelope.
	for i in range(130):
		var p := Vector3(rng.randf_range(-108, 108), 0, rng.randf_range(-108, 108))
		var ellipse := pow(p.x / 64.0, 2) + pow(p.z / 88.0, 2)
		if ellipse < 1.0 or (p.x < -56 and p.z > 33 and p.z < 70):
			continue
		if i % 4 == 0:
			var radius := rng.randf_range(0.7, 2.0)
			var rock := _cylinder(p + Vector3(0, radius * 0.38, 0), radius, radius * 0.55, radius * 0.76, stone, 5, true)
			rock.rotation.y = rng.randf_range(0, TAU)
		else:
			_shrub(p, rng.randf_range(0.7, 1.6))
	# A few tall cacti frame the range without cluttering the road.
	for p in [Vector3(87, 0, 30), Vector3(-88, 0, -45), Vector3(65, 0, 77), Vector3(42, 0, -94), Vector3(-26, 0, 97)]:
		_cactus(p)

func _mesa(at: Vector3, radius: float, height: float, yaw: float) -> void:
	# One continuous six-facet shell. Adjacent bands share exact ring coordinates;
	# there are no overlapping frustums or hidden coplanar caps to z-fight.
	var ring_heights := [0.0, 0.68, 0.94, 1.0]
	var ring_radii := [1.0, 0.64, 0.52, 0.48]
	var colors := [Color("a77950"), Color("bd8e5d"), Color("d0a777")]
	var rings: Array[PackedVector3Array] = []
	for ring_index in range(4):
		var ring := PackedVector3Array()
		for corner in range(6):
			var angle := TAU * float(corner) / 6.0
			ring.append(Vector3(sin(angle) * radius * ring_radii[ring_index], height * ring_heights[ring_index], cos(angle) * radius * ring_radii[ring_index]))
		rings.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for band in range(3):
		st.set_color(colors[band])
		for corner in range(6):
			var next_corner := (corner + 1) % 6
			var lower_a := rings[band][corner]
			var lower_b := rings[band][next_corner]
			var upper_a := rings[band + 1][corner]
			var upper_b := rings[band + 1][next_corner]
			for point in [lower_a, upper_a, lower_b, lower_b, upper_a, upper_b]:
				st.add_vertex(point)
	# The crown has the only cap; the base is buried in the ground.
	st.set_color(colors[2])
	for corner in range(6):
		for point in [Vector3(0, height, 0), rings[3][(corner + 1) % 6], rings[3][corner]]:
			st.add_vertex(point)
	st.generate_normals()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at
	body.rotation.y = yaw
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	var material := _mat(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	mesh.material_override = material
	body.add_child(mesh)
	# Keep the original conservative lower-rock collider unchanged.
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height * 0.68
	collider.shape = shape
	collider.position.y = height * 0.34
	body.add_child(collider)
	add_child(body)

func _shrub(at: Vector3, scale_value: float) -> void:
	var greens := [Color("7b805c"), Color("8c8e69"), Color("707759")]
	for i in range(3):
		var p := at + Vector3((i - 1) * 0.45, 0.3 + float(i % 2) * 0.15, 0.1 * i) * scale_value
		var bush := _cylinder(p, 0.58 * scale_value, 0.24 * scale_value, (0.65 + float(i % 2) * 0.25) * scale_value, _mat(greens[i]), 5)
		bush.rotation.z = (i - 1) * 0.3

func _cactus(at: Vector3) -> void:
	_cylinder(at + Vector3(0, 1.8, 0), 0.28, 0.2, 3.6, olive, 7)
	for side in [-1, 1]:
		var arm := _cylinder(at + Vector3(side * 0.48, 1.7 + side * 0.35, 0), 0.18, 0.18, 0.95, olive, 6)
		arm.rotation.z = PI * 0.5
		_cylinder(at + Vector3(side * 0.9, 2.15 + side * 0.35, 0), 0.18, 0.13, 1.1, olive, 6)
