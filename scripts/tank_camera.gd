extends Camera3D
## Local optical intent and barrel trajectory; never simulates damage or network input.
const TankScript = preload("res://games/minigame/godot_party_default_tank_range/scripts/tank_controller.gd")
const TargetScript = preload("res://games/minigame/godot_party_default_tank_range/scripts/range_target.gd")
const DamageModel = preload("res://games/minigame/godot_party_default_tank_range/scripts/armor_damage.gd")
var tank: TankScript
var active: bool = false
var controllable: bool = false
var _elapsed: float = 0.0
var camera_yaw: float = 0.0
var camera_pitch: float = -0.023
var camera_position: Vector3 = Vector3.ZERO
var third_person_zoom: float = 0.25
var sight_zoom: float = 0.0
var first_person: bool = false
var shot_shake: float = 0.0
var actual_impact: Vector3 = Vector3.ZERO
var actual_hit_target: bool = false
var trajectory_timer: float = 0.0

func configure(vehicle: TankScript, can_control: bool) -> void:
	tank = vehicle
	controllable = can_control
	camera_yaw = tank.rotation.y
	camera_position = tank.position + Basis(Vector3.UP, camera_yaw) * Vector3(0, 6.5, 13)
	update_pose(1.0)

func advance(delta: float, elapsed: float) -> void:
	_elapsed = elapsed
	update_pose(delta)
	update_aim_point()
	trajectory_timer -= delta
	if trajectory_timer <= 0.0:
		predict_impact()
		trajectory_timer = 0.08
	shot_shake = maxf(0.0, shot_shake - delta * 3.0)

func move_look(relative: Vector2) -> void:
	var sensitivity: float = 0.0025 * tan(deg_to_rad(fov * 0.5)) / tan(deg_to_rad(67.0 * 0.5))
	camera_yaw -= relative.x * sensitivity
	camera_pitch = clampf(camera_pitch - relative.y * sensitivity, -0.58, 0.50 if first_person else 0.30)

func center_on_vehicle() -> void:
	camera_yaw = tank.rotation.y
	camera_pitch = -0.023

func _process(_delta: float) -> void:
	# Camera follows the final gun pose AFTER the vehicle physics step, avoiding
	# a one-frame disagreement between the bore reticle and the visible gun.
	if active and first_person:
		_update_sight_camera()

func set_first_person(active: bool) -> void:
	first_person = active
	tank.visual.visible = not active
	tank.aim_direction_mode = active
	if active:
		_update_sight_camera()
	else:
		update_pose(1.0)

func adjust_zoom(direction: float) -> void:
	if first_person:
		sight_zoom = clampf(sight_zoom + direction * 0.125, 0.0, 1.0)
	else:
		third_person_zoom = clampf(third_person_zoom + direction * 0.125, 0.0, 1.0)

func _update_sight_camera() -> void:
	var bore_basis: Basis = tank.visual.muzzle.global_basis.orthonormalized()
	self.global_position = tank.visual.barrel.global_position + bore_basis.y * 0.28 - bore_basis.z * 0.10
	var direction: Vector3 = Basis(Vector3.UP, camera_yaw) * Vector3(0, sin(camera_pitch), -cos(camera_pitch))
	# The optical view follows mouse intent; the gun marker shows the traversing barrel.
	self.look_at(self.global_position + direction, Vector3.UP)
	self.fov = 32.0 / pow(4.0, sight_zoom)
	camera_position = self.global_position

func update_pose(delta: float) -> void:
	if first_person:
		_update_sight_camera()
		return
	var aim_basis: Basis = Basis(Vector3.UP, camera_yaw)
	var focus: Vector3 = tank.global_position + Vector3(0, 1.6, 0)
	var distance: float = lerpf(16.0, 7.0, third_person_zoom)
	var pitch: float = camera_pitch
	var offset: Vector3 = aim_basis * Vector3(0, -sin(pitch) * distance + 1.0, cos(pitch) * distance)
	var desired: Vector3 = focus + offset
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(focus, desired, 1)
	var collision: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not collision.is_empty():
		desired = collision.position + collision.normal * 0.4
	camera_position = camera_position.lerp(desired, 1.0 - exp(-delta * 9.0))
	self.global_position = camera_position + Vector3(sin(_elapsed * 70), cos(_elapsed * 90), 0) * shot_shake * 0.07
	var direction: Vector3 = aim_basis * Vector3(0, sin(pitch), -cos(pitch))
	# Orbit camera orientation is input-driven, not auto-centered on the hull.
	self.look_at(self.global_position + direction * 200, Vector3.UP)
	self.fov = lerpf(self.fov, lerpf(67.0, 42.0, third_person_zoom), 1.0 - exp(-delta * 10))

func update_aim_point() -> void:
	if not controllable or tank.dead:
		return
	if first_person:
		tank.requested_gun_direction = Basis(Vector3.UP, camera_yaw) * Vector3(0, sin(camera_pitch), -cos(camera_pitch))
		tank.aim_point = tank.visual.barrel.global_position + tank.requested_gun_direction * 500
		return
	var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var origin: Vector3 = self.project_ray_origin(center)
	var end: Vector3 = origin + self.project_ray_normal(center) * 500
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end, 5)
	query.collide_with_areas = true
	query.exclude = [tank.get_rid(), tank.armor.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	tank.aim_point = end if hit.is_empty() else hit.position

func predict_impact() -> void:
	var point: Vector3 = tank.shot_muzzle().global_position
	var gravity: float = DamageModel.gravity(tank.ammunition)
	var velocity: Vector3 = tank.muzzle_direction() * DamageModel.shell_speed(tank.ammunition)
	actual_hit_target = false
	actual_impact = point + velocity * 3
	# Same integrator/gravity as real shells; sweep each segment to avoid tunneling.
	for i: int in 130:
		var next: Vector3 = point + velocity * 0.04 + Vector3.DOWN * gravity * 0.0008
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point, next, 5)
		query.collide_with_areas = true
		query.exclude = [tank.get_rid(), tank.armor.get_rid()]
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			actual_impact = hit.position
			actual_hit_target = hit.collider is Area3D or (hit.collider is TargetScript and not hit.collider.dead)
			return
		point = next
		velocity.y -= gravity * 0.04
	actual_impact = point
