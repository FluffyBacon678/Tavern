class_name PlayerActions
extends RefCounted

## What a player does, as the game's own input layer does it: press a button
## through its `pressed` signal, click a tile the way WorldInput turns a click
## into a build, drag the way it opens and closes a drag.
##
## Used by the tutorial's automated player (every TutorialStep's `perform`) and
## by dev/playthrough.gd. Never sets results directly -- an action a player
## cannot take is not one these may take either.


## Choose a piece in the build bar, opening the bar and its category first.
static func select(world, id: StringName) -> void:
	var def: BuildingDef = BuildingCatalog.get_def(id)
	var bar: BuildBar = world.hud._build_bar
	if bar != null and not bar.visible:
		world.hud._toggle_build_bar()
	if bar != null and bar._item_buttons.has(id):
		bar._show_category(def.category)
		bar._item_buttons[id].pressed.emit()
	else:
		world.build.select(def)


## A left click on a tile in build mode. Returns whether a piece went down.
static func click(world, tile: Vector2i, rotation: int = 0) -> bool:
	var before: int = world.build.grid.live_count()
	world.build.rotation_steps = rotation
	world.build.update_hover(tile, true)
	world.commit_build_action()
	world.build.rotation_steps = 0
	return world.build.grid.live_count() > before


## Press on `from`, release on `to`. Returns how many pieces went down.
static func drag(world, from: Vector2i, to: Vector2i) -> int:
	var before: int = world.build.grid.live_count()
	world.build.update_hover(from, true)
	if not world.build.begin_drag(from):
		return 0
	world.build.update_hover(to, true)
	world.commit_area_build()
	return world.build.grid.live_count() - before


## Place `id` at each tile, from a build bar selection. Returns how many went down.
static func place_all(world, id: StringName, tiles: Array, rotation: int = 0) -> int:
	select(world, id)
	var n: int = 0
	for tile in tiles:
		n += int(click(world, tile, rotation))
	return n


## Demolish mode, then a click on the tile.
static func demolish(world, tile: Vector2i) -> bool:
	var bar: BuildBar = world.hud._build_bar
	if bar != null and not bar.visible:
		world.hud._toggle_build_bar()
	# Pressing the toggle is what the player does; it sets demolish mode.
	if bar != null and not bar._demolish_button.button_pressed:
		bar._demolish_button.button_pressed = true
	world.build.mode = BuildController.Mode.DEMOLISH
	world.build.update_hover(tile, true)
	var before: int = world.build.grid.live_count()
	world.commit_build_action()
	return world.build.grid.live_count() < before


## The take-back key in the build bar, as WorldInput answers it.
static func undo(world) -> int:
	if world.hud._build_bar != null and not world.hud._build_bar.visible:
		world.hud._toggle_build_bar()
	return world.undo_last_placement()


## Leave build mode and close the bar, as Esc does.
static func stop_building(world) -> void:
	world.build.mode = BuildController.Mode.OFF
	if world.hud._build_bar != null and world.hud._build_bar.visible:
		world.hud._toggle_build_bar()


## Press the first visible, enabled button whose text starts with `text`.
static func press(root: Node, text: String) -> bool:
	var b: Button = find_button(root, text)
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	return true


static func find_button(root: Node, text: String) -> Button:
	if root == null:
		return null
	if root is Button and root.is_visible_in_tree() and (root.text == text or root.text.begins_with(text)):
		return root
	for child in root.get_children():
		var found: Button = find_button(child, text)
		if found != null:
			return found
	return null


## The first member of staff in a position, or null.
static func staff(world, role_id: StringName) -> Worker:
	for worker in world.workers:
		if is_instance_valid(worker) and worker.role != null and worker.role.id == role_id:
			return worker
	return null
