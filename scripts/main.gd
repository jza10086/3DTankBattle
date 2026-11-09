extends Node3D
## Thunder War: host simulation, scope-bound inputs/snapshots and local camera/HUD.
const TankScript = preload("res://games/minigame/godot_party_default_tank_range/scripts/tank_controller.gd")
const TargetScript = preload("res://games/minigame/godot_party_default_tank_range/scripts/range_target.gd")
const ShellScript = preload("res://games/minigame/godot_party_default_tank_range/scripts/shell.gd")
const CameraScript = preload("res://games/minigame/godot_party_default_tank_range/scripts/tank_camera.gd")
const AudioScript = preload("res://games/minigame/godot_party_default_tank_range/scripts/combat_audio.gd")
const Spec = preload("res://games/minigame/godot_party_default_tank_range/scripts/vehicle_spec.gd")
const SPECS: Array[Spec] = [preload("res://games/minigame/godot_party_default_tank_range/vehicles/m1_abrams.tres"), preload("res://games/minigame/godot_party_default_tank_range/vehicles/bmpt.tres"), preload("res://games/minigame/godot_party_default_tank_range/vehicles/bradley.tres")]
@export var camera: CameraScript
@export var audio: AudioScript
const Pages = preload("res://games/protocols/godot_party_default_protocol/round_pages.gd")
const DamageModel = preload("res://games/minigame/godot_party_default_tank_range/scripts/armor_damage.gd")
const INPUT_INTERVAL: float = 0.05
const SNAPSHOT_INTERVAL: float = 0.05
const INPUT_EXPIRY: float = 0.5
var api: PartyAPI
var request: Dictionary
var pages: Pages
var players: Array[Dictionary] = []
var vehicles: Dictionary[String, TankScript] = {}
var commands: Dictionary[String, Dictionary] = {}
var withdrawn: Dictionary[String, bool] = {}
var remote_states: Dictionary = {}
var shells: Dictionary[int, ShellScript] = {}
var local_id: String = ""
var tank: TankScript
var targets: Array[TargetScript] = []
var hud: Control
var selecting: bool = false
var selection_sent: bool = false
var vehicle_choices: Dictionary[String, int] = {}
var started: bool = false
var finished: bool = false
var combat_ended: bool = false
var _round_end_remaining: float = 0.0
var _requested_ammunition: int = DamageModel.Ammo.AP
var elapsed: float = 0.0
var duration: float
var hits: int = 0
var destroyed_count: int = 0
var total_targets: int = 6
var hit_flash: float = 0.0
var feedbacks: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var _input_clock: float = 0.0
var _snapshot_clock: float = 0.0
var _input_sequence: int = 0
var _state_sequence: int = 0
var _received_state: int = -1
var _shot_id: int = 0
var _focused: bool = true
var _blocked: bool = true
var _pending_fire: bool = false
var _pending_recover: bool = false

func party_setup(value: PartyAPI, config: Dictionary) -> void:
	assert(camera != null and audio != null, "Thunder War requires its camera and combat audio components.")
	api = value
	audio.scope.prepare_scope()
	request = config.duplicate(true)
	players = api.get_players()
	duration = float(api.get_settings().duration)
	for player: Dictionary in players:
		if player.is_local:
			local_id = player.player_id
	api.net.message_received.connect(_message)
	api.players_changed.connect(_players_changed)

