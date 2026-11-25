extends Node3D
## Host-only swept ballistic projectile driven by TankShellSpec resources; peers receive shot/impact presentation events.
signal impacted(point: Vector3, normal: Vector3, hits: Array[Dictionary])
const Tank = preload("res://games/minigame/GP_tank_war/scripts/tank_controller.gd")
const Target = preload("res://games/minigame/GP_tank_war/scripts/range_target.gd")
const DamageModel = preload("res://games/minigame/GP_tank_war/scripts/armor_damage.gd")
var ammunition: int = DamageModel.Ammo.AP
var spec: TankShellSpec
var damage_targets: Array[Node3D] = []
var velocity: Vector3 = Vector3.ZERO
var age: float = 0.0
var distance_traveled: float = 0.0
var shooter: Tank
var authoritative: bool = true
var network_position: Vector3 = Vector3.ZERO
var network_velocity: Vector3 = Vector3.ZERO
var guidance_error: Vector3 = Vector3.ZERO
var synchronizer: MultiplayerSynchronizer

func _resolve_spec() -> TankShellSpec:
	if spec != null:
		return spec
	if shooter != null:
		spec = shooter.ammo_spec_for(ammunition)
	if spec == null:
		spec = DamageModel.get_spec(ammunition)
	return spec

## The spawner owns lifetime; a missile synchronizer owns only guidance samples.
func configure_guidance() -> void:
	var active_spec: TankShellSpec = _resolve_spec()
	if not active_spec.guided_missile:
		return
	synchronizer = MultiplayerSynchronizer.new()
	synchronizer.name = "Guidance"
	synchronizer.replication_interval = 0.05
	var config: SceneReplicationConfig = SceneReplicationConfig.new()
	for path: NodePath in [NodePath(":network_position"), NodePath(":network_velocity")]:
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	synchronizer.replication_config = config
	synchronizer.synchronized.connect(_receive_guidance)
	add_child(synchronizer)

func _receive_guidance() -> void:
	if not authoritative and network_position.is_finite() and network_velocity.is_finite():
		guidance_error = network_position - global_position
		velocity = network_velocity

func _ready() -> void:
	var active_spec: TankShellSpec = _resolve_spec()
	_build_visual(active_spec)
	_orient_to_velocity()

func _build_visual(active_spec: TankShellSpec) -> void:
	if active_spec.model_scene != null:
		var instance: Node3D = active_spec.model_scene.instantiate() as Node3D
		if instance != null:
			instance.name = "ProjectileVisual"
			instance.scale = active_spec.model_scale
			add_child(instance)
			return
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = maxf(active_spec.visual_radius, 0.01)
	mesh.height = maxf(active_spec.visual_length, mesh.radius * 2.2)
	mesh.radial_segments = 8
	mesh.rings = 3
	var item: MeshInstance3D = MeshInstance3D.new()
	item.name = "ProjectileVisual"
	item.mesh = mesh
	item.rotation.x = PI * 0.5
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = active_spec.tracer_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	item.material_override = material
	add_child(item)

func _orient_to_velocity() -> void:
	if velocity.length_squared() <= 0.0001:
		return
	var dir: Vector3 = velocity.normalized()
	var up_axis: Vector3 = Vector3.FORWARD if absf(dir.y) > 0.98 else Vector3.UP
	look_at(global_position + dir, up_axis)

func _physics_process(delta: float) -> void:
	var active_spec: TankShellSpec = _resolve_spec()
	if not authoritative:
		var correction: Vector3 = guidance_error * (1.0 - exp(-20.0 * delta))
		global_position += correction
		guidance_error -= correction
	var gravity: float = active_spec.gravity
	if authoritative and active_spec.guided_missile and shooter != null and not shooter.dead:
		var to_aim: Vector3 = shooter.aim_point - global_position
		if to_aim.length_squared() > 0.0001:
			var direction: Vector3 = to_aim.normalized()
			velocity = velocity.normalized().slerp(direction, minf(1.0, delta * active_spec.guidance_turn_rate)) * active_spec.muzzle_velocity
	var next: Vector3 = global_position + velocity * delta + Vector3.DOWN * gravity * delta * delta * 0.5
	if authoritative:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position, next, 5)
		query.collide_with_areas = true
		if shooter != null:
			query.exclude = [shooter.get_rid(), shooter.armor.get_rid()]
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var hit_distance: float = distance_traveled + global_position.distance_to(hit.position)
			var collider: Node = hit.collider.get_parent() if hit.collider is Area3D else hit.collider
			var contacts: Array[Dictionary] = []
			if collider is Tank or collider is Target:
				var incoming: Vector3 = (velocity + Vector3.DOWN * gravity * delta * 0.5).normalized()
				var result: Dictionary = collider.apply_shell_hit(hit.position, hit.normal, incoming, int(hit.shape), ammunition, hit_distance, active_spec)
				contacts.append({"target": collider, "result": result})
			if active_spec.explosive and active_spec.splash_radius > 0.0 and active_spec.splash_damage > 0.0:
				contacts.append_array(_blast_hits(hit.position + hit.normal * 0.08, collider, active_spec))
			impacted.emit(hit.position, hit.normal, contacts)
			queue_free()
			set_physics_process(false)
			return
	distance_traveled += global_position.distance_to(next)
	global_position = next
	velocity.y -= gravity * delta
	if active_spec.drag_factor > 0.0 and not active_spec.guided_missile:
		velocity *= maxf(0.0, 1.0 - active_spec.drag_factor * delta)
	_orient_to_velocity()
	age += delta
	if authoritative:
		network_position = global_position
		network_velocity = velocity
	if age > active_spec.max_lifetime or global_position.y < -10.0:
		if authoritative:
			queue_free()
		else:
			hide()
			set_physics_process(false)

## A target takes direct OR blast damage, never both from the same explosion.
## World geometry and other tanks block blast propagation.
func _blast_hits(origin: Vector3, direct_target: Node, active_spec: TankShellSpec) -> Array[Dictionary]:
	var contacts: Array[Dictionary] = []
	for target: Node3D in damage_targets:
		if target == direct_target or target.dead:
			continue
		var aim: Vector3 = target.get_aim_point()
		var amount: float = active_spec.blast_damage_at_distance(origin.distance_to(aim))
		if amount <= 0.0:
			continue
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, aim, 5)
		query.collide_with_areas = true
		var cover: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not cover.is_empty():
			var obstacle: Node = cover.collider.get_parent() if cover.collider is Area3D else cover.collider
			if obstacle != target:
				continue
		contacts.append({"target": target, "result": target.apply_blast_hit(origin, amount, active_spec.splash_track_threshold)})
	return contacts
