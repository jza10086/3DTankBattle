extends CharacterBody3D

const TankVisualScript = preload("res://games/minigame/GP_tank_war/scripts/tank_visual.gd")

## Deliberately accessible tracked-vehicle model, not a full rigid-body simulator.
## Four suspension contacts tilt the rendered hull while a stable chassis handles collision.
@export var spec: TankVehicleSpec
@export_group("Prefab Overrides")
@export var hp_override: float = 0.0
@export var weapon_overrides: Array[TankShellSpec] = []
@export var coax_override: TankShellSpec
var vehicle_index: int = 0
const GRAVITY: float = 20.0
const ComponentState = preload("res://games/minigame/GP_tank_war/scripts/component_status.gd")
var speed: float = 0.0
var yaw_rate: float = 0.0
var throttle: float = 0.0
var steering: float = 0.0
var brake: bool = false
var aim_point: Vector3 = Vector3(0, 1.6, -100)
var aim_direction_mode: bool = false
var requested_gun_direction: Vector3 = Vector3.FORWARD
var components: ComponentState = ComponentState.new()
# The HUD reads the same component reload timer as the simulation.
var reload_remaining: float:
	get:
		return components.reload_remaining
	set(value):
		components.reload_remaining = maxf(value, 0.0)
var ammunition: int = DamageModel.Ammo.AP
var _slot_loaded_ammo: Dictionary[StringName, int] = {}
const MG_BELT_SIZE: int = 100
const MG_RELOAD_SECONDS: float = 4.0
var mg_rounds: int = MG_BELT_SIZE
var mg_reload_remaining: float = 0.0
var mg_cooldown: float = 0.0
var mg_shots_fired: int = 0
@export var coax_muzzle: Marker3D
var rounds_fired: int = 0
var recoil: float = 0.0
var ground_normal: Vector3 = Vector3.UP
var contact_count: int = 0
var left_track_speed: float = 0.0
var right_track_speed: float = 0.0
@export var visual: TankVisualScript
var start_transform: Transform3D = Transform3D.IDENTITY
var ground_offsets: Array[float] = []
var hull_pitch: float = 0.0
var hull_roll: float = 0.0
var muzzle_obstructed: bool = false
var _interp_ready: bool = false
var _prev_body_pos: Vector3 = Vector3.ZERO
var _curr_body_pos: Vector3 = Vector3.ZERO
var _prev_body_yaw: float = 0.0
var _curr_body_yaw: float = 0.0
var _prev_hull_pitch: float = 0.0
var _curr_hull_pitch: float = 0.0
var _prev_hull_roll: float = 0.0
var _curr_hull_roll: float = 0.0
var _prev_turret_yaw: float = 0.0
var _curr_turret_yaw: float = 0.0
var _prev_barrel_pitch: float = 0.0
var _curr_barrel_pitch: float = 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 3
	floor_snap_length = 0.95
	floor_max_angle = deg_to_rad(43)
	floor_stop_on_slope = true
	floor_constant_speed = true
	assert(coax_muzzle != null and spec != null and visual != null and armor != null and _turret_shape != null and _barrel_shape != null and nameplate != null, "Vehicle requires its spec and authored rig.")
	max_hp = configured_max_hp()
	hp = 0.0 if dead else max_hp
	mg_rounds = mg_belt_size()
	var codes: Array[int] = weapon_codes()
	ammunition = codes[0] if not codes.is_empty() else DamageModel.Ammo.AP
	_init_weapon_slots()
	start_transform = global_transform
	_update_armor()
	snap_interpolation()

func _physics_process(delta: float) -> void:
	if not simulation_enabled or dead:
		return
	_begin_physics_step()
	components.tick(delta)
	mg_cooldown = maxf(0.0, mg_cooldown - delta)
	if mg_reload_remaining > 0.0:
		mg_reload_remaining = maxf(0.0, mg_reload_remaining - delta)
		if mg_reload_remaining <= 0.0:
			mg_rounds = mg_belt_size()
	integrate_drive(delta)
	recoil = move_toward(recoil, 0.0, delta * 1.7)
	visual.set_recoil(recoil)
	_update_aim(delta)
	_update_armor()
	_capture_physics_state(false)