func _ready() -> void:
	if api == null:
		push_error("请从 GodotParty 大厅启动雷霆战争")
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	add_to_group("party_minimal_hud")
	hud = $GameHUD/RangeHUD
	hud.game = self
	for index: int in players.size():
		var vehicle: TankScript = SPECS[0].scene.instantiate()
		vehicle.spec = SPECS[0]
		vehicle.name = "Tank%d" % index
		add_child(vehicle)
		vehicle.position = Vector3(0, 0.8, 18)
		var id: String = players[index].player_id
		vehicle.player_id = id
		vehicle.player_name = players[index].name
		vehicles[id] = vehicle
		if players.size() > 1:
			var angle: float = TAU * index / players.size()
			vehicle.position = Vector3(sin(angle) * 48.0, 0.8, cos(angle) * 48.0)
			vehicle.rotation.y = angle
		vehicle.start_transform = vehicle.transform
		vehicle.nameplate.text = vehicle.player_name
		vehicle.nameplate.hide()
		vehicle.nameplate.modulate = Color(api.get_appearance(id).color)
		commands[id] = {"sequence": 0, "age": INPUT_EXPIRY, "fire": false, "machine_gun": false}
	if players.size() == 1:
		targets.assign($TargetStations.get_children())
	else:
		# The same authored map becomes the arena; training dummies are solo-only.
		for target: Node in $TargetStations.get_children():
			$TargetStations.remove_child(target)
			target.queue_free()
	tank = vehicles[local_id] if not local_id.is_empty() else vehicles[players[0].player_id]
	camera.configure(tank, not local_id.is_empty())
	for index: int in SPECS.size():
		var button: Button = %VehicleCards.get_child(index)
		button.text = "\n\n" + api.i18n.text(SPECS[index].name_key) + "\n" + api.i18n.text(SPECS[index].description_key).replace(" · ", "\n")
		button.get_node("Silhouette").texture = SPECS[index].silhouette
		button.pressed.connect(select_vehicle.bind(index))
	pages = Pages.new()
	var error: Error = pages.prepare(self, api, request, _begin_selection)
	if error != OK:
		_network_failure(error)

func godot_party_graphics_targets() -> Dictionary:
	return {"world": $WorldEnvironment1, "sun": $DirectionalLight3D2, "materials_root": self}

func party_start() -> void:
	pages.transport_started()

func _start_game() -> void:
	started = true
	for vehicle: TankScript in vehicles.values():
		vehicle.simulation_enabled = api.is_host()
	_players_changed()
	camera.active = true
	var audio_vehicles: Array[TankScript] = []
	audio_vehicles.assign(vehicles.values())
	audio.start(audio_vehicles, tank if not local_id.is_empty() else null)
	if api.is_host():
		_publish()

func party_stop(_reason: StringName) -> void:
	started = false
	set_physics_process(false)
	set_process(false)
	set_process_unhandled_input(false)
	for vehicle: TankScript in vehicles.values():
		vehicle.simulation_enabled = false
	for shell: ShellScript in shells.values():
		if is_instance_valid(shell):
			shell.set_physics_process(false)
	if api.net.message_received.is_connected(_message):
		api.net.message_received.disconnect(_message)
	if api.players_changed.is_connected(_players_changed):
		api.players_changed.disconnect(_players_changed)
	camera.active = false
	audio.stop()
	for target: TargetScript in targets:
		target.set_physics_process(false)
	pages.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func godot_party_audio_target() -> PartyGameAudio:
	return audio.scope

func _unhandled_input(event: InputEvent) -> void:
	if not started or finished or api.input.input_blocked or not _focused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera.move_look(event.relative)
	if api.input.event_matches(event, &"tank_zoom_in"):
		camera.adjust_zoom(1.0)
	elif api.input.event_matches(event, &"tank_zoom_out"):
		camera.adjust_zoom(-1.0)
	if local_id.is_empty() or tank.dead or combat_ended:
		return
	if api.input.event_matches(event, &"tank_sight"):
		camera.set_first_person(not camera.first_person)
	elif api.input.event_matches(event, &"tank_ammunition"):
		_requested_ammunition = tank.spec.weapons[1] if _requested_ammunition == tank.spec.weapons[0] else tank.spec.weapons[0]
		_input_clock = INPUT_INTERVAL
	elif api.input.event_matches(event, &"tank_fire"):
		_pending_fire = true
	elif api.input.event_matches(event, &"tank_recover") and players.size() == 1:
		_pending_recover = true
	elif api.input.event_matches(event, &"tank_center"):
		camera.center_on_vehicle()

