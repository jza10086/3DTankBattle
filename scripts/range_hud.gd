extends Control
## War Thunder-style combat HUD: mouse aim ring, per-barrel real-time impact reticles, and bore-anchored optic.
const Tank = preload("res://games/minigame/GP_tank_war/scripts/tank_controller.gd")
const DamageModel = preload("res://games/minigame/GP_tank_war/scripts/armor_damage.gd")
const GUN_ICONS: Array[Texture2D] = [preload("res://games/minigame/GP_tank_war/assets/ui/m68_cannon.svg"), preload("res://games/minigame/GP_tank_war/assets/ui/twin_cannon.svg"), preload("res://games/minigame/GP_tank_war/assets/ui/autocannon.svg")]
const LAUNCHER_ICON: Texture2D = preload("res://games/minigame/GP_tank_war/assets/ui/missile_launcher.svg")
const WHITE: Color = Color("f3eedc")
const GREEN: Color = Color("6ce87a")
const AMBER: Color = Color("ffc66d")
const RED: Color = Color("ff685c")
const SHADOW: Color = Color(0.02, 0.03, 0.02, 0.78)
const OPTIC_LINE: Color = Color(0.06, 0.08, 0.06, 0.88)
const OPTIC_HIGHLIGHT: Color = Color(0.86, 0.90, 0.82, 0.26)
var game: Node3D
var font: Font = ThemeDB.fallback_font

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if game == null or not game.started:
		return
	var tank: Tank = game.tank
	%Speed.text = "%02d" % roundi(absf(tank.speed) * 3.6)
	%HullHealth.max_value = maxf(tank.max_hp, 1.0)
	%HullHealth.value = tank.hp
	%HealthValue.text = str(roundi(tank.hp))
	%HullHealth.modulate = RED if tank.hp <= tank.max_hp * 0.25 else WHITE
	var condition: PackedStringArray = []
	if tank.dead:
		condition.append(game.api.i18n.text("坦克已被击毁"))
	elif game.local_id.is_empty():
		condition.append(game.api.i18n.text("观战"))
	else:
		if tank.components.engine_remaining > 0.0: condition.append(game.api.i18n.text("发动机瘫痪"))
		if tank.components.left_track_remaining > 0.0 or tank.components.right_track_remaining > 0.0:
			condition.append(game.api.i18n.text("履带损毁"))
		if tank.components.barrel_remaining > 0.0: condition.append(game.api.i18n.text("主炮维修中"))
		if tank.muzzle_obstructed: condition.append(game.api.i18n.text("炮口受阻"))
	%VehicleCondition.text = " · ".join(condition)
	var repairing: bool = tank.is_active_weapon_repairing()
	var remaining: float = tank.reload_remaining
	var loaded: bool = remaining <= 0.0 and not repairing and not tank.dead
	var reload_progress: float = 0.0 if repairing or tank.dead else clampf(1.0 - remaining / maxf(tank.components.reload_duration, 0.001), 0.0, 1.0)
	var shell_spec: TankShellSpec = tank.ammo_spec()
	%AmmoName.text = game.api.i18n.text(shell_spec.display_name)
	%WeaponName.text = game.api.i18n.text(shell_spec.weapon_name)
	var default_gun_icon: Texture2D = GUN_ICONS[clampi(tank.vehicle_index, 0, GUN_ICONS.size() - 1)]
	var gun_tex: Texture2D = tank.spec.gun_icon if tank.spec != null and tank.spec.gun_icon != null else default_gun_icon
	var launcher_tex: Texture2D = tank.spec.launcher_icon if tank.spec != null and tank.spec.launcher_icon != null else LAUNCHER_ICON
	%WeaponIcon.texture = launcher_tex if shell_spec.guided_missile else gun_tex
	%VehicleIcon.texture = tank.spec.silhouette
	%AmmoState.text = game.api.i18n.text("武器失效") if tank.dead else (game.api.i18n.text("主炮维修中") if repairing else (game.api.i18n.text("准备就绪") if loaded else game.api.i18n.text("hud.reloading", {"seconds": "%.1f" % remaining})))
	%AmmoState.modulate = WHITE if loaded else AMBER
	if shell_spec.icon != null:
		%ShellFill.texture_under = shell_spec.icon
		%ShellFill.texture_progress = shell_spec.icon
	%ShellFill.value = 100.0 * reload_progress
	%ShellFill.tint_progress = WHITE if loaded else AMBER
	var active_slot: StringName = tank.reload_slot_for(tank.ammunition)
	var choice_parts: PackedStringArray = []
	for code: int in tank.weapon_codes():
		var option_spec: TankShellSpec = tank.ammo_spec_for(code)
		var label: String = option_spec.short_label if not option_spec.short_label.is_empty() else game.api.i18n.text(option_spec.display_name)
		var option_slot: StringName = option_spec.resolved_reload_slot()
		if code == tank.ammunition:
			choice_parts.append("[ %s ]" % label)
		else:
			var bg_remaining: float = tank.weapon_reload_remaining_for(code)
			var bg_duration: float = tank.weapon_reload_duration_for(code)
			if option_slot != active_slot and bg_remaining > 0.0 and bg_duration >= 0.35:
				choice_parts.append("%s %.1fs" % [label, bg_remaining])
			else:
				choice_parts.append(label)
	var choices: String = "   ".join(choice_parts)
	%AmmoSelector.text = game.api.i18n.text("hud.weapon_selector", {"key": game.api.input.binding_text(&"tank_ammunition"), "choices": choices})
	%MachineGunStatus.text = game.api.i18n.text("hud.machine_gun", {"key": game.api.input.binding_text(&"tank_machine_gun"), "rounds": tank.mg_rounds}) if tank.mg_reload_remaining <= 0.0 else game.api.i18n.text("hud.machine_gun_reload", {"seconds": "%.1f" % tank.mg_reload_remaining})
	%MachineGunReload.value = 100.0 * (1.0 - tank.mg_reload_remaining / tank.mg_reload_seconds())
	%MachineGunRow.modulate = RED if tank.dead else (AMBER if tank.mg_reload_remaining > 0.0 else WHITE)
	var center: Vector2 = size * 0.5
	var optic_radius: float = size.y * 0.475
	if game.camera.first_person:
		_draw_optic(center, optic_radius, tank)
	_draw_mouse_aim_ring(center)
	_draw_barrel_reticles(center, optic_radius, tank, loaded, repairing, reload_progress)
	_draw_coax_reticle(center, optic_radius)
	if game.hit_flash > 0.0:
		for axis: Vector2 in [Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(1.0, -1.0), Vector2(-1.0, -1.0)]:
			draw_line(center + axis * 26.0, center + axis * 35.0, SHADOW, 3.6, true)
			draw_line(center + axis * 26.0, center + axis * 35.0, WHITE, 2.0, true)
	for i: int in game.feedbacks.size():
		var entry: Dictionary = game.feedbacks[i]
		var color: Color = RED if entry.kind == "kill" else (AMBER if entry.kind == "disabled" else WHITE)
		color.a = minf(1.0, (1.6 - entry.age) / 0.4)
		var point: Vector2 = center + Vector2(66.0, -24.0 + i * 28.0 - entry.age * 12.0)
		_caption(entry.text, point, color, 23 if entry.kind == "kill" else 20)

