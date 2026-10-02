extends Node

## Sandboxed tutorial observer. Default: play manually in the real window.
## -- auto: use the existing scripted actions, but keep the LIVE director.
## -- out=res://...: compact state.json, transition-only events.jsonl and shots.
## Create <out>/stop to finish a manual session cleanly. No gameplay edits.
var world: TavernWorld
var out_dir: String = "res://.verification/tutorial_watch"
var automatic: bool = false
var probe_filter: bool = false
var _status: String = "RUNNING"
var _last_step: String = ""
var _step_started: float = 0.0
var _real_started: int = 0
var _step_real: int = 0
var _next_snapshot: int = 0
var _acted: Dictionary = {}
var _events: FileAccess
var _ending: bool = false


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg == "auto":
			automatic = true
		elif arg == "probe_filter":
			automatic = true
			probe_filter = true
		elif arg.begins_with("out="):
			out_dir = arg.trim_prefix("out=")
	if DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		get_tree().quit(2)
		return
	_events = FileAccess.open(out_dir.path_join("events.jsonl"), FileAccess.WRITE)
	if _events == null:
		get_tree().quit(2)
		return
	SimWait.seed_run()
	var level: LevelDef = LevelCatalog.tutorial()
	GameState.pending_level = level.id
	GameState.start_new_run(level.tavern_name, level.world_seed, GameState.MAX_SLOTS - 1, true)
	world = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	if automatic:
		SimWait.configure(world)
		# The OS pointer is unrelated to the scripted hover action. Leave normal
		# pointer handling intact in manual mode, isolate it only in auto mode.
		world.input.hover_enabled = false
	_real_started = Time.get_ticks_msec()
	# Wall-time watchdog also covers an action coroutine or paused-clock stall.
	get_tree().create_timer(180.0 if automatic else 1800.0).timeout.connect(func() -> void: _finish("TIMEOUT", 1))
	print("WATCH: %s; read %s/state.json; screenshots only at step changes" % ["scripted live director" if automatic else "manual controls", out_dir])
	while not _ending:
		await get_tree().process_frame
		if FileAccess.file_exists(out_dir.path_join("stop")):
			DirAccess.remove_absolute(out_dir.path_join("stop"))
			_finish("STOPPED", 0)
			return
		var director: TutorialDirector = world.hud.tutorial
		if director == null:
			_finish("NO DIRECTOR", 1)
			return
		var step: TutorialStep = director.current()
		if director.is_complete():
			_finish("COMPLETE", 0)
			return
		if step == null:
			continue
		if step.id != _last_step:
			_last_step = step.id
			_step_started = world.sim.sim_time
			_step_real = Time.get_ticks_msec()
			_record("step")
			await _shot("%02d_%s" % [director.index + 1, step.id])
		if Time.get_ticks_msec() >= _next_snapshot:
			_snapshot()
			_next_snapshot = Time.get_ticks_msec() + 1000
		if not automatic:
			continue
		if not _acted.has(step.id):
			_acted[step.id] = true
			if probe_filter and step.id == "filter":
				await _probe_filter()
				return
			if step.perform.is_valid():
				await step.perform.call(world, director.ctx)
		# At turbo speed a selected guest may leave before the director's real-
		# time poll. Point at another actual guest, as a player would; never skip.
		if step.id in ["hover_guest", "guest_type"] and not step.done.call(world, director.ctx):
			await step.perform.call(world, director.ctx)
		# Match a player's continuation after an unexpected day close, but let
		# the actual tutorial handle the lessons explicitly teaching the summary.
		if world.simulation_paused and step.id not in ["day_end", "reviews"]:
			if not PlayerActions.press(world.hud._day_summary, "Open tomorrow"):
				PlayerActions.press(world.hud._day_summary, "Keep trading")
		var overdue: bool = world.sim.sim_time - _step_started > step.budget + 2.0
		var frozen: bool = Time.get_ticks_msec() - _step_real > 30000 and world.sim.sim_time - _step_started < 1.0
		if overdue or frozen:
			_finish("STALLED", 1)
			return


