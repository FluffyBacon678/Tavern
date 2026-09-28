class_name InspectorPanel
extends PanelContainer

## What is this thing, and what is it doing?
##
## A management game is unplayable without it. You can watch five identical
## figures cross a room, but until you can click one and read "Hilda Fairbrook,
## baking (40%)", you cannot tell a busy tavern from a stuck one -- and the
## whole appeal of the genre is diagnosing why the machine is misbehaving.
##
## Refreshes live rather than snapshotting: a pawn's status changes every second
## and a panel showing what it *was* doing would actively mislead.

enum Kind { NONE, PAWN, BUILDING, ITEMS, GROUND }

const REFRESH_INTERVAL: float = 0.25

## Emitted whenever what the panel describes changes, including to nothing, so
## the world can move its selection ring.
signal subject_changed(subject: Dictionary)

var world  ## TavernWorld

var kind: int = Kind.NONE
var pawn: Pawn = null
var building_index: int = -1
var tile := Vector2i(-1, -1)

var _rows: VBoxContainer
var _extras: VBoxContainer
## Which recipes could be done by hand when the buttons were last built. The
## buttons come and go with the ingredients, so a change here rebuilds them.
var _extras_key: String = ""
var _timer: float = 0.0


func setup(p_world) -> void:
	world = p_world
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 16
	offset_right = 356
	offset_top = -300
	offset_bottom = -180
	custom_minimum_size = Vector2(340, 0)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	visible = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	# The close button sits over the title's corner rather than in a row of its
	# own, which would push every figure down by a line for one glyph.
	var head := Control.new()
	head.custom_minimum_size = Vector2(0, 0)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = "Close (right-click anywhere)"
	close.flat = true
	close.add_theme_font_size_override("font_size", 18)
	close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -26
	close.offset_top = -6
	close.pressed.connect(clear)
	head.add_child(close)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	column.add_child(_rows)
	_extras = VBoxContainer.new()
	_extras.add_theme_constant_override("separation", 5)
	column.add_child(_extras)


func clear() -> void:
	var was: bool = kind != Kind.NONE
	kind = Kind.NONE
	pawn = null
	building_index = -1
	tile = Vector2i(-1, -1)
	visible = false
	if was:
		subject_changed.emit({})


func show_pawn(p: Pawn) -> void:
	_set_subject({"kind": WorldStats.Kind.PAWN, "pawn": p})


func show_building(index: int) -> void:
	_set_subject({"kind": WorldStats.Kind.BUILDING, "index": index})


## Whatever WorldStats.subject_at found.
func show_subject(wanted: Dictionary) -> void:
	if int(wanted.get("kind", WorldStats.Kind.NONE)) == WorldStats.Kind.NONE:
		clear()
		return
	_set_subject(wanted)


## What the panel is describing, in WorldStats' terms. Empty when closed.
func subject() -> Dictionary:
	match kind:
		Kind.PAWN:
			return {"kind": WorldStats.Kind.PAWN, "pawn": pawn}
		Kind.BUILDING:
			return {"kind": WorldStats.Kind.BUILDING, "index": building_index}
		Kind.ITEMS:
			return {"kind": WorldStats.Kind.ITEMS, "tile": tile}
		Kind.GROUND:
			return {"kind": WorldStats.Kind.GROUND, "tile": tile}
	return {}


func _on_pawn_leaving(leaving: Pawn) -> void:
	if kind == Kind.PAWN and pawn == leaving:
		clear()


func _set_subject(wanted: Dictionary) -> void:
	kind = Kind.NONE
	pawn = null
	building_index = -1
	tile = Vector2i(-1, -1)
	match int(wanted["kind"]):
		WorldStats.Kind.PAWN:
			kind = Kind.PAWN
			pawn = wanted["pawn"]
			# Closed the moment they leave, not at the next refresh: at speed a
			# quarter of a second is long enough to show somebody already gone.
			if is_instance_valid(pawn) and not pawn.tree_exiting.is_connected(_on_pawn_leaving):
				pawn.tree_exiting.connect(_on_pawn_leaving.bind(pawn), CONNECT_ONE_SHOT)
		WorldStats.Kind.BUILDING:
			kind = Kind.BUILDING
			building_index = wanted["index"]
		WorldStats.Kind.ITEMS:
			kind = Kind.ITEMS
			tile = wanted["tile"]
		WorldStats.Kind.GROUND:
			kind = Kind.GROUND
			tile = wanted["tile"]
	_present()
	subject_changed.emit(subject())


func _present() -> void:
	theme = TavernTheme.build(TavernTheme.scale_for_control(self) * 0.8)
	visible = true
	_timer = 0.0
	refresh()
	_rebuild_extras()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_INTERVAL
	refresh()