func _draw_mouse_aim_ring(center: Vector2) -> void:
	var alpha: float = 0.58 if game.camera.first_person else 0.78
	var ring_color: Color = Color(WHITE.r, WHITE.g, WHITE.b, alpha)
	var shadow_color: Color = Color(SHADOW.r, SHADOW.g, SHADOW.b, alpha * 0.85)
	var ring_radius: float = 23.0
	draw_arc(center, ring_radius, 0.0, TAU, 56, shadow_color, 3.0, true)
	draw_arc(center, ring_radius, 0.0, TAU, 56, ring_color, 1.4, true)
	for axis: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + axis * 14.0, center + axis * 19.0, shadow_color, 2.8, true)
		draw_line(center + axis * 14.0, center + axis * 19.0, ring_color, 1.3, true)
	draw_circle(center, 2.2, shadow_color)
	draw_circle(center, 1.4, ring_color)

func _draw_barrel_reticles(center: Vector2, optic_radius: float, tank: Tank, loaded: bool, repairing: bool, reload_progress: float) -> void:
	var impacts: Array[Dictionary] = game.camera.barrel_impacts
	var multi_barrel: bool = impacts.size() > 1
	var ring_radius: float = 6.5 if multi_barrel else 10.5
	var show_reload_arc: bool = (not loaded) and (repairing or tank.components.reload_duration >= 0.35)
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, size)
	var projected: Array[Dictionary] = []
	for entry: Dictionary in impacts:
		var world_point: Vector3 = entry.impact
		if game.camera.is_position_behind(world_point):
			continue
		var screen_pos: Vector2 = game.camera.unproject_position(world_point)
		projected.append({"entry": entry, "pos": screen_pos})
	# Keep twin-barrel direction reticles cleanly separated and sharp at long range while
	# using exact physical projection whenever their screen spacing exceeds min_sep.
	if projected.size() == 2:
		var delta_px: Vector2 = (projected[1].pos as Vector2) - (projected[0].pos as Vector2)
		var min_sep: float = ring_radius * 2.5
		if delta_px.length() < min_sep:
			var axis: Vector2 = delta_px.normalized() if delta_px.length_squared() > 0.001 else Vector2.RIGHT
			var mid: Vector2 = ((projected[0].pos as Vector2) + (projected[1].pos as Vector2)) * 0.5
			projected[0].pos = mid - axis * (min_sep * 0.5)
			projected[1].pos = mid + axis * (min_sep * 0.5)
	for item: Dictionary in projected:
		var entry: Dictionary = item.entry
		var screen_pos: Vector2 = item.pos
		if not viewport_rect.has_point(screen_pos):
			continue
		if game.camera.first_person and screen_pos.distance_to(center) > optic_radius - 4.0:
			continue
		var color: Color = _impact_color(tank, entry, repairing)
		var obstructed: bool = bool(entry.obstructed)
		draw_arc(screen_pos, ring_radius, 0.0, TAU, 48, SHADOW, 3.4, true)
		if show_reload_arc:
			var dim_color: Color = Color(color.r, color.g, color.b, 0.34)
			draw_arc(screen_pos, ring_radius, 0.0, TAU, 48, dim_color, 1.4, true)
			if not repairing and not tank.dead and reload_progress > 0.01:
				draw_arc(screen_pos, ring_radius, -PI * 0.5, -PI * 0.5 + TAU * reload_progress, 40, AMBER, 2.2, true)
		else:
			draw_arc(screen_pos, ring_radius, 0.0, TAU, 48, color, 1.6, true)
		var tick_inner: float = ring_radius + 1.4
		var tick_outer: float = ring_radius + (3.8 if multi_barrel else 5.8)
		for axis: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(screen_pos + axis * tick_inner, screen_pos + axis * tick_outer, SHADOW, 3.0, true)
			draw_line(screen_pos + axis * tick_inner, screen_pos + axis * tick_outer, color, 1.45, true)
		if obstructed:
			var cross: float = ring_radius * 0.48
			draw_line(screen_pos + Vector2(-cross, -cross), screen_pos + Vector2(cross, cross), SHADOW, 3.0, true)
			draw_line(screen_pos + Vector2(-cross, cross), screen_pos + Vector2(cross, -cross), SHADOW, 3.0, true)
			draw_line(screen_pos + Vector2(-cross, -cross), screen_pos + Vector2(cross, cross), AMBER, 1.5, true)
			draw_line(screen_pos + Vector2(-cross, cross), screen_pos + Vector2(cross, -cross), AMBER, 1.5, true)
		else:
			draw_circle(screen_pos, 2.5, SHADOW)
			draw_circle(screen_pos, 1.7, color)

