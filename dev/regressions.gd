extends Node

## The regression suite: every group, each on a fresh tavern of its own.
##
##   godot --headless --path . res://dev/regressions.tscn
##   godot --headless --path . res://dev/regressions.tscn -- group=people
##
## The checks live in dev/regressions_<group>.gd, on dev/regression_group.gd.
## A new check goes in the group it belongs to, and sets up anything it needs
## rather than counting on what an earlier check left lying about.
const GROUPS: Array[String] = ["goods", "building", "people", "game", "garden"]

var failures: int = 0


func _ready() -> void:
	if not OS.is_debug_build():
		get_tree().quit(1)
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--storage-plan-only"):
		var goods: Node = load("res://dev/regressions_goods.gd").new()
		add_child(goods)
		goods._check_planned_storage_filters()
		print("STORAGE PLANS %s (%d failures)" % ["PASS" if goods.failures == 0 else "FAIL", goods.failures])
		get_tree().quit(0 if goods.failures == 0 else 1)
		return
	if not GameState.begin_test_session():
		push_error("Regression save isolation could not be established")
		get_tree().quit(1)
		return

	var only: String = ""
	for arg in args:
		if arg.begins_with("group="):
			only = arg.trim_prefix("group=")
	if not only.is_empty() and not GROUPS.has(only):
		push_error("No regression group '%s'; there are %s" % [only, ", ".join(GROUPS)])
		get_tree().quit(2)
		return

	var tally: PackedStringArray = PackedStringArray()
	for name in GROUPS:
		if not only.is_empty() and name != only:
			continue
		print("=== group: %s ===" % name)
		var group: Node = load("res://dev/regressions_%s.gd" % name).new()
		group.name = name.capitalize()
		add_child(group)
		group.build_fixture()
		await group.run()
		await group.free_fixture()
		failures += group.failures
		tally.append("%s %d" % [name, group.failures])
		group.queue_free()
		await get_tree().process_frame

	# Summary last, and only here: the suite must not announce its result, and
	# exit, while a group still has checks to run.
	print("Failures by group: %s" % ", ".join(tally))
	print("REGRESSIONS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
