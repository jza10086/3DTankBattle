extends Control
## Edge HUD and world-space markers; the framework owns menus and round pages.
const Tank = preload("res://games/minigame/godot_party_default_tank_range/scripts/tank_controller.gd")
var game: Node3D
var font: Font = ThemeDB.fallback_font
const WHITE: Color = Color("f3eedc")
const AMBER: Color = Color("ffc66d")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if game == null or not game.started:
		return
	var tank: Tank = game.tank
	var solo: bool = game.players.size() == 1
	var alive: int = 0
	for vehicle: Tank in game.vehicles.values():
		if not vehicle.dead:
			alive += 1
	%Targets.text = "%d / %d 靶标" % [game.destroyed_count, game.total_targets] if solo else "%d / %d 存活" % [alive, game.players.size()]
	%RangeSub.text = "M1 ABRAMS · 单人炮术训练" if solo else "M1 ABRAMS · 自由交战"
	%Clearance.text = "清空全部靶标" if solo else "最后存活者获胜"
	%Elapsed.text = "剩余 %02d:%02d" % [int(maxf(0.0, game.duration - game.elapsed)) / 60, int(maxf(0.0, game.duration - game.elapsed)) % 60]
	%VehicleSpeed.text = "%02d km/h" % roundi(absf(tank.speed) * 3.6)
	%Drive.text = "观战 · " + tank.player_name if game.local_id.is_empty() else ("已被击毁 · 等待本轮结束" if tank.dead else "生命 %d / 100 · 击毁 %d" % [roundi(tank.hp), tank.kills])
	var repairing: bool = tank.components.barrel_remaining > 0.0
	var remaining: float = tank.components.barrel_remaining if repairing else tank.reload_remaining
	%GunState.text = "已被击毁" if tank.dead else ("炮管维修 %.1f s" % remaining if repairing else ("装填 %.1f s" % remaining if remaining > 0.0 else "准备开火"))
	%Reload.value = 1.0 - tank.reload_remaining / Tank.RELOAD_TIME
	var center: Vector2 = size * 0.5
	for axis: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + axis * 14.0, center + axis * 26.0, WHITE, 1.5, true)
	draw_circle(center, 2.0, WHITE)
	if not game.camera.is_position_behind(game.actual_impact):
		var impact: Vector2 = game.camera.unproject_position(game.actual_impact)
		draw_arc(impact, 11, 0, TAU, 24, Color("9fe0a8") if game.actual_hit_target else AMBER, 2.0, true)
	if game.first_person:
		draw_arc(center, 350, 0, TAU, 96, Color(0.1, 0.15, 0.1, 0.4), 2.0, true)
		_caption("炮手瞄准镜 · %.1f×" % (4.2 if game.zooming else 2.1), Vector2(center.x, 145), AMBER)
	if game.hit_flash > 0.0:
		for axis: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(center + axis * 30.0, center + axis * 42.0, AMBER, 3.0, true)
	if game.notice_time > 0.0:
		_caption(game.notice, center + Vector2(0, 135), AMBER)
	var statuses: PackedStringArray = []
	if tank.components.engine_remaining > 0.0:
		statuses.append("发动机维修 %.1fs" % tank.components.engine_remaining)
	if tank.components.left_track_remaining > 0.0:
		statuses.append("左履带维修 %.1fs" % tank.components.left_track_remaining)
	if tank.components.right_track_remaining > 0.0:
		statuses.append("右履带维修 %.1fs" % tank.components.right_track_remaining)
	if tank.muzzle_obstructed:
		statuses.append("炮口被阻挡")
	_caption(" · ".join(statuses), Vector2(center.x, size.y - 95), AMBER)
	for target: Node3D in game.targets:
		_marker(target, "靶标 %d" % (target.index + 1))
	for vehicle: Tank in game.vehicles.values():
		if vehicle != tank:
			_marker(vehicle, vehicle.player_name)

func _marker(target: Node3D, label: String) -> void:
	if target.dead or game.camera.is_position_behind(target.global_position):
		return
	var point: Vector2 = game.camera.unproject_position(target.get_marker_point())
	if not Rect2(50, 130, size.x - 100, size.y - 300).has_point(point):
		return
	_caption(label + " · %d HP" % roundi(target.hp), point - Vector2(0, 12), AMBER)
	draw_rect(Rect2(point - Vector2(35, 0), Vector2(70, 5)), Color(0.03, 0.06, 0.05, 0.8))
	draw_rect(Rect2(point - Vector2(35, 0), Vector2(70 * target.hp / target.max_hp, 5)), AMBER)

func _caption(value: String, point: Vector2, color: Color) -> void:
	var width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var at: Vector2 = point - Vector2(width * 0.5, 0)
	draw_string_outline(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color(0.03, 0.05, 0.04, 0.9))
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, color)