func _begin_physics_step() -> void:
	if not _interp_ready:
		_capture_physics_state(true)
		return
	visual.position = Vector3.ZERO
	visual.rotation = Vector3(_curr_hull_pitch, 0.0, _curr_hull_roll)
	visual.turret.rotation.y = _curr_turret_yaw
	visual.barrel.rotation.x = _curr_barrel_pitch
	visual.aim_launcher()
	_prev_body_pos = _curr_body_pos
	_prev_body_yaw = _curr_body_yaw
	_prev_hull_pitch = _curr_hull_pitch
	_prev_hull_roll = _curr_hull_roll
	_prev_turret_yaw = _curr_turret_yaw
	_prev_barrel_pitch = _curr_barrel_pitch

func _capture_physics_state(snap_previous: bool) -> void:
	_curr_body_pos = global_position
	_curr_body_yaw = rotation.y
	_curr_hull_pitch = visual.rotation.x
	_curr_hull_roll = visual.rotation.z
	_curr_turret_yaw = visual.turret.rotation.y
	_curr_barrel_pitch = visual.barrel.rotation.x
	if snap_previous or not _interp_ready:
		_prev_body_pos = _curr_body_pos
		_prev_body_yaw = _curr_body_yaw
		_prev_hull_pitch = _curr_hull_pitch
		_prev_hull_roll = _curr_hull_roll
		_prev_turret_yaw = _curr_turret_yaw
		_prev_barrel_pitch = _curr_barrel_pitch
		_interp_ready = true

func snap_interpolation() -> void:
	if visual == null:
		return
	visual.position = Vector3.ZERO
	visual.rotation.y = 0.0
	_capture_physics_state(true)

## Smoothly interpolates visual hull, turret, and barrel between physics ticks for jitter-free high-FPS rendering.
func apply_render_interpolation() -> void:
	if not _interp_ready or visual == null:
		return
	var frac: float = clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var render_pos: Vector3 = _prev_body_pos.lerp(_curr_body_pos, frac)
	var render_yaw: float = lerp_angle(_prev_body_yaw, _curr_body_yaw, frac)
	visual.global_position = render_pos
	visual.rotation = Vector3(
		lerpf(_prev_hull_pitch, _curr_hull_pitch, frac),
		wrapf(render_yaw - rotation.y, -PI, PI),
		lerpf(_prev_hull_roll, _curr_hull_roll, frac)
	)
	visual.turret.rotation.y = lerp_angle(_prev_turret_yaw, _curr_turret_yaw, frac)
	visual.barrel.rotation.x = lerpf(_prev_barrel_pitch, _curr_barrel_pitch, frac)
	visual.aim_launcher()

func render_chassis_position() -> Vector3:
	if not _interp_ready:
		return global_position
	var frac: float = clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	return _prev_body_pos.lerp(_curr_body_pos, frac)

