class_name WorldInput
extends Node3D

## Everything the player does with the pointer and the keyboard in the world:
## the tile cursor, clicking to select or build, the hover card and its rings,
## following someone with the camera, and the shortcut keys.
##
## Split out of TavernWorld, which had grown to a thousand lines doing all of
## this beside land, days, saving and staff. The world still owns the rules --
## what a click *costs*, what building means -- and this owns what a click *is*.
##
## Must stay the world's first child. Input reaches later siblings first, and
## the camera rig has to see a right-click before this clears the inspector on
## it, or orbiting stops working.

var world  ## TavernWorld
## Off only for screen captures, where wherever the real pointer happens to
## rest would otherwise put a card over the thing being photographed.
var hover_enabled: bool = true
## Under whatever the inspector describes, and under whatever the pointer rests
## on. Two markers because both questions are live at once: "which one did I
## click?" and "which one is this card about?"
var selection_marker: SelectionMarker
var hover_marker: SelectionMarker
## The tile under the pointer, or (-1, -1) when it is off the map.
var cursor_tile := Vector2i(-1, -1)

var _cursor: MeshInstance3D


func setup(p_world) -> void:
	world = p_world
	name = "Input"
	_cursor = MeshInstance3D.new()
	_cursor.name = "TileCursor"
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Drawn on top of the terrain it hugs, otherwise it z-fights badly on slopes.
	mat.no_depth_test = true
	_cursor.material_override = mat
	_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cursor)
	selection_marker = SelectionMarker.new()
	selection_marker.name = "SelectionMarker"
	selection_marker.set_colour(Color(TavernTheme.CANDLE, 0.95))
	add_child(selection_marker)
	hover_marker = SelectionMarker.new()
	hover_marker.name = "HoverMarker"
	hover_marker.set_colour(Color(TavernTheme.PARCHMENT, 0.45))
	add_child(hover_marker)


func _process(delta: float) -> void:
	if world == null:
		return
	_update_cursor()
	_update_hover(delta)


# --- keys and clicks -----------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if world == null or world.simulation_paused or world.hud.pause_menu_open():
		return
	var build: BuildController = world.build
	var hud = world.hud
	if event.is_action_pressed("ui_cancel"):
		# Escape backs out one level at a time rather than leaving the game from
		# inside a build action.
		if build != null and build.mode != BuildController.Mode.OFF:
			build.mode = BuildController.Mode.OFF
		elif not hud.close_top_panel():
			# Nothing left to close: the pause menu, never straight out of the
			# game -- that dropped players at the title screen, unsaved.
			hud.open_pause_menu()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed:
		# The build bar's own keys first: C takes back a placement there, and
		# only switches the camera when the bar is shut.
		if not event.echo and hud._build_bar != null and hud._build_bar.visible \
				and event.is_action_pressed("build_undo"):
			world.undo_last_placement()
			get_viewport().set_input_as_handled()
			return
		# T: the next style of the piece being placed.
		if not event.echo and hud._build_bar != null and hud._build_bar.visible \
				and event.is_action_pressed("build_style"):
			hud._build_bar.next_style()
			get_viewport().set_input_as_handled()
			return
		# F3, debug builds only: the developer's figures, kept off the Ledger.
		if not event.echo and event.keycode == KEY_F3 and OS.is_debug_build():
			hud.toggle_developer_figures()
			get_viewport().set_input_as_handled()
			return
		# Zoom keys repeat while held, like the wheel; everything else fires once.
		if event.is_action_pressed("cam_zoom_in", true):
			world.rig.zoom_by(-1.0)
		elif event.is_action_pressed("cam_zoom_out", true):
			world.rig.zoom_by(1.0)
		elif not event.echo:
			for action in _SHORTCUTS:
				if event.is_action_pressed(action):
					_shortcut(action)
					get_viewport().set_input_as_handled()
					break
		return

	# Playing the keeper: the pointer moves them, RuneScape-style.
	var controls: KeeperControls = world.keeper_controls
	if controls != null and controls.playing and (build == null or build.mode == BuildController.Mode.OFF) \
			and (event is InputEventMouseButton or event is InputEventScreenTouch):
		if controls.handle(event):
			get_viewport().set_input_as_handled()
		return

	if not (event is InputEventMouseButton):
		return

	# Build mode takes both edges of the click: flooring is painted by dragging
	# a rectangle, so the press opens an area and the release commits it.
	# Everything else is still placed on the press, where it has always been.
	if build != null and build.mode != BuildController.Mode.OFF:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not build.begin_drag(cursor_tile):
					world.commit_build_action()
			elif build.is_dragging():
				world.commit_area_build()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if build.is_dragging():
				build.cancel_drag()
			else:
				build.mode = BuildController.Mode.OFF
			get_viewport().set_input_as_handled()
		return

	if not event.pressed:
		return

	# Outside build mode a click selects. It used to order every pawn to walk to
	# the clicked tile, which was a pathfinding test crutch -- the job system
	# gives them work now, and "all staff drop everything and walk here" is not
	# a thing a tavern keeper should be able to do by accident.
	if event.button_index == MOUSE_BUTTON_LEFT:
		select_at(get_viewport().get_mouse_position())
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		hud.inspector.clear()
		get_viewport().set_input_as_handled()