func _physics_process(delta: float) -> void:
	if not started or finished:
		return
	var blocked: bool = api.input.input_blocked or not _focused
	if blocked != _blocked:
		_blocked = blocked
		_pending_fire = false
		_pending_recover = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if blocked else Input.MOUSE_MODE_CAPTURED
		_input_clock = INPUT_INTERVAL
	if api.is_host():
		if not combat_ended:
			elapsed += delta
		else:
			_round_end_remaining -= delta
			if _round_end_remaining <= 0.0:
				_finish_round()
				return
	else:
		for id: String in remote_states:
			vehicles[id].apply_snapshot(remote_states[id], delta)
	camera.advance(delta, elapsed)
	_input_clock += delta
	if _input_clock >= INPUT_INTERVAL and not local_id.is_empty():
		_input_clock = 0.0
		_send_input(blocked)
	if api.is_host():
		for id: String in vehicles:
			var vehicle: TankScript = vehicles[id]
			commands[id].age += delta
			if commands[id].age > INPUT_EXPIRY or vehicle.dead:
				vehicle.throttle = 0.0
				vehicle.steering = 0.0
				vehicle.brake = true
				commands[id].machine_gun = false
			if commands[id].fire:
				commands[id].fire = false
				_fire_vehicle(id)
			if commands[id].machine_gun:
				_fire_machine_gun(id)
		_snapshot_clock += delta
		if _snapshot_clock >= SNAPSHOT_INTERVAL:
			_snapshot_clock = 0.0
			_publish()
		_check_finish()
	hit_flash = maxf(0.0, hit_flash - delta)
	for feedback: Dictionary in feedbacks:
		feedback.age += delta
	while not feedbacks.is_empty() and feedbacks[0].age >= 1.6:
		feedbacks.pop_front()
	_update_effects(delta)
	audio.advance(delta)
	hud.queue_redraw()

func _send_input(blocked: bool) -> void:
	_input_sequence += 1
	var drive: float = 0.0
	var steer: float = 0.0
	if not blocked and not tank.dead:
		drive = float(api.input.is_pressed(&"move_up")) - float(api.input.is_pressed(&"move_down"))
		steer = float(api.input.is_pressed(&"move_left")) - float(api.input.is_pressed(&"move_right"))
	var data: Dictionary = {"seq": _input_sequence, "drive": drive, "steer": steer,
		"brake": blocked or api.input.is_pressed(&"tank_brake"), "aim": tank.aim_point,
		"direction_mode": camera.first_person, "direction": tank.requested_gun_direction,
		"fire": (_pending_fire or (DamageModel.is_automatic(_requested_ammunition) and api.input.is_pressed(&"tank_fire"))) and not blocked, "machine_gun": api.input.is_pressed(&"tank_machine_gun") and not blocked, "recover": _pending_recover and not blocked, "ammunition": _requested_ammunition}
	_pending_fire = false
	_pending_recover = false
	if api.is_host():
		_accept_input(local_id, data)
	else:
		_network_failure(api.net.send_to_host(&"tank_input", data))

## Authenticate ownership before consuming logical actions. Never accept client poses or damage.
func _message(sender: Dictionary, topic: StringName, payload: Variant) -> void:
	if topic == &"tank_selection" and not started and not finished:
		_selection_message(sender, payload)
		return
	if not started or finished or not payload is Dictionary:
		return
	if topic == &"tank_input" and api.is_host():
		for player: Dictionary in api.get_players():
			if player.connected and player.player_id in sender.player_ids and not withdrawn.has(player.player_id):
				_accept_input(player.player_id, payload)
				return
	elif sender.peer_id == 1 and not api.is_host():
		if topic == &"tank_state":
			if payload.sequence <= _received_state:
				return
			_received_state = payload.sequence
			elapsed = payload.elapsed
			combat_ended = payload.ending
			if combat_ended:
				audio.end_combat()
			var packed: PackedFloat32Array = payload.vehicles
			if packed.size() != players.size() * TankScript.SNAPSHOT_FLOATS:
				_network_failure(ERR_INVALID_DATA)
				return
			for i: int in players.size():
				remote_states[players[i].player_id] = packed.slice(i * TankScript.SNAPSHOT_FLOATS, (i + 1) * TankScript.SNAPSHOT_FLOATS)
			destroyed_count = payload.destroyed
			hits = payload.hits
			for i: int in targets.size():
				var target: TargetScript = targets[i]
				var state: Dictionary = payload.targets[i]
				if state.hp < target.hp:
					target.damage(target.hp - state.hp)
		elif topic == &"tank_missiles":
			if shells.has(payload.id) and is_instance_valid(shells[payload.id]):
				shells[payload.id].global_position = payload.position
				shells[payload.id].velocity = payload.velocity
		elif topic == &"tank_events":
			if payload.kind == "shot":
				_spawn_shell(payload.id, payload.player, payload.position, payload.velocity, false, payload.ammunition)
			elif payload.kind == "impact":
				if shells.has(payload.id) and is_instance_valid(shells[payload.id]):
					shells[payload.id].queue_free()
				shells.erase(payload.id)
				_impact_effect(payload.position, payload.normal, payload.player, payload.feedback, payload.ammunition, payload.surface)