func _state() -> Dictionary:
	var director: TutorialDirector = world.hud.tutorial
	var step: TutorialStep = director.current() if director != null else null
	var panels: Array[String] = []
	for child in world.hud._hud.get_children():
		if child is PanelContainer and child.is_visible_in_tree():
			panels.append(String(child.name))
	return {"status": _status, "mode": "scripted" if automatic else "manual", "step": step.id if step != null else "complete",
		"pid": OS.get_process_id(), "updated_unix": Time.get_unix_time_from_system(),
		"already_done": step.done.call(world, director.ctx) if step != null else true,
		"index": director.index + 1 if step != null else director.steps.size(), "total": director.steps.size(),
		"instruction": step.text if step != null else "Tutorial complete", "day": world.clock.day,
		"clock": world.clock.clock_text(), "speed": world.sim.speed, "held": world.sim.held,
		"gold": GameState.gold, "blueprints": TutorialPlan.blueprints(world), "staff": world.workers.size(),
		"guests": world.customers.customers.size(), "served": world.customers.served_count,
		"step_game_s": snappedf(world.sim.sim_time - _step_started, 0.1),
		"real_s": (Time.get_ticks_msec() - _real_started) / 1000, "panels": panels,
		"trouble": Trouble.diagnose(world)}


func _snapshot() -> void:
	var file := FileAccess.open(out_dir.path_join("state.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_state()))
	else:
		_finish("STATE WRITE FAILED", 2)


func _record(event: String) -> void:
	var state: Dictionary = _state()
	state["event"] = event
	_events.store_line(JSON.stringify(state))
	_events.flush()
	print("WATCH %s %02d/%02d %-14s day=%d %s gold=%d blueprints=%d served=%d" % [event, state.index, state.total, state.step, state.day, state.clock, state.gold, state.blueprints, state.served])
	_snapshot()


func _shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var error: int = get_viewport().get_texture().get_image().save_png(out_dir.path_join(label + ".png"))
	if error != OK:
		_finish("CAPTURE FAILED", 2)


func _finish(reason: String, code: int) -> void:
	if _ending:
		return
	_ending = true
	_status = reason
	SimWait.hold(world)
	if reason == "COMPLETE":
		var report: Node = load("res://dev/world_scenario.gd").new()
		report.world = world
		add_child(report)
		var was_brief: bool = TestOutput.brief
		TestOutput.brief = true
		var balanced: bool = report.reconcile(false)
		TestOutput.brief = was_brief
		if not balanced:
			reason = "RECONCILIATION FAILED"
			_status = reason
			code = 1
	_record(reason)
	if code != 0:
		print("WATCH diagnostic: " + JSON.stringify(_state()))
	await _shot("final_" + reason.to_lower().replace(" ", "_"))
	print("TUTORIAL WATCH: %s" % reason)
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(code)


## Reproduce the lesson using one actual checkbox toggle, then wait for the
## live director. Do not call its done/advance or change a filter directly.
func _probe_filter() -> void:
	var index: int = world.build.grid.placement_at(TutorialPlan.at(world, TutorialPlan.SHELVES[0]))
	world.hud.inspector.show_subject({"kind": WorldStats.Kind.BUILDING, "index": index})
	await get_tree().process_frame
	await _shot("filter_before")
	var flour: CheckBox
	var ticked: int = 0
	for box in world.hud.inspector.find_children("*", "CheckBox", true, false):
		ticked += int(box.button_pressed)
		if box.text.begins_with("Flour"):
			flour = box
	print("FILTER PROBE: initially ticked=%d; instruction=%s" % [ticked, world.hud.tutorial.current().text])
	if flour == null:
		_finish("PROBE CONTROL MISSING", 2)
		return
	flour.button_pressed = true
	await get_tree().create_timer(0.6).timeout
	var accepts_yeast: bool = world.build.grid.allows(index, &"yeast")
	var advanced: bool = world.hud.tutorial.current().id != "filter"
	print("FILTER PROBE: after ticking only Flour: allows_yeast=%s advanced=%s current=%s" % [accepts_yeast, advanced, world.hud.tutorial.current().id])
	await _shot("filter_after_one_tick")
	_finish("FILTER BUG REPRODUCED" if advanced and not accepts_yeast else "FILTER BUG NOT REPRODUCED", 1 if advanced and not accepts_yeast else 0)
