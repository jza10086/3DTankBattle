class_name TankShell
extends Node3D
signal impacted(point: Vector3, normal: Vector3, hit_target: Node, result: Dictionary)
var velocity := Vector3.ZERO
var age := 0.0
const GRAVITY := 9.8

func _ready() -> void:
	add_to_group("shells")
	var mesh := SphereMesh.new()
	mesh.radius = 0.075
	mesh.height = 0.15
	mesh.radial_segments = 6
	mesh.rings = 3
	var item := MeshInstance3D.new()
	item.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("fff2ac")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	item.material_override = mat
	add_child(item)

func _physics_process(delta: float) -> void:
	var next := global_position + velocity * delta + Vector3.DOWN * GRAVITY * delta * delta * 0.5
	var query := PhysicsRayQueryParameters3D.create(global_position, next, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider: Node = hit.collider
		var result: Dictionary = {}
		if collider.has_method("apply_shell_hit"):
			# Mid-step velocity matches the curved swept segment at contact; normals
			# and incoming direction are BOTH in world space.
			var incoming := (velocity + Vector3.DOWN * GRAVITY * delta * 0.5).normalized()
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