func _accept_input(id: String, data: Dictionary) -> void:
	if combat_ended:
		return
	if not data.get("ammunition") is int or data.ammunition not in vehicles[id].spec.weapons:
		return
	if not data.get("seq") is int or data.seq <= commands[id].sequence:
		return
	for key: String in ["drive", "steer"]:
		if not (data.get(key) is float or data.get(key) is int) or not is_finite(float(data[key])) or absf(data[key]) > 1.0:
			return
	for key: String in ["brake", "direction_mode", "fire", "recover", "machine_gun"]:
		if not data.get(key) is bool:
			return
	for key: String in ["aim", "direction"]:
		if not data.get(key) is Vector3 or not data[key].is_finite():
			return
	if data.aim.length() > 2000.0 or data.direction.length_squared() < 0.5 or data.direction.length_squared() > 1.5:
		return
	var vehicle: TankScript = vehicles[id]
	commands[id].sequence = data.seq
	commands[id].age = 0.0
	if vehicle.dead or withdrawn.has(id):
		return
	vehicle.switch_ammunition(data.ammunition)
	vehicle.throttle = data.drive
	vehicle.steering = data.steer
	vehicle.brake = data.brake
	vehicle.aim_point = data.aim
	vehicle.aim_direction_mode = data.direction_mode
	vehicle.requested_gun_direction = data.direction.normalized()
	commands[id].fire = commands[id].fire or data.fire
	commands[id].machine_gun = data.machine_gun
	if data.recover and players.size() == 1:
		vehicle.reset_vehicle()

func _fire_vehicle(id: String) -> void:
	if combat_ended:
		return
	var vehicle: TankScript = vehicles[id]
	if not vehicle.begin_fire():
		return
	_shot_id += 1
	var origin: Vector3 = vehicle.shot_muzzle().global_position
	var velocity: Vector3 = vehicle.muzzle_direction() * DamageModel.shell_speed(vehicle.ammunition)
	_spawn_shell(_shot_id, id, origin, velocity, true, vehicle.ammunition)
	_network_failure(api.net.broadcast_stream(&"tank_events", {"kind": "shot", "id": _shot_id, "player": id, "position": origin, "velocity": velocity, "ammunition": vehicle.ammunition}, "instance", true))

func _fire_machine_gun(id: String) -> void:
	var vehicle: TankScript = vehicles[id]
	if combat_ended or withdrawn.has(id) or not vehicle.begin_machine_gun_fire():
		return
	_shot_id += 1
	var origin: Vector3 = vehicle.coax_muzzle.global_position
	var velocity: Vector3 = -vehicle.coax_muzzle.global_basis.z.normalized() * DamageModel.shell_speed(DamageModel.Ammo.MG)
	_spawn_shell(_shot_id, id, origin, velocity, true, DamageModel.Ammo.MG)
	_network_failure(api.net.broadcast_stream(&"tank_events", {"kind": "shot", "id": _shot_id, "player": id, "position": origin, "velocity": velocity, "ammunition": DamageModel.Ammo.MG}, "instance", true))