func integrate_drive(delta: float) -> void:
	_update_ground(delta)
	var mobility: Vector2 = components.get_track_multipliers()
	var drive_factor: float = (mobility.x + mobility.y) * 0.5
	var engine_disabled: bool = components.engine_remaining > 0.0
	var requested_speed: float = throttle * (spec.max_speed if throttle >= 0 else spec.reverse_speed) * drive_factor
	var deceleration: float = spec.braking if brake or throttle * speed < -0.1 else spec.acceleration * drive_factor
	if brake:
		requested_speed = 0.0
	elif is_zero_approx(throttle):
		deceleration = spec.coast_deceleration
	if engine_disabled:
		# A disabled engine cannot retain powered translation OR pivot momentum.
		# Horizontal movement stops even in the air, but gravity/contact keep running.
		speed = 0.0
		yaw_rate = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
	elif contact_count >= 2:
		speed = clampf(speed, -spec.reverse_speed * drive_factor, spec.max_speed * drive_factor)
		speed = move_toward(speed, requested_speed, deceleration * delta)
	# Healthy movement is unchanged. Damaged tracks reduce propulsion and turn
	# authority; a single weak track also pulls toward that side while rolling.
	var turn_authority: float = lerpf(spec.pivot_turn_rate, spec.move_turn_rate, clampf(absf(speed) / maxf(spec.max_speed, 0.1), 0.0, 1.0))
	var requested_yaw: float = steering * turn_authority * (0.32 if brake else 1.0) * drive_factor
	var track_pull: float = (mobility.y - mobility.x) * clampf(speed / maxf(spec.max_speed, 0.1), -1.0, 1.0) * 0.85
	requested_yaw += track_pull
	if contact_count < 2:
		requested_yaw *= 0.15
	if not engine_disabled:
		yaw_rate = move_toward(yaw_rate, requested_yaw, delta * spec.yaw_acceleration)
	rotate_y(yaw_rate * delta)
	var forward: Vector3 = -global_basis.z
	var direction: Vector3 = forward.slide(ground_normal).normalized() if contact_count >= 2 else forward
	if contact_count >= 2:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	if is_on_floor() and contact_count >= 2:
		velocity.y = direction.y * speed - 1.5
	else:
		velocity.y -= GRAVITY * delta
	var before: Vector3 = global_position
	move_and_slide()
	# A collision must not keep the speedometer / tracks accelerating into a wall.
	if is_on_wall():
		var realized: float = Vector2(global_position.x - before.x, global_position.z - before.z).length() / maxf(delta, 0.001)
		speed = signf(speed) * minf(absf(speed), realized + 0.08)
	left_track_speed = speed - yaw_rate * 1.8
	right_track_speed = speed + yaw_rate * 1.8
	visual.animate_tracks(left_track_speed, right_track_speed, delta, ground_offsets)
	if global_position.y < -12 or global_position.length() > 400:
		reset_vehicle()

func _update_ground(delta: float) -> void:
	var normal_sum: Vector3 = Vector3.ZERO
	var heights: Array[float] = []
	contact_count = 0
	ground_offsets.clear()
	for point: Vector3 in [Vector3(-1.2, 1.5, -1.8), Vector3(1.2, 1.5, -1.8), Vector3(-1.2, 1.5, 1.8), Vector3(1.2, 1.5, 1.8)]:
		var origin: Vector3 = global_transform * point
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 4.3, 1)
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and origin.y - hit.position.y <= 2.8:
			normal_sum += hit.normal
			heights.append(hit.position.y)
			ground_offsets.append(clampf(hit.position.y - (global_position.y - 0.6), -0.3, 0.3))
			contact_count += 1
		else:
			heights.append(global_position.y - 0.6)
			ground_offsets.append(-0.15)
	if contact_count >= 3:
		# Height differences capture chassis pitch while crossing a ramp seam.
		var pitch: float = atan2((heights[0] + heights[1] - heights[2] - heights[3]) * 0.5, 3.6)
		var roll: float = atan2((heights[1] + heights[3] - heights[0] - heights[2]) * 0.5, 2.4)
		hull_pitch = lerpf(hull_pitch, clampf(pitch, -0.55, 0.55), 1.0 - exp(-delta * 9))
		hull_roll = lerpf(hull_roll, clampf(roll, -0.45, 0.45), 1.0 - exp(-delta * 9))
		ground_normal = ground_normal.lerp((normal_sum / contact_count).normalized(), 1.0 - exp(-delta * 12)).normalized()
	else:
		ground_normal = ground_normal.lerp(Vector3.UP, delta * 2).normalized()
	visual.rotation.x = hull_pitch + sin(Time.get_ticks_msec() * 0.018) * minf(absf(speed) * 0.0009, 0.009)
	visual.rotation.z = hull_roll - yaw_rate * absf(speed) * 0.0015

