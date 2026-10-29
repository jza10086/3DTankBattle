class_name RangeHud
extends Control

var game: Node3D
var font: Font = ThemeDB.fallback_font
const WHITE := Color("f3eedc")
const MUTED := Color("c7cbb8")
const AMBER := Color("ffc66d")
const DARK := Color(0.06, 0.10, 0.09, 0.82)
var sx := 1.0
var sy := 1.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if not is_instance_valid(game.tank):
		return
	var screen := get_viewport_rect().size
	sx = screen.x / 1600.0
	sy = screen.y / 900.0
	draw_set_transform(Vector2.ZERO, 0, Vector2(sx, sy))
	var tank: TankController = game.tank
	# Slim framing, with the world occupying the entire display.
	_rect(Rect2(34, 24, 300, 67), Color(0.06, 0.10, 0.09, 0.57))
	_rect(Rect2(1324, 24, 240, 80), Color(0.06, 0.10, 0.09, 0.57))
	_rect(Rect2(34, 32, 3, 54), AMBER)
	_text("IRON RANGE", Vector2(52, 54), 23, WHITE)
	_text("07 / DESERT PROVING GROUND", Vector2(53, 78), 11, MUTED)
	_text("RANGE CLEARANCE", Vector2(1340, 47), 11, MUTED)
	_text("%02d / %02d" % [game.destroyed_count, game.total_targets], Vector2(1340, 78), 28, WHITE)
	for i in game.total_targets:
		_rect(Rect2(1341 + i * 28, 91, 20, 3), AMBER if i < game.destroyed_count else Color(1, 1, 1, 0.25))
	_draw_compass()
	if game.started:
		_draw_targets()
		_draw_reticle()
		_draw_dashboard()
		if game.notice_time > 0:
			var color := AMBER if game.hit_flash > 0 else WHITE
			_center(game.notice, 800, 565, 16, color)
		if game.destroyed_count == game.total_targets:
			_rect(Rect2(540, 130, 520, 86), DARK)
			_center("RANGE CLEAR", 800, 161, 23, AMBER)
			var accuracy := int(round(float(game.hits) / maxi(tank.rounds_fired, 1) * 100))
			_center("%s  /  %d SHOTS  /  %d%% HITS  •  R TO RESTART" % [_time(game.elapsed), tank.rounds_fired, accuracy], 800, 192, 13, WHITE)
		if game.paused:
			_draw_title(true)
	else:
		_draw_title(false)

func _draw_compass() -> void:
	var view_direction: Vector3 = -game.camera.global_basis.z
	var heading := fposmod(rad_to_deg(atan2(view_direction.x, -view_direction.z)), 360.0)
	var center := 800.0
	for mark in range(-5, 6):
		var value := floori(heading / 15.0) * 15 + mark * 15
		var x := center + (value - heading) * 4
		if x < 550 or x > 1050:
			continue
		draw_line(Vector2(x, 40), Vector2(x, 47), Color(1, 1, 1, 0.45), 1)
		var cardinal := ""
		match posmod(value, 360):
			0: cardinal = "N"
			90: cardinal = "E"
			180: cardinal = "S"
			270: cardinal = "W"
		if not cardinal.is_empty():
			_center(cardinal, x, 31, 13, WHITE)
		elif posmod(value, 30) == 0:
			_center(str(posmod(value, 360)), x, 31, 10, MUTED)
	draw_colored_polygon(PackedVector2Array([Vector2(795, 53), Vector2(805, 53), Vector2(800, 58)]), AMBER)