func _spawn_shell(id: int, player: String, origin: Vector3, velocity: Vector3, authoritative: bool, ammunition: int) -> void:
	var shell: ShellScript = ShellScript.new()
	shell.authoritative = authoritative
	shell.ammunition = ammunition
	if authoritative:
		shell.damage_targets.assign(vehicles.values() + targets)
	shell.shooter = vehicles[player]
	shell.velocity = velocity
	add_child(shell)
	shell.global_position = origin
	shells[id] = shell
	if authoritative:
		shell.impacted.connect(_shell_impact.bind(id, player, ammunition))
	shell.tree_exited.connect(func() -> void: shells.erase(id))
	var automatic: bool = DamageModel.is_automatic(ammunition)
	if player == local_id:
		camera.shot_shake = maxf(camera.shot_shake, 0.035 if ammunition == DamageModel.Ammo.MG else (0.18 if automatic else 1.0))
	audio.fire(ammunition, origin, shell)
	_emit_effect(origin, Color("ffdb7c"), 0.12 if ammunition == DamageModel.Ammo.MG else (0.3 if camera.first_person and player == local_id else 0.9), 0.12, Vector3.ZERO)

func _shell_impact(point: Vector3, normal: Vector3, contacts: Array[Dictionary], id: int, player: String, ammunition: int) -> void:
	var feedback: Array[Dictionary] = []
	var surface: StringName = &"ground"
	for contact: Dictionary in contacts:
		var collider: Node3D = contact.target
		var result: Dictionary = contact.result
		if surface != &"wreck":
			surface = &"wreck" if collider.dead and result.damage > 0.0 else (&"ricochet" if result.get("ricochet", false) else &"armor")
		var damage: float = result.damage
		if damage <= 0.0:
			if result.get("ricochet", false):
				feedback.append({"kind": "ricochet", "text": "跳弹"})
			elif not result.get("ignored", false):
				feedback.append({"kind": "blocked", "text": "未击穿"})
			continue
		if collider is TankScript and collider.dead:
			collider.death_time = elapsed
		if collider == vehicles[player]:
			continue
		vehicles[player].damage_dealt += damage
		hits += 1
		if collider.dead:
			if collider is TankScript:
				vehicles[player].kills += 1
			else:
				destroyed_count += 1
			feedback.append({"kind": "kill", "text": "击杀" if collider is TankScript else "目标摧毁"})
		elif result.disabled:
			var label: String = "敌人瘫痪"
			if result.component == &"barrel": label = "敌方主炮瘫痪"
			elif String(result.component).ends_with("track"): label = "敌方履带损毁"
			feedback.append({"kind": "disabled", "text": label})
		else:
			feedback.append({"kind": "hit", "text": "命中"})
	_impact_effect(point, normal, player, feedback, ammunition, surface)
	_network_failure(api.net.broadcast_stream(&"tank_events", {"kind": "impact", "id": id, "position": point,
		"normal": normal, "player": player, "feedback": feedback, "ammunition": ammunition, "surface": surface}, "instance", true))

func _impact_effect(point: Vector3, normal: Vector3, player: String, feedback: Array, ammunition: int, surface: StringName) -> void:
	audio.impact(point, ammunition, surface, feedback, player == local_id)
	if player == local_id:
		for entry: Dictionary in feedback:
			feedbacks.append({"kind": entry.kind, "text": api.i18n.text(entry.text), "age": 0.0})
			if entry.kind in ["hit", "disabled", "kill"]: hit_flash = 0.4
		while feedbacks.size() > 4:
			feedbacks.pop_front()
	var explosive: bool = DamageModel.is_explosive(ammunition)
	_emit_effect(point + normal * 0.2, Color("ffca67"), 2.8 if explosive else 0.8, 0.25 if explosive else 0.12, Vector3.ZERO)
	for i: int in (14 if explosive else 6):
		_emit_effect(point, Color("746e57"), randf_range(0.4, 1.1) if explosive else randf_range(0.15, 0.4), randf_range(0.7, 1.5), Vector3(randf_range(-3, 3), randf_range(0.4, 5), randf_range(-3, 3)))

