extends Camera3D
## Jitter-free War Thunder-style camera (physics-interpolated chassis follow) and smooth barrel-direction reticles.
const TankScript = preload("res://games/minigame/GP_tank_war/scripts/tank_controller.gd")
const TargetScript = preload("res://games/minigame/GP_tank_war/scripts/range_target.gd")
const DamageModel = preload("res://games/minigame/GP_tank_war/scripts/armor_damage.gd")
const THIRD_PERSON_FOV_MAX: float = 64.0
const THIRD_PERSON_FOV_MIN: float = 38.0
const THIRD_PERSON_DIST_MAX: float = 14.5
const THIRD_PERSON_DIST_MIN: float = 6.2
const SIGHT_FOV_MAX: float = 28.0
const SIGHT_FOV_MIN: float = 7.0
const AIM_MAX_DISTANCE: float = 500.0
var tank: TankScript
var active: bool = false
var controllable: bool = false
var _elapsed: float = 0.0
var _render_updated: bool = false
var camera_yaw: float = 0.0
var camera_pitch: float = -0.023
var camera_position: Vector3 = Vector3.ZERO
var _focus_pivot: Vector3 = Vector3.ZERO
var _current_distance: float = 12.4
var _collision_distance: float = 12.4
var _smooth_aim_distance: float = 60.0
var third_person_zoom: float = 0.25
var sight_zoom: float = 0.0
var first_person: bool = false
var shot_shake: float = 0.0
var actual_impact: Vector3 = Vector3.ZERO
var actual_hit_target: bool = false
var barrel_impacts: Array[Dictionary] = []
var bore_aim_point: Vector3 = Vector3.ZERO
var coax_active: bool = false
var coax_impact: Vector3 = Vector3.ZERO
var coax_hit_target: bool = false
var coax_armor_grade: int = -1
var coax_obstructed: bool = false
var coax_valid: bool = false
var current_range_meters: float = 60.0

func configure(vehicle: TankScript, can_control: bool) -> void:
	tank = vehicle
	controllable = can_control
	camera_yaw = tank.rotation.y
	camera_pitch = -0.023
	_current_distance = _target_distance()
	_collision_distance = _current_distance
	_focus_pivot = _desired_focus()
	camera_position = _focus_pivot - _look_direction() * _current_distance + Vector3(0.0, _vertical_lift(), 0.0)
	self.fov = _target_fov()
	update_pose(1.0)
	update_aim_point()
	_smooth_aim_distance = clampf(current_range_meters, 12.0, AIM_MAX_DISTANCE)
	predict_impacts()

func advance(delta: float, elapsed: float) -> void:
	_elapsed = elapsed
	if active and not _render_updated:
		shot_shake = maxf(0.0, shot_shake - delta * 3.2)
		update_pose(delta)
		update_aim_point()
		_smooth_aim_distance = lerpf(_smooth_aim_distance, clampf(current_range_meters, 12.0, AIM_MAX_DISTANCE), 1.0 - exp(-delta * 12.0))
		predict_impacts()
	_render_updated = false

## Runs every render frame from main._process right after vehicle render interpolation for zero-jitter high-FPS follow.
func render_update(delta: float) -> void:
	if not active or tank == null:
		return
	var dt: float = maxf(delta, 0.0001)
	_elapsed += dt
	shot_shake = maxf(0.0, shot_shake - dt * 3.2)
	update_pose(dt)
	update_aim_point()
	_smooth_aim_distance = lerpf(_smooth_aim_distance, clampf(current_range_meters, 12.0, AIM_MAX_DISTANCE), 1.0 - exp(-dt * 12.0))
	predict_impacts()
	_render_updated = true

func move_look(relative: Vector2) -> void:
	var sensitivity: float = 0.0024 * tan(deg_to_rad(fov * 0.5)) / tan(deg_to_rad(THIRD_PERSON_FOV_MAX * 0.5))
	camera_yaw -= relative.x * sensitivity
	camera_pitch = clampf(camera_pitch - relative.y * sensitivity, -0.45 if first_person else -0.62, 0.52 if first_person else 0.42)

func center_on_vehicle() -> void:
	camera_yaw = tank.rotation.y
	camera_pitch = -0.023

