class_name RangeTarget
extends StaticBody3D
signal destroyed(target: RangeTarget)
var index := 0
var hit_points := 2
var dead := false
var visual: Node3D
var plate: MeshInstance3D
var last_hit := 0.0

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("range_targets")
	visual = Node3D.new()
	add_child(visual)
	_box(Vector3(5.6, 0.3, 3.6), Vector3(0, 0.15, 0), Color("756957"))
	_box(Vector3(0.32, 2.8, 0.32), Vector3(-1.6, 1.4, 0), Color("3e4540"))
	_box(Vector3(0.32, 2.8, 0.32), Vector3(1.6, 1.4, 0), Color("3e4540"))
	plate = _box(Vector3(4.4, 2.6, 0.38), Vector3(0, 2.55, 0), Color("a95130"))
	_box(Vector3(2.7, 1.45, 0.08), Vector3(0, 2.55, 0.23), Color("efdbc0"))
	_box(Vector3(2.7, 1.45, 0.08), Vector3(0, 2.55, -0.23), Color("efdbc0"))
	for z in [-0.29, 0.29]:
		_box(Vector3(1.6, 0.55, 0.06), Vector3(0, 2.3, z), Color("424b43"))
		_box(Vector3(0.8, 0.4, 0.06), Vector3(0, 2.75, z), Color("424b43"))
		_box(Vector3(1.0, 0.13, 0.06), Vector3(0.65, 2.76, z), Color("424b43"))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.4, 2.6, 0.48)
	shape.position.y = 2.55
	shape.shape = box
	add_child(shape)
	var label := Label3D.new()
	label.text = "%02d" % (index + 1)
	label.position = Vector3(0, 4.25, 0)
	label.font_size = 72
	label.pixel_size = 0.007
	label.modulate = Color("f3ddad")
	label.outline_modulate = Color("3e493d")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.92
	m.material_override = mat
	visual.add_child(m)
	return m

func damage(_amount: float = 1.0) -> void:
	if dead:
		return
	hit_points -= 1
	last_hit = Time.get_ticks_msec() * 0.001
	if hit_points <= 0:
		dead = true
		collision_layer = 0
		plate.material_override.albedo_color = Color("393e35")
		var tween := create_tween()
		tween.tween_property(visual, "rotation:x", -PI * 0.46, 0.55).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		destroyed.emit(self)
	else:
		plate.material_override.albedo_color = Color("d38642")
		var tween := create_tween()
		tween.tween_property(visual, "rotation:z", 0.05, 0.07)
		tween.tween_property(visual, "rotation:z", 0.0, 0.15)
