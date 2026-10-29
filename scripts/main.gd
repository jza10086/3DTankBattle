extends Node3D

const TankScript = preload("res://scripts/tank_controller.gd")
const WorldScript = preload("res://scripts/range_world.gd")
const HudScript = preload("res://scripts/range_hud.gd")
const TargetScript = preload("res://scripts/range_target.gd")
const ShellScript = preload("res://scripts/shell.gd")
var tank: TankController
var world: Node3D
var camera: Camera3D
var hud: Control
var targets: Array[RangeTarget] = []
var camera_yaw := 0.0
var camera_pitch := -0.023
var camera_position := Vector3.ZERO
var started := false
var paused := false
var zooming := false
var destroyed_count := 0
var total_targets := 6
var elapsed := 0.0
var hits := 0
var hit_flash := 0.0
var shot_shake := 0.0
var actual_impact := Vector3.ZERO
var actual_hit_target := false
var trajectory_timer := 0.0
var notice := ""
var notice_time := 0.0
var effects: Array[Dictionary] = []
var engine_audio: AudioStreamPlayer
var cannon_audio: AudioStreamPlayer
var impact_audio: AudioStreamPlayer
var capture_mode := false
var capture_guard := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_seed_environment()
	world = WorldScript.new()
	add_child(world)
	tank = TankScript.new()
	tank.process_mode = Node.PROCESS_MODE_PAUSABLE
	tank.position = Vector3(0, 0.8, 18)
	add_child(tank)
	tank.controls_enabled = false
	camera = Camera3D.new()
	camera.fov = 67
	camera.far = 800
	camera.near = 0.12
	add_child(camera)
	camera.current = true
	_create_targets()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = HudScript.new()
	hud.game = self
	canvas.add_child(hud)
	_make_audio()
	camera_position = tank.global_position + Vector3(0, 6.5, 13)
	_update_camera(1.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if "--autostart" in OS.get_cmdline_user_args():
		start_game()

func _seed_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = Color("6b9ca6")
	material.sky_horizon_color = Color("dddfc8")
	material.ground_bottom_color = Color("a08d68")
	material.ground_horizon_color = Color("dddfc8")
	material.sky_curve = 0.3
	sky.sky_material = material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b5cad0")
	env.ambient_light_energy = 0.40
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color("d9ceb0")
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.15
	env.fog_light_energy = 0.70
	var environment := WorldEnvironment.new()
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43, -28, 0)
	sun.light_color = Color("ffedc7")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 130
	sun.shadow_bias = 0.07
	add_child(sun)

func _create_targets() -> void:
	for old in targets:
		old.queue_free()
	targets.clear()
	var positions: Array = world.get_target_positions()
	for i in positions.size():
		var target := TargetScript.new()
		target.process_mode = Node.PROCESS_MODE_PAUSABLE
		target.index = i
		target.position = positions[i]
		# Double-sided plates remain hittable from either side of the circuit.
		target.rotation.y = [0.0, -0.3, 0.5, 1.5, -1.2, 0.0][i % 6]
		add_child(target)
		target.destroyed.connect(_target_destroyed)
		targets.append(target)
	total_targets = targets.size()

func _make_audio() -> void:
	engine_audio = AudioStreamPlayer.new()
	engine_audio.stream = load("res://assets/audio/engine.wav")
	engine_audio.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	engine_audio.stream.loop_end = 44100
	engine_audio.volume_db = -22
	add_child(engine_audio)
	engine_audio.play()
	cannon_audio = AudioStreamPlayer.new()
	cannon_audio.stream = load("res://assets/audio/cannon.wav")
	cannon_audio.volume_db = -8
	add_child(cannon_audio)
	impact_audio = AudioStreamPlayer.new()
	impact_audio.stream = load("res://assets/audio/impact.wav")
	impact_audio.volume_db = -14
	add_child(impact_audio)

