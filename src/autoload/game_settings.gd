extends Node

## Persisted player settings, loaded once at boot and applied immediately.
##
## Stored as a ConfigFile under user:// so it survives across platforms without
## us hand-rolling a format. Every setter applies the change *and* writes, so
## there is no separate "save settings" step to forget.
##
## Grouped as the settings screen shows them -- gameplay, video, audio -- and
## each group can be put back to its defaults on its own.

const SAVE_PATH := "user://settings.cfg"

## Presets exist mainly for Android: the forest bakes a full-screen ground
## texture and instances every tree, and a weaker device is much happier with a
## coarser grid and a smaller world.
enum Quality { LOW, MEDIUM, HIGH }
## How the game sits on the desktop. Borderless is a window the size of the
## screen: alt-tab friendly, which exclusive fullscreen is not.
enum DisplayMode { WINDOWED, BORDERLESS, FULLSCREEN }

## Window sizes offered in windowed mode, largest that fits the screen first.
const WINDOW_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]
## Frame caps offered; 0 means uncapped.
const FRAME_CAPS: Array[int] = [30, 60, 120, 144, 0]

signal quality_changed(level: int)
signal audio_changed
## Anything else changed: UI scale, camera, hints. Listeners re-read what they use.
signal changed
## A key was rebound: labels that name keys should read them again.
signal bindings_changed

# --- gameplay ---------------------------------------------------------------
## Save at every close of business. Off, the game saves only when asked.
var autosave: bool = true
## Pan the camera when the pointer rests at the edge of the screen.
var edge_scroll: bool = false
## Multiplier on camera panning speed.
var camera_speed: float = 1.0
## Multiplier on every panel's text and controls, on top of the automatic
## sizing for the window. For players at a distance from a big screen, or
## close to a small one.
var ui_scale: float = 1.0
## The getting-started checklist and the level's goal line.
var show_hints: bool = true

# --- video --------------------------------------------------------------------
var quality: int = Quality.HIGH:
	set = set_quality
var display_mode: int = DisplayMode.WINDOWED
var window_size: Vector2i = Vector2i(1280, 720)
var vsync: bool = true
var max_fps: int = 0
## Menu background animation can be turned off entirely -- it is the single
## biggest battery cost on a phone sitting at the title screen.
var animated_background: bool = true
## A faint outline round each person: gold for staff, blue for guests.
var outline_people: bool = true
## Little bubbles over heads saying what each person is doing.
var thought_bubbles: bool = true

# --- audio --------------------------------------------------------------------
var master_volume: float = 1.0:
	set = set_master_volume
var music_volume: float = 0.7:
	set = set_music_volume
var sfx_volume: float = 0.9:
	set = set_sfx_volume
## Clicks and menu sounds, on their own bus.
var interface_volume: float = 0.8
## Go quiet while another window has focus.
var mute_unfocused: bool = true

## Old name for display_mode, kept for anything that only asks yes or no.
var fullscreen: bool:
	get:
		return display_mode != DisplayMode.WINDOWED
	set(value):
		set_display_mode(DisplayMode.BORDERLESS if value else DisplayMode.WINDOWED)

var _loading: bool = false
var _focused: bool = true


func _ready() -> void:
	load_settings()


## F11, anywhere: windowed, or the screen.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		set_display_mode(DisplayMode.WINDOWED if display_mode != DisplayMode.WINDOWED else DisplayMode.BORDERLESS)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Muting in the background is done on the master bus through the same path
	# as every other volume, so a slider moved while muted is not lost.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		audio_changed.emit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
		audio_changed.emit()


## The master volume as it should sound right now.
func effective_master() -> float:
	return 0.0 if mute_unfocused and not _focused else master_volume


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		# No file yet: keep defaults, but pick a sensible quality for the device.
		quality = Quality.MEDIUM if OS.has_feature("mobile") else Quality.HIGH
		KeyBindings.install()
		_apply_all()
		return

	_loading = true
	autosave = cfg.get_value("gameplay", "autosave", autosave)
	edge_scroll = cfg.get_value("gameplay", "edge_scroll", edge_scroll)
	camera_speed = clampf(cfg.get_value("gameplay", "camera_speed", camera_speed), 0.5, 2.0)
	ui_scale = clampf(cfg.get_value("gameplay", "ui_scale", ui_scale), 0.8, 1.4)
	show_hints = cfg.get_value("gameplay", "show_hints", show_hints)
	quality = cfg.get_value("video", "quality", quality)
	# Older files only knew fullscreen or not.
	var legacy_fullscreen: bool = cfg.get_value("video", "fullscreen", false)
	display_mode = clampi(cfg.get_value("video", "display_mode",
		DisplayMode.BORDERLESS if legacy_fullscreen else DisplayMode.WINDOWED), 0, 2)
	window_size = cfg.get_value("video", "window_size", window_size)
	vsync = cfg.get_value("video", "vsync", vsync)
	max_fps = cfg.get_value("video", "max_fps", max_fps)
	animated_background = cfg.get_value("video", "animated_background", animated_background)
	outline_people = cfg.get_value("video", "outline_people", outline_people)
	thought_bubbles = cfg.get_value("video", "thought_bubbles", thought_bubbles)
	master_volume = cfg.get_value("audio", "master", master_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	interface_volume = cfg.get_value("audio", "interface", interface_volume)
	mute_unfocused = cfg.get_value("audio", "mute_unfocused", mute_unfocused)
	var bound: Dictionary = {}
	if cfg.has_section("controls"):
		for id in cfg.get_section_keys("controls"):
			bound[id] = cfg.get_value("controls", id, [])
	KeyBindings.install(bound)
	_loading = false

	_apply_all()


## The player's file, or a test run's scratch copy: a fixture that flips a
## setting must never change the player's own.
func settings_path() -> String:
	var dir: String = GameState.save_dir() if GameState != null else ""
	return SAVE_PATH if dir == GameState.SAVE_DIR else dir.path_join("settings.cfg")


func save_settings() -> void:
	if _loading:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("gameplay", "autosave", autosave)
	cfg.set_value("gameplay", "edge_scroll", edge_scroll)
	cfg.set_value("gameplay", "camera_speed", camera_speed)
	cfg.set_value("gameplay", "ui_scale", ui_scale)
	cfg.set_value("gameplay", "show_hints", show_hints)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "display_mode", display_mode)
	cfg.set_value("video", "window_size", window_size)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "max_fps", max_fps)
	cfg.set_value("video", "animated_background", animated_background)
	cfg.set_value("video", "outline_people", outline_people)
	cfg.set_value("video", "thought_bubbles", thought_bubbles)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "interface", interface_volume)
	cfg.set_value("audio", "mute_unfocused", mute_unfocused)
	var bound: Dictionary = KeyBindings.overrides()
	for id in bound:
		cfg.set_value("controls", id, bound[id])
	cfg.save(settings_path())


