class_name TankVisual
extends "res://scripts/tank_visual_procedural.gd"
## Quaternius Animated Tanks (2019), Tank2, CC0. See assets/quaternius.
## Imported mesh has independent turret and gun pivots; original procedural fallback
## can be selected without changing the driving / ballistics interface.

@export var use_procedural := false
const MODEL := preload("res://assets/quaternius/tank_desert.glb")
const MODEL_SCALE := 0.8136
var _model: Node3D
var _track_players: Array[AnimationPlayer] = []
var _track_phase: Array[float] = [0.0, 0.0]
var _track_cycle := 0.8333333
var _barrel_rest := Vector3.ZERO
var _model_materials: Array[StandardMaterial3D] = []
var _original_colors: Array[Color] = []

func _build() -> void:
	if use_procedural:
		super._build()
		return
	_model = MODEL.instantiate()
	add_child(_model)
	_model.scale = Vector3.ONE * MODEL_SCALE
	_model.position.y = -0.60
	turret = _model.get_node("TankDesert/TurretPivot")
	barrel = turret.get_node("BarrelPivot")
	muzzle = barrel.get_node("Muzzle")
	_barrel_rest = barrel.position
	left_track = _model.get_node("TankDesert/TrackOrientation/TrackRig/Skeleton3D/TrackMesh_L")
	right_track = _model.get_node("TankDesert/TrackOrientation/TrackRig/Skeleton3D/TrackMesh_R")
	# Separate the source clip by side, so pivot turns and asymmetric steering
	# actually drive the two tread belts at independently signed speeds.
	var source_player: AnimationPlayer = _model.get_node("AnimationPlayer")
	var source_animation := source_player.get_animation("Forward")
	_track_cycle = source_animation.length
	source_player.stop()
	for side in [".L", ".R"]:
		var clip := source_animation.duplicate() as Animation
		for index in range(clip.get_track_count() - 1, -1, -1):
			if not String(clip.track_get_path(index)).ends_with(side):
				clip.remove_track(index)
		clip.loop_mode = Animation.LOOP_LINEAR
		var library := AnimationLibrary.new()
		library.add_animation("tread", clip)
		var player := AnimationPlayer.new()
		_model.add_child(player)
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.add_animation_library("", library)
		player.play("tread")
		player.seek(0, true)
		_track_players.append(player)
	_duplicate_materials(_model)
	# Small original ID plate/antenna to tie the licensed vehicle to the range.
	var id_plate := Label3D.new()
	turret.add_child(id_plate)
	id_plate.text = "07"
	id_plate.font_size = 42
	id_plate.pixel_size = 0.007
	id_plate.outline_size = 0
	id_plate.modulate = Color("e5d9b3")
	id_plate.position = Vector3(0, 0.09, 1.76)
	# Label3D faces local +Z already: rear-facing plate must not mirror its text.
	id_plate.rotation.y = 0.0
	var antenna_mat := _mat(Color("373c34"))
	_cylinder(turret, 0.014, 0.023, 1.21, Vector3(-0.82, 0.86, 0.68), antenna_mat, Vector3(0, 0, -0.06), 5)

func _duplicate_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		for surface in range(instance.mesh.get_surface_count()):
			var source := instance.get_active_material(surface)
			if source is StandardMaterial3D:
				var material := source.duplicate() as StandardMaterial3D
				instance.set_surface_override_material(surface, material)
				_model_materials.append(material)
				_original_colors.append(material.albedo_color)
	for child in node.get_children():
		_duplicate_materials(child)

func animate_tracks(left_speed: float, right_speed: float, dt: float, ground_offsets: Array = []) -> void:
	if use_procedural:
		super.animate_tracks(left_speed, right_speed, dt, ground_offsets)
		return
	if _destroyed:
		return
	for side in range(_track_players.size()):
		var speed := left_speed if side == 0 else right_speed
		# One source cycle advances one tread pitch, not the entire belt.
		_track_phase[side] = fposmod(_track_phase[side] + speed * dt * 0.72, _track_cycle)
		_track_players[side].seek(_track_phase[side], true)

func set_recoil(amount: float) -> void:
	if use_procedural:
		super.set_recoil(amount)
		return
	if is_instance_valid(barrel):
		barrel.position = _barrel_rest + Vector3(0, 0, clampf(amount, 0, 1) * 0.30 / MODEL_SCALE)

func set_destroyed(value: bool) -> void:
	if use_procedural:
		super.set_destroyed(value)
		return
	_destroyed = value
	for i in range(_model_materials.size()):
		_model_materials[i].albedo_color = _original_colors[i].darkened(0.54) if value else _original_colors[i]