func toggle_camera_mode() -> void:
	var rig: CameraRig = world.rig
	rig.mode = CameraRig.Mode.FREE if rig.mode == CameraRig.Mode.LOCKED else CameraRig.Mode.LOCKED


# --- the cursor ------------------------------------------------------------------

## Follow the pointer with a highlight that matches the hovered tile's corner
## heights, so it lies flat on slopes instead of hovering over them. This is the
## picking path that building placement uses.
func _update_cursor() -> void:
	var rig: CameraRig = world.rig
	var build: BuildController = world.build
	if rig == null or _cursor == null:
		return
	if world.simulation_paused:
		_cursor.visible = false
		return
	var hit: Array = []
	if not rig.ground_point_at(get_viewport().get_mouse_position(), hit):
		_off_map()
		return

	var p: Vector3 = hit[0]
	var tx: int = int(floor(p.x / TerrainMeshBuilder.TILE))
	var tz: int = int(floor(p.z / TerrainMeshBuilder.TILE))
	if tx < 0 or tz < 0 or tx >= world.grid.cols or tz >= world.grid.rows:
		_off_map()
		return

	_cursor.visible = true
	var tile := Vector2i(tx, tz)
	if build != null:
		build.update_hover(tile, true)
	if tile == cursor_tile:
		return
	cursor_tile = tile

	var terrain: TerrainMeshBuilder = world.terrain
	var lift: float = 0.04
	var fx: float = float(tx) * TerrainMeshBuilder.TILE
	var fz: float = float(tz) * TerrainMeshBuilder.TILE
	var mb := MeshBuilder.new()
	mb.add_quad(
		Vector3(fx, terrain.height_at_corner(tx, tz) + lift, fz),
		Vector3(fx, terrain.height_at_corner(tx, tz + 1) + lift, fz + TerrainMeshBuilder.TILE),
		Vector3(fx + TerrainMeshBuilder.TILE, terrain.height_at_corner(tx + 1, tz + 1) + lift, fz + TerrainMeshBuilder.TILE),
		Vector3(fx + TerrainMeshBuilder.TILE, terrain.height_at_corner(tx + 1, tz) + lift, fz),
		Color(1.0, 0.86, 0.45, 0.35)
	)
	_cursor.mesh = mb.commit()


func _off_map() -> void:
	_cursor.visible = false
	cursor_tile = Vector2i(-1, -1)
	if world.build != null:
		world.build.update_hover(Vector2i(-1, -1), false)


# --- selecting and hovering ------------------------------------------------------