func _update_aim(delta: float) -> void:
	# War Thunder-style line-of-sight convergence: turret and gun align directly to
	# aim_point (parallax convergence without auto-gravity sky-jerk), while the HUD
	# projects each barrel's real gravity-affected impact point every render frame.
	var pivot: Vector3 = visual.turret.global_position
	var direction: Vector3 = requested_gun_direction if aim_direction_mode else aim_point - pivot
	if direction.length_squared() > 0.0001:
		var local_direction: Vector3 = visual.global_basis.orthonormalized().inverse() * direction
		var target_yaw: float = atan2(-local_direction.x, -local_direction.z)
		visual.turret.rotation.y = rotate_toward(visual.turret.rotation.y, target_yaw, spec.traverse_rate * delta)
	var weapon_pivot: Vector3 = visual.launcher.global_position if DamageModel.is_missile(ammunition) else visual.barrel.global_position
	var barrel_target: Vector3 = requested_gun_direction if aim_direction_mode else aim_point - weapon_pivot
	if barrel_target.length_squared() > 0.0001:
		var local_barrel: Vector3 = visual.turret.global_basis.orthonormalized().inverse() * barrel_target
		var horizontal: float = maxf(Vector2(local_barrel.x, local_barrel.z).length(), 0.001)
		var elevation: float = clampf(atan2(local_barrel.y, horizontal), deg_to_rad(spec.min_depression_deg), deg_to_rad(spec.max_elevation_deg))
		visual.barrel.rotation.x = move_toward(visual.barrel.rotation.x, elevation, spec.elevation_rate * delta)
	visual.aim_launcher()
	var any_clear: bool = false
	for muzzle_node: Node3D in active_muzzles():
		if not is_muzzle_obstructed(muzzle_node):
			any_clear = true
			break
	muzzle_obstructed = not any_clear

func active_muzzles() -> Array[Node3D]:
	return visual.active_muzzles(DamageModel.is_missile(ammunition))

func is_muzzle_obstructed(muzzle_node: Node3D) -> bool:
	if muzzle_node == null or not is_inside_tree() or get_world_3d() == null:
		return false
	var breech: Vector3 = visual.launcher.global_position if DamageModel.is_missile(ammunition) else visual.barrel.global_position
	var forward: Vector3 = muzzle_direction_for(muzzle_node)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(breech, muzzle_node.global_position + forward * 0.2, 1)
	query.hit_from_inside = true
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func muzzle_direction_for(muzzle_node: Node3D) -> Vector3:
	return -muzzle_node.global_basis.z.normalized()

func bore_direction() -> Vector3:
	var pivot: Node3D = visual.launcher if DamageModel.is_missile(ammunition) else visual.barrel
	return -pivot.global_basis.z.normalized()

func muzzle_direction() -> Vector3:
	return muzzle_direction_for(shot_muzzle())

func can_fire() -> bool:
	return not dead and components.can_fire() and not muzzle_obstructed

func begin_fire() -> bool:
	if not can_fire() or not components.begin_fire():
		return false
	rounds_fired += 1
	recoil = ammo_spec().recoil_impulse
	return true

## Coax has its own belt and cadence; main-gun reload/damage does not block it.
func begin_machine_gun_fire() -> bool:
	if dead or mg_rounds == 0 or mg_cooldown > 0.0001 or mg_reload_remaining > 0.0:
		return false
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(visual.barrel.global_position, coax_muzzle.global_position, 1)
	query.hit_from_inside = true
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return false
	mg_rounds -= 1
	mg_shots_fired += 1
	mg_cooldown = coax_ammo_spec().reload_time
	if mg_rounds == 0:
		mg_reload_remaining = mg_reload_seconds()
	return true

func configured_max_hp() -> float:
	if hp_override > 0.0:
		return hp_override
	return spec.max_hp if spec != null else 100.0

func mg_belt_size() -> int:
	return maxi(spec.mg_belt_size, 1) if spec != null else MG_BELT_SIZE

func mg_reload_seconds() -> float:
	return maxf(spec.mg_reload_seconds, 0.1) if spec != null else MG_RELOAD_SECONDS

func weapon_codes() -> Array[int]:
	var codes: Array[int] = []
	for entry: TankShellSpec in weapon_overrides:
		if entry != null and entry.ammo_code not in codes:
			codes.append(entry.ammo_code)
	if not codes.is_empty():
		return codes
	return spec.weapon_codes() if spec != null else [DamageModel.Ammo.AP]

func ammo_spec() -> TankShellSpec:
	return ammo_spec_for(ammunition)

