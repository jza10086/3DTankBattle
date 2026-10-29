class_name RangeTarget
extends StaticBody3D
## Static CC0 training tank: each connected visible mesh island gets its own
## convex collider. Wheels and tread meshes are track armor, not an empty plate.
signal destroyed(target: RangeTarget)
const DamageModel = preload("res://scripts/armor_damage.gd")
const MODEL_PATHS := [
	"res://assets/quaternius/tank_olive_target.glb",
	"res://assets/quaternius/tank_heavy_target.glb",
	"res://assets/quaternius/tank_artillery_target.glb",
]
const MODEL_NAMES := ["FIELD TANK", "HEAVY TANK", "ASSAULT GUN"]
# Immutable local-space convex resources survive range resets. Each vehicle
# still owns its collider nodes, transforms, material copies and damage state.
# This is memory-only: no generated cache files are written into the project.
static var _collision_mesh_cache: Dictionary = {}
var index := 0
var model_variant := -1
var model_name := ""
var max_hp := 100.0
var hp := 100.0
var hit_points: int:
	get:
		return ceili(hp)
var dead := false
var visual: Node3D
var last_hit := 0.0
var marker_height := 3.3
var last_hit_result: Dictionary = {}
var _turret: Node3D
var _aim_local := Vector3(0, 0.8, 0)
var _materials: Array[StandardMaterial3D] = []
var _collision_bindings: Array[Dictionary] = []
var _largest_hull_volume := 0.0
var _shape_count := 0

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("range_targets")
	hp = max_hp
	model_variant = posmod(index if model_variant < 0 else model_variant, MODEL_PATHS.size())
	model_name = MODEL_NAMES[model_variant]
	visual = Node3D.new()
	visual.name = "VehicleVisual"
	add_child(visual)
	var resource := load(MODEL_PATHS[model_variant]) as PackedScene
	if resource == null:
		push_error("Missing target tank asset: " + MODEL_PATHS[model_variant])
		return
	var model := resource.instantiate() as Node3D
	visual.add_child(model)
	_turret = model.find_child("TurretPivot", true, false) as Node3D
	_build_mesh_collisions(model)
	# Station identity and HP are drawn once by the HUD at get_marker_point().

