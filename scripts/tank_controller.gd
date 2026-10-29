class_name TankController
extends CharacterBody3D

## Deliberately accessible tracked-vehicle model, not a full rigid-body simulator.
## Four suspension contacts tilt the rendered hull while a stable chassis handles collision.
const MAX_FORWARD := 14.5
const MAX_REVERSE := 5.5
const ACCELERATION := 4.2
const BRAKING := 12.0
const TURRET_RATE := 0.68
const ELEVATION_RATE := 0.38
const GRAVITY := 20.0
const SHELL_SPEED := 105.0
const SHELL_GRAVITY := 9.8
const RELOAD_TIME := 3.2
var speed := 0.0
var yaw_rate := 0.0
var throttle := 0.0
var steering := 0.0
var brake := false
var controls_enabled := true
var aim_point := Vector3(0, 1.6, -100)
var reload_remaining := 0.0
var rounds_fired := 0
var recoil := 0.0
var ground_normal := Vector3.UP
var contact_count := 0
var left_track_speed := 0.0
var right_track_speed := 0.0
var visual: TankVisual
var start_transform := Transform3D.IDENTITY
var ground_offsets: Array[float] = []
var hull_pitch := 0.0
var hull_roll := 0.0
var muzzle_obstructed := false

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.95
	floor_max_angle = deg_to_rad(43)
	floor_stop_on_slope = true
	floor_constant_speed = true
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 1.15, 4.5)
	collider.shape = box
	add_child(collider)
	visual = TankVisual.new()
	add_child(visual)
	start_transform = global_transform

func _physics_process(delta: float) -> void:
	if controls_enabled:
		throttle = float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
		steering = float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)) - float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
		brake = Input.is_physical_key_pressed(KEY_SPACE)
	integrate_drive(delta)
	reload_remaining = maxf(0.0, reload_remaining - delta)
	recoil = move_toward(recoil, 0.0, delta * 1.7)
	visual.set_recoil(recoil)
	_update_aim(delta)

func integrate_drive(delta: float) -> void:
	_update_ground(delta)
	var requested_speed := throttle * (MAX_FORWARD if throttle >= 0 else MAX_REVERSE)
	var deceleration := BRAKING if brake or throttle * speed < -0.1 else ACCELERATION
	if brake:
		requested_speed = 0.0
	elif is_zero_approx(throttle):
		deceleration = 2.8
	if contact_count >= 2:
		speed = move_toward(speed, requested_speed, deceleration * delta)
	# Tracked differential steering: pivot at rest, gentler yaw at cruising speed.
	var turn_authority := lerpf(1.08, 0.54, clampf(absf(speed) / MAX_FORWARD, 0, 1))
	var requested_yaw := steering * turn_authority * (0.32 if brake else 1.0)
	if contact_count < 2:
		requested_yaw *= 0.15
	yaw_rate = move_toward(yaw_rate, requested_yaw, delta * 2.4)
	rotate_y(yaw_rate * delta)
	var forward := -global_basis.z
	var direction := forward.slide(ground_normal).normalized() if contact_count >= 2 else forward
	if contact_count >= 2:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	if is_on_floor() and contact_count >= 2:
		velocity.y = direction.y * speed - 1.5
	else:
		velocity.y -= GRAVITY * delta
	var before := global_position
	move_and_slide()
	# A collision must not keep the speedometer / tracks accelerating into a wall.
	if is_on_wall():
		var realized := Vector2(global_position.x - before.x, global_position.z - before.z).length() / maxf(delta, 0.001)
		speed = signf(speed) * minf(absf(speed), realized + 0.08)
	left_track_speed = speed - yaw_rate * 1.8
	right_track_speed = speed + yaw_rate * 1.8
	visual.animate_tracks(left_track_speed, right_track_speed, delta, ground_offsets)
	if global_position.y < -12 or global_position.length() > 400:
		reset_vehicle()

func _update_ground(delta: float) -> void:
	var normal_sum := Vector3.ZERO
	var heights: Array[float] = []
	contact_count = 0
	ground_offsets.clear()
	for point in [Vector3(-1.2, 1.5, -1.8), Vector3(1.2, 1.5, -1.8), Vector3(-1.2, 1.5, 1.8), Vector3(1.2, 1.5, 1.8)]:
		var origin: Vector3 = global_transform * point
		var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 4.3, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
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
		var pitch := atan2((heights[0] + heights[1] - heights[2] - heights[3]) * 0.5, 3.6)
		var roll := atan2((heights[1] + heights[3] - heights[0] - heights[2]) * 0.5, 2.4)
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
	var pivot := visual.turret.global_position
	var direction := aim_point - pivot
	var local_direction := visual.global_basis.inverse() * direction
	var target_yaw := atan2(-local_direction.x, -local_direction.z)
	visual.turret.rotation.y = rotate_toward(visual.turret.rotation.y, target_yaw, TURRET_RATE * delta)
	var local_barrel := visual.turret.global_basis.orthonormalized().inverse() * (aim_point - visual.barrel.global_position)
	var horizontal := Vector2(local_barrel.x, local_barrel.z).length()
	# Low ballistic arc; finite elevation/depression like a real tank.
	var v2 := SHELL_SPEED * SHELL_SPEED
	var discriminant := v2 * v2 - SHELL_GRAVITY * (SHELL_GRAVITY * horizontal * horizontal + 2.0 * local_barrel.y * v2)
	var elevation := atan2(local_barrel.y, horizontal)
	if horizontal > 1.0 and discriminant >= 0.0:
		elevation = atan((v2 - sqrt(discriminant)) / (SHELL_GRAVITY * horizontal))
	elevation = clampf(elevation, deg_to_rad(-9), deg_to_rad(23))
	visual.barrel.rotation.x = move_toward(visual.barrel.rotation.x, elevation, ELEVATION_RATE * delta)
	var breech := visual.barrel.global_position
	var query := PhysicsRayQueryParameters3D.create(breech, visual.muzzle.global_position + muzzle_direction() * 0.2, 1)
	query.hit_from_inside = true
	muzzle_obstructed = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func muzzle_direction() -> Vector3:
	return -visual.muzzle.global_basis.z.normalized()

func can_fire() -> bool:
	return reload_remaining <= 0 and not muzzle_obstructed

func begin_fire() -> bool:
	if not can_fire():
		return false
	reload_remaining = RELOAD_TIME
	rounds_fired += 1
	recoil = 1.0
	return true

func reset_vehicle() -> void:
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
	reload_remaining = 0.0