func set_first_person(enable: bool) -> void:
	if tank == null:
		first_person = enable
		return
	var previous_aim: Vector3 = tank.aim_point
	first_person = enable
	tank.visual.visible = not enable
	tank.aim_direction_mode = false
	if enable:
		var sight_origin: Vector3 = _sight_camera_position()
		_align_look_to_point(sight_origin, previous_aim)
		self.fov = _target_fov()
		_update_sight_camera(1.0)
	else:
		_focus_pivot = _desired_focus()
		_current_distance = _target_distance()
		_collision_distance = _current_distance
		self.fov = _target_fov()
		var rough_origin: Vector3 = _focus_pivot - _look_direction() * _current_distance + Vector3(0.0, _vertical_lift(), 0.0)
		_align_look_to_point(rough_origin, previous_aim)
		update_pose(1.0)
	update_aim_point()
	_smooth_aim_distance = clampf(current_range_meters, 12.0, AIM_MAX_DISTANCE)
	predict_impacts()

func adjust_zoom(direction: float) -> void:
	if first_person:
		sight_zoom = clampf(sight_zoom + direction * 0.25, 0.0, 1.0)
	else:
		third_person_zoom = clampf(third_person_zoom + direction * 0.125, 0.0, 1.0)

func _align_look_to_point(from_origin: Vector3, target_point: Vector3) -> void:
	var delta_vec: Vector3 = target_point - from_origin
	if delta_vec.length_squared() < 4.0:
		return
	var dir: Vector3 = delta_vec.normalized()
	camera_yaw = atan2(-dir.x, -dir.z)
	camera_pitch = clampf(asin(clampf(dir.y, -0.99, 0.99)), -0.45 if first_person else -0.62, 0.52 if first_person else 0.42)

func _look_direction() -> Vector3:
	return (Basis(Vector3.UP, camera_yaw) * Vector3(0.0, sin(camera_pitch), -cos(camera_pitch))).normalized()

func _target_distance() -> float:
	return lerpf(THIRD_PERSON_DIST_MAX, THIRD_PERSON_DIST_MIN, third_person_zoom)

func _target_fov() -> float:
	if first_person:
		return SIGHT_FOV_MAX / pow(SIGHT_FOV_MAX / SIGHT_FOV_MIN, sight_zoom)
	return lerpf(THIRD_PERSON_FOV_MAX, THIRD_PERSON_FOV_MIN, third_person_zoom)

func _desired_focus() -> Vector3:
	# Anchor to the physics-interpolated chassis position so hull pitch/roll vibration never shakes the camera.
	var height: float = lerpf(1.85, 1.55, third_person_zoom)
	return tank.render_chassis_position() + Vector3(0.0, height, 0.0)

func _vertical_lift() -> float:
	return lerpf(0.65, 0.35, third_person_zoom)

func _sight_camera_position() -> Vector3:
	var turret_basis: Basis = tank.visual.turret.global_basis.orthonormalized()
	return tank.visual.barrel.global_position + turret_basis.y * 0.28 - turret_basis.z * 0.12

func _update_sight_camera(delta: float) -> void:
	var base_pos: Vector3 = _sight_camera_position()
	var shake: Vector3 = Vector3.ZERO
	if shot_shake > 0.001:
		shake = Vector3(sin(_elapsed * 70.0), cos(_elapsed * 90.0), 0.0) * shot_shake * 0.015
	self.global_position = base_pos + shake
	var direction: Vector3 = _look_direction()
	self.look_at(self.global_position + direction * 200.0, Vector3.UP)
	var target_fov: float = _target_fov()
	self.fov = target_fov if delta >= 1.0 else lerpf(self.fov, target_fov, 1.0 - exp(-delta * 16.0))
	camera_position = self.global_position