func _publish() -> void:
	var states: PackedFloat32Array = []
	for player: Dictionary in players:
		states.append_array(vehicles[player.player_id].make_snapshot())
	for id: int in shells:
		var shell: ShellScript = shells[id]
		if is_instance_valid(shell) and DamageModel.is_missile(shell.ammunition):
			_network_failure(api.net.broadcast_stream(&"tank_missiles", {"id": id, "position": shell.global_position, "velocity": shell.velocity}, "instance", true))
	var target_states: Array[Dictionary] = []
	for target: TargetScript in targets:
		target_states.append({"hp": target.hp})
	_state_sequence += 1
	_network_failure(api.net.broadcast_stream(&"tank_state", {"sequence": _state_sequence, "elapsed": elapsed, "ending": combat_ended,
		"vehicles": states, "targets": target_states, "destroyed": destroyed_count, "hits": hits}, "instance", true))

func _players_changed() -> void:
	if not api.is_host() or (not started and not selecting) or finished:
		return
	for player: Dictionary in api.get_players():
		if not player.connected and not withdrawn.has(player.player_id):
			withdrawn[player.player_id] = true
			var vehicle: TankScript = vehicles[player.player_id]
			vehicle.dead = true
			vehicle.hp = 0.0
			vehicle.speed = 0.0
			vehicle.visual.set_destroyed(true)
	if selecting: _publish_selection()

func _check_finish() -> void:
	if combat_ended:
		return
	var alive: int = 0
	for vehicle: TankScript in vehicles.values():
		if not vehicle.dead:
			alive += 1
	if (players.size() > 1 and alive <= 1) or (players.size() == 1 and destroyed_count == total_targets) or elapsed >= duration:
		combat_ended = true
		audio.end_combat()
		_round_end_remaining = 1.6
		for vehicle: TankScript in vehicles.values():
			vehicle.simulation_enabled = false
		for shell: ShellScript in shells.values():
			if is_instance_valid(shell): shell.set_physics_process(false)

## Survival ranks first; simultaneous eliminations tie unless damage separates them.
func _better(a: TankScript, b: TankScript) -> bool:
	if a.dead != b.dead:
		return not a.dead
	if not a.dead and a.hp != b.hp:
		return a.hp > b.hp
	if a.dead and not is_equal_approx(a.death_time, b.death_time):
		return a.death_time > b.death_time
	return a.damage_dealt > b.damage_dealt

func _finish_round() -> void:
	if finished:
		return
	finished = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera.active = false
	audio.stop()
	var rankings: Array[Dictionary] = []
	for id: String in vehicles:
		var vehicle: TankScript = vehicles[id]
		var rank_value: int = 1
		for other: String in vehicles:
			if not withdrawn.has(other) and _better(vehicles[other], vehicle):
				rank_value += 1
		rankings.append({"player_id": id, "rank": 0 if withdrawn.has(id) else rank_value,
			"status": "withdrawn" if withdrawn.has(id) else "completed",
			"metrics": {"damage": roundi(vehicle.damage_dealt), "kills": vehicle.kills if players.size() > 1 else destroyed_count,
				"hp": roundi(vehicle.hp), "time": roundi(elapsed * 1000.0)}})
	var result: Dictionary = {"request_id": request.request_id, "reason": "completed", "rankings": rankings,
		"columns": [{"key": "kills", "title": "击毁", "format": "integer"}, {"key": "damage", "title": "伤害", "format": "integer"},
			{"key": "hp", "title": "剩余生命", "format": "integer"}, {"key": "time", "title": "用时", "format": "time"}]}
	_network_failure(pages.present(result))

func _network_failure(error: Error) -> void:
	if error == OK:
		return
	push_error("雷霆战争：" + error_string(error))
	started = false
	audio.stop()
	process_mode = Node.PROCESS_MODE_DISABLED
	api.fail("tank_round_failed", error_string(error))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _emit_effect(at: Vector3, color: Color, size: float, duration: float, velocity: Vector3) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = size * 0.5
	mesh.height = size
	mesh.radial_segments = 6
	mesh.rings = 3
	node.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	node.material_override = mat
	add_child(node)
	node.global_position = at
	effects.append({"node": node, "life": duration, "total": duration, "velocity": velocity})

