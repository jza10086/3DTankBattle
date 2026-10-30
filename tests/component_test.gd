extends SceneTree
## Focused component clocks, real mesh contacts and live controller constraints.
const Status = preload("res://scripts/component_status.gd")
const Target = preload("res://scripts/range_target.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS  ", label)
	else:
		failed += 1
		push_error("FAIL  " + label)

func frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame

func contact(target, from_local: Vector3, to_local: Vector3) -> Dictionary:
	var start: Vector3 = target.global_transform * from_local
	var end: Vector3 = target.global_transform * to_local
	var hit: Dictionary = target.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, end, 1))
	if hit.is_empty() or hit.collider != target:
		return {}
	return target.apply_shell_hit(hit.position, hit.normal, (end - start).normalized(), int(hit.shape))

func run() -> void:
	var state = Status.new()
	state.apply_component(&"engine")
	state.tick(1.5)
	state.apply_component(&"engine")
	check(is_equal_approx(state.engine_remaining, 4.0) and state.get_track_multipliers() == Vector2.ZERO, "Engine refresh is bounded to four seconds and blocks both tracks")
	state.tick(4.0)
	check(state.get_track_multipliers() == Vector2.ONE, "Engine expires exactly and restores healthy mobility")
	state.apply_component(&"left_track")
	check(state.get_track_multipliers() == Vector2(0.25, 1.0), "Left track damage affects only left drive factor")
	state.apply_component(&"right_track")
	check(state.get_track_multipliers() == Vector2(0.25, 0.25), "Both tracks combine without permanently locking motion")
	state.tick(5.0)
	check(state.get_track_multipliers() == Vector2.ONE, "Track repairs expire at five seconds")
	check(state.begin_fire(), "Healthy loaded gun fires")
	state.tick(1.0)
	state.apply_component(&"barrel")
	state.tick(3.9)
	check(not state.can_fire() and is_equal_approx(state.reload_remaining, 3.2), "Barrel damage cancels reload progress and holds the full reload during repair")
	state.tick(0.2)
	check(is_zero_approx(state.barrel_remaining) and absf(state.reload_remaining - 3.1) < 0.0001, "Repair boundary consumes only the leftover frame time for reload")
	state.tick(3.1)
	check(state.can_fire(), "Full post-repair reload restores firing")
	state.apply_component(&"barrel")
	state.tick(2.0)
	state.apply_component(&"barrel")
	check(is_equal_approx(state.barrel_remaining, 4.0), "Repeated barrel hits refresh rather than add repair durations")
	state.clear()
	check(state.can_fire() and state.get_track_multipliers() == Vector2.ONE, "Clear removes all component and reload state")

	# Actual convex mesh shape IDs, with a rotated target, not guessed model names.
	var fixture := Node3D.new()
	root.add_child(fixture)
	var target = Target.new()
	target.rotation.y = 1.13
	target.max_hp = 1000
	fixture.add_child(target)
	await frames(2)
	var left := contact(target, Vector3(-6, 0.45, 0), Vector3(0, 0.45, 0))
	var right := contact(target, Vector3(6, 0.45, 0), Vector3(0, 0.45, 0))
	check(left.get("component") == "left_track" and right.get("component") == "right_track", "Rotated real left/right tread collisions select the correct side")
	var shell = load("res://scripts/shell.gd").new()
	fixture.add_child(shell)
	shell.global_position = target.to_global(Vector3(-6, 0.45, 0))
	shell.velocity = target.global_basis * Vector3.RIGHT * 105.0
	await frames(10)
	check(target.last_hit_result.get("component", "") == "left_track" and target.components.left_track_remaining > 4.7, "Actual swept projectile carries shape metadata through to track incapacitation")
	var rear := contact(target, Vector3(0, 0.85, 8), Vector3(0, 0.85, 0))
	check(rear.get("component") == "engine" and target.components.engine_remaining > 3.9, "Actual rear hull contact inside engine compartment disables engine")
	var front := contact(target, Vector3(0, 0.85, -8), Vector3(0, 0.85, 0))
	check(front.get("component", "") == "", "Frontal hull contact does not fabricate engine damage")
	var barrel_mesh := target.find_child("BarrelMesh", true, false) as MeshInstance3D
	var barrel_center: Vector3 = target.to_local(barrel_mesh.to_global(barrel_mesh.mesh.get_aabb().get_center()))
	var barrel := contact(target, barrel_center + Vector3(0, 0, -10), barrel_center)
	check(barrel.get("component") == "barrel" and barrel.get("damage", 100) <= 8 and not target.components.can_fire(), "Real muzzle contact uses low barrel damage and blocks target gun state")
	var hp_before: float = target.hp
	var query := PhysicsRayQueryParameters3D.create(target.to_global(Vector3(-6, 0.45, 0)), target.to_global(Vector3.ZERO + Vector3.UP * 0.45), 1)
	var grazing_hit: Dictionary = target.get_world_3d().direct_space_state.intersect_ray(query)
	target.components.clear()
	var tangent: Vector3 = grazing_hit.normal.cross(Vector3.UP).normalized()
	var glance: Dictionary = target.apply_shell_hit(grazing_hit.position, grazing_hit.normal, tangent, int(grazing_hit.shape))
	check(glance.ricochet and glance.get("component", "") == "" and target.hp == hp_before and target.components.get_track_multipliers() == Vector2.ONE, "Ricochet cannot damage HP or disable a component")
	target.components.apply_component(&"engine")
	target.damage(10000)
	check(target.dead and target.components.engine_remaining == 0 and target.components.barrel_remaining == 0, "Death clears repair clocks and leaves no recovering wreck")
	fixture.queue_free()
	await frames(2)

	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await frames(2)
	game.start_game()
	game.set_physics_process(false)
	var tank = game.tank
	tank.controls_enabled = false
	tank.brake = false
	tank.throttle = 1.0
	await frames(90)
	var healthy_speed: float = tank.speed
	tank.apply_component_hit(&"engine")
	var stopped_at: Vector3 = tank.global_position
	tank.steering = 1.0
	await frames(60)
	check(absf(tank.speed) < 0.001 and absf(tank.yaw_rate) < 0.001 and Vector2(tank.position.x - stopped_at.x, tank.position.z - stopped_at.z).length() < 0.02, "Real controller engine outage prevents driving and pivot, not gravity")
	await frames(190)
	check(tank.speed > 0.1, "Controller resumes responding to held drive after engine repairs")
	tank.reset_vehicle()
	tank.controls_enabled = false
	tank.brake = false
	tank.throttle = 1.0
	tank.apply_component_hit(&"left_track")
	await frames(90)
	var left_yaw: float = tank.yaw_rate
	check(tank.speed > 0 and tank.speed < healthy_speed and absf(left_yaw) > 0.02, "Left track damage actually slows the controller and creates asymmetric pull")
	tank.reset_vehicle()
	tank.controls_enabled = false
	tank.brake = false
	tank.throttle = 1.0
	tank.apply_component_hit(&"right_track")
	await frames(90)
	check(tank.yaw_rate * left_yaw < 0, "Right track damage mirrors the steering pull")
	tank.begin_fire()
	tank.reload_remaining = 0.7
	tank.apply_component_hit(&"barrel")
	await frames(60)
	check(not tank.can_fire() and not game.fire() and is_equal_approx(tank.reload_remaining, 3.2), "Player barrel outage blocks actual fire and discards partial reload")
	var remaining: float = tank.components.barrel_remaining
	var enemy = game.targets[0]
	enemy.components.apply_component(&"engine")
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	game._unhandled_input(event)
	await frames(60)
	check(is_equal_approx(tank.components.barrel_remaining, remaining) and is_equal_approx(enemy.components.engine_remaining, 4.0), "Pause freezes player and target repair clocks")
	game.start_game()
	tank.controls_enabled = false
	tank.brake = false
	await frames(190)
	check(tank.components.barrel_remaining == 0 and tank.reload_remaining > 2.9 and not tank.can_fire(), "Player repair completion starts a full fresh reload")
	# The user-facing panel dispatches the same real status methods as contacts.
	event.keycode = KEY_F3
	game._unhandled_input(event)
	check(game.component_panel_open and game.component_panel.visible and not paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "F3 opens a clickable panel without pausing simulation")
	game.component_panel.buttons[&"engine"].pressed.emit()
	await frames(30)
	check(tank.components.engine_remaining > 3.4 and tank.components.engine_remaining < 3.6, "Panel engine button applies a live, ticking player impairment")
	var shots_before: int = tank.rounds_fired
	var yaw_before: float = game.camera_yaw
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(400, 0)
	game._unhandled_input(mouse)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	game._unhandled_input(click)
	check(not game.fire() and tank.rounds_fired == shots_before and is_equal_approx(game.camera_yaw, yaw_before), "Open panel blocks cannon click-through and unintended mouse aiming")
	event.keycode = KEY_SHIFT
	game._unhandled_input(event)
	game.component_panel.buttons[&"barrel"].pressed.emit()
	check(game.first_person and not tank.visual.visible and tank.components.barrel_remaining == 4.0, "Panel remains functional in Shift gunsight view")
	enemy.components.apply_component(&"engine")
	game.component_panel.buttons[&"clear"].pressed.emit()
	check(tank.components.can_fire() and tank.components.engine_remaining == 0 and enemy.components.engine_remaining == 4.0, "Clear button restores only player effects and reload")
	game.component_panel.buttons[&"close"].pressed.emit()
	check(not game.component_panel_open and not game.component_panel.visible and tank.controls_enabled, "Close restores driving controls (mouse capture checked in native GUI)")
	game.set_component_panel(true)
	game.reset_range()
	await frames(2)
	check(not game.component_panel_open and tank.components.can_fire() and game.targets.all(func(t): return t.components.get_track_multipliers() == Vector2.ONE and t.components.can_fire()), "Range reset clears player and all target component states")
	for audio in [game.engine_audio, game.cannon_audio, game.impact_audio]:
		audio.stop()
		audio.stream = null
	await process_frame
	OS.delay_msec(100)
	print("\nCOMPONENT TESTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
