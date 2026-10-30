class_name ComponentStatus
extends RefCounted
## Small deterministic damage/recovery state shared by player and training tanks.
## Durations are gameplay seconds; callers tick once per unpaused physics frame.
const ENGINE_DURATION := 4.0
const TRACK_DURATION := 5.0
const BARREL_DURATION := 4.0
const RELOAD_TIME := 3.2
const DAMAGED_TRACK_MULTIPLIER := 0.25

var engine_remaining := 0.0
var left_track_remaining := 0.0
var right_track_remaining := 0.0
var barrel_remaining := 0.0
var reload_remaining := 0.0

## Repeated hits refresh the relevant timer; they never add durations together.
## The canonical component names are engine, left_track, right_track and barrel.
func apply_component(component: StringName) -> bool:
	match component:
		&"engine":
			engine_remaining = ENGINE_DURATION
		&"left_track":
			left_track_remaining = TRACK_DURATION
		&"right_track":
			right_track_remaining = TRACK_DURATION
		&"barrel":
			barrel_remaining = BARREL_DURATION
			# A broken barrel invalidates the current load, including a ready round.
			begin_reload()
		_:
			return false
	return true

func tick(delta: float) -> void:
	var elapsed := maxf(delta, 0.0)
	engine_remaining = maxf(0.0, engine_remaining - elapsed)
	left_track_remaining = maxf(0.0, left_track_remaining - elapsed)
	right_track_remaining = maxf(0.0, right_track_remaining - elapsed)
	# Reload is held at full duration during barrel repair. If this step crosses
	# repair expiry, ONLY the remaining part of the step advances the new reload.
	var blocked_time := minf(elapsed, barrel_remaining)
	barrel_remaining = maxf(0.0, barrel_remaining - elapsed)
	var reload_time := elapsed - blocked_time
	reload_remaining = maxf(0.0, reload_remaining - reload_time)

func clear() -> void:
	engine_remaining = 0.0
	left_track_remaining = 0.0
	right_track_remaining = 0.0
	barrel_remaining = 0.0
	reload_remaining = 0.0

func can_fire() -> bool:
	return barrel_remaining <= 0.0 and reload_remaining <= 0.0

func begin_fire() -> bool:
	if not can_fire():
		return false
	begin_reload()
	return true

func begin_reload() -> void:
	reload_remaining = RELOAD_TIME

func get_left_track_multiplier() -> float:
	if engine_remaining > 0.0:
		return 0.0
	return DAMAGED_TRACK_MULTIPLIER if left_track_remaining > 0.0 else 1.0

func get_right_track_multiplier() -> float:
	if engine_remaining > 0.0:
		return 0.0
	return DAMAGED_TRACK_MULTIPLIER if right_track_remaining > 0.0 else 1.0

func get_track_multipliers() -> Vector2:
	return Vector2(get_left_track_multiplier(), get_right_track_multiplier())