## The figures, every quarter second. The interactive parts below them are
## rebuilt only when the subject changes: a checkbox recreated four times a
## second cannot be clicked.
func refresh() -> void:
	if not visible or _rows == null:
		return
	var rows: Array = WorldStats.rows_for(world, subject())
	if rows.is_empty():
		clear()
		return
	StatRows.render(_rows, rows, false, custom_minimum_size.x - 32.0 - StatRows.LABEL_WIDTH - 8.0)
	reset_size()
	if kind == Kind.BUILDING and _performable_key() != _extras_key:
		_rebuild_extras()


func _performable_key() -> String:
	if world == null or building_index < 0 or building_index >= world.build.grid.placements.size():
		return ""
	var entry = world.build.grid.placements[building_index]
	if entry == null or not entry["built"]:
		return "unbuilt"
	var key: String = ""
	for recipe in RecipeCatalog.for_station(entry["def"].id):
		key += "1" if world.generator.can_perform(building_index, recipe) else "0"
	return key


func _rebuild_extras() -> void:
	_extras_key = _performable_key() if kind == Kind.BUILDING else ""
	for child in _extras.get_children():
		_extras.remove_child(child)
		child.queue_free()
	match kind:
		Kind.PAWN:
			_extras.add_child(_follow_button())
			if is_instance_valid(pawn) and pawn.get_node_or_null("Worker") != null:
				var staff := Button.new()
				staff.text = "Change what they work on" + KeyBindings.tag("staff")
				staff.pressed.connect(func() -> void:
					if world.hud != null and world.hud._priority_panel != null:
						world.hud._priority_panel.toggle()
				)
				_extras.add_child(staff)
		Kind.BUILDING:
			_building_extras()


## Follow [F]: keep the view on this person. Its label says which state it is
## in, and flips back by itself when a pan hands the camera to the player.
func _follow_button() -> Button:
	var b := Button.new()
	b.toggle_mode = true
	var rig: CameraRig = world.rig if world != null else null
	var refresh_label := func(target: Node3D) -> void:
		if not is_instance_valid(b):
			return
		var on: bool = target != null and target == pawn
		b.set_pressed_no_signal(on)
		b.text = "Following [F]" if on else "Follow [F]"
	refresh_label.call(rig.follow if rig != null else null)
	b.pressed.connect(func() -> void:
		if world != null:
			world.input.toggle_follow()
	)
	if rig != null:
		rig.follow_changed.connect(refresh_label)
		b.tree_exiting.connect(func() -> void:
			if rig.follow_changed.is_connected(refresh_label):
				rig.follow_changed.disconnect(refresh_label)
		)
	return b


func _building_extras() -> void:
	if world == null or building_index < 0 or building_index >= world.build.grid.placements.size():
		return
	var entry = world.build.grid.placements[building_index]
	if entry == null or not entry["built"]:
		return
	var def: BuildingDef = entry["def"]
	for recipe in RecipeCatalog.for_station(def.id):
		# Offered only when the ingredients are actually on the bench, so the
		# button never opens onto a kitchen that cannot do the work.
		if world.generator.can_perform(building_index, recipe):
			_extras.add_child(_do_it_button(recipe))
	if def.is_storage:
		_present_filter(entry)


## The storage filter from design notes section 11.
##
## Ticking boxes is the whole feature: there is no pantry type and no cellar
## type, there is a shelf with some boxes ticked. Nothing downstream knows the
## difference either -- the hauling rule already asks `items.accepts()` before
## choosing a destination, so a dedicated shelf simply stops being an answer for
## everything else, with no change to the job generator at all.
func _present_filter(entry: Dictionary) -> void:
	var filter: Dictionary = entry.get("filter", {})
	_extras.add_child(_subtitle("Choose what it holds" if filter.is_empty() else "Holds only what is ticked"))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	_extras.add_child(grid)

	var index: int = building_index
	for item in ItemCatalog.all():
		var box := CheckBox.new()
		box.text = item.display_name
		box.button_pressed = filter.has(item.id)
		box.add_theme_font_size_override("font_size", 12)
		var id: StringName = item.id
		box.toggled.connect(func(_on: bool) -> void:
			world.build.grid.toggle_filter(index, id)
			_rebuild_extras()
			refresh()
		)
		grid.add_child(box)

	if not filter.is_empty():
		var reset := Button.new()
		reset.text = "Accept anything"
		reset.pressed.connect(func() -> void:
			world.build.grid.set_filter(index, [])
			_rebuild_extras()
			refresh()
		)
		_extras.add_child(reset)


## The hands-on button. Section 22's promise in one control: step in during the
## rush, do it better than the staff, get straight back to managing.
func _do_it_button(recipe: Recipe) -> Button:
	var b := Button.new()
	b.text = "Do it yourself"
	b.tooltip_text = "Work the %s by hand. Faster than a cook, and better if you are any good." % recipe.display_name.to_lower()
	var index: int = building_index
	b.pressed.connect(func() -> void:
		if world.hud != null:
			world.hud.open_hands_on(index, recipe)
	)
	return b


# --- small builders ------------------------------------------------------

func _subtitle(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", TavernTheme.CANDLE_DIM)
	l.add_theme_font_size_override("font_size", 11)
	return l