func _update_effects(delta: float) -> void:
	for i: int in range(effects.size() - 1, -1, -1):
		var effect: Dictionary = effects[i]
		effect.life -= delta
		if effect.life <= 0:
			effect.node.queue_free()
			effects.remove_at(i)
			continue
		effect.node.position += effect.velocity * delta
		effect.velocity *= 1.0 - delta * 1.3
		effect.node.scale = Vector3.ONE * (1.0 + (1.0 - effect.life / effect.total) * 1.3) * minf(1.0, effect.life * 5)

func _begin_selection() -> void:
	if started:
		return
	selecting = true
	%SelectionTitle.text = api.i18n.text("selection.title")
	%SelectionSubtitle.text = api.i18n.text("selection.subtitle")
	$GameHUD.hide()
	%VehicleSelection.show()
	%SelectionStatus.text = api.i18n.text("selection.controls", {"weapon": api.input.binding_text(&"tank_ammunition"), "sight": api.input.binding_text(&"tank_sight")})
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if local_id.is_empty():
		for button: Button in %VehicleCards.get_children(): button.disabled = true
		%SelectionStatus.text = api.i18n.text("selection.spectating")
	if api.is_host(): _players_changed()

## Selection is immutable after confirmation and owned by the sending participant.
func select_vehicle(index: int) -> void:
	if not selecting or selection_sent or local_id.is_empty():
		return
	selection_sent = true
	for button: Button in %VehicleCards.get_children(): button.disabled = true
	%SelectionStatus.text = api.i18n.text("selection.waiting", {"vehicle": api.i18n.text(SPECS[index].name_key)})
	_network_failure(api.net.send_to_host(&"tank_selection", {"kind": "choose", "vehicle": index}))

func _selection_message(sender: Dictionary, payload: Variant) -> void:
	if not payload is Dictionary:
		return
	if api.is_host() and payload.get("kind") == "choose":
		if not payload.get("vehicle") is int or payload.vehicle < 0 or payload.vehicle >= SPECS.size():
			return
		for player: Dictionary in api.get_players():
			if player.connected and player.peer_id == sender.peer_id and player.player_id in sender.player_ids and not vehicle_choices.has(player.player_id):
				vehicle_choices[player.player_id] = payload.vehicle
				_publish_selection()
				return
	elif sender.peer_id == 1 and not api.is_host() and payload.get("kind") == "deploy":
		if not payload.get("choices") is Dictionary or payload.choices.size() != players.size():
			_network_failure(ERR_INVALID_DATA)
			return
		for player: Dictionary in players:
			var value: Variant = payload.choices.get(player.player_id)
			if not value is int or value < 0 or value >= SPECS.size():
				_network_failure(ERR_INVALID_DATA)
				return
		vehicle_choices.assign(payload.choices)
		_deploy_vehicles()

func _publish_selection() -> void:
	if not selecting:
		return
	for player: Dictionary in api.get_players():
		if not player.connected:
			vehicle_choices[player.player_id] = 0
		elif not vehicle_choices.has(player.player_id):
			return
	var error: Error = api.net.broadcast(&"tank_selection", {"kind": "deploy", "choices": vehicle_choices})
	if error != OK:
		_network_failure(error)
		return
	_deploy_vehicles()

func _deploy_vehicles() -> void:
	for id: String in vehicles:
		var previous: TankScript = vehicles[id]
		var index: int = vehicle_choices[id]
		var vehicle: TankScript = SPECS[index].scene.instantiate()
		vehicle.spec = SPECS[index]
		vehicle.vehicle_index = index
		vehicle.transform = previous.transform
		vehicle.player_id = previous.player_id
		vehicle.player_name = previous.player_name
		vehicle.hp = previous.hp
		vehicle.dead = previous.dead
		add_child(vehicle)
		vehicle.nameplate.text = previous.nameplate.text
		vehicle.nameplate.modulate = previous.nameplate.modulate
		vehicle.nameplate.hide()
		vehicle.visual.set_destroyed(vehicle.dead)
		vehicles[id] = vehicle
		remove_child(previous)
		previous.queue_free()
	tank = vehicles[local_id] if not local_id.is_empty() else vehicles[players[0].player_id]
	camera.configure(tank, not local_id.is_empty())
	_requested_ammunition = tank.ammunition
	selecting = false
	%VehicleSelection.hide()
	$GameHUD.show()
	_start_game()