## Pick whatever is under the pointer, in the order a player means it.
##
## People first, because they are what you are usually asking about and they
## stand *on* the floor and items you would otherwise hit. Then whatever is
## built on the tile, then loose goods lying on it.
func select_at(screen_pos: Vector2) -> void:
	var hit: Array = []
	if world.rig == null or not world.rig.ground_point_at(screen_pos, hit):
		world.hud.inspector.clear()
		return
	# The same answer the hover card gives, so clicking what the card describes
	# always opens that thing and never the one beneath it.
	world.hud.inspector.show_subject(WorldStats.subject_at(world, hit[0]))


## Feed the hover card whatever the pointer is resting on, and ring it.
func _update_hover(delta: float) -> void:
	var hud = world.hud
	if hud == null or hud.hover == null:
		return
	var subject: Dictionary = {}
	if _hover_allowed():
		var hit: Array = []
		if world.rig.ground_point_at(get_viewport().get_mouse_position(), hit):
			subject = WorldStats.subject_at(world, hit[0])
	hud.hover.track(subject, delta)

	if hover_marker == null:
		return
	# Nothing to ring twice: the selection ring already marks the chosen one.
	var selected: Dictionary = hud.inspector.subject() if hud.inspector != null else {}
	if subject.is_empty() or WorldStats.same(subject, selected):
		hover_marker.clear()
		return
	match int(subject["kind"]):
		WorldStats.Kind.PAWN:
			if hover_marker._pawn != subject["pawn"]:
				hover_marker.follow_pawn(subject["pawn"])
		WorldStats.Kind.BUILDING:
			frame_placement(hover_marker, subject["index"])
		_:
			hover_marker.clear()


## Only over the world, with nothing else going on: not over a panel, not in
## build mode (which has its own hover), not while the camera is being dragged,
## and not while the day summary holds the game.
func _hover_allowed() -> bool:
	if world.keeper_controls != null and world.keeper_controls.menu != null and world.keeper_controls.menu.visible:
		return false
	if world.simulation_paused or world.rig == null or not hover_enabled:
		return false
	if world.build != null and world.build.mode != BuildController.Mode.OFF:
		return false
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		return false
	# Not with the pointer outside the window: no control is "under" it there,
	# so the world used to take the screen's edge as hovered and leave a card
	# up over the top bar after the mouse had gone to another program.
	if not _pointer_inside or not _pointer_over_window():
		return false
	if world.hud.covers_point(get_viewport().get_mouse_position()):
		return false
	return get_viewport().gui_get_hovered_control() == null


## The system pointer against the window itself: the exit notification never
## comes if the pointer was outside the window from the start.
func _pointer_over_window() -> bool:
	var window: Window = get_window()
	if window == null or DisplayServer.get_name() == "headless":
		return true
	return Rect2i(window.position, window.size).has_point(DisplayServer.mouse_get_position())


var _pointer_inside: bool = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		_pointer_inside = false
	elif what == NOTIFICATION_WM_MOUSE_ENTER:
		_pointer_inside = true


## Move the selection ring to whatever the inspector now describes.
func on_inspected(subject: Dictionary) -> void:
	var rig: CameraRig = world.rig
	# Following belongs to the person being inspected. Choosing somebody else,
	# or closing the inspector, lets the view go.
	if rig != null and rig.follow != null:
		var same: bool = int(subject.get("kind", WorldStats.Kind.NONE)) == WorldStats.Kind.PAWN and subject["pawn"] == rig.follow
		if not same:
			rig.follow = null
	if selection_marker == null:
		return
	match int(subject.get("kind", WorldStats.Kind.NONE)):
		WorldStats.Kind.PAWN:
			selection_marker.follow_pawn(subject["pawn"])
		WorldStats.Kind.BUILDING:
			frame_placement(selection_marker, subject["index"])
		WorldStats.Kind.ITEMS, WorldStats.Kind.GROUND:
			selection_marker.frame_tiles([subject["tile"]], world.terrain.plot_height)
		_:
			selection_marker.clear()


