extends Node3D
## Host-only swept ballistic projectile; peers receive shot/impact presentation events.
signal impacted(point: Vector3, normal: Vector3, target: Node, result: Dictionary)
const Tank = preload("res://games/minigame/godot_party_default_tank_range/scripts/tank_controller.gd")
const Target = preload("res://games/minigame/godot_party_default_tank_range/scripts/range_target.gd")
const GRAVITY: float = 9.8
var velocity: Vector3 = Vector3.ZERO
var age: float = 0.0
var shooter: Tank
var authoritative: bool = true

func _ready() -> void:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.075
	mesh.height = 0.15
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
	var next: Vector3 = global_position + velocity * delta + Vector3.DOWN * GRAVITY * delta * delta * 0.5
	if authoritative:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position, next, 5)
		query.collide_with_areas = true
		query.exclude = [shooter.get_rid(), shooter.armor.get_rid()]
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var collider: Node = hit.collider.get_parent() if hit.collider is Area3D else hit.collider
			var result: Dictionary = {}
			if collider is Tank or collider is Target:
				var incoming: Vector3 = (velocity + Vector3.DOWN * GRAVITY * delta * 0.5).normalized()
				result = collider.apply_shell_hit(hit.position, hit.normal, incoming, int(hit.shape))
			impacted.emit(hit.position, hit.normal, collider, result)
			queue_free()
			set_physics_process(false)
			return
	global_position = next
	velocity.y -= GRAVITY * delta
	age += delta
	if age > 8.0 or global_position.y < -10:
		queue_free()