func _draw_coax_reticle(center: Vector2, optic_radius: float) -> void:
	if not game.camera.coax_valid or game.camera.is_position_behind(game.camera.coax_impact):
		return
	var screen_pos: Vector2 = game.camera.unproject_position(game.camera.coax_impact)
	if not Rect2(Vector2.ZERO, size).has_point(screen_pos):
		return
	if game.camera.first_person and screen_pos.distance_to(center) > optic_radius - 4.0:
		return
	var color: Color = Color(WHITE.r, WHITE.g, WHITE.b, 0.72)
	if game.camera.coax_obstructed:
		color = Color(AMBER.r, AMBER.g, AMBER.b, 0.8)
	elif game.camera.coax_hit_target:
		if game.camera.coax_armor_grade >= 2:
			color = Color(GREEN.r, GREEN.g, GREEN.b, 0.85)
		elif game.camera.coax_armor_grade == 1:
			color = Color(AMBER.r, AMBER.g, AMBER.b, 0.85)
		else:
			color = Color(RED.r, RED.g, RED.b, 0.85)
	draw_arc(screen_pos, 4.5, 0.0, TAU, 24, SHADOW, 2.6, true)
	draw_arc(screen_pos, 4.5, 0.0, TAU, 24, color, 1.2, true)
	draw_circle(screen_pos, 1.2, color)

