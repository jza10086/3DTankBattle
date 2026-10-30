class_name ArmorDamage
extends RefCounted
## Deterministic TRAINING-GAME armor model, not real armor penetration physics.
## Resistance values below are abstract balance units, NOT millimeters.
## Normal damage = 100 * 50 / (50 + resistance).
## Actual damage = round(normal damage * cos(incidence)^1.5).
## Incidence is measured between outward surface normal and -incoming velocity:
## 0 degrees is a square hit; 75 degrees or more ricochets for zero HP damage.
## A rotated target's facing is determined from its LOCAL surface normal.

const RICOCHET_ANGLE := 75.0
const ANGLE_POWER := 1.5
# Roof/underside surfaces must lie within about 18 degrees of horizontal.
# A steeply sloped frontal glacis still uses front resistance; its obliquity
# is handled independently by the actual shell/normal incidence calculation.
const ROOF_NORMAL_Y := 0.95
const RESISTANCE := {
	"hull": {"front": 110.0, "side": 52.0, "rear": 24.0, "roof": 42.0, "underside": 32.0},
	"turret": {"front": 145.0, "side": 85.0, "rear": 50.0, "roof": 58.0, "underside": 48.0},
	"track": {"front": 200.0, "side": 200.0, "rear": 200.0, "roof": 200.0, "underside": 200.0},
	# A barrel hit primarily disables the weapon; it does only 8 HP at normal incidence.
	"barrel": {"front": 550.0, "side": 550.0, "rear": 550.0, "roof": 550.0, "underside": 550.0},
}

static func evaluate(part: StringName, target_basis: Basis, world_normal: Vector3, incoming_direction: Vector3) -> Dictionary:
	var part_name := String(part).to_lower()
	if not RESISTANCE.has(part_name):
		part_name = "hull"
	if world_normal.length_squared() < 0.000001 or incoming_direction.length_squared() < 0.000001:
		return {"part": part_name, "facing": "unknown", "region": part_name.to_upper(), "damage": 0.0, "angle_degrees": 90.0, "ricochet": false, "invalid": true, "ignored": true, "resistance": 0.0, "incidence_cos": 0.0}
	var normal := world_normal.normalized()
	var local_normal := target_basis.orthonormalized().inverse() * normal
	var facing := classify_facing(local_normal)
	var resistance: float = RESISTANCE[part_name][facing]
	var incidence_cos := clampf(-incoming_direction.normalized().dot(normal), 0.0, 1.0)
	var angle := rad_to_deg(acos(incidence_cos))
	# A tiny tolerance makes the exactly-75 degree boundary stable in float32.
	var ricochet := incidence_cos <= cos(deg_to_rad(RICOCHET_ANGLE)) + 0.000001
	var base_damage := 100.0 * 50.0 / (50.0 + resistance)
	var damage := 0.0 if ricochet else maxf(1.0, roundf(base_damage * pow(incidence_cos, ANGLE_POWER)))
	var region := "TRACKS" if part_name == "track" else ("BARREL" if part_name == "barrel" else "%s %s" % [part_name.to_upper(), facing.to_upper()])
	return {"part": part_name, "facing": facing, "region": region, "damage": damage, "angle_degrees": angle, "ricochet": ricochet, "invalid": false, "ignored": false, "resistance": resistance, "incidence_cos": incidence_cos}

static func classify_facing(local_normal: Vector3) -> String:
	var n := local_normal.normalized()
	if absf(n.y) >= ROOF_NORMAL_Y:
		return "roof" if n.y > 0 else "underside"
	if absf(n.z) >= absf(n.x):
		return "front" if n.z < 0 else "rear"
	return "side"
