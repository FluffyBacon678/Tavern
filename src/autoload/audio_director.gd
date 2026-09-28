extends Node

## Event-ID based audio playback.
##
## Game code asks for a *sound event* ("ui_click", "cooking_chop"), never a file.
## The registry maps an event to one or more streams and this picks between them,
## so prototype sounds can be swapped for final ones, or a single sound grown
## into a randomised set, without touching a single call site. That indirection
## is a design rule for the project, so it is here from the start.
##
## No audio has been authored yet, so the UI events are synthesised at boot as
## short procedural blips. They are placeholders in the most literal sense --
## delete the synth, drop real files into the registry, and nothing else changes.

const MIX_RATE: int = 44100
const POOL_SIZE: int = 12

enum Bus { MASTER, MUSIC, SFX, UI }

const BUS_NAMES: Array[String] = ["Master", "Music", "SFX", "UI"]

## event id -> { streams: Array[AudioStream], bus: String, volume_db: float }
var _registry: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _warned_missing: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	_ensure_buses()
	_build_pool()
	_register_placeholder_ui_sounds()
	GameSettings.audio_changed.connect(_apply_volumes)
	_apply_volumes()


func _ensure_buses() -> void:
	# Created in code rather than shipped as a bus layout resource so the layout
	# cannot drift out of sync with the names this script uses.
	for name in BUS_NAMES:
		if AudioServer.get_bus_index(name) != -1:
			continue
		var idx: int = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master")


func _build_pool() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)


func _apply_volumes() -> void:
	_set_bus_volume("Master", GameSettings.effective_master())
	_set_bus_volume("Music", GameSettings.music_volume)
	_set_bus_volume("SFX", GameSettings.sfx_volume)
	_set_bus_volume("UI", GameSettings.interface_volume)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


## Register an event. Call with several streams to get random variation.
func register(event_id: String, streams: Array, bus: String = "SFX", volume_db: float = 0.0) -> void:
	_registry[event_id] = {"streams": streams, "bus": bus, "volume_db": volume_db}


## Its own dice. Pitch and variant used to come from the global generator,
## which the simulation also draws from (hiring, guests), so every click in a
## menu shifted the game's later rolls and a seeded run stopped repeating.
var _rng := RandomNumberGenerator.new()


func play(event_id: String, pitch_variation: float = 0.06) -> void:
	if not _registry.has(event_id):
		# Warn once per unknown event: a missing sound should never spam the log
		# or, worse, throw during a menu interaction.
		if not _warned_missing.has(event_id):
			_warned_missing[event_id] = true
			push_warning("AudioDirector: no sound registered for event '%s'." % event_id)
		return

	var entry: Dictionary = _registry[event_id]
	var streams: Array = entry["streams"]
	if streams.is_empty():
		return

	var player: AudioStreamPlayer = _pool[_next_player]
	_next_player = (_next_player + 1) % _pool.size()

	player.stream = streams[_rng.randi() % streams.size()]
	player.bus = entry["bus"]
	player.volume_db = entry["volume_db"]
	player.pitch_scale = 1.0 + _rng.randf_range(-pitch_variation, pitch_variation)
	player.play()


# --- placeholder synthesis ----------------------------------------------

func _register_placeholder_ui_sounds() -> void:
	register("ui_hover", [_blip(880.0, 0.045, 0.18, 0.35)], "UI", -6.0)
	register("ui_click", [_blip(520.0, 0.075, 0.42, 0.55)], "UI", -3.0)
	register("ui_back", [_blip(330.0, 0.090, 0.38, 0.5)], "UI", -4.0)
	register("ui_start", [_blip(392.0, 0.220, 0.45, 0.25)], "UI", -2.0)


## A short percussive tone: a triangle-ish wave with a touch of noise and an
## exponential decay, which reads as a soft wooden tap rather than a beep.
func _blip(freq: float, duration: float, amplitude: float, noise_mix: float) -> AudioStreamWAV:
	var frames: int = int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)

	var phase: float = 0.0
	var step: float = freq / float(MIX_RATE)
	for i in range(frames):
		var t: float = float(i) / float(frames)
		var env: float = pow(1.0 - t, 3.0)

		phase = fmod(phase + step, 1.0)
		# Triangle wave: warmer and less piercing than a sine at these lengths.
		var tri: float = 4.0 * absf(phase - 0.5) - 1.0
		var noise: float = _rng.randf_range(-1.0, 1.0)
		var sample: float = lerpf(tri, noise, noise_mix) * env * amplitude

		var v: int = clampi(int(sample * 32767.0), -32768, 32767)
		if v < 0:
			v += 65536
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