func ammo_spec_for(value: int) -> TankShellSpec:
	for entry: TankShellSpec in weapon_overrides:
		if entry != null and entry.ammo_code == value:
			return entry
	if coax_override != null and coax_override.ammo_code == value:
		return coax_override
	if spec != null:
		var custom: TankShellSpec = spec.find_ammo_spec(value)
		if custom != null:
			return custom
	return DamageModel.get_spec(value)

func coax_ammo_spec() -> TankShellSpec:
	if coax_override != null:
		return coax_override
	if spec != null and spec.coax_ammo != null:
		return spec.coax_ammo
	return DamageModel.get_spec(DamageModel.Ammo.MG)

func get_armor_scale() -> float:
	return spec.armor_scale if spec != null else 1.0

func armor_part_and_override(shape_index: int, world_normal: Vector3) -> Dictionary:
	var owner_id: int = armor.shape_find_owner(shape_index)
	var shape: CollisionShape3D = armor.shape_owner_get_owner(owner_id) as CollisionShape3D
	var part: String = "hull"
	var override_mm: float = 0.0
	if shape != null:
		if shape is TankArmorZone:
			var zone: TankArmorZone = shape
			part = String(zone.part) if not zone.part.is_empty() else String(shape.get_meta("part", "hull"))
			if world_normal.length_squared() > 0.000001:
				var local_normal: Vector3 = global_basis.orthonormalized().inverse() * world_normal.normalized()
				var facing: String = DamageModel.classify_facing(local_normal)
				override_mm = zone.thickness_for_facing(facing)
		else:
			part = String(shape.get_meta("part", "hull"))
	return {"part": part, "override_mm": override_mm}

func apply_component_hit(component: StringName) -> bool:
	if not components.apply_component(component):
		return false
	if component == &"engine":
		speed = 0.0
		yaw_rate = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		left_track_speed = 0.0
		right_track_speed = 0.0
	return true

func reset_vehicle() -> void:
	components.clear()
	_init_weapon_slots()
	mg_rounds = mg_belt_size()
	mg_reload_remaining = 0.0
	mg_cooldown = 0.0
	global_transform = start_transform
	velocity = Vector3.ZERO
	speed = 0.0
	yaw_rate = 0.0
	throttle = 0.0
	steering = 0.0
	ground_normal = Vector3.UP
	hull_pitch = 0.0
	hull_roll = 0.0
	recoil = 0.0
	visual.rotation = Vector3.ZERO
	visual.turret.rotation = Vector3.ZERO
	visual.barrel.rotation = Vector3.ZERO
	snap_interpolation()

var simulation_enabled: bool = false
var player_id: String = ""
var player_name: String = ""
var hp: float = 100.0
var max_hp: float = 100.0
var dead: bool = false
var damage_dealt: float = 0.0
var kills: int = 0
var death_time: float = 0.0
@export var armor: Area3D
@export var _turret_shape: CollisionShape3D
@export var _barrel_shape: CollisionShape3D
@export var nameplate: Label3D
const DamageModel = preload("res://games/minigame/GP_tank_war/scripts/armor_damage.gd")

@export var turret_center: Vector3
@export var barrel_length: float

func _update_armor() -> void:
	_turret_shape.global_transform = visual.turret.global_transform.translated_local(turret_center)
	_barrel_shape.global_transform = visual.barrel.global_transform.translated_local(Vector3(0, 0, -barrel_length * 0.5))

func get_marker_point() -> Vector3:
	return global_position + Vector3(0, 2.8, 0)