func frame_placement(marker: SelectionMarker, index: int) -> void:
	var build: BuildController = world.build
	if build == null or index < 0 or index >= build.grid.placements.size() or build.grid.placements[index] == null:
		marker.clear()
		return
	var tiles: Array = build.grid.placements[index]["tiles"]
	var height: float = world.terrain.plot_height
	for t in tiles:
		height = maxf(height, world.terrain.height_at_corner(t.x, t.y))
	marker.frame_tiles(tiles, height)


## Keep the view on whoever the inspector is showing, or stop.
func toggle_follow() -> void:
	var rig: CameraRig = world.rig
	var hud = world.hud
	if rig == null or hud == null or hud.inspector == null:
		return
	var subject: Dictionary = hud.inspector.subject()
	if rig.follow != null:
		rig.follow = null
	elif int(subject.get("kind", WorldStats.Kind.NONE)) == WorldStats.Kind.PAWN and is_instance_valid(subject["pawn"]):
		rig.follow = subject["pawn"]
	else:
		hud.flash("Select someone to follow first")


## Nearest person to a world point, staff or patron, within grabbing distance.
##
## Distance is measured on the ground plane only: a pawn's origin is at its
## feet, so including height would bias every pick toward whoever is standing
## downhill.
func pawn_near(point: Vector3, radius: float = 0.75) -> Pawn:
	var best: Pawn = null
	var best_distance: float = radius * radius

	var candidates: Array = []
	candidates.append_array(world.pawns)
	if world.keeper != null and is_instance_valid(world.keeper.pawn):
		candidates.append(world.keeper.pawn)
	if world.customers != null:
		for brain in world.customers.customers:
			if is_instance_valid(brain) and is_instance_valid(brain.pawn):
				candidates.append(brain.pawn)

	for candidate in candidates:
		if not is_instance_valid(candidate):
			continue
		var delta := Vector2(candidate.position.x - point.x, candidate.position.z - point.z)
		var distance: float = delta.length_squared()
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## Shortcuts the world answers, by KeyBindings action. Camera turning is the
## rig's own, fullscreen is GameSettings', and Esc is handled above.
const _SHORTCUTS: Array[String] = ["pause", "speed_1", "speed_2", "speed_3", "speed_4",
	"cam_mode", "cam_follow", "cam_home", "rotate", "build", "demolish", "staff", "production",
	"supplies", "ledger", "land", "rooms", "cutaway", "quicksave", "screenshot", "play_keeper"]

## Shortcuts that belong to managing: pressed while playing the keeper, they
## step back out first, so the player never has to.
const _MANAGING: Array[String] = ["cam_mode", "cam_follow", "cam_home", "rotate", "build", "demolish", "land", "rooms"]


func _shortcut(action: String) -> void:
	var hud = world.hud
	if world.keeper_controls != null and world.keeper_controls.playing and _MANAGING.has(action):
		world.keeper_controls.stop()
	match action:
		"play_keeper": world.keeper_controls.toggle()
		"pause": world.sim.toggle_pause()
		"speed_1": world.sim.speed = 1
		"speed_2": world.sim.speed = 2
		"speed_3": world.sim.speed = 3
		"speed_4": world.sim.speed = 4
		"cam_mode": toggle_camera_mode()
		"cam_follow": toggle_follow()
		"cam_home":
			world.rig.follow = null
			var middle: Vector2 = Vector2(world.plot.position) + Vector2(world.plot.size) * 0.5
			world.rig.focus_on(Vector3(middle.x, world.terrain.plot_height, middle.y))
		"rotate":
			if world.build != null:
				world.build.rotate_selection()
		"build": hud._toggle_build_bar()
		"demolish": hud.toggle_demolish()
		"staff":
			if hud._priority_panel != null:
				hud._priority_panel.toggle()
		"production":
			if hud._production_panel != null:
				hud._production_panel.toggle()
		"supplies": hud.toggle_supplies()
		"ledger": hud.toggle_ledger()
		"land": hud.toggle_land()
		"rooms": world.toggle_room_overlay()
		"cutaway": hud.toggle_cutaway()
		"quicksave": hud.quick_save()
		"screenshot": hud.take_screenshot()
