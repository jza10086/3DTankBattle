extends Node3D
## Host-only swept ballistic projectile; peers receive shot/impact presentation events.
signal impacted(point: Vector3, normal: Vector3, hits: Array[Dictionary])
const Tank = preload("res://games/minigame/godot_party_default_tank_range/scripts/tank_controller.gd")
const Target = preload("res://games/minigame/godot_party_default_tank_range/scripts/range_target.gd")
const DamageModel = preload("res://games/minigame/godot_party_default_tank_range/scripts/armor_damage.gd")
var ammunition: int = DamageModel.Ammo.AP
var damage_targets: Array[Node3D] = []
var velocity: Vector3 = Vector3.ZERO
var age: float = 0.0
var shooter: Tank
var authoritative: bool = true

func _ready() -> void:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.09 if DamageModel.is_missile(ammunition) else (0.018 if ammunition == DamageModel.Ammo.MG else 0.045)
	mesh.height = 0.55 if DamageModel.is_missile(ammunition) else 0.09
	mesh.radial_segments = 6
	mesh.rings = 3
	var item: MeshInstance3D = MeshInstance3D.new()
	item.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("fff2ac")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	item.material_override = material
	add_child(item)

func _physics_process(delta: float) -> void:
	var gravity: float = DamageModel.gravity(ammunition)
	if authoritative and DamageModel.is_missile(ammunition) and not shooter.dead:
		var direction: Vector3 = (shooter.aim_point - global_position).normalized()
		velocity = velocity.normalized().slerp(direction, minf(1.0, delta * 2.4)) * DamageModel.shell_speed(ammunition)
	var next: Vector3 = global_position + velocity * delta + Vector3.DOWN * gravity * delta * delta * 0.5
	if authoritative:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position, next, 5)
		query.collide_with_areas = true
		query.exclude = [shooter.get_rid(), shooter.armor.get_rid()]
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var collider: Node = hit.collider.get_parent() if hit.collider is Area3D else hit.collider
			var contacts: Array[Dictionary] = []
			if collider is Tank or collider is Target:
				var incoming: Vector3 = (velocity + Vector3.DOWN * gravity * delta * 0.5).normalized()
				var result: Dictionary = collider.apply_shell_hit(hit.position, hit.normal, incoming, int(hit.shape), ammunition)
				contacts.append({"target": collider, "result": result})
			if DamageModel.is_explosive(ammunition):
				contacts.append_array(_blast_hits(hit.position + hit.normal * 0.08, collider))
			impacted.emit(hit.position, hit.normal, contacts)
			queue_free()
			set_physics_process(false)
			return
	global_position = next
	if DamageModel.is_missile(ammunition) and velocity.length_squared() > 0.0:
		# The bright elongated projectile makes guidance readable at gameplay distance.
		look_at(global_position + velocity.normalized(), Vector3.UP)
		get_child(0).rotation.x = PI * 0.5
	velocity.y -= gravity * delta
	age += delta
	if age > 8.0 or global_position.y < -10:
		queue_free()


## A target takes direct OR blast damage, never both from the same explosion.
## World geometry and other tanks block blast propagation.
func _blast_hits(origin: Vector3, direct_target: Node) -> Array[Dictionary]:
	var contacts: Array[Dictionary] = []
	for target: Node3D in damage_targets:
		if target == direct_target or target.dead:
			continue
		var aim: Vector3 = target.get_aim_point()
		var amount: float = DamageModel.blast_damage(origin.distance_to(aim))
		if amount <= 0.0:
			continue
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, aim, 5)
		query.collide_with_areas = true
		var cover: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not cover.is_empty():
			var obstacle: Node = cover.collider.get_parent() if cover.collider is Area3D else cover.collider
			if obstacle != target:
				continue
		contacts.append({"target": target, "result": target.apply_blast_hit(origin, amount)})
	return contacts
