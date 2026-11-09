extends Node
## Template PartyGameAudio owns mix, pause and cleanup. This component owns combat
## events and a bounded positional voice pool; it never reads physical input.
const Tank = preload("res://games/minigame/godot_party_default_tank_range/scripts/tank_controller.gd")
const VehicleAudio = preload("res://games/minigame/godot_party_default_tank_range/scripts/vehicle_audio.gd")
const Damage = preload("res://games/minigame/godot_party_default_tank_range/scripts/armor_damage.gd")
@export var scope: PartyGameAudio
@export var vehicle_audio_scene: PackedScene
@export var voices_root: Node3D
@export var alarm: AudioStreamPlayer
@export var peak_limiter: AudioEffectHardLimiter
@export var cues: Dictionary[StringName, PartyAudioCue] = {}
var emitters: Array[VehicleAudio] = []
var active: bool = false
var _stopped: bool = true
var _missile_motors: Array[AudioStreamPlayer3D] = []
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_cues: Dictionary[AudioStreamPlayer3D, PartyAudioCue] = {}
var _voice_order: Dictionary[AudioStreamPlayer3D, int] = {}
var _serial: int = 0
var _pending_starts: Dictionary[AudioStreamPlayer3D, Dictionary] = {}
var _local: Tank
var _hp: float
var _reload: float
var _mg_reload: float
var _disabled: bool = false

func _ready() -> void:
	assert(scope != null and vehicle_audio_scene != null and voices_root != null and alarm != null and peak_limiter != null)
	_voices.assign(voices_root.get_children())
	for cue: PartyAudioCue in cues.values():
		assert(cue.validate() == OK)
	alarm.stream = cues[&"alarm"].playback_stream()
	alarm.volume_db = cues[&"alarm"].volume_db

func start(vehicles: Array[Tank], local_vehicle: Tank) -> void:
	active = true
	_stopped = false
	_local = local_vehicle
	for vehicle: Tank in vehicles:
		var emitter: VehicleAudio = vehicle_audio_scene.instantiate()
		vehicle.add_child(emitter)
		emitter.start(vehicle, scope)
		emitters.append(emitter)
	for voice: AudioStreamPlayer3D in _voices:
		scope.route_spatial(voice, PartyGameAudio.Category.SFX)
	scope.route_player(alarm, PartyGameAudio.Category.SFX)
	# This activation owns its SFX bus; the protocol removes it at scope teardown.
	AudioServer.add_bus_effect(AudioServer.get_bus_index(alarm.bus), peak_limiter)
	if _local != null:
		_hp = _local.hp
		_reload = _local.reload_remaining
		_mg_reload = _local.mg_reload_remaining

## Freeze continuous sources at the outcome, retaining the final hit/explosion
## tails until the existing settlement delay completes.
func end_combat() -> void:
	active = false
	alarm.stop()
	for emitter: VehicleAudio in emitters:
		emitter.engine.stop()
		emitter.tracks.stop()
		emitter.traverse.stop()
	for motor: AudioStreamPlayer3D in _missile_motors:
		if is_instance_valid(motor):
			motor.stop()

func stop() -> void:
	active = false
	_stopped = true
	_pending_starts.clear()
	scope.stop_all()

func advance(delta: float) -> void:
	if not active:
		return
	for emitter: VehicleAudio in emitters:
		emitter.advance(delta)
	if _local == null:
		return
	if _local.hp < _hp:
		scope.play_sfx(cues[&"interior_hit"])
	_hp = _local.hp
	var disabled: bool = _local.components.engine_remaining > 0.0 or _local.components.left_track_remaining > 0.0 or _local.components.right_track_remaining > 0.0 or _local.components.barrel_remaining > 0.0
	if _disabled and not disabled and not _local.dead:
		scope.play_sfx(cues[&"repair"])
	_disabled = disabled
	var warning: bool = not _local.dead and (disabled or _local.hp <= 25.0)
	if warning and not alarm.playing:
		alarm.play()
		scope.route_player(alarm, PartyGameAudio.Category.SFX)
	elif not warning:
		alarm.stop()
	if not _local.dead:
		if not Damage.is_automatic(_local.ammunition):
			_reload_feedback(_reload, _local.reload_remaining)
		_reload_feedback(_mg_reload, _local.mg_reload_remaining)
	_reload = _local.reload_remaining
	_mg_reload = _local.mg_reload_remaining