## Shell contacts use the actual armor shape, TankArmorZone overrides, surface angle, distance, and TankShellSpec. Health is host-owned.
func apply_shell_hit(point: Vector3, normal: Vector3, incoming: Vector3, shape_index: int, shell_ammunition: int = DamageModel.Ammo.AP, travel_distance: float = 0.0, shell_spec: TankShellSpec = null) -> Dictionary:
	var active_spec: TankShellSpec = shell_spec if shell_spec != null else DamageModel.get_spec(shell_ammunition)
	var plate: Dictionary = armor_part_and_override(shape_index, normal)
	var part: String = String(plate.part)
	var override_mm: float = float(plate.override_mm)
	var result: Dictionary = DamageModel.evaluate_spec(active_spec, &"track" if part.ends_with("track") else StringName(part), global_basis, normal, incoming, travel_distance, get_armor_scale(), false, override_mm)
	result["ignored"] = dead
	result["damage"] = 0.0 if dead else minf(hp, result.damage * spec.damage_multiplier)
	result["component"] = ""
	result["disabled"] = false
	result["component_duration"] = 0.0
	hp -= result.damage
	dead = hp <= 0.0
	if result.damage > 0.0 and not dead and active_spec.component_damage:
		var component: StringName = &""
		if part.ends_with("track") or part == "barrel":
			component = StringName(part)
		elif part == "hull" and to_local(point).z > 1.2 and result.facing == "rear":
			component = &"engine"
		if not component.is_empty():
			result.disabled = not components.is_disabled(component)
			apply_component_hit(component)
			result.component = component
			result.component_duration = ComponentState.TRACK_DURATION if part.ends_with("track") else ComponentState.ENGINE_DURATION
	if dead:
		speed = 0.0
		velocity = Vector3.ZERO
		visual.set_destroyed(true)
	result["destroyed"] = dead
	result["hp"] = hp
	return result

const MOTION_FLOATS: int = 11

## Only chassis and rig motion need replaceable samples. Combat facts travel as reliable events.
func motion_sample() -> PackedFloat32Array:
	var h_pitch: float = _curr_hull_pitch if _interp_ready else visual.rotation.x
	var h_roll: float = _curr_hull_roll if _interp_ready else visual.rotation.z
	var t_yaw: float = _curr_turret_yaw if _interp_ready else visual.turret.rotation.y
	var b_pitch: float = _curr_barrel_pitch if _interp_ready else visual.barrel.rotation.x
	return PackedFloat32Array([position.x, position.y, position.z, rotation.y, speed, yaw_rate,
		h_pitch, h_roll, t_yaw, b_pitch, recoil])

func apply_motion(state: PackedFloat32Array, delta: float) -> void:
	_begin_physics_step()
	var target: Transform3D = Transform3D(Basis(Vector3.UP, state[3]), Vector3(state[0], state[1], state[2]))
	transform = transform.interpolate_with(target, 1.0 - exp(-18.0 * delta))
	speed = state[4]
	yaw_rate = state[5]
	visual.rotation = Vector3(state[6], 0, state[7])
	visual.turret.rotation.y = lerp_angle(visual.turret.rotation.y, state[8], 1.0 - exp(-18.0 * delta))
	visual.barrel.rotation.x = lerpf(visual.barrel.rotation.x, state[9], 1.0 - exp(-18.0 * delta))
	visual.set_recoil(state[10])
	visual.set_destroyed(dead)
	visual.animate_tracks(speed - yaw_rate * 1.3, speed + yaw_rate * 1.3, delta)
	visual.aim_launcher()
	_update_armor()
	_capture_physics_state(false)

func combat_facts(now: int) -> Dictionary:
	var facts: Dictionary = {"hp": hp, "dead": dead, "damage_dealt": damage_dealt, "kills": kills,
		"rounds_fired": rounds_fired, "ammunition": ammunition, "mg_rounds": mg_rounds, "mg_shots_fired": mg_shots_fired}
	for part: String in ["engine", "left_track", "right_track", "barrel"]:
		var remaining: float = components.get(part + "_remaining")
		facts[part + "_end"] = now + roundi(remaining * 1000.0) if remaining > 0.0 else 0
	var weapon_reload_ends: Dictionary = {}
	for code: int in weapon_codes():
		var slot: StringName = reload_slot_for(code)
		var remaining: float = components.get_weapon_reload_remaining(slot)
		var barrel_offset: float = components.barrel_remaining if components.is_weapon_affected_by_barrel(slot) else 0.0
		weapon_reload_ends[code] = now + roundi((barrel_offset + remaining) * 1000.0) if remaining > 0.0 else 0
	facts["weapon_reload_ends"] = weapon_reload_ends
	facts["mg_reload_end"] = now + roundi(mg_reload_remaining * 1000.0) if mg_reload_remaining > 0.0 else 0
	return facts

