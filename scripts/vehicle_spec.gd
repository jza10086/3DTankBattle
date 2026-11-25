class_name TankVehicleSpec
extends Resource
## Configurable vehicle data resource: identity, HP, armor scale, mobility, turret dynamics, and weapon specs.

@export_group("Identity")
@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var name_key: StringName = &""
@export var description_key: StringName = &""
@export var scene: PackedScene
@export var silhouette: Texture2D
@export var gun_icon: Texture2D
@export var launcher_icon: Texture2D

@export_group("Survivability & Armor")
@export var max_hp: float = 100.0
@export var armor_scale: float = 1.0
@export var damage_multiplier: float = 1.0

@export_group("Mobility")
@export var max_speed: float = 14.5
@export var reverse_speed: float = 5.5
@export var acceleration: float = 4.2
@export var braking: float = 12.0
@export var coast_deceleration: float = 2.8
@export var pivot_turn_rate: float = 1.08
@export var move_turn_rate: float = 0.54
@export var yaw_acceleration: float = 2.4

@export_group("Turret & Weapons")
@export var traverse_rate: float = 0.68
@export var elevation_rate: float = 0.55
@export var min_depression_deg: float = -10.0
@export var max_elevation_deg: float = 24.0
@export var weapons: Array[int] = [0, 1]
@export var ammo_specs: Array[TankShellSpec] = []
@export var coax_ammo: TankShellSpec
@export var mg_belt_size: int = 100
@export var mg_reload_seconds: float = 4.0

func resolved_name_key() -> String:
	return display_name if not display_name.is_empty() else String(name_key)

func resolved_description_key() -> String:
	return description if not description.is_empty() else String(description_key)

func weapon_codes() -> Array[int]:
	var codes: Array[int] = []
	for entry: TankShellSpec in ammo_specs:
		if entry != null and entry.ammo_code not in codes:
			codes.append(entry.ammo_code)
	if not codes.is_empty():
		return codes
	return weapons.duplicate()

func find_ammo_spec(ammunition: int) -> TankShellSpec:
	for entry: TankShellSpec in ammo_specs:
		if entry != null and entry.ammo_code == ammunition:
			return entry
	if coax_ammo != null and coax_ammo.ammo_code == ammunition:
		return coax_ammo
	return null
