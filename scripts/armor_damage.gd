class_name ArmorDamage
extends RefCounted
## Shared game-balance damage and ammunition data; values are not a real weapon simulation.
## Resistance values below are abstract balance units, NOT millimeters.
## Normal damage = 100 * 50 / (50 + resistance).
## Actual damage = round(normal damage * cos(incidence)^1.5).
## Incidence is measured between outward surface normal and -incoming velocity:
## 0 degrees is a square hit; 75 degrees or more ricochets for zero HP damage.
## A rotated target's facing is determined from its LOCAL surface normal.

const RICOCHET_ANGLE: float = 75.0
const ANGLE_POWER: float = 1.5
# Roof/underside surfaces must lie within about 18 degrees of horizontal.
# A steeply sloped frontal glacis still uses front resistance; its obliquity
# is handled independently by the actual shell/normal incidence calculation.
const ROOF_NORMAL_Y: float = 0.95
const RESISTANCE: Dictionary = {
	"hull": {"front": 110.0, "side": 52.0, "rear": 24.0, "roof": 42.0, "underside": 32.0},
	"turret": {"front": 145.0, "side": 85.0, "rear": 50.0, "roof": 58.0, "underside": 48.0},
	"track": {"front": 200.0, "side": 200.0, "rear": 200.0, "roof": 200.0, "underside": 200.0},
	# A barrel hit primarily disables the weapon; it does only 8 HP at normal incidence.
	"barrel": {"front": 550.0, "side": 550.0, "rear": 550.0, "roof": 550.0, "underside": 550.0},
}

static func evaluate(part: StringName, target_basis: Basis, world_normal: Vector3, incoming_direction: Vector3, ammunition: int = Ammo.AP) -> Dictionary:
	var part_name: String = String(part).to_lower()
	if not RESISTANCE.has(part_name):
		part_name = "hull"
	if world_normal.length_squared() < 0.000001 or incoming_direction.length_squared() < 0.000001:
		return {"part": part_name, "facing": "unknown", "region": part_name.to_upper(), "damage": 0.0, "angle_degrees": 90.0, "ricochet": false, "invalid": true, "ignored": true, "resistance": 0.0, "incidence_cos": 0.0}
	var normal: Vector3 = world_normal.normalized()
	var local_normal: Vector3 = target_basis.orthonormalized().inverse() * normal
	var facing: String = classify_facing(local_normal)
	var resistance: float = RESISTANCE[part_name][facing]
	var incidence_cos: float = clampf(-incoming_direction.normalized().dot(normal), 0.0, 1.0)
	var angle: float = rad_to_deg(acos(incidence_cos))
	# A tiny tolerance makes the exactly-75 degree boundary stable in float32.
	var ricochet: bool = not is_explosive(ammunition) and incidence_cos <= cos(deg_to_rad(RICOCHET_ANGLE)) + 0.000001
	var base_damage: float
	match ammunition:
		Ammo.AP: base_damage = 100.0 * 50.0 / (50.0 + resistance)
		Ammo.HE: base_damage = 70.0 * 35.0 / (35.0 + resistance * 1.8)
		Ammo.AUTO30: base_damage = 11.0 * 50.0 / (50.0 + resistance)
		Ammo.AUTO25: base_damage = 13.0 * 50.0 / (50.0 + resistance)
		Ammo.ATAKA, Ammo.TOW: base_damage = 140.0 * 85.0 / (85.0 + resistance)
		Ammo.MG: base_damage = 1.0 if part_name == "track" or (part_name == "hull" and facing == "rear") else 0.0
	var damage: float = 0.0 if ricochet else maxf(1.0, roundf(base_damage * (pow(incidence_cos, ANGLE_POWER) if not is_explosive(ammunition) else 1.0)))
	if ammunition == Ammo.MG and base_damage == 0.0:
		damage = 0.0
	var region: String = "TRACKS" if part_name == "track" else ("BARREL" if part_name == "barrel" else "%s %s" % [part_name.to_upper(), facing.to_upper()])
	return {"part": part_name, "facing": facing, "region": region, "damage": damage, "angle_degrees": angle, "ricochet": ricochet, "invalid": false, "ignored": false, "resistance": resistance, "incidence_cos": incidence_cos}

static func classify_facing(local_normal: Vector3) -> String:
	var n: Vector3 = local_normal.normalized()
	if absf(n.y) >= ROOF_NORMAL_Y:
		return "roof" if n.y > 0 else "underside"
	if absf(n.z) >= absf(n.x):
		return "front" if n.z < 0 else "rear"
	return "side"

enum Ammo { AP, HE, AUTO30, AUTO25, ATAKA, TOW, MG }
const BLAST_RADIUS: float = 4.0

static func shell_speed(ammunition: int) -> float:
	return [145.0, 85.0, 180.0, 160.0, 55.0, 48.0, 240.0][ammunition]

static func reload_duration(ammunition: int) -> float:
	return [3.2, 4.0, 0.16, 0.24, 7.5, 8.5, 0.1][ammunition]

static func is_missile(ammunition: int) -> bool:
	return ammunition in [Ammo.ATAKA, Ammo.TOW]

static func is_automatic(ammunition: int) -> bool:
	return ammunition in [Ammo.AUTO30, Ammo.AUTO25, Ammo.MG]

static func is_explosive(ammunition: int) -> bool:
	return ammunition == Ammo.HE or is_missile(ammunition)

static func gravity(ammunition: int) -> float:
	return 0.0 if is_missile(ammunition) else 9.8

static func blast_damage(distance: float) -> float:
	return roundf(32.0 * maxf(0.0, 1.0 - distance / BLAST_RADIUS))

static func weapon_name(ammunition: int) -> String:
	return ["M68A1  /  105 mm", "M68A1  /  105 mm", "双联 2A42  /  30 mm", "M242  /  25 mm", "Ataka  /  反坦克导弹", "TOW  /  反坦克导弹", "同轴机枪  /  7.62 mm"][ammunition]

static func ammo_name(ammunition: int) -> String:
	return ["穿甲弹", "高爆弹", "30 mm 机炮弹", "25 mm 机炮弹", "Ataka 导弹", "TOW 导弹", "7.62 mm 机枪弹"][ammunition]