func _impact_color(tank: Tank, entry: Dictionary, repairing: bool) -> Color:
	if tank.dead or repairing:
		return RED
	if bool(entry.obstructed):
		return AMBER
	if bool(entry.hit_target):
		var grade: int = int(entry.armor_grade)
		if grade >= 2:
			return GREEN
		if grade == 1:
			return AMBER
		return RED
	return WHITE

func _draw_optic(center: Vector2, radius: float, tank: Tank) -> void:
	# Four annular quadrants mask the viewport outside the circular gunner telescope.
	for quadrant: int in 4:
		var polygon: PackedVector2Array = []
		for step: int in 33:
			var angle: float = (quadrant + step / 32.0) * PI * 0.5
			polygon.append(center + Vector2(cos(angle), sin(angle)) * radius)
		for step: int in range(32, -1, -1):
			var angle: float = (quadrant + step / 32.0) * PI * 0.5
			polygon.append(center + Vector2(cos(angle), sin(angle)) * size.length())
		draw_colored_polygon(polygon, Color(0.015, 0.02, 0.018, 0.97))
	draw_arc(center, radius, 0.0, TAU, 160, Color(0.16, 0.18, 0.15), 5.0, true)
	var clip_radius: float = radius - 4.0
	var bore_behind: bool = game.camera.is_position_behind(game.camera.bore_aim_point)
	var bore_pos: Vector2 = game.camera.unproject_position(game.camera.bore_aim_point)
	if bore_behind or bore_pos.distance_to(center) > clip_radius - 10.0:
		var to_bore: Vector2 = (center - bore_pos) if bore_behind else (bore_pos - center)
		if to_bore.length_squared() < 0.01:
			to_bore = Vector2.RIGHT
		var edge_dir: Vector2 = to_bore.normalized()
		var tip: Vector2 = center + edge_dir * (clip_radius - 10.0)
		var perp: Vector2 = Vector2(-edge_dir.y, edge_dir.x)
		var base_left: Vector2 = tip - edge_dir * 12.0 + perp * 7.0
		var base_right: Vector2 = tip - edge_dir * 12.0 - perp * 7.0
		draw_colored_polygon(PackedVector2Array([tip, base_left, base_right]), AMBER)
		return
	# Bore-anchored War Thunder ballistic crosshair moving with the physical gun barrel.
	var half_tan: float = tan(deg_to_rad(game.camera.fov * 0.5))
	var px_per_rad: float = (size.y * 0.5) / maxf(half_tan, 0.001)
	var gap: float = 14.0
	var span: float = clip_radius * 2.0
	_draw_optic_segment(bore_pos + Vector2.LEFT * gap, bore_pos + Vector2.LEFT * span, center, clip_radius, 1.4)
	_draw_optic_segment(bore_pos + Vector2.RIGHT * gap, bore_pos + Vector2.RIGHT * span, center, clip_radius, 1.4)
	_draw_optic_segment(bore_pos + Vector2.UP * gap, bore_pos + Vector2.UP * (clip_radius * 0.35), center, clip_radius, 1.2)
	_draw_optic_segment(bore_pos + Vector2.DOWN * gap, bore_pos + Vector2.DOWN * span, center, clip_radius, 1.4)
	# Central bore chevron.
	_draw_optic_segment(bore_pos + Vector2(-7.0, 5.0), bore_pos, center, clip_radius, 1.5)
	_draw_optic_segment(bore_pos + Vector2(7.0, 5.0), bore_pos, center, clip_radius, 1.5)
	# Horizontal angular mil-dot graduations (4 mil per step, scaling dynamically with FOV).
	var mil_step_px: float = tan(0.004) * px_per_rad
	if mil_step_px >= 6.0:
		for i: int in range(1, 16):
			var offset_x: float = i * mil_step_px
			if offset_x > clip_radius * 1.4:
				break
			var tick_h: float = 10.0 if i % 2 == 0 else 5.5
			for side: float in [-1.0, 1.0]:
				var at: Vector2 = bore_pos + Vector2(side * offset_x, 0.0)
				_draw_optic_segment(at - Vector2(0.0, tick_h), at + Vector2(0.0, tick_h), center, clip_radius, 1.1)
	# Vertical real ballistic drop graduations calibrated to current TankShellSpec velocity & gravity.
	var active_spec: TankShellSpec = tank.ammo_spec()
	var gravity: float = active_spec.gravity
	if gravity > 0.0:
		var speed: float = maxf(active_spec.muzzle_velocity, 1.0)
		var distances: PackedFloat32Array = PackedFloat32Array([50.0, 100.0, 150.0, 200.0, 250.0, 300.0, 400.0])
		for idx: int in distances.size():
			var dist: float = distances[idx]
			var drop_tan: float = (gravity * dist) / (2.0 * speed * speed)
			var dy: float = drop_tan * px_per_rad
			if dy < gap + 3.0:
				continue
			if dy > clip_radius * 1.6:
				break
			var half_w: float = 14.0 if idx % 2 == 1 else 8.0
			var at: Vector2 = bore_pos + Vector2(0.0, dy)
			_draw_optic_segment(at - Vector2(half_w, 0.0), at + Vector2(half_w, 0.0), center, clip_radius, 1.2)
	else:
		# Symmetric ATGM stadia ticks when guided missile has zero gravity drop.
		var step_y: float = maxf(mil_step_px, 16.0)
		for i: int in range(1, 6):
			var half_w: float = 12.0 if i % 2 == 0 else 7.0
			var at: Vector2 = bore_pos + Vector2(0.0, i * step_y)
			_draw_optic_segment(at - Vector2(half_w, 0.0), at + Vector2(half_w, 0.0), center, clip_radius, 1.1)

func _draw_optic_segment(a: Vector2, b: Vector2, center: Vector2, radius: float, width: float) -> void:
	var d: Vector2 = b - a
	var f: Vector2 = a - center
	var qa: float = d.dot(d)
	if qa < 0.0001:
		return
	var qb: float = 2.0 * f.dot(d)
	var qc: float = f.dot(f) - radius * radius
	var disc: float = qb * qb - 4.0 * qa * qc
	if disc <= 0.0:
		return
	var sqrt_disc: float = sqrt(disc)
	var t0: float = clampf((-qb - sqrt_disc) / (2.0 * qa), 0.0, 1.0)
	var t1: float = clampf((-qb + sqrt_disc) / (2.0 * qa), 0.0, 1.0)
	if t1 <= t0:
		return
	var p0: Vector2 = a + d * t0
	var p1: Vector2 = a + d * t1
	draw_line(p0, p1, OPTIC_HIGHLIGHT, width + 1.4, true)
	draw_line(p0, p1, OPTIC_LINE, width, true)

func _caption(value: String, point: Vector2, color: Color, font_size: int) -> void:
	draw_string_outline(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0.03, 0.05, 0.04, color.a * 0.9))
	draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