func update_pose(delta: float) -> void:
	if tank == null:
		return
	if first_person:
		_update_sight_camera(delta)
		return
	var target_focus: Vector3 = _desired_focus()
	var chassis_y: float = tank.render_chassis_position().y
	if delta >= 1.0:
		_focus_pivot = target_focus
		_current_distance = _target_distance()
		_collision_distance = _current_distance
	else:
		# Lock XZ directly to the physics-interpolated chassis (zero horizontal lag-jitter),
		# while gently damping vertical Y to smooth out terrain seams and slopes.
		_focus_pivot.x = target_focus.x
		_focus_pivot.z = target_focus.z
		_focus_pivot.y = lerpf(_focus_pivot.y, target_focus.y, 1.0 - exp(-delta * 12.0))
		_current_distance = lerpf(_current_distance, _target_distance(), 1.0 - exp(-delta * 12.0))
	var look_dir: Vector3 = _look_direction()
	var ray_offset: Vector3 = -look_dir * _current_distance + Vector3(0.0, _vertical_lift(), 0.0)
	var full_len: float = maxf(ray_offset.length(), 0.01)
	var ray_dir: Vector3 = ray_offset / full_len
	var desired_dist: float = full_len
	var world: World3D = get_world_3d()
	if world != null and world.direct_space_state != null:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(_focus_pivot, _focus_pivot + ray_offset, 1)
		var collision: Dictionary = world.direct_space_state.intersect_ray(query)
		if not collision.is_empty():
			desired_dist = maxf(2.2, _focus_pivot.distance_to(collision.position) - 0.35)
	if delta >= 1.0:
		_collision_distance = desired_dist
	else:
		var dist_rate: float = 28.0 if desired_dist < _collision_distance else 8.0
		_collision_distance = lerpf(_collision_distance, desired_dist, 1.0 - exp(-delta * dist_rate))
	var desired: Vector3 = _focus_pivot + ray_dir * _collision_distance
	desired.y = maxf(desired.y, chassis_y + 0.35)
	camera_position = desired
	var shake: Vector3 = Vector3.ZERO
	if shot_shake > 0.001:
		shake = Vector3(sin(_elapsed * 70.0), cos(_elapsed * 90.0), 0.0) * shot_shake * 0.055
	self.global_position = camera_position + shake
	self.look_at(self.global_position + look_dir * 200.0, Vector3.UP)
	var target_fov: float = _target_fov()
	self.fov = target_fov if delta >= 1.0 else lerpf(self.fov, target_fov, 1.0 - exp(-delta * 12.0))

func update_aim_point() -> void:
	if tank == null or not controllable or tank.dead:
		return
	var look_dir: Vector3 = _look_direction()
	tank.requested_gun_direction = look_dir
	var origin: Vector3 = self.global_position
	var ray_dir: Vector3 = look_dir
	var viewport: Viewport = get_viewport()
	if viewport != null and viewport.get_visible_rect().size.length_squared() > 1.0:
		var center: Vector2 = viewport.get_visible_rect().size * 0.5
		origin = self.project_ray_origin(center)
		ray_dir = self.project_ray_normal(center)
	var start_dist: float = 0.0
	if not first_person:
		# Ignore obstacles between the third-person camera and our own turret plane.
		start_dist = maxf(0.0, (tank.render_chassis_position() - origin).dot(ray_dir) + 0.5)
	var ray_start: Vector3 = origin + ray_dir * start_dist
	var end: Vector3 = origin + ray_dir * AIM_MAX_DISTANCE
	var world: World3D = get_world_3d()
	if world == null or world.direct_space_state == null:
		tank.aim_point = end
		current_range_meters = tank.visual.barrel.global_position.distance_to(end)
		return
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, end, 5)
	query.collide_with_areas = true
	query.exclude = [tank.get_rid(), tank.armor.get_rid()]
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	tank.aim_point = end if hit.is_empty() else hit.position
	current_range_meters = tank.visual.barrel.global_position.distance_to(tank.aim_point)

func predict_impact() -> void:
	predict_impacts()

