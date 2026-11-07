extends Node
## Scoped combat sound. Native engine pitch follows speed; one-shot cues retain one voice per effect.
@export var scope: PartyGameAudio
@export var engine: AudioStreamPlayer3D
@export var engine_loop: PartyAudioCue
@export var cannon: PartyAudioCue
@export var automatic_cannon: PartyAudioCue
@export var impact: PartyAudioCue
var _cannon_handle: PartyAudioHandle
var _impact_handle: PartyAudioHandle

func _ready() -> void:
	assert(scope != null and engine != null and engine_loop != null and cannon != null and automatic_cannon != null and impact != null, "Combat audio requires its scope, engine and cues.")
	engine.stream = engine_loop.playback_stream()

func start_engine() -> void:
	scope.route_spatial(engine, PartyGameAudio.Category.SFX)
	engine.play()

func update_engine(speed: float, maximum: float, destroyed: bool) -> void:
	engine.pitch_scale = lerpf(0.72, 1.65, absf(speed) / maximum)
	engine.volume_db = -40.0 if destroyed else lerpf(-24.0, -16.0, absf(speed) / maximum)

func play_cannon(automatic: bool) -> void:
	if _cannon_handle != null:
		_cannon_handle.stop()
	_cannon_handle = scope.play_sfx(automatic_cannon if automatic else cannon)

func play_impact() -> void:
	if _impact_handle != null:
		_impact_handle.stop()
	_impact_handle = scope.play_sfx(impact)