func _build_mesh_collisions(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var name_lower := String(mesh_node.name).to_lower()
		var part := "track" if "track" in name_lower or "wheel" in name_lower else ("turret" if "turret" in name_lower or "barrel" in name_lower else "hull")
		for surface in range(mesh_node.mesh.get_surface_count()):
			var source := mesh_node.get_active_material(surface)
			if source is StandardMaterial3D:
				var material := source.duplicate() as StandardMaterial3D
				mesh_node.set_surface_override_material(surface, material)
				_materials.append(material)
		var mesh_to_body := global_transform.affine_inverse() * mesh_node.global_transform
		var cache_key := "%d|%s|%s" % [model_variant, mesh_node.name, mesh_node.mesh.resource_path]
		for cached in _cached_island_shapes(mesh_node.mesh, cache_key):
			var bounds: AABB = cached.bounds
			var body_bounds := mesh_to_body * bounds
			var center: Vector3 = mesh_to_body * bounds.get_center()
			var island_part := part
			# The original source Hull includes disconnected road wheels. Its wheel
			# islands sit below 1m and outboard; keep them track armor, not hull.
			if part == "hull" and absf(center.x) > 1.05 and center.y < 0.95 and body_bounds.size.y < 1.1:
				island_part = "track"
			var collider := CollisionShape3D.new()
			collider.name = "Armor_%s_%d" % [island_part, _shape_count]
			collider.shape = cached.shape
			collider.set_meta("armor_part", island_part)
			add_child(collider)
			collider.transform = mesh_to_body
			_collision_bindings.append({"shape": collider, "mesh": mesh_node})
			_shape_count += 1
			marker_height = maxf(marker_height, body_bounds.end.y + 0.45)
			if island_part == "hull":
				var volume := bounds.size.x * bounds.size.y * bounds.size.z
				if volume > _largest_hull_volume:
					_largest_hull_volume = volume
					_aim_local = center
	for child in node.get_children():
		_build_mesh_collisions(child)

## A resource is cooked once per asset/mesh; reused Shape3D resources are never
## edited after insertion. Wreck transforms only move each instance's nodes.
func _cached_island_shapes(mesh: Mesh, key: String) -> Array[Dictionary]:
	if _collision_mesh_cache.has(key):
		return _collision_mesh_cache[key]
	var result: Array[Dictionary] = []
	for points in _connected_islands(mesh):
		if points.size() < 4:
			continue
		var bounds := AABB(points[0], Vector3.ZERO)
		for point in points:
			bounds = bounds.expand(point)
		if bounds.size.x * bounds.size.y * bounds.size.z < 0.000001:
			continue
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		result.append({"shape": shape, "bounds": bounds})
	_collision_mesh_cache[key] = result
	return result

## Weld position-identical vertices across material/normal seams, then union
## triangle edges. Convexifying each island avoids a single huge convex hull
## spanning the antenna, wheels, muzzle and the empty space between them.
func _connected_islands(mesh: Mesh) -> Array[PackedVector3Array]:
	var faces := mesh.get_faces()
	var positions: Array[Vector3] = []
	var parents: Array[int] = []
	var by_position: Dictionary = {}
	var ids: Array[int] = []
	for vertex in faces:
		var key := Vector3i(roundi(vertex.x * 10000), roundi(vertex.y * 10000), roundi(vertex.z * 10000))
		if not by_position.has(key):
			by_position[key] = positions.size()
			positions.append(vertex)
			parents.append(parents.size())
		ids.append(by_position[key])
	for i in range(0, ids.size(), 3):
		var root_a := _find_root(parents, ids[i])
		var root_b := _find_root(parents, ids[i + 1])
		var root_c := _find_root(parents, ids[i + 2])
		parents[root_b] = root_a
		parents[root_c] = root_a
	var groups: Dictionary = {}
	for i in positions.size():
		var root_index := _find_root(parents, i)
		if not groups.has(root_index):
			groups[root_index] = PackedVector3Array()
		var group: PackedVector3Array = groups[root_index]
		group.append(positions[i])
		groups[root_index] = group
	var result: Array[PackedVector3Array] = []
	for group in groups.values():
		result.append(group)
	return result

func _find_root(parents: Array[int], value: int) -> int:
	var root_index := value
	while parents[root_index] != root_index:
		root_index = parents[root_index]
	var current := value
	while parents[current] != current:
		var next := parents[current]
		parents[current] = root_index
		current = next
	return root_index

func get_aim_point() -> Vector3:
	return global_transform * _aim_local

func get_marker_point() -> Vector3:
	return global_transform * Vector3(0, marker_height, 0)

func _part_for_shape(shape_index: int) -> StringName:
	if shape_index >= 0 and shape_index < _shape_count:
		var owner_id := shape_find_owner(shape_index)
		var owner_node := shape_owner_get_owner(owner_id)
		if owner_node is CollisionShape3D:
			return StringName(owner_node.get_meta("armor_part", "hull"))
	return &"hull"

func apply_shell_hit(world_point: Vector3, world_normal: Vector3, incoming_direction: Vector3, shape_index: int = -1) -> Dictionary:
	var result := DamageModel.evaluate(_part_for_shape(shape_index), global_basis, world_normal, incoming_direction)
	result["hp"] = hp
	result["max_hp"] = max_hp
	result["point"] = world_point
	if dead:
		result["damage"] = 0.0
		result["ignored"] = true
		return result
	if bool(result.get("invalid", false)):
		return result
	last_hit = Time.get_ticks_msec() * 0.001
	var applied := minf(hp, float(result.damage))
	result["damage"] = applied
	damage(applied)
	result["hp"] = hp
	result["destroyed"] = dead
	last_hit_result = result
	return result

## Conventional direct HP damage for debug/tests. Actual shells call the method
## above so contact region, surface normal and incidence can never be skipped.
func damage(amount: float = 0.0) -> void:
	if dead or amount <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	last_hit = Time.get_ticks_msec() * 0.001
	if hp <= 0.0:
		dead = true
		for material in _materials:
			material.albedo_color = material.albedo_color.lerp(Color("252b28"), 0.85)
			material.roughness = 1.0
		# Small broken turret cant, not a folding paper target. The wreck remains
		# physical cover and its moved turret colliders follow the visible mesh.
		if is_instance_valid(_turret):
			_turret.rotation.z += 0.085
			_turret.rotation.x -= 0.045
		for binding in _collision_bindings:
			binding.shape.transform = global_transform.affine_inverse() * binding.mesh.global_transform
		destroyed.emit(self)