func _reload_feedback(previous: float, current: float) -> void:
	if current > previous + 0.1:
		scope.play_sfx(cues[&"reload"])
	elif previous > 0.0 and current <= 0.0:
		scope.play_sfx(cues[&"ready"])

func fire(ammunition: int, origin: Vector3, projectile: Node3D) -> void:
	if not active:
		return
	var names: Array[StringName] = [&"cannon", &"cannon_he", &"auto30", &"auto25", &"ataka", &"tow", &"machine_gun"]
	play_at(names[ammunition], origin)
	if active and Damage.is_missile(ammunition):
		var motor: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		var cue: PartyAudioCue = cues[&"missile_motor"]
		motor.stream = cue.playback_stream()
		motor.volume_db = cue.volume_db
		motor.unit_size = 10.0
		motor.max_distance = 160.0
		motor.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		projectile.add_child(motor)
		scope.route_spatial(motor, PartyGameAudio.Category.SFX)
		_start_spatial(motor)
		_missile_motors.append(motor)

func impact(origin: Vector3, ammunition: int, surface: StringName, feedback: Array, own_shot: bool) -> void:
	if Damage.is_explosive(ammunition):
		play_at(&"explosion", origin)
	elif surface == &"ground":
		play_at(&"ground", origin, -7.0 if Damage.is_automatic(ammunition) else 0.0)
	if surface == &"armor":
		play_at(&"armor", origin, -9.0 if Damage.is_automatic(ammunition) else 0.0)
	elif surface == &"ricochet":
		play_at(&"ricochet", origin)
	elif surface == &"wreck":
		play_at(&"wreck", origin)
	if not _stopped and own_shot and not feedback.is_empty():
		var cue: StringName = &"hit_confirm"
		for entry: Dictionary in feedback:
			if entry.kind == "kill":
				cue = &"kill_confirm"
				break
			elif entry.kind == "disabled":
				cue = &"disable_confirm"
		if feedback.any(func(entry: Dictionary) -> bool: return entry.kind in ["hit", "kill", "disabled"]):
			scope.play_sfx(cues[cue])

## Preserve overlapping tails. At capacity only replace an older equal/lower
## priority voice, so automatic fire cannot cut off a heavy explosion.
func play_at(name: StringName, origin: Vector3, gain: float = 0.0) -> void:
	if _stopped:
		return
	var cue: PartyAudioCue = cues[name]
	var selected: AudioStreamPlayer3D
	var oldest: int = 2147483647
	var same_count: int = 0
	for voice: AudioStreamPlayer3D in _voices:
		if voice.playing and _voice_cues[voice] == cue:
			same_count += 1
	if same_count >= cue.max_instances:
		return
	for voice: AudioStreamPlayer3D in _voices:
		if not voice.playing:
			selected = voice
			break
		if _voice_cues[voice].priority <= cue.priority and _voice_order[voice] < oldest:
			oldest = _voice_order[voice]
			selected = voice
	if selected == null:
		return
	selected.stop()
	selected.global_position = origin
	selected.stream = cue.playback_stream()
	selected.volume_db = cue.volume_db + gain
	selected.pitch_scale = cue.pitch_scale * randf_range(0.97, 1.03)
	_serial += 1
	_voice_cues[selected] = cue
	_voice_order[selected] = _serial
	_start_spatial(selected)

## Godot registers 3D playbacks on the next physics tick. Keep the initial
## buffer silent until routing can apply the scope's current pause state.
func _start_spatial(player: AudioStreamPlayer3D) -> void:
	_pending_starts[player] = {"stream": player.stream, "gain": player.volume_db, "frame": Engine.get_physics_frames()}
	player.volume_db = -80.0
	player.play()

func _process(_delta: float) -> void:
	for player: AudioStreamPlayer3D in _pending_starts.keys():
		var pending: Dictionary = _pending_starts[player]
		if Engine.get_physics_frames() <= pending.frame:
			continue
		_pending_starts.erase(player)
		# A projectile can hit, or a voice can be stolen, before its first mix.
		if not is_instance_valid(player) or not player.playing or player.stream != pending.stream:
			continue
		scope.route_spatial(player, PartyGameAudio.Category.SFX)
		player.volume_db = pending.gain
