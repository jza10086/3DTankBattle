## Lightweight catalog data. Do not load gameplay scenes or scripts here.
extends RefCounted

static func party_definition() -> Dictionary:
	return {"player_counts": [1, 2, 3, 4, 5, 6, 7, 8], "controls": {"move_up": "前进", "move_down": "倒车", "move_left": "左转", "move_right": "右转", "tank_fire": "开炮", "tank_sight": "切换第一 / 第三人称", "tank_brake": "刹车", "tank_center": "镜头回正", "tank_recover": "单人回正车辆", "tank_ammunition": "切换武器 / 弹药", "tank_zoom_in": "放大镜头 / 瞄准镜", "tank_zoom_out": "缩小镜头 / 瞄准镜", "tank_machine_gun": "同轴机枪连射"}}