func _init_weapon_slots() -> void:
	_slot_loaded_ammo.clear()
	components.clear_weapons()
	for code: int in weapon_codes():
		var w_spec: TankShellSpec = ammo_spec_for(code)
		var slot: StringName = w_spec.resolved_reload_slot()
		if not _slot_loaded_ammo.has(slot):
			_slot_loaded_ammo[slot] = code
			components.configure_weapon(slot, w_spec.reload_time, not w_spec.guided_missile)
	var active_spec: TankShellSpec = ammo_spec()
	var active_slot: StringName = active_spec.resolved_reload_slot()
	_slot_loaded_ammo[active_slot] = ammunition
	components.configure_weapon(active_slot, active_spec.reload_time, not active_spec.guided_missile)
	components.active_weapon_slot = active_slot

func reload_slot_for(value: int) -> StringName:
	return ammo_spec_for(value).resolved_reload_slot()

func weapon_reload_remaining_for(value: int) -> float:
	return components.get_weapon_reload_remaining(reload_slot_for(value))

func weapon_reload_duration_for(value: int) -> float:
	return components.get_weapon_reload_duration(reload_slot_for(value))

func is_active_weapon_repairing() -> bool:
	return components.is_weapon_repairing(ammo_spec().resolved_reload_slot())

## Applies host-authoritative active weapon selection on clients without restarting local reload timers.
func sync_active_ammunition(value: int) -> void:
	ammunition = value
	var active_spec: TankShellSpec = ammo_spec()
	var active_slot: StringName = active_spec.resolved_reload_slot()
	_slot_loaded_ammo[active_slot] = value
	components.configure_weapon(active_slot, active_spec.reload_time, not active_spec.guided_missile)
	components.active_weapon_slot = active_slot

func switch_ammunition(value: int) -> void:
	if dead or value == ammunition:
		return
	var previous_slot: StringName = ammo_spec().resolved_reload_slot()
	var target_spec: TankShellSpec = ammo_spec_for(value)
	var target_slot: StringName = target_spec.resolved_reload_slot()
	ammunition = value
	components.configure_weapon(target_slot, target_spec.reload_time, not target_spec.guided_missile)
	components.active_weapon_slot = target_slot
	if target_slot == previous_slot:
		# Same physical cannon switching shell type (e.g. AP <-> HE) must unload and load the new round.
		if int(_slot_loaded_ammo.get(target_slot, -1)) != value:
			_slot_loaded_ammo[target_slot] = value
			components.begin_reload_slot(target_slot, target_spec.reload_time)
	else:
		# Distinct physical equipment (e.g. autocannon <-> ATGM): preserve both weapons' loaded/reloading states.
		if not _slot_loaded_ammo.has(target_slot):
			_slot_loaded_ammo[target_slot] = value
		elif int(_slot_loaded_ammo[target_slot]) != value:
			_slot_loaded_ammo[target_slot] = value
			components.begin_reload_slot(target_slot, target_spec.reload_time)

func get_aim_point() -> Vector3:
	return global_position + Vector3(0, 0.25, 0)

## Blast pressure chips armor and disables the exposed track; cover is tested by the shell.
func apply_blast_hit(origin: Vector3, amount: float, track_threshold: float = 4.0) -> Dictionary:
	var result: Dictionary = {"damage": 0.0, "destroyed": false, "component": "", "disabled": false}
	if dead:
		return result
	result.damage = minf(hp, amount * spec.damage_multiplier)
	hp -= result.damage
	dead = hp <= 0.0
	result.destroyed = dead
	if dead:
		speed = 0.0
		velocity = Vector3.ZERO
		visual.set_destroyed(true)
	elif amount >= track_threshold:
		var component: StringName = &"left_track" if to_local(origin).x < 0.0 else &"right_track"
		result.disabled = not components.is_disabled(component)
		apply_component_hit(component)
		result.component = component
	return result

func shot_muzzle() -> Node3D:
	var preferred: Node3D = visual.firing_muzzle(DamageModel.is_missile(ammunition), rounds_fired)
	if not is_muzzle_obstructed(preferred):
		return preferred
	for candidate: Node3D in active_muzzles():
		if not is_muzzle_obstructed(candidate):
			return candidate
	return preferred