func start_game() -> void:
	started = true
	paused = false
	get_tree().paused = false
	tank.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	capture_guard = 0.18

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER:
			if not started or paused:
				start_game()
		elif event.keycode == KEY_ESCAPE:
			if started:
				paused = not paused
				get_tree().paused = paused
				tank.controls_enabled = not paused
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
				capture_guard = 0.18 if not paused else 0.0
		elif event.keycode == KEY_R and started:
			reset_range()
		elif event.keycode == KEY_F and started:
			tank.reset_vehicle()
			camera_yaw = 0
			camera_pitch = -0.023
			show_notice("VEHICLE RECOVERED")
		elif event.keycode == KEY_C and started:
			camera_yaw = tank.rotation.y
			camera_pitch = -0.023
	if event is InputEventMouseMotion and started and not paused and capture_guard <= 0:
		var sensitivity := 0.00135 if zooming else 0.0025
		camera_yaw -= event.relative.x * sensitivity
		camera_pitch = clampf(camera_pitch - event.relative.y * sensitivity, -0.58, 0.30)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not started:
			start_game()
		elif not paused:
			fire()

func _physics_process(delta: float) -> void:
	capture_guard = maxf(0, capture_guard - delta)
	if not is_instance_valid(tank):
		return
	if paused:
		engine_audio.volume_db = -40
		hud.queue_redraw()
		return
	if not started or paused:
		tank.throttle = 0
		tank.steering = 0
		tank.brake = true
	if started and not paused and destroyed_count < total_targets:
		elapsed += delta
	zooming = started and not paused and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	_update_camera(delta)
	_update_aim_point()
	trajectory_timer -= delta
	if trajectory_timer <= 0:
		_predict_impact()
		trajectory_timer = 0.06
	hit_flash = maxf(0.0, hit_flash - delta)
	shot_shake = maxf(0.0, shot_shake - delta * 3.0)
	notice_time = maxf(0.0, notice_time - delta)
	_update_effects(delta)
	engine_audio.pitch_scale = lerpf(0.72, 1.65, absf(tank.speed) / TankController.MAX_FORWARD)
	engine_audio.volume_db = -28.0 if paused or not started else lerpf(-24, -16, absf(tank.speed) / TankController.MAX_FORWARD)
	hud.queue_redraw()

func _update_camera(delta: float) -> void:
	var aim_basis := Basis(Vector3.UP, camera_yaw)
	var focus := tank.global_position + Vector3(0, 1.6, 0)
	var distance := 6.2 if zooming else 12.8
	var pitch := camera_pitch
	var offset := aim_basis * Vector3(0, -sin(pitch) * distance + (1.0 if zooming else 1.0), cos(pitch) * distance)
	var desired := focus + offset
	var query := PhysicsRayQueryParameters3D.create(focus, desired, 1)
	var collision := get_world_3d().direct_space_state.intersect_ray(query)
	if not collision.is_empty():
		desired = collision.position + collision.normal * 0.4
	camera_position = camera_position.lerp(desired, 1.0 - exp(-delta * 9.0))
	camera.global_position = camera_position + Vector3(sin(elapsed * 70), cos(elapsed * 90), 0) * shot_shake * 0.07
	var direction := aim_basis * Vector3(0, sin(pitch), -cos(pitch))
	# Orbit camera orientation is input-driven, not auto-centered on the hull.
	camera.look_at(camera.global_position + direction * 200, Vector3.UP)
	camera.fov = lerpf(camera.fov, 32.0 if zooming else 67.0, 1.0 - exp(-delta * 10))