func _draw_targets() -> void:
	for target in game.targets:
		if target.dead or game.camera.is_position_behind(target.global_position):
			continue
		var point: Vector2 = game.camera.unproject_position(target.get_marker_point() + Vector3(0, 0.6, 0)) / Vector2(sx, sy)
		if point.x < 65 or point.x > 1535 or point.y < 115 or point.y > 740:
			continue
		var distance: float = game.tank.global_position.distance_to(target.global_position)
		if distance > 160:
			continue
		var color := Color("ffdb98")
		var r := 5.0
		draw_polyline(PackedVector2Array([point + Vector2(0,-r), point + Vector2(r,0), point + Vector2(0,r), point + Vector2(-r,0), point + Vector2(0,-r)]), color, 1.5, true)
		_center("%02d  /  %d M" % [target.index + 1, roundi(distance)], point.x, point.y - 12, 10, color)
		_rect(Rect2(point.x - 27, point.y + 11, 54, 4), Color(0.05, 0.09, 0.07, 0.75))
		_rect(Rect2(point.x - 27, point.y + 11, 54 * clampf(target.hp / target.max_hp, 0, 1), 4), color)
		_center("%d HP" % roundi(target.hp), point.x, point.y + 29, 10, WHITE)

func _draw_reticle() -> void:
	var center := Vector2(800, 450)
	var color := Color(1, 1, 0.93, 0.58)
	for axis in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + axis * 13, center + axis * 22, color, 1.4, true)
	draw_circle(center, 1.7, color)
	if game.first_person:
		_draw_scope(center)
	elif game.zooming:
		draw_arc(center, 240, 0, TAU, 96, Color(1, 1, 1, 0.12), 1.0, true)
		_text("EXTERIOR / 2.1×", Vector2(1032, 685), 11, MUTED)
		for tick in range(-3, 4):
			draw_line(Vector2(800 + tick * 40, 510), Vector2(800 + tick * 40, 516), Color(1,1,1,0.3), 1)
	if not game.camera.is_position_behind(game.actual_impact):
		var actual: Vector2 = game.camera.unproject_position(game.actual_impact) / Vector2(sx, sy)
		if Rect2(25, 105, 1550, 640).has_point(actual):
			var aim_color := Color("9fe0a8") if game.actual_hit_target else AMBER
			if game.tank.muzzle_obstructed:
				aim_color = Color("f18b61")
			draw_arc(actual, 9, 0, TAU, 24, aim_color, 1.8, true)
			draw_line(actual + Vector2(-14, 0), actual + Vector2(-11, 0), aim_color, 2)
			draw_line(actual + Vector2(11, 0), actual + Vector2(14, 0), aim_color, 2)
			if game.first_person:
				_center("%d M" % roundi(game.tank.visual.muzzle.global_position.distance_to(game.actual_impact)), actual.x, actual.y + 26, 10, aim_color)
			if actual.distance_to(center) > 38:
				draw_line(center, actual, Color(1, 0.8, 0.5, 0.16), 1, true)
	if game.hit_flash > 0:
		for direction in [Vector2(1,1), Vector2(-1,1), Vector2(1,-1), Vector2(-1,-1)]:
			draw_line(center + direction * 27, center + direction * 36, AMBER, 3, true)
	if game.tank.muzzle_obstructed:
		_center("BARREL BLOCKED", 800, 494, 12, Color("ffab80"))

func _draw_scope(center: Vector2) -> void:
	# Keep the optical circle round even in a tall / resized window.
	var optical_center := Vector2(center.x, center.y * sy / sx)
	draw_set_transform(Vector2.ZERO, 0, Vector2(sx, sx))
	center = optical_center
	# Etched sight overlay: center follows the actual barrel, not mouse demand.
	var line := Color(0.07, 0.12, 0.09, 0.82)
	var light := Color(0.94, 0.95, 0.82, 0.68)
	for side in [-1, 1]:
		draw_line(center + Vector2(side * 30, 0), center + Vector2(side * 280, 0), line, 2, true)
		draw_line(center + Vector2(0, side * 30), center + Vector2(0, side * 215), line, 2, true)
		for tick in range(1, 7):
			var x: float = side * (40 + tick * 30)
			draw_line(center + Vector2(x, -5), center + Vector2(x, 5), light, 1.4, true)
		for tick in range(1, 5):
			var y: float = side * (40 + tick * 30)
			draw_line(center + Vector2(-5, y), center + Vector2(5, y), light, 1.4, true)
	draw_arc(center, 292, 0, TAU, 96, Color(0.06, 0.1, 0.08, 0.26), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0, Vector2(sx, sy))
	_rect(Rect2(670, 116, 260, 28), DARK)
	_center("GUN SIGHT  /  %s" % ("4.2×" if game.zooming else "2.1×"), 800, 135, 12, WHITE)
	_center("SHIFT  EXTERIOR VIEW", 800, 724, 11, MUTED)

