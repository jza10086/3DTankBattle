class_name ComponentPanel
extends PanelContainer
## Explicit training controls, not a permanent debug sidebar.
const Status = preload("res://games/minigame/gp_tank_war/scripts/component_status.gd")
signal component_requested(component: StringName)
signal clear_requested
signal close_requested
var buttons: Dictionary = {}

func _ready() -> void:
	for button: Button in find_children("*", "Button", true, false):
		var key: StringName = button.get_meta("component")
		buttons[key] = button
		match key:
			&"clear":
				button.pressed.connect(func() -> void: clear_requested.emit())
			&"close":
				button.pressed.connect(func() -> void: close_requested.emit())
			_:
				button.pressed.connect(_request_component.bind(key))

func _request_component(component: StringName) -> void:
	component_requested.emit(component)
