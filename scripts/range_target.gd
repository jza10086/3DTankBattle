class_name RangeTarget
extends StaticBody3D
## Static training target. Authored island colliders identify armor and damageable components.
signal destroyed(target: RangeTarget)
const DamageModel = preload("res://games/minigame/godot_party_default_tank_range/scripts/armor_damage.gd")
const ComponentStatusScript = preload("res://games/minigame/godot_party_default_tank_range/scripts/component_status.gd")
const Collider = preload("res://games/minigame/godot_party_default_tank_range/scripts/target_collider.gd")
@export var colliders: Array[Collider]
@export var index: int = 0
@export var model_name: String = ""
var max_hp: float = 100.0
var hp: float = 100.0
var components: ComponentStatusScript = ComponentStatusScript.new()
var reload_remaining: float:
	get:
		return components.reload_remaining
	set(value):
		components.reload_remaining = maxf(0.0, value)
# Model-relative compartment in target-local coordinates, not world-axis guesses.
@export var hull_bounds: AABB = AABB()
@export var engine_bounds: AABB = AABB()
var hit_points: int:
	get:
		return ceili(hp)
var dead: bool = false
@export var visual: Node3D
var last_hit: float = 0.0
@export var marker_height: float = 3.3
var last_hit_result: Dictionary = {}
@export var _turret: Node3D
@export var _aim_local: Vector3 = Vector3(0, 0.8, 0)
var _materials: Array[StandardMaterial3D] = []
var _colors: Array[Color] = []
var _roughness: Array[float] = []
var _turret_rest: Transform3D
func _ready() -> void:
	assert(visual != null and _turret != null and not colliders.is_empty(), "Target requires its authored visual, turret and armor colliders.")
	add_to_group("range_targets")
	hp = max_hp
	_turret_rest = _turret.transform
	_duplicate_materials(visual)

func _duplicate_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node
		for surface: int in mesh_node.mesh.get_surface_count():
			var source: Material = mesh_node.get_active_material(surface)
			if source is StandardMaterial3D:
				var material: StandardMaterial3D = source.duplicate()
				mesh_node.set_surface_override_material(surface, material)
				_materials.append(material)
				_colors.append(material.albedo_color)
				_roughness.append(material.roughness)
	for child: Node in node.get_children():
		_duplicate_materials(child)

func _physics_process(delta: float) -> void:
	if not dead:
		components.tick(delta)

# These expose the capability state for the HUD/tests and future controllers.
# Static training targets intentionally do not move or automatically fire.
func can_fire() -> bool:
	return not dead and components.can_fire()

func begin_fire() -> bool:
	return not dead and components.begin_fire()

func get_track_multipliers() -> Vector2:
	return Vector2.ZERO if dead else components.get_track_multipliers()

func get_aim_point() -> Vector3:
	return global_transform * _aim_local

func get_marker_point() -> Vector3:
	return global_transform * Vector3(0, marker_height, 0)

func _collider_for_shape(shape_index: int) -> Collider:
	if shape_index >= 0 and shape_index < colliders.size():
		return shape_owner_get_owner(shape_find_owner(shape_index))
	return null

func _part_for_shape(shape_index: int) -> StringName:
	var collider: Collider = _collider_for_shape(shape_index)
	return collider.armor_part if collider != null else &"hull"

## Called with the actual swept-ray contact and shape index. Missing/invalid
## shape metadata never fabricates a component hit from a world position alone.
func component_from_hit(world_point: Vector3, world_normal: Vector3, shape_index: int = -1) -> StringName:
	var collider: Collider = _collider_for_shape(shape_index)
	if collider == null:
		return &""
	var part: StringName = collider.armor_part
	if part == &"barrel" or part == &"track":
		return collider.component
	if part != &"hull" or world_normal.length_squared() < 0.000001:
		return &""
	var local_normal: Vector3 = global_basis.orthonormalized().inverse() * world_normal.normalized()
	if DamageModel.classify_facing(local_normal) != "rear":
		return &""
	# Include the outer armor boundary despite small ray/float precision errors.
	if engine_bounds.grow(0.025).has_point(to_local(world_point)):
		return &"engine"
	return &""

func apply_shell_hit(world_point: Vector3, world_normal: Vector3, incoming_direction: Vector3, shape_index: int = -1, ammunition: int = DamageModel.Ammo.AP) -> Dictionary:
	var result: Dictionary = DamageModel.evaluate(_part_for_shape(shape_index), global_basis, world_normal, incoming_direction, ammunition)
	result["hp"] = hp
	result["max_hp"] = max_hp
	result["point"] = world_point
	result["component"] = ""
	result["disabled"] = false
	result["component_duration"] = 0.0
	if dead:
		result["damage"] = 0.0
		result["ignored"] = true
		return result
	if bool(result.get("invalid", false)):
		return result
	last_hit = Time.get_ticks_msec() * 0.001
	var applied: float = minf(hp, float(result.damage))
	result["damage"] = applied
	damage(applied)
	result["hp"] = hp
	result["destroyed"] = dead
	# Ricochets/invalid/dead contacts neither apply nor refresh component timers.
	if applied > 0.0 and not dead and not bool(result.ricochet):
		var component: StringName = component_from_hit(world_point, world_normal, shape_index)
		if not component.is_empty():
			result.disabled = not components.is_disabled(component)
			components.apply_component(component)
			result["component"] = String(component)
			match component:
				&"engine": result["component_duration"] = ComponentStatusScript.ENGINE_DURATION
				&"left_track", &"right_track": result["component_duration"] = ComponentStatusScript.TRACK_DURATION
				&"barrel": result["component_duration"] = ComponentStatusScript.BARREL_DURATION
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
		components.clear()
		for material: StandardMaterial3D in _materials:
			material.albedo_color = material.albedo_color.lerp(Color("252b28"), 0.85)
			material.roughness = 1.0
		# Small broken turret cant, not a folding paper target. The wreck remains
		# physical cover and its moved turret colliders follow the visible mesh.
		if is_instance_valid(_turret):
			_turret.rotation.z += 0.085
			_turret.rotation.x -= 0.045
		for collider: Collider in colliders:
			collider.transform = global_transform.affine_inverse() * collider.source_mesh.global_transform
		destroyed.emit(self)

func reset_target() -> void:
	dead = false
	hp = max_hp
	last_hit = 0.0
	last_hit_result.clear()
	components.clear()
	if _turret != null:
		_turret.transform = _turret_rest
	for i: int in _materials.size():
		_materials[i].albedo_color = _colors[i]
		_materials[i].roughness = _roughness[i]
	for collider: Collider in colliders:
		collider.transform = global_transform.affine_inverse() * collider.source_mesh.global_transform

func apply_blast_hit(origin: Vector3, amount: float) -> Dictionary:
	var result: Dictionary = {"damage": 0.0, "destroyed": false, "component": "", "disabled": false}
	if dead:
		return result
	result.damage = minf(hp, amount)
	damage(result.damage)
	result.destroyed = dead
	if not dead and amount >= 4.0:
		var component: StringName = &"left_track" if to_local(origin).x < 0.0 else &"right_track"
		result.disabled = not components.is_disabled(component)
		components.apply_component(component)
		result.component = component
	return result
