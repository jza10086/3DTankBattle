extends SceneTree
## Focused gameplay integration checks. Uses real scene, physics, raycasts and shells.
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/range_test.gd

var game: Node3D
var tank: TankController
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		passed += 1
		print("PASS  ", label, "  ", detail)
	else:
		failed += 1
		push_error("FAIL  " + label + "  " + detail)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame

func _rest() -> void:
	tank.reset_vehicle()
	tank.controls_enabled = false
	tank.throttle = 0
	tank.steering = 0
	tank.brake = false
	await _frames(45)

func _press(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	game._unhandled_input(event)

func _ballistic_miss(point: Vector3) -> float:
	# Tank-shaped colliders intercept before their aim center; measure mathematical
	# convergence at the aim plane separately from collision/prediction checks.
	var origin := tank.visual.muzzle.global_position
	var direction := tank.muzzle_direction()
	var horizontal_distance := Vector2(point.x - origin.x, point.z - origin.z).length()
	var horizontal_speed := Vector2(direction.x, direction.z).length() * TankController.SHELL_SPEED
	var flight_time := horizontal_distance / maxf(horizontal_speed, 0.001)
	var at_plane := origin + direction * TankController.SHELL_SPEED * flight_time + Vector3.DOWN * TankController.SHELL_GRAVITY * flight_time * flight_time * 0.5
	return at_plane.distance_to(point)

func _rendered_geometry_count(node: Node) -> int:
	var count := 0
	if node is GeometryInstance3D and node.is_visible_in_tree() and (node.layers & game.camera.cull_mask) != 0:
		count += 1
	for child in node.get_children():
		count += _rendered_geometry_count(child)
	return count

func _check_sight() -> void:
	await _rest()
	game.start_game()
	tank.controls_enabled = false
	game.set_physics_process(true)
	await _frames(30)
	var own_geometry_before := _rendered_geometry_count(tank.visual)
	_press(KEY_SHIFT)
	await _frames(20)
	_check(game.first_person and tank.aim_direction_mode and own_geometry_before > 0 and _rendered_geometry_count(tank.visual) == 0, "Shift enters first-person and hides only the own-tank render")
	var query := PhysicsRayQueryParameters3D.create(tank.global_position + Vector3.UP * 8, tank.global_position + Vector3.DOWN * 2, 2)
	var chassis_hit := game.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not chassis_hit.is_empty() and chassis_hit.collider == tank and _rendered_geometry_count(game.targets[0]) > 0, "Gunsight preserves player collision and visible target models")
	_check((-game.camera.global_basis.z).dot(tank.muzzle_direction()) > 0.99999 and game.camera.global_position.distance_to(tank.visual.barrel.global_position) < 0.4, "First-person camera is bore-aligned at the breech sight mount")
	var previous_yaw: float = tank.visual.turret.rotation.y
	game.capture_guard = 0
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(320, -30)
	game._unhandled_input(mouse)
	await _frames(1)
	var first_step := absf(angle_difference(previous_yaw, tank.visual.turret.rotation.y))
	_check(first_step > 0 and first_step <= TankController.TURRET_RATE / 60.0 * 1.1, "Scoped mouse input slews the real turret within its rate limit")
	await _frames(120)
	_check(absf(angle_difference(previous_yaw, tank.visual.turret.rotation.y)) > 0.3 and tank.muzzle_direction().dot(tank.requested_gun_direction) > 0.9999, "Scoped mouse command converges to the actual gun direction")
	var stable_direction := tank.muzzle_direction()
	var stable_yaw: float = game.camera_yaw
	var stable_pitch: float = game.camera_pitch
	await _frames(240)
	_check(tank.muzzle_direction().distance_to(stable_direction) < 0.0001 and is_equal_approx(game.camera_yaw, stable_yaw) and is_equal_approx(game.camera_pitch, stable_pitch), "No-input gunsight stays stable without camera / ballistics feedback drift")
	_check((-game.camera.global_basis.z).dot(tank.muzzle_direction()) > 0.99999, "Sight camera remains synchronized after turret movement")
	var zoom := InputEventMouseButton.new()
	zoom.button_index = MOUSE_BUTTON_RIGHT
	zoom.pressed = true
	Input.parse_input_event(zoom)
	await _frames(5)
	_check(game.zooming and is_equal_approx(game.camera.fov, 16.0), "Held RMB magnifies the first-person sight")
	zoom = InputEventMouseButton.new()
	zoom.button_index = MOUSE_BUTTON_RIGHT
	zoom.pressed = false
	Input.parse_input_event(zoom)
	await _frames(5)
	_check(not game.zooming and is_equal_approx(game.camera.fov, 32.0), "Releasing RMB restores normal sight magnification")
	# Starting inside close cover is as unsafe as intersecting it ahead.
	var cover := StaticBody3D.new()
	cover.collision_layer = 1
	cover.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.8, 2.0)
	collision.shape = box
	cover.add_child(collision)
	game.add_child(cover)
	cover.global_position = tank.visual.barrel.global_position
	await _frames(5)
	var rounds_before := tank.rounds_fired
	_check(tank.muzzle_obstructed and not game.fire() and tank.rounds_fired == rounds_before, "First-person cannot fire while breech is inside cover")
	cover.queue_free()
	await _frames(5)
	_check(not tank.muzzle_obstructed, "Removing sight obstruction restores muzzle clearance")
	_press(KEY_ESCAPE)
	var paused_direction := tank.muzzle_direction()
	_press(KEY_SHIFT)
	await _frames(15)
	_check(game.paused and game.first_person and _rendered_geometry_count(tank.visual) == 0 and tank.muzzle_direction().is_equal_approx(paused_direction), "Pause preserves sight mode; Shift is ignored while paused")
	_press(KEY_ENTER)
	tank.controls_enabled = false
	await _frames(20)
	_check(not paused and game.first_person and tank.aim_direction_mode, "Resume retains a coherent first-person sight")
	_press(KEY_SHIFT)
	await _frames(5)
	_check(not game.first_person and not tank.aim_direction_mode and _rendered_geometry_count(tank.visual) == own_geometry_before, "Shift returns to third person and restores tank visuals")
	_press(KEY_SHIFT)
	_press(KEY_F)
	await _frames(20)
	_check(game.first_person and tank.aim_direction_mode and _rendered_geometry_count(tank.visual) == 0 and tank.position.distance_to(tank.start_transform.origin) < 0.3, "Vehicle recovery remains coherent while scoped")
	_press(KEY_R)
	await _frames(5)
	_check(not game.first_person and not tank.aim_direction_mode and _rendered_geometry_count(tank.visual) == own_geometry_before and game.destroyed_count == 0, "Range restart exits sight and restores the visible vehicle")
	game.set_physics_process(false)
	tank.controls_enabled = false