func _update_aim_point() -> void:
	var center := get_viewport().get_visible_rect().size * 0.5
	var origin := camera.project_ray_origin(center)
	var end := origin + camera.project_ray_normal(center) * 500
	var query := PhysicsRayQueryParameters3D.create(origin, end, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	tank.aim_point = end if hit.is_empty() else hit.position

func _predict_impact() -> void:
	var point := tank.visual.muzzle.global_position
	var velocity := tank.muzzle_direction() * TankController.SHELL_SPEED
	actual_hit_target = false
	actual_impact = point + velocity * 3
	# Same integrator/gravity as real shells; sweep each segment to avoid tunneling.
	for i in 130:
		var next := point + velocity * 0.04 + Vector3.DOWN * TankController.SHELL_GRAVITY * 0.0008
		var query := PhysicsRayQueryParameters3D.create(point, next, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			actual_impact = hit.position
			actual_hit_target = hit.collider is RangeTarget
			return
		point = next
		velocity.y -= TankController.SHELL_GRAVITY * 0.04
	actual_impact = point

func fire() -> bool:
	if tank.muzzle_obstructed:
		show_notice("BARREL BLOCKED — MOVE CLEAR")
		return false
	if not tank.begin_fire():
		return false
	var shell := ShellScript.new()
	shell.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(shell)
	shell.global_position = tank.visual.muzzle.global_position
	shell.velocity = tank.muzzle_direction() * TankController.SHELL_SPEED
	shell.impacted.connect(_shell_impact)
	shot_shake = 1.0
	cannon_audio.play()
	_emit_effect(shell.global_position, Color("ffdb7c"), 1.2, 0.12, Vector3.ZERO)
	for i in 7:
		_emit_effect(shell.global_position, Color("d1bd96"), randf_range(0.35, 0.65), randf_range(0.6, 1.0), tank.muzzle_direction() * randf_range(2, 6) + Vector3.UP)
	return true

func _shell_impact(point: Vector3, normal: Vector3, collider: Node) -> void:
	impact_audio.play()
	var target_hit := collider is RangeTarget
	if target_hit:
		hits += 1
		hit_flash = 0.5
		show_notice("TARGET DESTROYED" if collider.dead else "HIT • 1 / 2")
	_emit_effect(point + normal * 0.2, Color("ffca67"), 1.25 if target_hit else 0.8, 0.18, Vector3.ZERO)
	for i in 12:
		var velocity := Vector3(randf_range(-3, 3), randf_range(0.4, 5), randf_range(-3, 3))
		_emit_effect(point, Color("d0b58b") if not target_hit else Color("746e57"), randf_range(0.2, 0.65), randf_range(0.7, 1.5), velocity)

func _emit_effect(at: Vector3, color: Color, size: float, duration: float, velocity: Vector3) -> void:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = size * 0.5
	mesh.height = size
	mesh.radial_segments = 6
	mesh.rings = 3
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	node.material_override = mat
	add_child(node)
	node.global_position = at
	effects.append({"node": node, "life": duration, "total": duration, "velocity": velocity})

func _update_effects(delta: float) -> void:
	for i in range(effects.size() - 1, -1, -1):
		var effect: Dictionary = effects[i]
		effect.life -= delta
		if effect.life <= 0:
			effect.node.queue_free()
			effects.remove_at(i)
			continue
		effect.node.position += effect.velocity * delta
		effect.velocity *= 1.0 - delta * 1.3
		effect.node.scale = Vector3.ONE * (1.0 + (1.0 - effect.life / effect.total) * 1.3) * minf(1.0, effect.life * 5)

func _target_destroyed(_target: RangeTarget) -> void:
	destroyed_count += 1
	if destroyed_count == total_targets:
		show_notice("RANGE CLEAR — EXCELLENT SHOOTING", 6.0)

func show_notice(message: String, duration: float = 2.0) -> void:
	notice = message
	notice_time = duration

func reset_range() -> void:
	for effect in effects:
		effect.node.queue_free()
	effects.clear()
	hit_flash = 0.0
	shot_shake = 0.0
	for shell in get_tree().get_nodes_in_group("shells"):
		shell.queue_free()
	_create_targets()
	tank.reset_vehicle()
	tank.rounds_fired = 0
	destroyed_count = 0
	hits = 0
	elapsed = 0
	camera_yaw = 0
	camera_pitch = -0.023
	show_notice("FRESH RANGE • SIX TARGETS")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and started and not paused:
		paused = true
		get_tree().paused = true
		tank.controls_enabled = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
