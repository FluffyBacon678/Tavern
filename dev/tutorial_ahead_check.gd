extends Node

## A newcomer who goes ahead of the tutorial: builds, or runs the clock, before
## touching the camera. The look-around steps step aside instead of holding
## them on "Move the view" for ever; time already run counts as run.
##   godot --headless --path . res://dev/tutorial_ahead_check.tscn

var failures: int = 0
var world: TavernWorld


func check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	# Builds first: the build bar opened on the very first step.
	var director: TutorialDirector = await _open()
	check(director.current().id == "cam_move", "the tutorial opens on moving the view")
	check(not director._why.text.contains("Time is paused"), "and does not promise time is paused while it may run")
	world.hud._toggle_build_bar()
	await _wait(director, "time_speed")
	check(director.current().id == "time_speed", "opening the build bar passes the camera steps (now on %s)" % director.current().id)
	# Runs the clock first.
	director = await _open()
	world.sim.speed = 1
	await _wait(director, "inspect")
	check(director.current().id == "inspect", "running time passes the camera steps and counts as having run it (now on %s)" % director.current().id)
	check(world.sim.speed == 0, "and the next step starts paused, as steps that need doing do")
	# Does nothing: it stays where it is.
	director = await _open()
	var until: int = Time.get_ticks_msec() + 1200
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
	check(director.current().id == "cam_move", "a player who has not moved on is not moved on")
	print("TUTORIAL AHEAD CHECK: %d failure(s)" % failures)
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)


func _open() -> TutorialDirector:
	if is_instance_valid(world):
		world.queue_free()
		await get_tree().process_frame
	var level: LevelDef = LevelCatalog.tutorial()
	GameState.pending_level = level.id
	GameState.start_new_run(level.tavern_name, level.world_seed, GameState.MAX_SLOTS - 1, true)
	world = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	return world.hud.tutorial


## The director checks four times a real second; give it a few chances.
func _wait(director: TutorialDirector, id: String) -> void:
	var until: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < until and director.current() != null and director.current().id != id:
		await get_tree().process_frame
