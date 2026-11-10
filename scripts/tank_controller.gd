extends CharacterBody3D

const TankVisualScript = preload("res://games/minigame/gp_tank_war/scripts/tank_visual.gd")

## Deliberately accessible tracked-vehicle model, not a full rigid-body simulator.
## Four suspension contacts tilt the rendered hull while a stable chassis handles collision.
const Spec = preload("res://games/minigame/gp_tank_war/scripts/vehicle_spec.gd")
var vehicle_index: int = 0
var spec: Spec
const BRAKING: float = 12.0
const ELEVATION_RATE: float = 0.38
const GRAVITY: float = 20.0
const ComponentState = preload("res://games/minigame/gp_tank_war/scripts/component_status.gd")
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

func _ready() -> void:
	collision_layer = 2
	collision_mask = 3
	floor_snap_length = 0.95
	floor_max_angle = deg_to_rad(43)
	floor_stop_on_slope = true
	floor_constant_speed = true
	assert(coax_muzzle != null and spec != null and visual != null and armor != null and _turret_shape != null and _barrel_shape != null and nameplate != null, "Vehicle requires its spec and authored rig.")
	ammunition = spec.weapons[0]
	components.reload_duration = DamageModel.reload_duration(ammunition)
	start_transform = global_transform
	_update_armor()

func _physics_process(delta: float) -> void:
	if not simulation_enabled or dead:
		return
	components.tick(delta)
	mg_cooldown = maxf(0.0, mg_cooldown - delta)
	if mg_reload_remaining > 0.0:
		mg_reload_remaining = maxf(0.0, mg_reload_remaining - delta)
		if mg_reload_remaining <= 0.0:
			mg_rounds = MG_BELT_SIZE
	integrate_drive(delta)
	recoil = move_toward(recoil, 0.0, delta * 1.7)
	visual.set_recoil(recoil)
	_update_aim(delta)
	_update_armor()

func integrate_drive(delta: float) -> void:
	_update_ground(delta)
	var mobility: Vector2 = components.get_track_multipliers()
	var drive_factor: float = (mobility.x + mobility.y) * 0.5
	var engine_disabled: bool = components.engine_remaining > 0.0
	var requested_speed: float = throttle * (spec.max_speed if throttle >= 0 else spec.reverse_speed) * drive_factor
	var deceleration: float = BRAKING if brake or throttle * speed < -0.1 else spec.acceleration * drive_factor
	if brake:
		requested_speed = 0.0
	elif is_zero_approx(throttle):
		deceleration = 2.8
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
	var turn_authority: float = lerpf(1.08, 0.54, clampf(absf(speed) / spec.max_speed, 0, 1))
	var requested_yaw: float = steering * turn_authority * (0.32 if brake else 1.0) * drive_factor
	var track_pull: float = (mobility.y - mobility.x) * clampf(speed / spec.max_speed, -1.0, 1.0) * 0.85
	requested_yaw += track_pull
	if contact_count < 2:
		requested_yaw *= 0.15
	if not engine_disabled:
		yaw_rate = move_toward(yaw_rate, requested_yaw, delta * 2.4)
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
	# Solve world-space convergence from turret pivot, then use the ACTUAL muzzle
	# for the displayed trajectory. The camera cross is a request, not a hit promise.
	var pivot: Vector3 = visual.turret.global_position
	var direction: Vector3 = requested_gun_direction if aim_direction_mode else aim_point - pivot
	var local_direction: Vector3 = visual.global_basis.orthonormalized().inverse() * direction
	var target_yaw: float = atan2(-local_direction.x, -local_direction.z)
	visual.turret.rotation.y = rotate_toward(visual.turret.rotation.y, target_yaw, spec.traverse_rate * delta)
	var barrel_target: Vector3 = requested_gun_direction if aim_direction_mode else aim_point - visual.barrel.global_position
	var local_barrel: Vector3 = visual.turret.global_basis.orthonormalized().inverse() * barrel_target
	var horizontal: float = Vector2(local_barrel.x, local_barrel.z).length()
	# Third person solves a low ballistic arc to a requested world point.
	# The first-person sight instead commands a bore direction directly: feeding
	# the actual gun camera back into the arc solver would cause elevation drift.
	var shell_speed: float = DamageModel.shell_speed(ammunition)
	var gravity: float = DamageModel.gravity(ammunition)
	var v2: float = shell_speed * shell_speed
	var discriminant: float = v2 * v2 - gravity * (gravity * horizontal * horizontal + 2.0 * local_barrel.y * v2)
	var elevation: float = atan2(local_barrel.y, horizontal)
	if gravity > 0.0 and not aim_direction_mode and horizontal > 1.0 and discriminant >= 0.0:
		elevation = atan((v2 - sqrt(discriminant)) / (gravity * horizontal))
	elevation = clampf(elevation, deg_to_rad(-9), deg_to_rad(23))
	visual.barrel.rotation.x = move_toward(visual.barrel.rotation.x, elevation, ELEVATION_RATE * delta)
	visual.aim_launcher()
	var breech: Vector3 = visual.barrel.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(breech, shot_muzzle().global_position + muzzle_direction() * 0.2, 1)
	query.hit_from_inside = true
	muzzle_obstructed = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func muzzle_direction() -> Vector3:
	return -shot_muzzle().global_basis.z.normalized()

