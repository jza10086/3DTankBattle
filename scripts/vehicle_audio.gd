extends Node3D
## Positional powertrain loops follow the authoritative vehicle state on every peer.
const Tank = preload("res://games/minigame/gp_tank_war/scripts/tank_controller.gd")
@export var engine: AudioStreamPlayer3D
@export var tracks: AudioStreamPlayer3D
@export var traverse: AudioStreamPlayer3D
@export var engine_cue: PartyAudioCue
@export var tracks_cue: PartyAudioCue
@export var traverse_cue: PartyAudioCue
var tank: Tank
var _scope: PartyGameAudio
var _yaw: float
var _pitch: float
var _pending_loops: Dictionary[AudioStreamPlayer3D, Dictionary] = {}

func start(vehicle: Tank, scope: PartyGameAudio) -> void:
	tank = vehicle
	_scope = scope
	_yaw = tank.visual.turret.rotation.y
	_pitch = tank.visual.barrel.rotation.x
	var players: Array[AudioStreamPlayer3D] = [engine, tracks, traverse]
	var cues: Array[PartyAudioCue] = [engine_cue, tracks_cue, traverse_cue]
	for index: int in players.size():
		assert(cues[index].validate() == OK)
		players[index].stream = cues[index].playback_stream()
		players[index].volume_db = -60.0
		scope.route_spatial(players[index], PartyGameAudio.Category.SFX)

func advance(delta: float) -> void:
	var moving: float = clampf((absf(tank.speed) + absf(tank.yaw_rate) * 2.5) / tank.spec.max_speed, 0.0, 1.0)
	var powered: bool = not tank.dead and tank.components.engine_remaining <= 0.0
	_loop(engine, powered, engine_cue.volume_db + moving * 6.0, engine_cue.pitch_scale * lerpf(0.78, 1.45, moving), delta)
	_loop(tracks, not tank.dead and moving > 0.012, tracks_cue.volume_db + linear_to_db(maxf(moving, 0.01)), lerpf(0.65, 1.45, moving), delta)
	var yaw: float = tank.visual.turret.rotation.y
	var pitch: float = tank.visual.barrel.rotation.x
	var motion: float = (absf(angle_difference(_yaw, yaw)) + absf(pitch - _pitch)) / maxf(delta, 0.001)
	_loop(traverse, not tank.dead and motion > 0.015, traverse_cue.volume_db, clampf(motion * 0.7 + 0.65, 0.65, 1.2), delta)
	_yaw = yaw
	_pitch = pitch

func _loop(player: AudioStreamPlayer3D, audible: bool, gain: float, pitch: float, delta: float) -> void:
	player.pitch_scale = pitch
	if _pending_loops.has(player):
		if not audible:
			_pending_loops.erase(player)
			player.stop()
		return
	player.volume_db = move_toward(player.volume_db, gain if audible else -60.0, delta * 65.0)
	if audible and not player.playing:
		player.play()
		_route_started_loop(player)
	elif not audible and player.volume_db <= -59.0:
		player.stop()

func _route_started_loop(player: AudioStreamPlayer3D) -> void:
	_pending_loops[player] = {"gain": player.volume_db, "frame": Engine.get_physics_frames()}
	player.volume_db = -80.0

func _process(_delta: float) -> void:
	for player: AudioStreamPlayer3D in _pending_loops.keys():
		var pending: Dictionary = _pending_loops[player]
		if Engine.get_physics_frames() <= pending.frame:
			continue
		_pending_loops.erase(player)
		if player.playing:
			_scope.route_spatial(player, PartyGameAudio.Category.SFX)
			player.volume_db = pending.gain
