class_name ComponentStatus
extends RefCounted
## Small deterministic damage/recovery state shared by player and training tanks.
## Tracks parallel reload timers per physical weapon slot so unselected equipment keeps reloading.
const ENGINE_DURATION: float = 4.0
const TRACK_DURATION: float = 5.0
const BARREL_DURATION: float = 4.0
const RELOAD_TIME: float = 3.2
const DAMAGED_TRACK_MULTIPLIER: float = 0.25
const DEFAULT_WEAPON_SLOT: StringName = &"main_gun"

var engine_remaining: float = 0.0
var left_track_remaining: float = 0.0
var right_track_remaining: float = 0.0
var barrel_remaining: float = 0.0
var active_weapon_slot: StringName = DEFAULT_WEAPON_SLOT
var _weapon_reloads: Dictionary[StringName, Dictionary] = {}

var reload_remaining: float:
	get:
		return get_weapon_reload_remaining(active_weapon_slot)
	set(value):
		set_weapon_reload_remaining(active_weapon_slot, value)

var reload_duration: float:
	get:
		return get_weapon_reload_duration(active_weapon_slot)
	set(value):
		set_weapon_reload_duration(active_weapon_slot, value)

func _init() -> void:
	configure_weapon(DEFAULT_WEAPON_SLOT, RELOAD_TIME, true)

## Removes all registered weapon slots before re-initializing a vehicle's weapon set.
func clear_weapons() -> void:
	_weapon_reloads.clear()

## Registers or updates a physical weapon slot without disturbing any active reload countdown.
func configure_weapon(slot: StringName, duration: float, affected_by_barrel: bool = true) -> void:
	var key: StringName = slot if not slot.is_empty() else DEFAULT_WEAPON_SLOT
	var safe_duration: float = maxf(duration, 0.001)
	if not _weapon_reloads.has(key):
		_weapon_reloads[key] = {"remaining": 0.0, "duration": safe_duration, "affected_by_barrel": affected_by_barrel}
	else:
		var entry: Dictionary = _weapon_reloads[key]
		entry.duration = safe_duration
		entry.affected_by_barrel = affected_by_barrel

func get_weapon_reload_remaining(slot: StringName = &"") -> float:
	var key: StringName = active_weapon_slot if slot.is_empty() else slot
	if not _weapon_reloads.has(key):
		return 0.0
	return float(_weapon_reloads[key].remaining)

func set_weapon_reload_remaining(slot: StringName, value: float) -> void:
	var key: StringName = active_weapon_slot if slot.is_empty() else slot
	if not _weapon_reloads.has(key):
		configure_weapon(key, RELOAD_TIME, true)
	_weapon_reloads[key].remaining = maxf(0.0, value)

func get_weapon_reload_duration(slot: StringName = &"") -> float:
	var key: StringName = active_weapon_slot if slot.is_empty() else slot
	if not _weapon_reloads.has(key):
		return RELOAD_TIME
	return float(_weapon_reloads[key].duration)

func set_weapon_reload_duration(slot: StringName, value: float) -> void:
	var key: StringName = active_weapon_slot if slot.is_empty() else slot
	if not _weapon_reloads.has(key):
		configure_weapon(key, value, true)
	else:
		_weapon_reloads[key].duration = maxf(value, 0.001)

func is_weapon_affected_by_barrel(slot: StringName = &"") -> bool:
	var key: StringName = active_weapon_slot if slot.is_empty() else slot
	if not _weapon_reloads.has(key):
		return true
	return bool(_weapon_reloads[key].affected_by_barrel)

func is_weapon_repairing(slot: StringName = &"") -> bool:
	return barrel_remaining > 0.0 and is_weapon_affected_by_barrel(slot)

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
			# A broken gun barrel invalidates barrel-dependent rounds; independent launchers keep reloading.
			for slot: StringName in _weapon_reloads:
				var entry: Dictionary = _weapon_reloads[slot]
				if bool(entry.affected_by_barrel):
					entry.remaining = float(entry.duration)
		_:
			return false
	return true

func tick(delta: float) -> void:
	var elapsed: float = maxf(delta, 0.0)
	engine_remaining = maxf(0.0, engine_remaining - elapsed)
	left_track_remaining = maxf(0.0, left_track_remaining - elapsed)
	right_track_remaining = maxf(0.0, right_track_remaining - elapsed)
	# Barrel-dependent reloads pause during barrel repair; if this step crosses repair
	# expiry, only the remaining fraction advances them. Independent weapons always tick.
	var blocked_time: float = minf(elapsed, barrel_remaining)
	barrel_remaining = maxf(0.0, barrel_remaining - elapsed)
	var barrel_reload_time: float = elapsed - blocked_time
	for slot: StringName in _weapon_reloads:
		var entry: Dictionary = _weapon_reloads[slot]
		var step_time: float = barrel_reload_time if bool(entry.affected_by_barrel) else elapsed
		entry.remaining = maxf(0.0, float(entry.remaining) - step_time)

func clear() -> void:
	engine_remaining = 0.0
	left_track_remaining = 0.0
	right_track_remaining = 0.0
	barrel_remaining = 0.0
	for slot: StringName in _weapon_reloads:
		_weapon_reloads[slot].remaining = 0.0

func can_fire(slot: StringName = &"") -> bool:
	var key: StringName = active_weapon_slot if slot.is_empty() else slot
	return not is_weapon_repairing(key) and get_weapon_reload_remaining(key) <= 0.0

func begin_fire(slot: StringName = &"") -> bool:
	var key: StringName = active_weapon_slot if slot.is_empty() else slot
	if not can_fire(key):
		return false
	begin_reload_slot(key)
	return true

func begin_reload() -> void:
	begin_reload_slot(active_weapon_slot)

func begin_reload_slot(slot: StringName, duration: float = -1.0) -> void:
	var key: StringName = active_weapon_slot if slot.is_empty() else slot
	if not _weapon_reloads.has(key):
		configure_weapon(key, duration if duration > 0.0 else RELOAD_TIME, true)
	elif duration > 0.0:
		_weapon_reloads[key].duration = maxf(duration, 0.001)
	_weapon_reloads[key].remaining = float(_weapon_reloads[key].duration)

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

func is_disabled(component: StringName) -> bool:
	match component:
		&"engine": return engine_remaining > 0.0
		&"left_track": return left_track_remaining > 0.0
		&"right_track": return right_track_remaining > 0.0
		&"barrel": return barrel_remaining > 0.0
	return false
