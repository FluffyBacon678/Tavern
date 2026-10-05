class_name KeyBindings
extends RefCounted

## Every keyboard shortcut in the game, by name, with the keys it starts on.
##
## Each action has two slots (a key and a spare, like WASD and the arrows). The
## table is installed into Godot's InputMap at startup, and the game asks for
## actions by name, never for keys, so a rebinding in Settings > Controls moves
## every use at once: the shortcut itself, the [B] on a button, the hint line
## and the advice that says "under Staff (K)". The player's changes are kept
## by GameSettings, in the "controls" section of the settings file.
##
## Esc (back / pause menu), Alt (hold for stack counts) and the mouse are not
## in the table: they are fixed, and the Controls page lists them as such.

## [id, group, what it does, default keys (up to two)]
const ACTIONS: Array = [
	["cam_up", "Camera", "Move the view up", [KEY_W, KEY_UP]],
	["cam_down", "Camera", "Move the view down", [KEY_S, KEY_DOWN]],
	["cam_left", "Camera", "Move the view left", [KEY_A, KEY_LEFT]],
	["cam_right", "Camera", "Move the view right", [KEY_D, KEY_RIGHT]],
	["cam_turn_left", "Camera", "Turn the view left", [KEY_Q]],
	["cam_turn_right", "Camera", "Turn the view right", [KEY_E]],
	["cam_zoom_in", "Camera", "Zoom in", [KEY_EQUAL, KEY_KP_ADD]],
	["cam_zoom_out", "Camera", "Zoom out", [KEY_MINUS, KEY_KP_SUBTRACT]],
	["cam_home", "Camera", "Back to the tavern", [KEY_H]],
	["cam_mode", "Camera", "Free or locked camera", [KEY_C]],
	["cam_follow", "Camera", "Follow the selected person", [KEY_F]],
	["pause", "Time", "Pause and resume", [KEY_SPACE]],
	["speed_1", "Time", "Normal speed (1x)", [KEY_1, KEY_KP_1]],
	["speed_2", "Time", "Fast (2x)", [KEY_2, KEY_KP_2]],
	["speed_3", "Time", "Faster (3x)", [KEY_3, KEY_KP_3]],
	["speed_4", "Time", "Fastest (5x)", [KEY_4, KEY_KP_4]],
	["build", "Tavern", "Build", [KEY_B]],
	["play_keeper", "Tavern", "Play as your keeper, or back to managing", [KEY_TAB]],
	["rotate", "Building", "Rotate what you are placing", [KEY_R]],
	["demolish", "Building", "Demolish, or sell goods", [KEY_X]],
	["build_undo", "Building", "Take back the last placement", [KEY_C]],
	["build_style", "Building", "Next style of what you are placing", [KEY_T]],
	["staff", "Tavern", "Staff and hiring", [KEY_K]],
	["production", "Tavern", "Kitchen details (advanced)", [KEY_P]],
	["supplies", "Tavern", "Stores and meal targets", [KEY_U]],
	["ledger", "Tavern", "Ledger", [KEY_L]],
	["land", "Tavern", "Buy land", []],
	["rooms", "Tavern", "Show rooms", [KEY_O]],
	["cutaway", "Tavern", "Cutaway walls or full walls", [KEY_V]],
	["quicksave", "Game", "Save now", [KEY_F5]],
	["screenshot", "Game", "Take a screenshot", [KEY_F12]],
	["toggle_fullscreen", "Game", "Full screen or windowed", [KEY_F11]],
]

## Actions that only count while the build bar is open. They may share a key
## with an action that works everywhere else -- C takes back a placement while
## building, and switches the camera the rest of the time -- and they win while
## the bar is open.
const BUILD_ONLY: Array[String] = ["build_undo", "build_style"]

## Keys the table may not take: they mean something fixed.
const RESERVED: Array = [KEY_ESCAPE, KEY_ALT, KEY_SHIFT, KEY_CTRL, KEY_META]

## id -> [primary, spare] keycodes, 0 for an empty slot.
static var _keys: Dictionary = {}


