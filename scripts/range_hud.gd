extends Control
## Minimal combat instrumentation; camera intent and ballistic impact stay distinct.
const Tank = preload("res://games/minigame/godot_party_default_tank_range/scripts/tank_controller.gd")
const DamageModel = preload("res://games/minigame/godot_party_default_tank_range/scripts/armor_damage.gd")
const AP_ICON: Texture2D = preload("res://games/minigame/godot_party_default_tank_range/assets/ui/shell_ap.svg")
const HE_ICON: Texture2D = preload("res://games/minigame/godot_party_default_tank_range/assets/ui/shell_he.svg")
const WHITE: Color = Color("f3eedc")
const AMBER: Color = Color("ffc66d")
const RED: Color = Color("ff7668")
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
	%HullHealth.value = tank.hp
	%HealthValue.text = str(roundi(tank.hp))
	%HullHealth.modulate = RED if tank.hp <= 25.0 else WHITE
	var condition: PackedStringArray = []
	if tank.dead:
		condition.append("坦克已被击毁")
	elif game.local_id.is_empty():
		condition.append("观战")
	else:
		if tank.components.engine_remaining > 0.0: condition.append("发动机瘫痪")
		if tank.components.left_track_remaining > 0.0 or tank.components.right_track_remaining > 0.0:
			condition.append("履带损毁")
		if tank.muzzle_obstructed: condition.append("炮口受阻")
	%VehicleCondition.text = " · ".join(condition)
	var repairing: bool = tank.components.barrel_remaining > 0.0
	var remaining: float = tank.reload_remaining
	var loaded: bool = remaining <= 0.0 and not repairing and not tank.dead
	%AmmoName.text = "穿甲弹" if tank.ammunition == DamageModel.Ammo.AP else "高爆弹"
	%AmmoState.text = "武器失效" if tank.dead else ("主炮维修中" if repairing else ("准备就绪" if loaded else "装填中  %.1f s" % remaining))
	%AmmoState.modulate = WHITE if loaded else AMBER
	var icon: Texture2D = AP_ICON if tank.ammunition == DamageModel.Ammo.AP else HE_ICON
	%ShellFill.texture_under = icon
	%ShellFill.texture_progress = icon
	%ShellFill.value = 0.0 if repairing or tank.dead else 100.0 * (1.0 - remaining / tank.components.reload_duration)
	%ShellFill.tint_progress = WHITE if loaded else AMBER
	%AmmoSelector.text = "%s   %s" % [game.api.input.binding_text(&"tank_ammunition"), "[ AP ]   HE" if tank.ammunition == DamageModel.Ammo.AP else "AP   [ HE ]"]
	var center: Vector2 = size * 0.5
	if game.first_person:
		_draw_optic(center)
	# Thin ring = player intent. Smaller circle = the shell's predicted landing point.
	draw_arc(center, 21.0, 0, TAU, 48, Color(0.95, 0.93, 0.86, 0.55), 1.0, true)
	for axis: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + axis * 8.0, center + axis * 15.0, WHITE, 1.4, true)
	draw_circle(center, 1.6, WHITE)
	if not game.camera.is_position_behind(game.actual_impact):
		var impact: Vector2 = game.camera.unproject_position(game.actual_impact)
		if Rect2(Vector2.ZERO, size).has_point(impact):
			var bore_color: Color = AMBER if tank.muzzle_obstructed else WHITE
			draw_arc(impact, 9.0, 0, TAU, 32, Color(0.02, 0.03, 0.02, 0.8), 4.0, true)
			draw_arc(impact, 9.0, 0, TAU, 32, bore_color, 1.5, true)
			draw_circle(impact, 1.5, bore_color)
	if game.hit_flash > 0.0:
		for axis: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(center + axis * 24.0, center + axis * 32.0, WHITE, 2.0, true)
	for i: int in game.feedbacks.size():
		var entry: Dictionary = game.feedbacks[i]
		var color: Color = RED if entry.kind == "kill" else (AMBER if entry.kind == "disabled" else WHITE)
		color.a = minf(1.0, (1.6 - entry.age) / 0.4)
		var point: Vector2 = center + Vector2(66, -24 + i * 28 - entry.age * 12)
		_caption(entry.text, point, color, 23 if entry.kind == "kill" else 20)

func _draw_optic(center: Vector2) -> void:
	var radius: float = size.y * 0.46
	# Four annular quadrants mask the viewport outside the optic without covering HUD.
	for quadrant: int in 4:
		var polygon: PackedVector2Array = []
		for step: int in 33:
			var angle: float = (quadrant + step / 32.0) * PI * 0.5
			polygon.append(center + Vector2(cos(angle), sin(angle)) * radius)
		for step: int in range(32, -1, -1):
			var angle: float = (quadrant + step / 32.0) * PI * 0.5
			polygon.append(center + Vector2(cos(angle), sin(angle)) * size.length())
		draw_colored_polygon(polygon, Color(0.015, 0.02, 0.018, 0.97))
	draw_arc(center, radius, 0, TAU, 160, Color(0.16, 0.18, 0.15), 5.0, true)
	var etched: Color = Color(0.08, 0.12, 0.08, 0.8)
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
		draw_line(center + direction * 34.0, center + direction * radius * 0.88, etched, 1.0, true)
	# Angular graduations expand with magnification; they are not range estimates.
	var spacing: float = 35.0 * tan(deg_to_rad(16.0)) / tan(deg_to_rad(game.camera.fov * 0.5))
	for i: int in range(1, 13):
		var distance: float = i * spacing
		if distance >= radius * 0.86: break
		var length: float = 10.0 if i % 2 == 0 else 6.0
		for side: float in [-1.0, 1.0]:
			var at: Vector2 = center + Vector2(side * distance, 0)
			draw_line(at - Vector2(0, length), at + Vector2(0, length), etched, 1.0, true)
		var at: Vector2 = center + Vector2(0, distance)
		draw_line(at - Vector2(length, 0), at + Vector2(length, 0), etched, 1.0, true)

func _caption(value: String, point: Vector2, color: Color, font_size: int) -> void:
	draw_string_outline(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0.03, 0.05, 0.04, color.a * 0.9))
	draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
