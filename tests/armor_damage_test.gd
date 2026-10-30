extends SceneTree
## Pure deterministic armor boundaries plus real target geometry / shape metadata.
## godot --headless --path . --script res://tests/armor_damage_test.gd
const Armor = preload("res://scripts/armor_damage.gd")
const Target = preload("res://scripts/range_target.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS  ", label)
	else:
		failed += 1
		push_error("FAIL  " + label)

func _hit(part: StringName, normal: Vector3, incoming: Vector3, basis: Basis = Basis.IDENTITY) -> Dictionary:
	return Armor.evaluate(part, basis, normal, incoming)

func _run() -> void:
	var front := _hit(&"hull", Vector3.FORWARD, Vector3.BACK)
	var side := _hit(&"hull", Vector3.RIGHT, Vector3.LEFT)
	var rear := _hit(&"hull", Vector3.BACK, Vector3.FORWARD)
	_check(front.region == "HULL FRONT" and front.damage == 31, "Square frontal hull hit = 31 HP")
	_check(side.region == "HULL SIDE" and side.damage == 49, "Square side hull hit = 49 HP")
	_check(rear.region == "HULL REAR" and rear.damage == 68, "Square rear hull hit = 68 HP")
	_check(front.damage < side.damage and side.damage < rear.damage, "Front armor stronger than sides and rear")
	var turret := _hit(&"turret", Vector3.FORWARD, Vector3.BACK)
	_check(turret.damage == 26 and turret.damage < front.damage and turret.region == "TURRET FRONT", "Turret front is stronger armor")
	var tracks := _hit(&"track", Vector3.RIGHT, Vector3.LEFT)
	_check(tracks.damage == 20 and tracks.region == "TRACKS", "Road wheels / tracks use 20 HP normal-hit region")
	var roof := _hit(&"hull", Vector3.UP, Vector3.DOWN)
	_check(roof.region == "HULL ROOF" and roof.damage > front.damage, "Roof is classified from local surface normal")
	# Measured from a real ballistic hit on the heavy target's front glacis.
	# Point=(-.102,1.232,-1.943), outward normal=(0,.810885,-.585206).
	var glacis_normal := Vector3(0, 0.810885, -0.585206).normalized()
	var glacis_incoming := Vector3(0.055777, -0.033296, 0.997888).normalized()
	var glacis := _hit(&"hull", glacis_normal, glacis_incoming)
	_check(glacis.region == "HULL FRONT" and glacis.damage == 15 and absf(glacis.angle_degrees - 52.3404) < 0.02, "Measured sloped heavy glacis stays FRONT with unchanged incidence")
	var steep_glacis := _hit(&"hull", Vector3(0, 0.927, -sqrt(1.0 - 0.927 * 0.927)), Vector3.BACK)
	_check(steep_glacis.region == "HULL FRONT", "Steep assault-gun glacis is not mislabeled roof")
	var near_horizontal := _hit(&"hull", Vector3(0, 0.98, -sqrt(1.0 - 0.98 * 0.98)), Vector3.DOWN)
	_check(near_horizontal.region == "HULL ROOF", "Near-horizontal inclined roof remains ROOF")
	var below_roof := _hit(&"hull", Vector3(0, 0.949, -sqrt(1.0 - 0.949 * 0.949)), Vector3.BACK)
	var above_roof := _hit(&"hull", Vector3(0, 0.951, -sqrt(1.0 - 0.951 * 0.951)), Vector3.BACK)
	_check(below_roof.region == "HULL FRONT" and above_roof.region == "HULL ROOF", "Roof threshold separates .949 / .951 local-up normals")
	var glacis_basis := Basis(Vector3.UP, 1.9)
	var rotated_glacis := _hit(&"hull", glacis_basis * glacis_normal, glacis_basis * glacis_incoming, glacis_basis)
	_check(rotated_glacis.region == glacis.region and rotated_glacis.damage == glacis.damage and absf(rotated_glacis.angle_degrees - glacis.angle_degrees) < 0.01, "Rotated sloped glacis preserves both face and incidence")
	var angle_60 := _hit(&"hull", Vector3.FORWARD, Vector3(sin(deg_to_rad(60)), 0, cos(deg_to_rad(60))))
	_check(angle_60.damage > 0 and angle_60.damage < front.damage and not angle_60.ricochet, "Oblique 60-degree hit loses damage")
	var angle_below := _hit(&"hull", Vector3.FORWARD, Vector3(sin(deg_to_rad(74.9)), 0, cos(deg_to_rad(74.9))))
	var angle_at := _hit(&"hull", Vector3.FORWARD, Vector3(sin(deg_to_rad(75)), 0, cos(deg_to_rad(75))))
	var angle_above := _hit(&"hull", Vector3.FORWARD, Vector3(sin(deg_to_rad(78)), 0, cos(deg_to_rad(78))))
	_check(angle_below.damage > 0 and not angle_below.ricochet, "74.9-degree hit remains non-ricochet")
	_check(angle_at.damage == 0 and angle_at.ricochet, "Exactly 75 degrees ricochets")
	_check(angle_above.damage == 0 and angle_above.ricochet and absf(angle_above.angle_degrees - 78) < 0.01, "78-degree grazing hit ricochets with correct angle")
	var left := _hit(&"hull", Vector3.LEFT, Vector3.RIGHT)
	_check(left.damage == side.damage and left.region == side.region, "Mirrored left/right surfaces give symmetric armor")
	for degrees in [37, 90, 180, 271]:
		var basis := Basis(Vector3.UP, deg_to_rad(degrees))
		var rotated := _hit(&"hull", basis * Vector3.FORWARD, basis * Vector3.BACK, basis)
		_check(rotated.region == front.region and rotated.damage == front.damage and rotated.angle_degrees < 0.01, "Target rotation %d degrees preserves frontal armor" % degrees)
	var nonunit := _hit(&"hull", Vector3.FORWARD * 7, Vector3.BACK * 105)
	_check(nonunit.damage == front.damage and nonunit.angle_degrees < 0.01, "Normals and incoming velocities are normalized")
	var invalid := _hit(&"hull", Vector3.ZERO, Vector3.BACK)
	_check(invalid.damage == 0 and invalid.ignored and invalid.invalid, "Invalid zero normal cannot fabricate damage")

	var scene := Node3D.new()
	root.add_child(scene)
	for variant in range(3):
		var target := Target.new()
		target.index = variant
		target.position = Vector3(variant * 20, 0, 0)
		scene.add_child(target)
		await physics_frame
		await physics_frame
		var aim: Vector3 = target.get_aim_point()
		var front_query := PhysicsRayQueryParameters3D.create(aim + Vector3.FORWARD * 12, aim + Vector3.BACK * 12, 1)
		var hit := scene.get_world_3d().direct_space_state.intersect_ray(front_query)
		_check(not hit.is_empty() and hit.collider == target, "Variant %d aim point crosses real mesh armor" % variant)
		if not hit.is_empty() and hit.collider == target:
			var result: Dictionary = target.apply_shell_hit(hit.position, hit.normal, Vector3.BACK, int(hit.shape))
			_check(result.region.begins_with("HULL") and result.damage > 0 and target.hp < target.max_hp, "Variant %d actual shape maps hull and applies HP damage" % variant)
		if variant == 1:
			var glacis_query := PhysicsRayQueryParameters3D.create(target.position + Vector3(0, 1.25, -8), target.position + Vector3(0, 1.25, 0), 1)
			var glacis_hit := scene.get_world_3d().direct_space_state.intersect_ray(glacis_query)
			var real_glacis: Dictionary = {}
			if not glacis_hit.is_empty() and glacis_hit.collider == target:
				real_glacis = Armor.evaluate(target._part_for_shape(int(glacis_hit.shape)), target.global_basis, glacis_hit.normal, Vector3.BACK)
			_check(real_glacis.get("region", "") == "HULL FRONT" and float(real_glacis.get("angle_degrees", 0.0)) > 50.0, "Real heavy front-slope collision classifies FRONT, not ROOF")
		var track_query := PhysicsRayQueryParameters3D.create(target.position + Vector3(-6, 0.45, 0), target.position + Vector3(0, 0.45, 0), 1)
		var track_hit := scene.get_world_3d().direct_space_state.intersect_ray(track_query)
		var track_result: Dictionary = {}
		if not track_hit.is_empty() and track_hit.collider == target:
			track_result = target.apply_shell_hit(track_hit.position, track_hit.normal, Vector3.RIGHT, int(track_hit.shape))
		_check(track_result.get("region", "") == "TRACKS" and track_result.get("damage", 0.0) == 20.0, "Variant %d real side tread hit selects track armor, not hull" % variant)
		var high_query := PhysicsRayQueryParameters3D.create(target.position + Vector3(0.85, 2.6, -12), target.position + Vector3(0.85, 2.6, 12), 1)
		_check(scene.get_world_3d().direct_space_state.intersect_ray(high_query).is_empty(), "Variant %d empty space above hull is not an invisible target box" % variant)
		var part_counts := {"hull": 0, "turret": 0, "track": 0, "barrel": 0}
		for owner_id in target.get_shape_owners():
			var shape_node = target.shape_owner_get_owner(owner_id)
			part_counts[String(shape_node.get_meta("armor_part", "hull"))] += 1
		_check(part_counts.hull > 0 and part_counts.turret > 0 and part_counts.track > 0, "Variant %d has distinct hull / turret / track collision metadata" % variant)
		target.damage(1000)
		var ignored: Dictionary = target.apply_shell_hit(aim, Vector3.FORWARD, Vector3.BACK)
		_check(target.dead and target.hp == 0 and ignored.ignored and ignored.damage == 0 and target.collision_layer == 1, "Variant %d destroyed wreck ignores damage and remains cover" % variant)
	print("\nARMOR TESTS: %d passed, %d failed" % [passed, failed])
	scene.queue_free()
	await process_frame
	quit(0 if failed == 0 else 1)
