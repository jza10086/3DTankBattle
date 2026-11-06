extends RefCounted
## Local combat input bindings and host round duration.

static func schema() -> Dictionary:
	return {
	    "schema_format": 3,
	    "settings_version": 1,
	    "fields": {
	        "duration": {
	            "type": "int",
	            "default": 300,
	            "title": "回合时限（秒）",
	            "audience": "room",
	            "apply": "next_round",
	            "min": 60,
	            "max": 900,
	            "control": "number"
	        },
	        "move_up": {
	            "type": "array",
	            "action": "move_up",
	            "default": [
	                {
	                    "kind": "key",
	                    "code": 87,
	                    "physical": true
	                }
	            ],
	            "title": "前进",
	            "audience": "local",
	            "apply": "immediate",
	            "control": "binding",
	            "items": {
	                "type": "object",
	                "format": "binding"
	            },
	            "max_items": 2
	        },
	        "move_down": {
	            "type": "array",
	            "action": "move_down",
	            "default": [
	                {
	                    "kind": "key",
	                    "code": 83,
	                    "physical": true
	                }
	            ],
	            "title": "倒车",
	            "audience": "local",
	            "apply": "immediate",
	            "control": "binding",
	            "items": {
	                "type": "object",
	                "format": "binding"
	            },
	            "max_items": 2
	        },
	        "move_left": {
	            "type": "array",
	            "action": "move_left",
	            "default": [
	                {
	                    "kind": "key",
	                    "code": 65,
	                    "physical": true
	                }
	            ],
	            "title": "左转",
	            "audience": "local",
	            "apply": "immediate",
	            "control": "binding",
	            "items": {
	                "type": "object",
	                "format": "binding"
	            },
	            "max_items": 2
	        },
	        "move_right": {
	            "type": "array",
	            "action": "move_right",
	            "default": [
	                {
	                    "kind": "key",
	                    "code": 68,
	                    "physical": true
	                }
	            ],
	            "title": "右转",
	            "audience": "local",
	            "apply": "immediate",
	            "control": "binding",
	            "items": {
	                "type": "object",
	                "format": "binding"
	            },
	            "max_items": 2
	        },
	        "tank_fire": {
	            "type": "array",
	            "action": "tank_fire",
	            "default": [
	                {
	                    "kind": "mouse",
	                    "code": 1
	                }
	            ],
	            "title": "开炮",
	            "audience": "local",
	            "apply": "immediate",
	            "control": "binding",
	            "items": {
	                "type": "object",
	                "format": "binding"
	            },
	            "max_items": 2
	        },
	        "tank_sight": {
	            "type": "array",
	            "action": "tank_sight",
	            "default": [
	                {
	                    "kind": "key",
	                    "code": 4194325,
	                    "physical": true
	                }
	            ],
	            "title": "第一 / 第三人称",
	            "audience": "local",
	            "apply": "immediate",
	            "control": "binding",
	            "items": {
	                "type": "object",
	                "format": "binding"
	            },
	            "max_items": 2
	        },
	        "tank_brake": {
	            "type": "array",
	            "action": "tank_brake",
	            "default": [
	                {
	                    "kind": "key",
	                    "code": 32,
	                    "physical": true
	                }
	            ],
	            "title": "刹车",
	            "audience": "local",
	            "apply": "immediate",
	            "control": "binding",
	            "items": {
	                "type": "object",
	                "format": "binding"
	            },
	            "max_items": 2
	        },
	        "tank_center": {
	            "type": "array",
	            "action": "tank_center",
	            "default": [
	                {
	                    "kind": "key",
	                    "code": 67,
	                    "physical": true
	                }
	            ],
	            "title": "镜头回正",
	            "audience": "local",
	            "apply": "immediate",
	            "control": "binding",
	            "items": {
	                "type": "object",
	                "format": "binding"
	            },
	            "max_items": 2
	        },
	        "tank_recover": {
	            "type": "array",
	            "action": "tank_recover",
	            "default": [
	                {
	                    "kind": "key",
	                    "code": 70,
	                    "physical": true
	                }
	            ],
	            "title": "单人回正车辆",
	            "audience": "local",
	            "apply": "immediate",
	            "control": "binding",
	            "items": {
	                "type": "object",
	                "format": "binding"
	            },
	            "max_items": 2
	        },
	        "tank_ammunition": {
	            "type": "array",
	            "action": "tank_ammunition",
	            "default": [
	                {
	                    "kind": "key",
	                    "code": 81,
	                    "physical": true
	                }
	            ],
	            "title": "切换武器 / 弹药",
	            "audience": "local",
	            "apply": "immediate",
	            "control": "binding",
	            "items": {
	                "type": "object",
	                "format": "binding"
	            },
	            "max_items": 2
	        },
	        "tank_zoom_in": {
	            "type": "array",
	            "action": "tank_zoom_in",
	            "default": [
	                {
	                    "kind": "mouse",
	                    "code": 4
	                }
	            ],
	            "title": "放大镜头",
	            "audience": "local",
	            "apply": "immediate",
	            "control": "binding",
	            "items": {
	                "type": "object",
	                "format": "binding"
	            },
	            "max_items": 2
	        },
	        "tank_zoom_out": {
	            "type": "array",
	            "action": "tank_zoom_out",
	            "default": [
	                {
	                    "kind": "mouse",
	                    "code": 5
	                }
	            ],
	            "title": "缩小镜头",
	            "audience": "local",
	            "apply": "immediate",
	            "control": "binding",
	            "items": {
	                "type": "object",
	                "format": "binding"
	            },
	            "max_items": 2
	        }
	    },
	    "layout": [
	        {
	            "id": "room",
	            "title": "回合规则",
	            "children": [
	                {
	                    "field": "duration"
	                }
	            ]
	        },
	        {
	            "id": "controls",
	            "title": "驾驶与炮术",
	            "children": [
	                {
	                    "field": "move_up"
	                },
	                {
	                    "field": "move_down"
	                },
	                {
	                    "field": "move_left"
	                },
	                {
	                    "field": "move_right"
	                },
	                {
	                    "field": "tank_fire"
	                },
	                {
	                    "field": "tank_sight"
	                },
	                {
	                    "field": "tank_brake"
	                },
	                {
	                    "field": "tank_center"
	                },
	                {
	                    "field": "tank_recover"
	                },
	                {
	                    "field": "tank_ammunition"
	                },
	                {
	                    "field": "tank_zoom_in"
	                },
	                {
	                    "field": "tank_zoom_out"
	                }
	            ]
	        }
	    ]
	}