## Put the defaults, then the player's changes, into the InputMap.
static func install(overrides: Dictionary = {}) -> void:
	_keys.clear()
	for entry in ACTIONS:
		var keys: Array = [0, 0]
		for i in range(mini(2, entry[3].size())):
			keys[i] = int(entry[3][i])
		_keys[entry[0]] = keys
	for id in overrides:
		if _keys.has(id) and overrides[id] is Array and overrides[id].size() == 2:
			_keys[id] = [int(overrides[id][0]), int(overrides[id][1])]
	for id in _keys:
		_apply(id)


## Only what differs from the defaults, for the settings file.
static func overrides() -> Dictionary:
	var out: Dictionary = {}
	for entry in ACTIONS:
		var keys: Array = keys_of(entry[0])
		var defaults: Array = [0, 0]
		for i in range(mini(2, entry[3].size())):
			defaults[i] = int(entry[3][i])
		if keys != defaults:
			out[entry[0]] = keys
	return out


static func keys_of(id: String) -> Array:
	if _keys.is_empty():
		install()
	return _keys.get(id, [0, 0]).duplicate()


## Bind a slot. Returns the action that had this key before and lost it ("" if
## none): one key does one thing, so taking it moves it rather than doubling up.
static func bind(id: String, slot: int, keycode: int) -> String:
	if _keys.is_empty():
		install()
	if not _keys.has(id) or slot < 0 or slot > 1 or RESERVED.has(keycode):
		return ""
	var taken_from: String = ""
	if keycode != 0:
		for other in _keys:
			# A build-bar action and an everywhere-else one can share a key.
			if BUILD_ONLY.has(other) != BUILD_ONLY.has(id):
				continue
			for s in range(2):
				if int(_keys[other][s]) == keycode and not (other == id and s == slot):
					_keys[other][s] = 0
					taken_from = other
					_apply(other)
	_keys[id][slot] = keycode
	_apply(id)
	return taken_from


static func label_of(id: String) -> String:
	for entry in ACTIONS:
		if entry[0] == id:
			return entry[2]
	return id


## "B", "W / Up", or "" when nothing is bound.
static func text_for(id: String) -> String:
	var names: PackedStringArray = PackedStringArray()
	for k in keys_of(id):
		if int(k) != 0:
			names.append(key_name(int(k)))
	return " / ".join(names)


## The key to name in a sentence: the first bound one, or a plain word.
static func first(id: String) -> String:
	for k in keys_of(id):
		if int(k) != 0:
			return key_name(int(k))
	return "(no key set)"


## The four movement keys of one slot, "WASD" or "Up Left Down Right".
static func move_keys(slot: int = 0) -> String:
	var names: Array[String] = []
	for id in ["cam_up", "cam_left", "cam_down", "cam_right"]:
		var k: int = int(keys_of(id)[slot])
		if k == 0:
			return ""
		names.append(key_name(k))
	var letters: bool = names.all(func(n: String) -> bool: return n.length() == 1)
	return "".join(names) if letters else " ".join(names)


## " [B]" for a button label, or nothing when unbound.
static func tag(id: String) -> String:
	var keys: Array = keys_of(id)
	return " [%s]" % key_name(int(keys[0])) if int(keys[0]) != 0 else ""


## " (K)" for a sentence, or nothing when unbound.
static func hint(id: String) -> String:
	var keys: Array = keys_of(id)
	return " (%s)" % key_name(int(keys[0])) if int(keys[0]) != 0 else ""


static func key_name(keycode: int) -> String:
	match keycode:
		KEY_EQUAL: return "="
		KEY_MINUS: return "-"
		KEY_KP_ADD: return "Num +"
		KEY_KP_SUBTRACT: return "Num -"
		KEY_SPACE: return "Space"
	if keycode >= KEY_KP_0 and keycode <= KEY_KP_9:
		return "Num %d" % (keycode - KEY_KP_0)
	return OS.get_keycode_string(keycode)


static func _apply(id: String) -> void:
	if not InputMap.has_action(id):
		InputMap.add_action(id)
	InputMap.action_erase_events(id)
	for k in _keys[id]:
		if int(k) == 0:
			continue
		var event := InputEventKey.new()
		event.keycode = int(k)
		InputMap.action_add_event(id, event)
