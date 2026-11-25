class_name ArmorDamage
extends RefCounted
## War Thunder-style armor penetration, slope normalization, overmatch, ricochet, overpressure, and splash evaluation.
## Ammunition parameters live in configurable TankShellSpec .tres resources under res://games/minigame/GP_tank_war/ammo/.

enum Ammo { AP, HE, AUTO30, AUTO25, ATAKA, TOW, MG }

const DEFAULT_SPECS: Array[TankShellSpec] = [
	preload("res://games/minigame/GP_tank_war/ammo/ap_105.tres"),
	preload("res://games/minigame/GP_tank_war/ammo/he_105.tres"),
	preload("res://games/minigame/GP_tank_war/ammo/auto30_apds.tres"),
	preload("res://games/minigame/GP_tank_war/ammo/auto25_apds.tres"),
	preload("res://games/minigame/GP_tank_war/ammo/atgm_ataka.tres"),
	preload("res://games/minigame/GP_tank_war/ammo/atgm_tow.tres"),
	preload("res://games/minigame/GP_tank_war/ammo/mg_762.tres"),
]

const ROOF_NORMAL_Y: float = 0.95
const ARMOR_THICKNESS_MM: Dictionary = {
	"hull": {"front": 120.0, "side": 55.0, "rear": 28.0, "roof": 30.0, "underside": 24.0},
	"turret": {"front": 150.0, "side": 85.0, "rear": 45.0, "roof": 32.0, "underside": 40.0},
	"track": {"front": 25.0, "side": 25.0, "rear": 25.0, "roof": 25.0, "underside": 25.0},
	"barrel": {"front": 30.0, "side": 30.0, "rear": 30.0, "roof": 30.0, "underside": 30.0},
}

static func get_spec(ammunition: int) -> TankShellSpec:
	if ammunition >= 0 and ammunition < DEFAULT_SPECS.size():
		return DEFAULT_SPECS[ammunition]
	return DEFAULT_SPECS[0]

static func evaluate(
	part: StringName,
	target_basis: Basis,
	world_normal: Vector3,
	incoming_direction: Vector3,
	ammunition: int = Ammo.AP,
	travel_distance: float = 0.0,
	armor_scale: float = 1.0,
	deterministic: bool = false
) -> Dictionary:
	return evaluate_spec(get_spec(ammunition), part, target_basis, world_normal, incoming_direction, travel_distance, armor_scale, deterministic)