## Projects each active gun barrel's smooth pointing direction (not gravity landing point) every render frame.
func predict_impacts() -> void:
	if tank == null:
		return
	var bore_pivot: Node3D = tank.visual.launcher if DamageModel.is_missile(tank.ammunition) else tank.visual.barrel
	bore_aim_point = bore_pivot.global_position + tank.bore_direction() * _smooth_aim_distance
	barrel_impacts.clear()
	actual_hit_target = false
	var primary_spec: TankShellSpec = tank.ammo_spec()
	var muzzles: Array[Node3D] = tank.active_muzzles()
	var any_clear: bool = false
	for muzzle_node: Node3D in muzzles:
		var obstructed: bool = tank.is_muzzle_obstructed(muzzle_node)
		if not obstructed:
			any_clear = true
		var entry: Dictionary = _sample_muzzle_direction(muzzle_node, primary_spec, obstructed)
		barrel_impacts.append(entry)
		if bool(entry.hit_target):
			actual_hit_target = true
	if not tank.simulation_enabled:
		tank.muzzle_obstructed = not any_clear
	if not barrel_impacts.is_empty():
		actual_impact = barrel_impacts[0].impact
	else:
		actual_impact = bore_aim_point
	coax_valid = false
	if coax_active and tank.coax_muzzle != null and not tank.dead:
		var coax_blocked: bool = _is_coax_obstructed()
		var coax_entry: Dictionary = _sample_muzzle_direction(tank.coax_muzzle, tank.coax_ammo_spec(), coax_blocked)
		coax_impact = coax_entry.impact
		coax_hit_target = bool(coax_entry.hit_target)
		coax_armor_grade = int(coax_entry.armor_grade)
		coax_obstructed = bool(coax_entry.obstructed)
		coax_valid = true

func _is_coax_obstructed() -> bool:
	var world: World3D = get_world_3d()
	if world == null or world.direct_space_state == null:
		return false
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(tank.visual.barrel.global_position, tank.coax_muzzle.global_position, 1)
	query.hit_from_inside = true
	return not world.direct_space_state.intersect_ray(query).is_empty()

func _sample_muzzle_direction(muzzle_node: Node3D, shell_spec: TankShellSpec, obstructed: bool) -> Dictionary:
	var origin: Vector3 = muzzle_node.global_position
	var forward: Vector3 = -muzzle_node.global_basis.z.normalized()
	var direction_point: Vector3 = origin + forward * _smooth_aim_distance
	var is_target: bool = false
	var armor_grade: int = -1
	var hit_distance: float = _smooth_aim_distance
	if not obstructed:
		var world: World3D = get_world_3d()
		if world != null and world.direct_space_state != null:
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + forward * AIM_MAX_DISTANCE, 5)
			query.collide_with_areas = true
			query.exclude = [tank.get_rid(), tank.armor.get_rid()]
			var hit: Dictionary = world.direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				hit_distance = origin.distance_to(hit.position)
				var collider: Node = hit.collider.get_parent() if hit.collider is Area3D else hit.collider
				if (collider is TankScript or collider is TargetScript) and not collider.dead:
					is_target = true
					armor_grade = _evaluate_armor_grade(collider, hit, forward, shell_spec, hit_distance)
	return {
		"muzzle": muzzle_node,
		"impact": direction_point,
		"hit_target": is_target,
		"armor_grade": armor_grade,
		"obstructed": obstructed,
		"distance": hit_distance,
	}

func _evaluate_armor_grade(collider: Node, hit: Dictionary, incoming: Vector3, shell_spec: TankShellSpec, travel_distance: float) -> int:
	var part_name: StringName = &"hull"
	var target_armor_scale: float = 1.0
	var armor_override_mm: float = 0.0
	if collider is TankScript:
		var target_tank: TankScript = collider
		target_armor_scale = target_tank.get_armor_scale()
		var plate: Dictionary = target_tank.armor_part_and_override(int(hit.shape), hit.normal)
		var part: String = String(plate.part)
		part_name = &"track" if part.ends_with("track") else StringName(part)
		armor_override_mm = float(plate.override_mm)
	elif collider is TargetScript:
		var target_node: TargetScript = collider
		target_armor_scale = target_node.get_armor_scale()
		part_name = target_node._part_for_shape(int(hit.shape))
	var result: Dictionary = DamageModel.evaluate_spec(shell_spec, part_name, collider.global_basis, hit.normal, incoming, travel_distance, target_armor_scale, true, armor_override_mm)
	if bool(result.get("ricochet", false)):
		return 0
	var penetrated: bool = bool(result.get("penetrated", false))
	var damage: float = float(result.get("damage", 0.0))
	if not penetrated and damage <= 0.0:
		return 0
	if float(result.get("ricochet_chance", 0.0)) > 0.0 or not penetrated:
		return 1
	if bool(result.get("overpressure", false)):
		return 2
	var pen_mm: float = float(result.get("penetration_mm", 0.0))
	var eff_armor_mm: float = float(result.get("effective_armor_mm", 1.0))
	return 2 if pen_mm >= eff_armor_mm * 1.18 else 1