func can_fire() -> bool:
	return not dead and components.can_fire() and not muzzle_obstructed

func begin_fire() -> bool:
	if not can_fire() or not components.begin_fire():
		return false
	rounds_fired += 1
	recoil = 0.24 if DamageModel.is_automatic(ammunition) else 1.0
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
	mg_cooldown = DamageModel.reload_duration(DamageModel.Ammo.MG)
	if mg_rounds == 0:
		mg_reload_remaining = MG_RELOAD_SECONDS
	return true

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
	mg_rounds = MG_BELT_SIZE
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
const DamageModel = preload("res://games/minigame/gp_tank_war/scripts/armor_damage.gd")

@export var turret_center: Vector3
@export var barrel_length: float

func _update_armor() -> void:
	_turret_shape.global_transform = visual.turret.global_transform.translated_local(turret_center)
	_barrel_shape.global_transform = visual.barrel.global_transform.translated_local(Vector3(0, 0, -barrel_length * 0.5))

func get_marker_point() -> Vector3:
	return global_position + Vector3(0, 2.8, 0)

## Shell contacts use the actual armor shape and surface angle. Health is host-owned.
func apply_shell_hit(point: Vector3, normal: Vector3, incoming: Vector3, shape_index: int, shell_ammunition: int = DamageModel.Ammo.AP) -> Dictionary:
	var shape: CollisionShape3D = armor.shape_owner_get_owner(armor.shape_find_owner(shape_index))
	var part: String = shape.get_meta("part")
	var result: Dictionary = DamageModel.evaluate(&"track" if part.ends_with("track") else StringName(part), global_basis, normal, incoming, shell_ammunition)
	result["ignored"] = dead
	result["damage"] = 0.0 if dead else minf(hp, result.damage * spec.damage_multiplier)
	result["component"] = ""
	result["disabled"] = false
	result["component_duration"] = 0.0
	hp -= result.damage
	dead = hp <= 0.0
	if result.damage > 0.0 and not dead and shell_ammunition != DamageModel.Ammo.MG:
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
	return PackedFloat32Array([position.x, position.y, position.z, rotation.y, speed, yaw_rate,
		visual.rotation.x, visual.rotation.z, visual.turret.rotation.y, visual.barrel.rotation.x, recoil])

func apply_motion(state: PackedFloat32Array, delta: float) -> void:
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

func combat_facts(now: int) -> Dictionary:
	var facts: Dictionary = {"hp": hp, "dead": dead, "damage_dealt": damage_dealt, "kills": kills,
		"rounds_fired": rounds_fired, "ammunition": ammunition, "mg_rounds": mg_rounds, "mg_shots_fired": mg_shots_fired}
	for part: String in ["engine", "left_track", "right_track", "barrel"]:
		var remaining: float = components.get(part + "_remaining")
		facts[part + "_end"] = now + roundi(remaining * 1000.0) if remaining > 0.0 else 0
	facts["reload_end"] = now + roundi((components.barrel_remaining + components.reload_remaining) * 1000.0) if components.reload_remaining > 0.0 else 0
	facts["mg_reload_end"] = now + roundi(mg_reload_remaining * 1000.0) if mg_reload_remaining > 0.0 else 0
	return facts

func switch_ammunition(value: int) -> void:
	if dead or value == ammunition:
		return
	ammunition = value
	components.reload_duration = DamageModel.reload_duration(ammunition)
	components.begin_reload()

func get_aim_point() -> Vector3:
	return global_position + Vector3(0, 0.25, 0)

## Blast pressure chips armor and disables the exposed track; cover is tested by the shell.
func apply_blast_hit(origin: Vector3, amount: float) -> Dictionary:
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
	elif amount >= 4.0:
		var component: StringName = &"left_track" if to_local(origin).x < 0.0 else &"right_track"
		result.disabled = not components.is_disabled(component)
		apply_component_hit(component)
		result.component = component
	return result

func shot_muzzle() -> Node3D:
	return visual.firing_muzzle(DamageModel.is_missile(ammunition), rounds_fired)
