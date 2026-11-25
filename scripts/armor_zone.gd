class_name TankArmorZone
extends CollisionShape3D
## Per-collider armor plate inside a vehicle prefab; set millimeter overrides (> 0) in the Inspector to tune individual zones.

@export var part: StringName = &"hull"

@export_group("Armor Thickness Overrides (mm, 0 = default)")
@export var front_mm: float = 0.0
@export var side_mm: float = 0.0
@export var rear_mm: float = 0.0
@export var roof_mm: float = 0.0
@export var underside_mm: float = 0.0

func _ready() -> void:
	if not part.is_empty():
		set_meta("part", String(part))

## Returns the authored millimeter override for the impacted local facing, or 0.0 to use the default table.
func thickness_for_facing(facing: String) -> float:
	match facing:
		"front": return front_mm
		"side": return side_mm
		"rear": return rear_mm
		"roof": return roof_mm
		"underside": return underside_mm
	return 0.0
