extends Control

## Dev tool, not shipped content.
##
## Loads a screen, waits for it to settle (the forest atlases build on first run
## and take a moment), captures the viewport to a PNG and quits. Lets menu
## visuals be checked from the command line without driving the window by hand.
##
## Usage:
##   godot --path . res://scenes/_screenshot_harness.tscn -- <scene_path> <out_png> [seconds] [key=value,...]

const DEFAULT_SCENE := "res://src/ui/main_menu/main_menu.tscn"
const DEFAULT_OUT := "user://screenshot.png"
const DEFAULT_WAIT: float = 5.0


func _ready() -> void:
	if not OS.is_debug_build():
		get_tree().quit(1)
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_path: String = args[0] if args.size() > 0 else DEFAULT_SCENE
	var out_path: String = args[1] if args.size() > 1 else DEFAULT_OUT
	var wait: float = float(args[2]) if args.size() > 2 else DEFAULT_WAIT
	var opts: Dictionary = {}
	if args.size() > 3:
		for pair in args[3].split(",", false):
			var kv: PackedStringArray = pair.split("=", false)
			if kv.size() == 2:
				opts[kv[0].strip_edges()] = kv[1].strip_edges()
	if opts.has("seed"):
		GameState.world_seed = int(opts["seed"])
		seed(GameState.world_seed)
	if opts.has("report") and float(opts["report"]) >= wait:
		push_error("Report must run before the screenshot wait expires")
		get_tree().quit(1)
		return

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Screenshot harness: could not load '%s'." % scene_path)
		get_tree().quit(1)
		return

	var screen: Node = packed.instantiate()
	add_child(screen)

	# Optional 4th arg: "key=value,key=value" handed to the scene, so a capture
	# can be set up (camera angle, zoom) without a human driving it.
	if args.size() > 3:
		await get_tree().process_frame
		if screen is TavernWorld:
			var scenario: Node = load("res://dev/world_scenario.gd").new()
			scenario.world = screen
			add_child(scenario)
			scenario.screenshot_setup(opts)
		elif screen.has_method("screenshot_setup"):
			screen.call("screenshot_setup", opts)

	await get_tree().create_timer(wait).timeout
	if DisplayServer.get_name() == "headless":
		print("Headless checks complete; screenshot skipped")
		get_tree().quit(0)
		return
	# The viewport texture is only valid once the frame has actually been drawn.
	await RenderingServer.frame_post_draw

	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(out_path)
	if err != OK:
		push_error("Screenshot harness: save failed (%d) for '%s'." % [err, out_path])
		get_tree().quit(1)
		return

	print("Screenshot written: %s (%dx%d)" % [out_path, img.get_width(), img.get_height()])
	get_tree().quit(0)
