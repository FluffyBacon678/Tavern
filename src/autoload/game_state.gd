extends Node

## Run-level game state and save-slot bookkeeping.
##
## Slot ownership is separate from load intent, so a new tavern can replace a
## chosen slot without accidentally continuing its previous contents.

const SAVE_DIR := "user://saves"
const SLOT_FILE_FORMAT := "user://saves/slot_%d.json"
## Where test fixtures keep their scratch saves, one directory per run.
const TEST_SAVE_ROOT := "res://.verification/test_saves"
const MAX_SLOTS: int = 3
const SAVE_FORMAT_VERSION: int = 2
## Enough to build a working tavern, stock it, and pay wages while it finds its
## feet.
##
## Measured against the guided opening rather than estimated. A player following
## the on-screen objectives builds about 410g of tavern -- the two bread
## stations, a vat, a wash basin, seven tiles of storage, three tables with
## chairs, and sixty floor tiles at 2g each, which is the part that is easy to
## forget. The first delivery is 115g and the first day's wages 30g before a
## single customer has paid.
##
## Anything less makes a player who follows the instructions correctly go broke
## for doing so, which is the worst possible first lesson.
##
## 800 since 2026-09-28: that sum left out walls, and a scripted newcomer who
## walled a 10 x 8 room as the hint suggests ran out before the kitchen. Wages
## have also doubled since (58g a night for the opening crew).
const STARTING_GOLD: int = 800

signal run_started

## The level a new run should open into, or empty for a bare plot.
##
## Set by the menu just before the scene changes and cleared once the world has
## read it, so a later run does not inherit somebody else's tavern.
var pending_level: StringName = &""

## Populated when a run is in progress. Empty between runs.
var tavern_name: String = ""
var world_seed: int = 0
## Personal identity belongs to this tavern/save, separate from its name.
var owner_profile: CharacterProfile = CharacterProfile.default_owner()
var active_slot: int = -1
## Starting purse. Placeholder value from the design notes' demo economy.
var gold: int = STARTING_GOLD
## New and Continue are explicit intents; an occupied slot never implies load.
var load_requested: bool = false
## Set by start_new_run(), the one confirmed way to put a fresh tavern into a
## slot. The world consumes it. Entering with neither this nor load_requested
## is a caller's mistake -- the main menu made it for every Continue and Open --
## and the world then loads rather than overwrite the save.
var new_run_pending: bool = false
## Set by the title screen for a new game: open paused, so the player can plan
## before the clock runs. The world consumes it. Tests never set it.
var start_paused: bool = false
## A new sandbox opens in the finished test house (TestHouse) rather than on
## an empty plot. Set by the main menu only, so test fixtures keep their plot.
var full_house_start: bool = false
## A failed resume is shown at the menu rather than opening an empty tavern.
var load_error: String = ""
var _test_save_dir: String = ""
var _test_previous_state: Dictionary = {}


## Development fixtures must call this before any slot operation. Each session
## gets a fresh workspace directory; player saves are never test scratch space.
func begin_test_session() -> bool:
	if not OS.is_debug_build() or not _test_save_dir.is_empty():
		return false
	var path := "%s/%d_%d" % [TEST_SAVE_ROOT, OS.get_process_id(), Time.get_ticks_usec()]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path)) != OK:
		return false
	_test_previous_state = {"slot": active_slot, "name": tavern_name, "seed": world_seed,
		"gold": gold, "load": load_requested, "owner": owner_profile}
	_test_save_dir = path
	active_slot = -1
	load_requested = false
	owner_profile = CharacterProfile.default_owner(world_seed)
	return true


## Also the fixture's tidy-up: its scratch saves go with it. No suite ever
## called this, so every run left a directory behind -- 273 of them by the
## time anyone looked -- and it now runs by itself when the game exits.
func end_test_session() -> void:
	if _test_save_dir.is_empty():
		return
	_remove_test_dir(_test_save_dir)
	active_slot = _test_previous_state["slot"]
	tavern_name = _test_previous_state["name"]
	world_seed = _test_previous_state["seed"]
	gold = _test_previous_state["gold"]
	load_requested = _test_previous_state["load"]
	owner_profile = _test_previous_state["owner"]
	_test_save_dir = ""
	_test_previous_state.clear()


func _exit_tree() -> void:
	end_test_session()


## Only ever a test workspace: the path is checked, never trusted.
func _remove_test_dir(path: String) -> void:
	if not path.begins_with(TEST_SAVE_ROOT + "/"):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func save_dir() -> String:
	return _test_save_dir if not _test_save_dir.is_empty() else SAVE_DIR


func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [save_dir(), slot] if slot >= 0 and slot < MAX_SLOTS else ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func has_any_save() -> bool:
	for slot in range(MAX_SLOTS):
		if has_save(slot):
			return true
	return false


## Is there a file in any slot, readable or not?
##
## Distinct from has_any_save(), which asks whether anything can be *loaded*. A
## save from an older format counts here and not there -- otherwise a player
## whose slots all predate a format change is shown no way to clear them.
func has_any_slot_data() -> bool:
	for slot in range(MAX_SLOTS):
		if has_slot_data(slot):
			return true
	return false


func has_save(slot: int) -> bool:
	return not slot_summary(slot).is_empty()


func has_slot_data(slot: int) -> bool:
	var path := slot_path(slot)
	return not path.is_empty() and (FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak"))


## Metadata for a slot, for the menu to label a Continue button.
## Returns an empty dictionary when the slot is empty or unreadable.
func slot_summary(slot: int) -> Dictionary:
	var summary: Dictionary = SaveGame.read(slot)
	if not summary.is_empty():
		# Keep provenance on the card; another slot read changes the shared flag.
		summary["backup_recovered"] = SaveGame.recovered_backup
	return summary


func most_recent_slot() -> int:
	var best: int = -1
	var best_time: int = -1
	for slot in range(MAX_SLOTS):
		var summary: Dictionary = slot_summary(slot)
		if summary.is_empty():
			continue
		var t: int = int(summary.get("saved_at", 0))
		if t > best_time:
			best_time = t
			best = slot
	return best


## A full set of slots needs an explicit selection and replacement decision.
func start_new_run(p_tavern_name: String, p_seed: int = -1, slot: int = -1, replace_existing: bool = false) -> bool:
	var chosen: int = _first_free_slot() if slot < 0 else slot
	if chosen < 0 or chosen >= MAX_SLOTS or (has_slot_data(chosen) and not replace_existing):
		return false
	tavern_name = p_tavern_name.strip_edges()
	if tavern_name.is_empty():
		tavern_name = "The Drunken Dwarf"
	world_seed = p_seed if p_seed >= 0 else randi() % 1_000_000
	owner_profile = CharacterProfile.default_owner(world_seed)
	gold = STARTING_GOLD
	active_slot = chosen
	load_requested = false
	new_run_pending = true
	run_started.emit()
	return true


func request_continue(slot: int) -> bool:
	if not has_save(slot):
		return false
	active_slot = slot
	load_requested = true
	new_run_pending = false
	return true


func _first_free_slot() -> int:
	for slot in range(MAX_SLOTS):
		if not has_slot_data(slot):
			return slot
	return -1


func delete_slot(slot: int) -> void:
	var path := slot_path(slot)
	if path.is_empty():
		return
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