func _draw_dashboard() -> void:
	var tank: TankController = game.tank
	# Navigation / gun status on the left; one clear large speed readout on the right.
	_rect(Rect2(36, 766, 300, 83), DARK)
	_rect(Rect2(36, 766, 3, 83), AMBER)
	_text("105 MM  /  PRACTICE AP", Vector2(54, 790), 12, MUTED)
	var ready := tank.reload_remaining <= 0
	_text("READY" if ready else "RELOADING", Vector2(53, 820), 22, WHITE if ready else AMBER)
	_text("∞" if ready else "%.1f s" % tank.reload_remaining, Vector2(270, 820), 20, WHITE)
	_rect(Rect2(54, 833, 264, 3), Color(1,1,1,0.15))
	_rect(Rect2(54, 833, 264 * (1.0 - tank.reload_remaining / TankController.RELOAD_TIME), 3), AMBER)
	_text("%s  /  FLANK ARMOR FOR MORE DAMAGE" % _time(game.elapsed), Vector2(37, 745), 11, MUTED)
	var v := absf(tank.speed) * 3.6
	_rect(Rect2(1360, 750, 204, 99), DARK)
	_text("%02d" % roundi(v), Vector2(1380, 817), 54, WHITE)
	_text("KM/H", Vector2(1492, 816), 13, MUTED)
	_text("REVERSE" if tank.speed < -0.25 else ("PIVOT" if absf(tank.yaw_rate) > .2 and v < 2 else "DRIVE"), Vector2(1380, 839), 10, AMBER)
	_text("BRAKE" if tank.brake else "TRACKED / 07", Vector2(1460, 839), 10, MUTED)
	_rect(Rect2(0, 869, 1600, 31), Color(0.04,0.07,0.06,0.72))
	_center("W S  DRIVE   A D  STEER   MOUSE  AIM   LMB  FIRE   SHIFT  SIGHT   RMB  ZOOM   SPACE  BRAKE   C  CENTER   F  RECOVER   R  RESTART   ESC  PAUSE", 800, 889, 11, MUTED)

func _draw_title(is_pause: bool) -> void:
	_rect(Rect2(0, 0, 1600, 900), Color(0.03, 0.07, 0.06, 0.43))
	_rect(Rect2(490, 269, 620, 350), Color(0.06, 0.1, 0.09, 0.92))
	_rect(Rect2(490, 269, 620, 3), AMBER)
	_center("RANGE PAUSED" if is_pause else "IRON RANGE", 800, 334, 36, WHITE)
	_center("A TRACKED DRIVING & GUNNERY PLAYGROUND", 800, 366, 12, AMBER)
	_center("Drive the course. Flank enemy armor. Clear all six tanks.", 800, 409, 16, WHITE)
	_center("W S  drive    /    A D  pivot & steer    /    Mouse  aim turret", 800, 445, 14, MUTED)
	_center("SHIFT  first-person sight    /    Hold RMB  zoom    /    LMB  fire", 800, 473, 14, MUTED)
	_center("Sight cross = gun bore  •  Amber ring = actual shell impact", 800, 510, 13, AMBER)
	_center("ENTER TO RESUME" if is_pause else "ENTER TO DRIVE", 800, 563, 22, WHITE)
	_center("F  recover vehicle     R  restart range", 800, 594, 12, MUTED)

func _text(value: String, at: Vector2, size: int, color: Color) -> void:
	draw_string(font, at + Vector2(0, 1), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.04,0.07,0.05,0.8))
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _center(value: String, x: float, y: float, size: int, color: Color) -> void:
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(value, Vector2(x - width * 0.5, y), size, color)

func _rect(rect: Rect2, color: Color) -> void:
	draw_rect(rect, color)

func _time(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]
