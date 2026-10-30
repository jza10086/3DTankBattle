class_name ComponentPanel
extends PanelContainer
## Explicit training controls, not a permanent debug sidebar.
const Status = preload("res://scripts/component_status.gd")
signal component_requested(component: StringName)
signal clear_requested
signal close_requested
var buttons: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -360
	offset_right = -36
	offset_top = 132
	offset_bottom = 494
	var background := StyleBoxFlat.new()
	background.bg_color = Color("17251fec")
	background.border_color = Color("cfa65f")
	background.set_border_width_all(1)
	background.set_corner_radius_all(4)
	background.content_margin_left = 18
	background.content_margin_right = 18
	background.content_margin_top = 16
	background.content_margin_bottom = 16
	add_theme_stylebox_override("panel", background)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var heading := Label.new()
	heading.text = "COMPONENT EFFECT TEST"
	heading.add_theme_color_override("font_color", Color("ffcc7b"))
	heading.add_theme_font_size_override("font_size", 17)
	column.add_child(heading)
	var hint := Label.new()
	hint.text = "Apply to YOUR tank. Timers stay live."
	hint.add_theme_font_size_override("font_size", 12)
	column.add_child(hint)
	for entry in [[&"engine", "ENGINE OUT  /  %.0f s" % Status.ENGINE_DURATION], [&"left_track", "LEFT TRACK  /  %.0f s" % Status.TRACK_DURATION], [&"right_track", "RIGHT TRACK  /  %.0f s" % Status.TRACK_DURATION], [&"barrel", "BARREL + RELOAD  /  %.0f s" % Status.BARREL_DURATION]]:
		var button := _button(String(entry[1]), column)
		buttons[entry[0]] = button
		button.pressed.connect(_request_component.bind(entry[0]))
	var clear := _button("CLEAR EFFECTS + RELOAD", column)
	buttons[&"clear"] = clear
	clear.pressed.connect(func(): clear_requested.emit())
	var close := _button("RETURN TO DRIVE  /  F3", column)
	buttons[&"close"] = close
	close.pressed.connect(func(): close_requested.emit())

func _button(caption: String, column: VBoxContainer) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(288, 36)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color("f3eedc"))
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("34463b") if state == "normal" else (Color("52604a") if state == "hover" else Color("78633d"))
		style.set_corner_radius_all(3)
		button.add_theme_stylebox_override(state, style)
	column.add_child(button)
	return button

func _request_component(component: StringName) -> void:
	component_requested.emit(component)