func _check_armor_rules() -> void:
	var armor = load("res://scripts/armor_damage.gd")
	var front: Dictionary = armor.evaluate(&"hull", Basis.IDENTITY, Vector3.FORWARD, Vector3.BACK)
	var side: Dictionary = armor.evaluate(&"hull", Basis.IDENTITY, Vector3.RIGHT, Vector3.LEFT)
	var rear: Dictionary = armor.evaluate(&"hull", Basis.IDENTITY, Vector3.BACK, Vector3.FORWARD)
	_check(front.damage > 0 and front.damage < side.damage and side.damage < rear.damage, "Hull front / side / rear have distinct damage", "%.1f / %.1f / %.1f" % [front.damage, side.damage, rear.damage])
	var oblique_incoming := Vector3(sin(deg_to_rad(60)), 0, cos(deg_to_rad(60)))
	var oblique: Dictionary = armor.evaluate(&"hull", Basis.IDENTITY, Vector3.FORWARD, oblique_incoming)
	_check(oblique.damage > 0 and oblique.damage < front.damage and absf(oblique.angle_degrees - 60) < 0.01, "Oblique armor impact reduces damage", "damage=%.1f angle=%.1f" % [oblique.damage, oblique.angle_degrees])
	var grazing_incoming := Vector3(sin(deg_to_rad(80)), 0, cos(deg_to_rad(80)))
	var grazing: Dictionary = armor.evaluate(&"hull", Basis.IDENTITY, Vector3.FORWARD, grazing_incoming)
	_check(grazing.ricochet and grazing.damage == 0, "Grazing hit ricochets without HP damage")
	var rotated := Basis(Vector3.UP, 1.2)
	var rotated_side: Dictionary = armor.evaluate(&"hull", rotated, rotated * Vector3.RIGHT, rotated * Vector3.LEFT)
	_check(is_equal_approx(rotated_side.damage, side.damage) and rotated_side.region == side.region, "Rotated hull preserves local armor classification")
	var turret: Dictionary = armor.evaluate(&"turret", Basis.IDENTITY, Vector3.FORWARD, Vector3.BACK)
	var track: Dictionary = armor.evaluate(&"track", Basis.IDENTITY, Vector3.RIGHT, Vector3.LEFT)
	_check(turret.region.begins_with("TURRET") and track.region.begins_with("TRACK") and turret.damage != front.damage and track.damage != side.damage, "Turret and track hit regions use separate damage rules")

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	tank = game.tank
	tank.controls_enabled = false
	await _frames(60)
	_check(game.targets.size() == 6, "Six target stations created")
	_check_armor_rules()
	_check(tank.is_on_floor() and tank.contact_count == 4, "Grounded four-contact spawn", "y=%.3f" % tank.position.y)

	# Forward / brake / reverse are actual kinematic physics, not isolated math.
	var start_z := tank.position.z
	tank.throttle = 1
	await _frames(120)
	_check(tank.speed > 7.5 and tank.position.z < start_z - 7.0, "Forward acceleration", "speed=%.2f distance=%.2f" % [tank.speed, start_z - tank.position.z])
	var fast_speed := tank.speed
	tank.brake = true
	await _frames(20)
	_check(tank.speed < fast_speed - 3.0, "Service brake decelerates", "%.2f -> %.2f" % [fast_speed, tank.speed])
	await _frames(40)
	_check(absf(tank.speed) < 0.05, "Brake reaches rest")
	tank.brake = false
	tank.throttle = -1
	start_z = tank.position.z
	await _frames(90)
	_check(tank.speed < -5.0 and tank.position.z > start_z + 3.0, "Reverse acceleration", "speed=%.2f distance=%.2f" % [tank.speed, tank.position.z - start_z])

	await _rest()
	var pivot_start := tank.position
	tank.steering = 1
	await _frames(120)
	_check(absf(tank.rotation.y) > 1.5 and tank.position.distance_to(pivot_start) < 0.2, "Stationary differential pivot", "yaw=%.2f" % tank.rotation.y)
	_check(tank.left_track_speed < -1.0 and tank.right_track_speed > 1.0, "Tracks counter-rotate during pivot")

	# Recovery is the same method invoked by the F key.
	tank.velocity = Vector3(8, -3, 2)
	tank.reload_remaining = 2
	tank.visual.turret.rotation.y = 1.1
	tank.visual.barrel.rotation.x = 0.2
	tank.reset_vehicle()
	_check(tank.global_transform.is_equal_approx(tank.start_transform) and tank.speed == 0.0 and tank.velocity == Vector3.ZERO and tank.yaw_rate == 0.0, "F recovery restores transform and motion")
	_check(tank.visual.turret.rotation.is_zero_approx() and tank.visual.barrel.rotation.is_zero_approx() and tank.reload_remaining == 0.0, "F recovery clears aim and reload")

	# Traverse the real western ramp, retaining contact and visual slope response.
	await _rest()
	tank.position = Vector3(-43, 0.8, 12)
	await _frames(40)
	tank.throttle = 1
	var max_height := tank.position.y
	var max_pitch := 0.0
	var min_contacts := 4
	for i in 200:
		await physics_frame
		max_height = maxf(max_height, tank.position.y)
		max_pitch = maxf(max_pitch, absf(tank.hull_pitch))
		min_contacts = mini(min_contacts, tank.contact_count)
	await process_frame
	_check(max_height > 3.0 and tank.position.z < -7, "Climbs physical ramp", "height=%.2f z=%.2f" % [max_height, tank.position.z])
	_check(max_pitch > 0.10 and min_contacts >= 3 and tank.is_on_floor(), "Ramp suspension tilts and remains grounded", "pitch=%.3f minimum_contacts=%d" % [max_pitch, min_contacts])

	# Real transverse slope regression: +Z rotation raises the ground on +X.
	# The rendered right track must follow it upward, not tilt into the ramp.
	await _rest()
	var cross_slope := StaticBody3D.new()
	cross_slope.collision_layer = 1
	cross_slope.collision_mask = 0
	var slope_collision := CollisionShape3D.new()
	var slope_box := BoxShape3D.new()
	slope_box.size = Vector3(12, 1, 12)
	slope_collision.shape = slope_box
	cross_slope.add_child(slope_collision)
	game.add_child(cross_slope)
	cross_slope.global_position = Vector3(-90, 2, 0)
	cross_slope.rotation.z = 0.16
	tank.position = Vector3(-90, 3.6, 0)
	await _frames(70)
	_check(tank.contact_count == 4 and tank.visual.global_basis.x.y > 0.10, "Cross-slope raises the correct side of the hull", "ground_right_y=%.3f hull_right_y=%.3f contacts=%d" % [cross_slope.global_basis.x.y, tank.visual.global_basis.x.y, tank.contact_count])
	cross_slope.queue_free()
	await _frames(2)

	# Slew limits are sampled one physics step at a time before convergence.
	await _rest()
	tank.aim_point = tank.visual.turret.global_position + Vector3(100, 90, 0)
	var previous_yaw := tank.visual.turret.rotation.y
	var previous_pitch := tank.visual.barrel.rotation.x
	await _frames(1)
	var yaw_step := absf(angle_difference(previous_yaw, tank.visual.turret.rotation.y))
	var pitch_step := absf(tank.visual.barrel.rotation.x - previous_pitch)
	_check(yaw_step > 0 and yaw_step <= TankController.TURRET_RATE / 60.0 * 1.1, "Turret slew rate bounded", "step=%.5f" % yaw_step)
	_check(pitch_step > 0 and pitch_step <= TankController.ELEVATION_RATE / 60.0 * 1.1, "Barrel elevation rate bounded", "step=%.5f" % pitch_step)
	await _frames(190)
	_check(tank.visual.barrel.rotation.x <= deg_to_rad(23.01), "Elevation limit respected")
	tank.aim_point = tank.visual.turret.global_position + Vector3(30, -100, 0)
	await _frames(110)
	_check(tank.visual.barrel.rotation.x >= deg_to_rad(-9.01), "Depression limit respected")

	# Real swept ballistic shells damage a rotated 100-HP tank, not a plate.
	await _rest()
	var target: RangeTarget = game.targets[1]
	tank.aim_point = target.get_aim_point()
	await _frames(240)
	var expected := (tank.aim_point - tank.visual.turret.global_position).normalized()
	var muzzle := tank.muzzle_direction()
	_check(Vector2(muzzle.x, muzzle.z).normalized().dot(Vector2(expected.x, expected.z).normalized()) > 0.999, "Turret converges to world aim point")
	_check(_ballistic_miss(tank.aim_point) < 0.35, "Ballistic aim converges within 35 cm at the aim plane", "miss=%.3f m" % _ballistic_miss(tank.aim_point))
	game._predict_impact()
	_check(game.actual_hit_target and game.actual_impact.distance_to(target.global_position) < 5.0, "Predicted muzzle trajectory hits rotated tank 02", str(game.actual_impact))
	_check(is_equal_approx(target.max_hp, 100.0) and absf(target.rotation.y) > 0.1, "Targets use 100 HP and distinct hull orientation")
	_check(game.fire(), "Ready cannon fires")
	_check(not game.fire(), "Reload prevents immediate second shot")
	await _frames(90)
	_check(target.hp > 0 and target.hp < target.max_hp and not target.dead and game.hits == 1, "Real shell applies nonlethal armor damage", "HP=%.1f hits=%d" % [target.hp, game.hits])
	var impact_result: Dictionary = game.last_hit_result
	_check(not impact_result.is_empty() and is_equal_approx(float(impact_result.damage), target.max_hp - target.hp) and is_equal_approx(float(impact_result.hp), target.hp) and float(impact_result.angle_degrees) >= 0 and float(impact_result.angle_degrees) < 75 and not String(impact_result.region).is_empty(), "Real contact reports region, incidence and matching HP loss", "%s / %.1f degrees" % [impact_result.region, impact_result.angle_degrees])
	await _frames(130)
	_check(tank.can_fire(), "Cannon reload completes")
	var shots := 1
	while not target.dead and shots < 8:
		var previous_hp: float = target.hp
		_check(game.fire(), "Reloaded cannon fires shot %d" % (shots + 1))
		shots += 1
		await _frames(220)
		_check(target.hp < previous_hp, "Real shell reduces remaining armor HP", "%.1f -> %.1f" % [previous_hp, target.hp])
	_check(target.dead and target.hp == 0 and game.destroyed_count == 1 and game.hits == shots, "Real shells destroy rotated target and score once", "shots=%d destroyed=%d hits=%d" % [shots, game.destroyed_count, game.hits])
	game._predict_impact()
	_check(not game.actual_hit_target and game.actual_impact.distance_to(target.global_position) < 5.0 and (target.collision_layer & 1) != 0, "Destroyed tank remains physical ballistic cover, not an active target")
	_check(game.fire(), "Can fire a verification shell into the wreck")
	await _frames(220)
	_check(target.hp == 0 and game.destroyed_count == 1 and game.hits == shots, "A real shell hitting a wreck cannot add damage or score")

	# Close solid geometry across the breech-to-muzzle ray must block firing.
	await _rest()
	tank.aim_point = Vector3(0, 2.5, -100)
	await _frames(70)
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 0.3)
	shape.shape = box
	blocker.add_child(shape)
	game.add_child(blocker)
	blocker.global_position = tank.visual.barrel.global_position.lerp(tank.visual.muzzle.global_position, 0.68)
	await _frames(5)
	var rounds_before := tank.rounds_fired
	_check(tank.muzzle_obstructed and not game.fire() and tank.rounds_fired == rounds_before, "Close cover blocks cannon without consuming a round")
	blocker.queue_free()
	await _frames(5)
	_check(not tank.muzzle_obstructed and tank.can_fire(), "Clearing cover restores firing")

	await _check_sight()

	# Escape uses the real input handler: tank, shells and timers all freeze.
	await _rest()
	game.start_game()
	tank.controls_enabled = false
	tank.throttle = 1
	tank.aim_point = tank.position + Vector3(0, 80, -100)
	await _frames(80)
	game.fire()
	await _frames(1)
	var pause_shell: Node3D = get_nodes_in_group("shells")[0]
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	game._unhandled_input(escape)
	game.set_physics_process(true)
	var paused_tank_position := tank.global_position
	var paused_shell_position := pause_shell.global_position
	var paused_reload := tank.reload_remaining
	var paused_elapsed: float = game.elapsed
	await _frames(35)
	_check(paused and game.paused and tank.global_position.is_equal_approx(paused_tank_position), "Escape pauses vehicle physics")
	_check(pause_shell.global_position.is_equal_approx(paused_shell_position) and is_equal_approx(tank.reload_remaining, paused_reload) and is_equal_approx(game.elapsed, paused_elapsed), "Pause freezes shells, reload and course timer")
	game._unhandled_input(escape)
	game.set_physics_process(false)
	tank.controls_enabled = false
	tank.throttle = 0
	await _frames(10)
	_check(not paused and not game.paused and pause_shell.global_position.distance_to(paused_shell_position) > 1 and tank.reload_remaining < paused_reload, "Escape resumes gameplay without resetting it")

	game.reset_range()
	await _frames(5)
	var fresh: bool = game.targets.size() == 6
	for station in game.targets:
		fresh = fresh and not station.dead and is_equal_approx(station.hp, station.max_hp)
	_check(fresh and game.destroyed_count == 0 and game.hits == 0 and tank.rounds_fired == 0, "Restart restores all targets and counters")
	_check(get_nodes_in_group("shells").is_empty(), "Restart clears active shells")
	# Exercise the entire six-station completion state through the normal target
	# damage/signal path (actual shell damage was exercised above).
	for station in game.targets:
		for hit_index in range(8):
			if station.dead:
				break
			var outward: Vector3 = -station.global_basis.z.normalized()
			station.apply_shell_hit(station.get_aim_point(), outward, -outward)
	_check(game.destroyed_count == game.total_targets and game.notice == "RANGE CLEAR — EXCELLENT SHOOTING", "All six stations trigger range-clear result")
	var dead_target: RangeTarget = game.targets[0]
	var ignored_hit: Dictionary = dead_target.apply_shell_hit(dead_target.get_aim_point(), Vector3.UP, Vector3.DOWN)
	_check(ignored_hit.ignored and dead_target.hp == 0 and game.destroyed_count == game.total_targets, "Destroyed tanks ignore repeated damage and cannot score twice")
	game.set_physics_process(true)
	var finish_time: float = game.elapsed
	await _frames(30)
	_check(is_equal_approx(game.elapsed, finish_time), "Completed range freezes the completion timer")
	game.reset_range()
	await _frames(5)
	_check(game.destroyed_count == 0 and game.targets.size() == 6 and game.targets.all(func(station): return not station.dead and is_equal_approx(station.hp, station.max_hp)), "Restart after full completion restores a playable fresh range")
	print("\nIRON RANGE INTEGRATION: %d passed, %d failed" % [passed, failed])
	# Dummy audio runs on its own thread even with --fixed-fps. Drain playback
	# before freeing the scene, rather than misreporting audio teardown as a leak.
	for player in [game.engine_audio, game.cannon_audio, game.impact_audio]:
		player.stop()
		player.stream = null
	await _frames(5)
	OS.delay_msec(80)
	game.queue_free()
	await process_frame
	quit(0 if failed == 0 else 1)
