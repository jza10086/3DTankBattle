extends CollisionShape3D
## Authored contact region; source_mesh also keeps wreck collision aligned with its visual.
@export var source_mesh: MeshInstance3D
@export_enum("hull", "turret", "barrel", "track") var armor_part: String
## Empty for armor without an individually damageable component.
@export var component: StringName = &""

func _ready() -> void:
	assert(source_mesh != null and shape != null, "Target collider requires its source mesh and shape.")
	assert(armor_part in ["hull", "turret", "barrel", "track"], "Target collider requires an explicit armor region.")
	assert((armor_part == "track" and component in [&"left_track", &"right_track"]) or (armor_part == "barrel" and component == &"barrel") or (armor_part in ["hull", "turret"] and component.is_empty()), "Target collider component must match its armor region.")
