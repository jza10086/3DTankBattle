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

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	tank = game.tank
	tank.controls_enabled = false
	await _frames(60)
	_check(game.targets.size() == 6, "Six target stations created")
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

	# Fire at station 02. Real swept ballistic shells must hit twice with reload.
	await _rest()
	var target: RangeTarget = game.targets[1]
	tank.aim_point = target.global_position + Vector3(0, 2.55, 0)
	await _frames(240)
	var expected := (tank.aim_point - tank.visual.turret.global_position).normalized()
	var muzzle := tank.muzzle_direction()
	_check(Vector2(muzzle.x, muzzle.z).normalized().dot(Vector2(expected.x, expected.z).normalized()) > 0.999, "Turret converges to world aim point")
	game._predict_impact()
	_check(game.actual_hit_target and game.actual_impact.distance_to(tank.aim_point) < 0.35, "Predicted muzzle trajectory hits requested station", str(game.actual_impact))
	_check(game.fire(), "Ready cannon fires")
	_check(not game.fire(), "Reload prevents immediate second shot")
	await _frames(90)
	_check(target.hit_points == 1 and not target.dead and game.hits == 1, "Real shell damages station 02 once", "HP=%d hits=%d" % [target.hit_points, game.hits])
	await _frames(130)
	_check(tank.can_fire(), "Cannon reload completes")
	_check(game.fire(), "Reloaded cannon fires")
	await _frames(100)
	_check(target.dead and game.destroyed_count == 1 and game.hits == 2, "Second shell destroys target and scores", "destroyed=%d hits=%d" % [game.destroyed_count, game.hits])

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
		fresh = fresh and not station.dead and station.hit_points == 2
	_check(fresh and game.destroyed_count == 0 and game.hits == 0 and tank.rounds_fired == 0, "Restart restores all targets and counters")
	_check(get_nodes_in_group("shells").is_empty(), "Restart clears active shells")
	# Exercise the entire six-station completion state through the normal target
	# damage/signal path (actual shell damage was exercised above).
	for station in game.targets:
		station.damage(1.0)
		station.damage(1.0)
	_check(game.destroyed_count == game.total_targets and game.notice == "RANGE CLEAR — EXCELLENT SHOOTING", "All six stations trigger range-clear result")
	game.set_physics_process(true)
	var finish_time: float = game.elapsed
	await _frames(30)
	_check(is_equal_approx(game.elapsed, finish_time), "Completed range freezes the completion timer")
	game.reset_range()
	await _frames(5)
	_check(game.destroyed_count == 0 and game.targets.size() == 6 and game.targets.all(func(station): return not station.dead and station.hit_points == 2), "Restart after full completion restores a playable fresh range")
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
