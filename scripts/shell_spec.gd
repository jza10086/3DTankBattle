class_name TankShellSpec
extends Resource
## War Thunder-style configurable ammunition resource: ballistics, 3D model, penetration, ricochet, overmatch, and splash.

enum ShellType {
	AP,    ## Kinetic penetrator (AP / APDS / APFSDS): distance pen drop, normalization, overmatch, ricochet.
	APHE,  ## Armor-piercing high-explosive: kinetic penetration with enhanced internal spall/explosive damage.
	HE,    ## High-explosive: distance-independent overpressure on thin plates and blast splash on thick armor.
	HEAT,  ## Chemical shaped-charge / ATGM warhead: distance-independent penetration with splash blast.
	MG,    ## Rifle-caliber coaxial tracer: high speed, low penetration, no one-shot component disable.
}

@export_group("Identity")
@export var id: StringName = &""
@export var ammo_code: int = 0
@export var display_name: String = ""
@export var short_label: String = ""
@export var weapon_name: String = ""
@export var reload_slot: StringName = &""
@export var shell_type: ShellType = ShellType.AP
@export var icon: Texture2D
@export var fire_audio_cue: StringName = &"cannon"

@export_group("Model & Size")
@export var model_scene: PackedScene
@export var model_scale: Vector3 = Vector3.ONE
@export var caliber_mm: float = 105.0
@export var visual_radius: float = 0.045
@export var visual_length: float = 0.34
@export var tracer_color: Color = Color("fff2ac")
@export var impact_flash_size: float = 0.85
@export var impact_smoke_count: int = 6

@export_group("Ballistics")
@export var muzzle_velocity: float = 165.0
@export var gravity: float = 9.8
@export var drag_factor: float = 0.0
@export var max_lifetime: float = 8.0
@export var reload_time: float = 3.2
@export var automatic: bool = false
@export var guided_missile: bool = false
@export var guidance_turn_rate: float = 2.4
@export var recoil_impulse: float = 1.0
@export var camera_shake: float = 1.0

@export_group("Penetration & Ricochet")
@export var penetration_mm: float = 210.0
@export var penetration_drop_per_100m: float = 16.0
@export var normalization_deg: float = 5.0
@export var ricochet_start_angle: float = 72.0
@export var ricochet_guaranteed_angle: float = 80.0
@export var overmatch_ratio: float = 7.0

@export_group("Damage & Splash")
@export var base_damage: float = 52.0
@export var spall_bonus_ratio: float = 0.30
@export var component_damage: bool = true
@export var explosive: bool = false
@export var splash_radius: float = 0.0
@export var splash_damage: float = 0.0
@export var splash_track_threshold: float = 4.0
@export var overpressure_penetration_mm: float = 0.0

## Distance-attenuated penetration (mm RHA). Chemical shells set drop_per_100m to 0.
func penetration_at_distance(distance_meters: float) -> float:
	return maxf(1.0, penetration_mm - penetration_drop_per_100m * (maxf(distance_meters, 0.0) / 100.0))

## Identifies which physical weapon/breech loads this shell. Distinct slots reload independently in parallel.
func resolved_reload_slot() -> StringName:
	if not reload_slot.is_empty():
		return reload_slot
	if guided_missile:
		return &"missile_launcher"
	if shell_type == ShellType.MG:
		return &"coax_mg"
	if not weapon_name.is_empty():
		return StringName(weapon_name)
	return &"main_gun"

## Linearly attenuated blast damage within splash_radius; 0 outside or for non-splash shells.
func blast_damage_at_distance(distance_meters: float) -> float:
	if splash_radius <= 0.0 or splash_damage <= 0.0:
		return 0.0
	return roundf(splash_damage * maxf(0.0, 1.0 - distance_meters / splash_radius))