## Evaluates a War Thunder-style shell hit using a configurable TankShellSpec resource.
## When armor_override_mm > 0 (e.g. from a TankArmorZone on a vehicle prefab), it directly overrides the default thickness table.
static func evaluate_spec(
	spec: TankShellSpec,
	part: StringName,
	target_basis: Basis,
	world_normal: Vector3,
	incoming_direction: Vector3,
	travel_distance: float = 0.0,
	armor_scale: float = 1.0,
	deterministic: bool = false,
	armor_override_mm: float = 0.0
) -> Dictionary:
	var part_name: String = String(part).to_lower()
	if not ARMOR_THICKNESS_MM.has(part_name):
		part_name = "hull"
	if spec == null or world_normal.length_squared() < 0.000001 or incoming_direction.length_squared() < 0.000001:
		return {
			"part": part_name, "facing": "unknown", "region": part_name.to_upper(),
			"damage": 0.0, "angle_degrees": 90.0, "effective_angle_degrees": 90.0,
			"armor_mm": 0.0, "effective_armor_mm": 0.0, "penetration_mm": 0.0,
			"penetrated": false, "overpressure": false, "ricochet": false,
			"ricochet_chance": 0.0, "overmatch": false, "invalid": true,
			"ignored": true, "resistance": 0.0, "incidence_cos": 0.0,
		}
	var normal: Vector3 = world_normal.normalized()
	var local_normal: Vector3 = target_basis.orthonormalized().inverse() * normal
	var facing: String = classify_facing(local_normal)
	var scale_factor: float = 1.0 if part_name in ["track", "barrel"] else maxf(armor_scale, 0.1)
	var base_armor_mm: float = armor_override_mm if armor_override_mm > 0.0 else float(ARMOR_THICKNESS_MM[part_name][facing]) * scale_factor
	var incidence_cos: float = clampf(-incoming_direction.normalized().dot(normal), 0.0, 1.0)
	var angle_deg: float = rad_to_deg(acos(incidence_cos))

	var caliber_ratio: float = spec.caliber_mm / maxf(base_armor_mm, 1.0)
	var full_overmatch: bool = spec.overmatch_ratio > 0.0 and caliber_ratio >= spec.overmatch_ratio
	var partial_overmatch: bool = caliber_ratio >= 1.3

	# War Thunder ricochet angle window (0% -> 100%) with caliber overmatch override.
	var ricochet: bool = false
	var ricochet_chance: float = 0.0
	if spec.shell_type == TankShellSpec.ShellType.HE:
		if angle_deg >= spec.ricochet_guaranteed_angle - 0.001:
			ricochet = true
			ricochet_chance = 1.0
	elif full_overmatch:
		if angle_deg >= 88.0:
			ricochet = true
			ricochet_chance = 1.0
	else:
		var start_angle: float = spec.ricochet_start_angle + (3.0 if partial_overmatch else 0.0)
		var guaranteed_angle: float = minf(89.0, spec.ricochet_guaranteed_angle + (2.0 if partial_overmatch else 0.0))
		if angle_deg >= guaranteed_angle - 0.001:
			ricochet = true
			ricochet_chance = 1.0
		elif angle_deg > start_angle:
			ricochet_chance = clampf((angle_deg - start_angle) / maxf(guaranteed_angle - start_angle, 0.01), 0.0, 1.0)
			if not deterministic and randf() < ricochet_chance:
				ricochet = true

	# Normalization and effective LOS armor thickness (mm RHA).
	var effective_angle_deg: float = angle_deg
	var effective_armor_mm: float = base_armor_mm
	if spec.shell_type == TankShellSpec.ShellType.AP or spec.shell_type == TankShellSpec.ShellType.APHE:
		var norm: float = spec.normalization_deg
		if partial_overmatch:
			norm += clampf((caliber_ratio - 1.3) * 2.5, 0.0, 5.0)
		effective_angle_deg = maxf(0.0, angle_deg - norm)
		effective_armor_mm = base_armor_mm / maxf(cos(deg_to_rad(effective_angle_deg)), 0.08)
	elif spec.shell_type == TankShellSpec.ShellType.HEAT:
		effective_armor_mm = base_armor_mm / maxf(cos(deg_to_rad(angle_deg)), 0.08)
	elif spec.shell_type == TankShellSpec.ShellType.MG:
		effective_armor_mm = base_armor_mm / maxf(cos(deg_to_rad(angle_deg)), 0.1)
	else:
		# HE overpressure acts normal to the armor plate regardless of impact slope.
		effective_angle_deg = 0.0
		effective_armor_mm = base_armor_mm

	var pen_mm: float = spec.penetration_at_distance(travel_distance)
	var penetrated: bool = false
	var overpressure: bool = false
	var damage: float = 0.0
	var part_scale: float = 0.16 if part_name == "barrel" else (0.35 if part_name == "track" else 1.0)

	if not ricochet:
		match spec.shell_type:
			TankShellSpec.ShellType.HE:
				var op_pen: float = maxf(spec.overpressure_penetration_mm, pen_mm)
				if op_pen >= base_armor_mm:
					penetrated = true
					overpressure = true
					var op_margin: float = clampf((op_pen - base_armor_mm) / maxf(op_pen, 1.0), 0.0, 0.35)
					damage = maxf(1.0, roundf(spec.base_damage * part_scale * (1.0 + op_margin)))
				else:
					# Non-overpressure HE still delivers exterior concussive blast on heavy armor.
					damage = maxf(1.0, roundf(spec.base_damage * 0.42 * 50.0 / (50.0 + base_armor_mm) * (0.45 if part_name == "barrel" else 1.0)))
			TankShellSpec.ShellType.MG:
				if part_name == "track" or pen_mm >= effective_armor_mm:
					penetrated = true
					damage = maxf(1.0, roundf(spec.base_damage))
			_:
				if pen_mm >= effective_armor_mm:
					penetrated = true
					var margin: float = clampf((pen_mm - effective_armor_mm) / maxf(pen_mm, 1.0), 0.0, 1.0)
					var spall_mult: float = 0.72 + 0.28 * clampf(margin * 2.2, 0.0, 1.0) + spec.spall_bonus_ratio * margin
					damage = maxf(1.0, roundf(spec.base_damage * part_scale * spall_mult))
				elif spec.explosive and spec.overpressure_penetration_mm >= base_armor_mm:
					penetrated = true
					overpressure = true
					damage = maxf(1.0, roundf(spec.base_damage * part_scale * 0.75))

	var region: String = "TRACKS" if part_name == "track" else ("BARREL" if part_name == "barrel" else "%s %s" % [part_name.to_upper(), facing.to_upper()])
	return {
		"part": part_name,
		"facing": facing,
		"region": region,
		"damage": damage,
		"angle_degrees": angle_deg,
		"effective_angle_degrees": effective_angle_deg,
		"armor_mm": base_armor_mm,
		"effective_armor_mm": effective_armor_mm,
		"penetration_mm": pen_mm,
		"penetrated": penetrated,
		"overpressure": overpressure,
		"ricochet": ricochet,
		"ricochet_chance": ricochet_chance,
		"overmatch": full_overmatch,
		"invalid": false,
		"ignored": false,
		"resistance": effective_armor_mm,
		"incidence_cos": incidence_cos,
	}

static func classify_facing(local_normal: Vector3) -> String:
	var n: Vector3 = local_normal.normalized()
	if absf(n.y) >= ROOF_NORMAL_Y:
		return "roof" if n.y > 0 else "underside"
	if absf(n.z) >= absf(n.x):
		return "front" if n.z < 0 else "rear"
	return "side"

static func shell_speed(ammunition: int) -> float:
	return get_spec(ammunition).muzzle_velocity

static func reload_duration(ammunition: int) -> float:
	return get_spec(ammunition).reload_time

static func is_missile(ammunition: int) -> bool:
	return get_spec(ammunition).guided_missile

static func is_automatic(ammunition: int) -> bool:
	return get_spec(ammunition).automatic

static func is_explosive(ammunition: int) -> bool:
	return get_spec(ammunition).explosive

static func gravity(ammunition: int) -> float:
	return get_spec(ammunition).gravity

static func blast_damage(distance: float, ammunition: int = Ammo.HE) -> float:
	return get_spec(ammunition).blast_damage_at_distance(distance)

static func fire_audio_cue(ammunition: int) -> StringName:
	return get_spec(ammunition).fire_audio_cue

static func weapon_name(ammunition: int) -> String:
	return get_spec(ammunition).weapon_name

static func ammo_name(ammunition: int) -> String:
	return get_spec(ammunition).display_name