func _apply_all() -> void:
	_apply_display()
	_apply_frame_pacing()
	audio_changed.emit()
	quality_changed.emit(quality)
	changed.emit()


# --- setters: each applies, announces and saves --------------------------------

## Anything without its own setter: gameplay switches, interface volume.
func set_value(key: String, value) -> void:
	set(key, value)
	match key:
		"interface_volume", "mute_unfocused":
			audio_changed.emit()
		"vsync", "max_fps":
			_apply_frame_pacing()
	changed.emit()
	save_settings()


func set_quality(value: int) -> void:
	quality = clampi(value, Quality.LOW, Quality.HIGH)
	quality_changed.emit(quality)
	save_settings()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	audio_changed.emit()
	save_settings()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	audio_changed.emit()
	save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	audio_changed.emit()
	save_settings()


func set_display_mode(value: int) -> void:
	display_mode = clampi(value, DisplayMode.WINDOWED, DisplayMode.FULLSCREEN)
	_apply_display()
	changed.emit()
	save_settings()


func set_window_size(value: Vector2i) -> void:
	window_size = value
	_apply_display()
	changed.emit()
	save_settings()


## Kept for older callers.
func set_fullscreen(value: bool) -> void:
	fullscreen = value


## Put one group back as it came. "gameplay", "video" or "audio".
func reset_section(section: String) -> void:
	_loading = true
	match section:
		"gameplay":
			autosave = true
			edge_scroll = false
			camera_speed = 1.0
			ui_scale = 1.0
			show_hints = true
		"video":
			quality = Quality.MEDIUM if OS.has_feature("mobile") else Quality.HIGH
			display_mode = DisplayMode.WINDOWED
			window_size = Vector2i(1280, 720)
			vsync = true
			max_fps = 0
			animated_background = true
			outline_people = true
			thought_bubbles = true
		"audio":
			master_volume = 1.0
			music_volume = 0.7
			sfx_volume = 0.9
			interface_volume = 0.8
			mute_unfocused = true
		"controls":
			KeyBindings.install()
			bindings_changed.emit()
	_loading = false
	_apply_all()
	save_settings()


## Window sizes that fit on this screen, for the resolution list.
func available_window_sizes() -> Array[Vector2i]:
	var screen: Vector2i = DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i(3840, 2160)
	var out: Array[Vector2i] = []
	for size in WINDOW_SIZES:
		if size.x <= screen.x and size.y <= screen.y:
			out.append(size)
	if out.is_empty():
		out.append(WINDOW_SIZES[0])
	return out


func _apply_display() -> void:
	# Phones and tablets are always fullscreen; forcing a mode there fights the
	# OS. A headless run has no window to change.
	if OS.has_feature("mobile") or DisplayServer.get_name() == "headless":
		return
	match display_mode:
		DisplayMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		DisplayMode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			# A size given on the command line wins: the capture tools and the
			# layout test ask for exact window shapes.
			if OS.get_cmdline_args().has("--resolution"):
				return
			if window_size.x > 0 and window_size.y > 0 and DisplayServer.window_get_size() != window_size:
				DisplayServer.window_set_size(window_size)
				var screen: Vector2i = DisplayServer.screen_get_size()
				DisplayServer.window_set_position((screen - window_size) / 2 + DisplayServer.screen_get_position())


func _apply_frame_pacing() -> void:
	Engine.max_fps = max_fps
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


## Per-quality forest tuning, applied on top of whatever the scene authored.
func apply_quality_to_forest(config: ForestConfig) -> void:
	match quality:
		Quality.LOW:
			config.cell_size = 16
			config.world_scale = 1.0
			config.tree_density = 0.34
		Quality.MEDIUM:
			config.cell_size = 12
			config.world_scale = 1.25
			config.tree_density = 0.42
		_:
			config.cell_size = 10
			config.world_scale = 1.5
			config.tree_density = 0.46


## Rebind one slot and keep it. Returns the action that lost the key, if any.
func bind_key(id: String, slot: int, keycode: int) -> String:
	var taken_from: String = KeyBindings.bind(id, slot, keycode)
	save_settings()
	bindings_changed.emit()
	return taken_from
