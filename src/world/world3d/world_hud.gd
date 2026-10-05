class_name WorldHUD
extends Node

## Owns controls and presentation; player actions delegate to the world.
var world: TavernWorld
var _hud: Control
var _stats_label: Label
var _mode_button: Button
var _build_bar: BuildBar
var _flash_label: Label
var _day_summary: DaySummary
var _hands_on: HandsOnPanel
var _production_panel: ProductionPanel
var _priority_panel: PriorityPanel
var _title_label: Label
var _clock_label: Label
var _gold_label: Label
## Today's profit so far, small beside the purse.
var _today_label: Label
var _bread_label: Label
var _beer_label: Label
var _staff_label: Label
var _reputation_label: Label
var _reputation_stars: StarRating
var _walls_button: Button
var _rooms_button: Button
var _details_panel: PanelContainer
var _land_panel: PanelContainer
## The merchant's order form, behind the Supplies button.
var _supply_panel: SupplyPanel
## Esc with nothing else open, and the Menu button.
var pause_menu: PauseMenu
## The tutorial, when this run is one.
var tutorial: TutorialDirector
var _land_rows: VBoxContainer
var _objectives_panel: ObjectivesPanel
var _goal_label: Label
## What is going wrong right now, from `Trouble`. Hidden when nothing is.
var _trouble_panel: PanelContainer
var _trouble_label: Label
var _briefing_panel: PanelContainer
## Public: the world drives selection through it.
var inspector: InspectorPanel
## Public: the world feeds it whatever the pointer rests on.
var hover: HoverCard
## The header chips, kept so their tooltips can carry live figures.
var _gold_chip: Control
## Pause and the three speeds, beside the clock; and the notice that says so.
var _speed_buttons: Array[SpeedButton] = []
var _paused_label: Label
var _bread_chip: Control
var _beer_chip: Control
## The two strips across the top. Everything below them is placed from where
## they actually end, not from a pixel count: their height changes with the
## window, with the text scale, and when the bar wraps onto a second row.
var _header: PanelContainer
var _bar: HFlowContainer
## Where the space under the header and bar begins, in canvas units.
var _below_top: float = 134.0
var _layout_queued: bool = false
var _owner_button: Button
## Step in as the keeper, or back to managing.
var _play_button: Button
var _character_creator: CharacterCreator
var _profile_previous_hold: bool = false
var _profile_previous_lock: bool = false


func _build_hud() -> void:
	# Every good's and building's picture, shot now on two sheets, so no menu
	# opens on placeholder dots.
	IconStudio.prewarm()
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.theme = TavernTheme.build(TavernTheme.scale_for_control(_hud) * HUD_SCALE)
	# Built once, the text scale kept whatever the window was when the game
	# opened: drag the window smaller and the bar ran off the edge.
	get_viewport().size_changed.connect(_apply_scale)
	# Settings > Interface size, and the hints switch, while playing.
	GameSettings.changed.connect(func() -> void:
		_apply_scale()
		refresh_stats()
	)

	var header := PanelContainer.new()
	_header = header
	_hud.add_child(header)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 12
	header.offset_right = -12
	header.offset_top = 10
	header.add_theme_stylebox_override("panel", _panel_style())
	# Stock, staff and reputation grow as the tavern grows. Flow whole chips
	# onto another line when their real widths exceed the window, just as the
	# toolbar does; the title alone may shorten, never the live status figures.
	var header_row := HFlowContainer.new()
	header_row.add_theme_constant_override("h_separation", 12)
	header_row.add_theme_constant_override("v_separation", 6)
	header.add_child(header_row)
	var crest := TextureRect.new()
	crest.texture = load("res://assets/prototype/ui/game_icons/beer-stein.svg")
	crest.custom_minimum_size = Vector2(38, 42)
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.modulate = Color("d7b568")
	crest.tooltip_text = "Beer stein: Lorc · Bread / Coins: Delapouite\ngame-icons.net · CC BY 3.0\nhttps://creativecommons.org/licenses/by/3.0/\nDisplayed in gold; original SVG geometry unchanged."
	header_row.add_child(crest)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 0)
	header_row.add_child(title_box)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	title_box.add_child(title_row)
	_title_label = Label.new()
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.clip_text = true
	_title_label.add_theme_font_size_override("font_size", 19)
	_title_label.add_theme_color_override("font_color", Color("edcf90"))
	title_row.add_child(_title_label)
	_owner_button = _hud_button("Keeper", open_owner_profile)
	_owner_button.name = "OwnerProfile"
	_owner_button.focus_mode = Control.FOCUS_ALL
	title_row.add_child(_owner_button)
	_play_button = _keyed_button("Take control", "play_keeper", func() -> void:
		if world.keeper_controls != null:
			world.keeper_controls.toggle())
	_play_button.name = "PlayKeeper"
	_play_button.set_meta("tip", "Play as your keeper: click to walk, right-click for options")
	title_row.add_child(_play_button)
	# The clock and the speed controls on one line, as in Prison Architect:
	# the question "how fast is time going" belongs beside "what time is it".
	var clock_row := HBoxContainer.new()
	clock_row.add_theme_constant_override("separation", 10)
	title_box.add_child(clock_row)
	# How much of the open day is gone, with the rushes marked.
	_day_bar = DayBar.new()
	_day_bar.custom_minimum_size = Vector2(0, 5)
	_day_bar.tooltip_text = "The trading day, 08:00 to 23:00. Lunch and evening rushes are marked."
	title_box.add_child(_day_bar)
	_clock_label = Label.new()
	_clock_label.add_theme_font_size_override("font_size", 12)
	_clock_label.add_theme_color_override("font_color", Color("bdad8a"))
	_clock_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clock_row.add_child(_clock_label)
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 2)
	clock_row.add_child(speeds)
	var hints: Array[String] = ["Pause", "Normal speed", "Fast, 2x", "Faster, 3x", "Fastest, 5x"]
	var speed_keys: Array[String] = ["pause", "speed_1", "speed_2", "speed_3", "speed_4"]
	for i in range(SimClock.SPEEDS.size()):
		var b := SpeedButton.new()
		b.speed = i
		# Tooltip and key through the same path as the other shortcut buttons.
		b.set_meta("base", "")
		b.set_meta("tip", hints[i])
		b.set_meta("action", speed_keys[i])
		b.set_meta("in_label", false)
		_keyed.append(b)
		_label_keyed(b)
		var chosen: int = i
		b.pressed.connect(func() -> void:
			AudioDirector.play("ui_click")
			world.sim.speed = chosen
			_show_speed(world.sim.speed)
		)
		speeds.add_child(b)
		_speed_buttons.append(b)
	world.sim.speed_changed.connect(_show_speed)
	_show_speed(world.sim.speed)
	_gold_label = _stock_chip(header_row, "coins", "Gold in the purse")
	_bread_label = _stock_chip(header_row, "item:bread", "Bread, including carried stock")
	_beer_label = _stock_chip(header_row, "item:beer", "Beer, including carried stock")
	_lemonade_label = _stock_chip(header_row, "item:lemonade", "Lemonade, including carried stock")
	_fish_label = _stock_chip(header_row, "item:grilled_fish", "Fish dishes: grilled fish and fish soup")
	_gold_chip = _gold_label.get_parent()
	# Today's running total sits with the purse it changes. It lived at the end
	# of the clock line, whose length then pushed the header onto a second row
	# at 1920 x 1080 every busy lunchtime.
	_today_label = Label.new()
	_today_label.add_theme_font_size_override("font_size", 12)
	_today_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gold_chip.add_child(_today_label)
	_bread_chip = _bread_label.get_parent()
	_beer_chip = _beer_label.get_parent()
	_fish_chip = _fish_label.get_parent()
	_lemonade_chip = _lemonade_label.get_parent()
	_staff_label = Label.new()
	# Takes the mouse so it can carry a tooltip: who is doing what.
	_staff_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_staff_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_staff_label.add_theme_font_size_override("font_size", 13)
	header_row.add_child(_staff_label)
	# Standing sits in the header beside the purse, because it is the other
	# number that decides tomorrow.
	_reputation_stars = StarRating.new()
	_reputation_stars.star_size = 15.0
	_reputation_stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var standing_row := HBoxContainer.new()
	standing_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_row.add_child(standing_row)
	standing_row.add_child(_reputation_stars)
	_reputation_label = Label.new()
	_reputation_label.add_theme_font_size_override("font_size", 13)
	_reputation_label.add_theme_color_override("font_color", Color("edcf90"))
	_reputation_label.mouse_filter = Control.MOUSE_FILTER_STOP
	standing_row.add_child(_reputation_label)

	# Two groups in a flow: what to do on the left, how to look on the right.
	# On a 16:9 window they share one row; on anything squarer the right-hand
	# group wraps onto a second row instead of running off the screen, which is
	# where Save and Menu used to go at 1440x900 and 1024x768.
	_bar = HFlowContainer.new()
	var bar := _bar
	_hud.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 12
	bar.offset_right = -12
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("h_separation", 4)
	bar.add_theme_constant_override("v_separation", 4)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(actions)
	actions.add_child(_keyed_button("Build", "build", _toggle_build_bar))
	# Hiring is a choice of position now, made where the staff are listed.
	var hire: Button = _hud_button("Hire", func() -> void:
		if not _priority_panel.visible:
			_priority_panel.toggle()
	)
	hire.tooltip_text = "Take somebody on: each position has a fee and a daily wage (Staff%s)" % KeyBindings.hint("staff")
	actions.add_child(hire)
	var supplies: Button = _keyed_button("Stores", "supplies", toggle_supplies, false)
	supplies.set_meta("tip", "Meal stock targets and automatic ingredient deliveries")
	actions.add_child(supplies)
	actions.add_child(_keyed_button("Staff", "staff", func() -> void: _priority_panel.toggle()))
	actions.add_child(_keyed_button("Buy land", "land", toggle_land, false))
	actions.add_child(_keyed_button("Ledger", "ledger", toggle_ledger, false))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)
	var view := HBoxContainer.new()
	view.add_theme_constant_override("separation", 4)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(view)
	# Glyphs rather than words to keep the bar inside 1280px, but drawn larger:
	# at the bar's text size the arrows came out as specks nobody could read.
	for turn in [[-1, "↶", "cam_turn_left"], [1, "↷", "cam_turn_right"]]:
		var step: int = turn[0]
		var button: Button = _keyed_button(turn[1], turn[2], func() -> void: world.rig.rotate_step(step), false)
		button.add_theme_font_size_override("font_size", 22)
		view.add_child(button)
	# Through a lambda: the HUD is built before the world's input exists.
	_mode_button = _hud_button("View: locked", func() -> void: world.input.toggle_camera_mode())
	view.add_child(_mode_button)
	_rooms_button = _keyed_button("Rooms", "rooms", func() -> void: world.toggle_room_overlay())
	_rooms_button.set_meta("tip", "Show what the game counts as a room, and what each one is worth.")
	view.add_child(_rooms_button)
	_walls_button = _keyed_button("Cutaway", "cutaway", toggle_cutaway, false)
	view.add_child(_walls_button)
	view.add_child(_keyed_button("Save", "quicksave", quick_save, false))
	var menu: Button = _hud_button("Menu", open_pause_menu)
	menu.tooltip_text = "Pause, save, settings, or leave (Esc)"
	view.add_child(menu)
	header.resized.connect(_queue_layout)
	bar.resized.connect(_queue_layout)

	# Buying land: four sides, each with a price and a reason it cannot be had.
	_land_panel = PanelContainer.new()
	_hud.add_child(_land_panel)
	_land_panel.position = Vector2(12, 134)
	_land_panel.custom_minimum_size = Vector2(300, 0)
	_land_panel.add_theme_stylebox_override("panel", _panel_style())
	_land_panel.visible = false
	_land_rows = VBoxContainer.new()
	_land_rows.add_theme_constant_override("separation", 6)
	_land_panel.add_child(_land_rows)

	_supply_panel = SupplyPanel.new()
	_supply_panel.name = "SupplyPanel"
	_hud.add_child(_supply_panel)
	_supply_panel.position = Vector2(12, 134)
	_supply_panel.add_theme_stylebox_override("panel", _panel_style())
	_supply_panel.setup(world)

	# The working ledger is available without covering the kitchen by default.
	_details_panel = PanelContainer.new()
	_hud.add_child(_details_panel)
	_details_panel.position = Vector2(12, 134)
	_details_panel.custom_minimum_size = Vector2(325, 0)
	_details_panel.add_theme_stylebox_override("panel", _panel_style())
	_details_panel.visible = false
	_stats_label = Label.new()
	_stats_label.custom_minimum_size.x = 300
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_label.add_theme_font_size_override("font_size", 13)
	_details_panel.add_child(_stats_label)

	var help := Label.new()
	_hud.add_child(help)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	help.offset_left = -520
	help.offset_right = -16
	help.offset_top = -58
	help.offset_bottom = -14
	# Grows leftwards: at a larger text scale it is wider than its box, and
	# growing the default way pushed the ends of both lines off the screen.
	help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Two lines: moving the view, then looking at things. The second is what
	# made follow and the stack counts findable at all -- neither has a button
	# of its own until something is selected.
	_help = help
	_write_help()
	GameSettings.bindings_changed.connect(_on_bindings_changed)
	help.add_theme_color_override("font_color", Color("e4d4aa"))
	help.add_theme_color_override("font_outline_color", TavernTheme.INK)
	help.add_theme_constant_override("outline_size", 4)
	help.add_theme_font_size_override("font_size", 12)

	# RimWorld's cue: a paused world should say so where the eye already is,
	# or a player who hit Space by accident waits for customers who never come.
	_paused_label = Label.new()
	_paused_label.text = "PAUSED  ·  %s to resume" % KeyBindings.first("pause")
	_paused_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_paused_label.offset_left = -160
	_paused_label.offset_right = 160
	_paused_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paused_label.add_theme_font_size_override("font_size", 18)
	_paused_label.add_theme_color_override("font_color", TavernTheme.CANDLE)
	_paused_label.add_theme_color_override("font_outline_color", TavernTheme.INK)
	_paused_label.add_theme_constant_override("outline_size", 6)
	_paused_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paused_label.visible = false
	_hud.add_child(_paused_label)

	_flash_label = Label.new()
	_hud.add_child(_flash_label)
	_flash_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_flash_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_flash_label.offset_top = -212
	_flash_label.offset_bottom = -184
	_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash_label.add_theme_color_override("font_color", Color("f4d18e"))
	_flash_label.add_theme_color_override("font_outline_color", TavernTheme.INK)
	_flash_label.add_theme_constant_override("outline_size", 5)
	_flash_label.modulate.a = 0.0

	_production_panel = ProductionPanel.new()
	_production_panel.name = "ProductionPanel"
	_hud.add_child(_production_panel)
	_production_panel.add_theme_stylebox_override("panel", _panel_style())
	_fade_in_when_shown(_production_panel)

	_priority_panel = PriorityPanel.new()
	_priority_panel.name = "PriorityPanel"
	_hud.add_child(_priority_panel)
	_priority_panel.setup(world)
	for panel in [_land_panel, _supply_panel, _details_panel, _priority_panel]:
		_fade_in_when_shown(panel)
	_objectives_panel = ObjectivesPanel.new()
	_objectives_panel.name = "ObjectivesPanel"
	_hud.add_child(_objectives_panel)
	_objectives_panel.setup(world.objectives)
	_objectives_panel.offset_top = 134

	# The level's target, under the checklist. Its own label rather than a row
	# inside the panel because it changes with every coin taken, and the panel
	# rebuilds itself wholesale.
	_goal_label = Label.new()
	_goal_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_goal_label.offset_left = -330
	_goal_label.offset_right = -16
	_goal_label.offset_top = 260
	_goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_goal_label.add_theme_font_size_override("font_size", 13)
	_goal_label.add_theme_color_override("font_color", TavernTheme.CANDLE)
	# Outlined like the flash line: it floats over grass and floorboards, and
	# candle-yellow on sunlit timber was barely there.
	_goal_label.add_theme_color_override("font_outline_color", TavernTheme.INK)
	_goal_label.add_theme_constant_override("outline_size", 4)
	_goal_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_goal_label)

	# Under the goal, on a panel of its own with a warning edge. It has to be
	# noticed without being a modal: the whole point is the problem a player has
	# not spotted, and a tavern quietly earning nothing does not look alarming.
	_trouble_panel = PanelContainer.new()
	_trouble_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_trouble_panel.offset_left = -330
	_trouble_panel.offset_right = -16
	_trouble_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trouble_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var trouble_style: StyleBoxFlat = _panel_style()
	trouble_style.border_color = TavernTheme.DANGER
	trouble_style.border_width_left = 5
	trouble_style.content_margin_top = 8
	trouble_style.content_margin_bottom = 8
	_trouble_panel.add_theme_stylebox_override("panel", trouble_style)
	_trouble_label = Label.new()
	_trouble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trouble_label.custom_minimum_size = Vector2(280, 0)
	_trouble_label.add_theme_font_size_override("font_size", 13)
	_trouble_label.add_theme_color_override("font_color", TavernTheme.PARCHMENT)
	_trouble_panel.add_child(_trouble_label)
	_trouble_panel.visible = false
	_hud.add_child(_trouble_panel)
	_objectives_panel.add_theme_stylebox_override("panel", _panel_style())
	_production_panel.visibility_changed.connect(func() -> void:
		if is_instance_valid(_objectives_panel):
			_objectives_panel.visible = not _production_panel.visible and not world.objectives.all_done()
		if _production_panel.visible and _build_bar != null:
			_build_bar.hide()
			if world.build != null:
				world.build.mode = BuildController.Mode.OFF
	)
	inspector = InspectorPanel.new()
	inspector.name = "Inspector"
	_hud.add_child(inspector)
	inspector.setup(world)
	inspector.add_theme_stylebox_override("panel", _panel_style())
	inspector.visibility_changed.connect(func() -> void:
		if inspector.visible:
			_details_panel.hide()
	)
	_build_bar = BuildBar.new()
	_build_bar.name = "BuildBar"
	_build_bar.visible = false
	_hud.add_child(_build_bar)
	_build_bar.visibility_changed.connect(func() -> void: help.visible = not _build_bar.visible)
	_build_bar.item_chosen.connect(func(def: BuildingDef) -> void: world.build.select(def))
	_build_bar.demolish_toggled.connect(func(on: bool) -> void:
		world.build.mode = BuildController.Mode.DEMOLISH if on else BuildController.Mode.OFF
	)
	# Doing it yourself. Added before the day summary so the reckoning still
	# draws over the top of it if a day happens to end mid-bake.
	_hands_on = HandsOnPanel.new()
	_hands_on.name = "HandsOn"
	_hands_on.finished.connect(func(_p: float) -> void: refresh_stats())
	_hud.add_child(_hands_on)

	_day_summary = DaySummary.new()
	_day_summary.name = "DaySummary"
	_day_summary.dismissed.connect(world._begin_next_day)
	_day_summary.leave_requested.connect(world._go_back)
	_hud.add_child(_day_summary)

	# Last, so it draws over every panel it might sit beside.
	hover = HoverCard.new()
	hover.name = "HoverCard"
	_hud.add_child(hover)
	hover.setup(world)
	# Over everything, day summary included.
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	_hud.add_child(pause_menu)
	pause_menu.setup(world)
	_apply_scale()
	_layout_top()


## Text scale and click targets for the window as it is now. Run on building
## and on every resize, so a window dragged to a new shape gets the same HUD a
## game opened at that shape would have.
func _apply_scale() -> void:
	if _hud == null:
		return
	var ui_scale: float = TavernTheme.scale_for_control(_hud) * HUD_SCALE
	var theme: Theme = TavernTheme.build(ui_scale)
	# Narrower padding than the menus use. Fourteen buttons share the bar, and
	# at the menus' padding they were a few units wider than a 16:9 window: the
	# old bar hid that by spilling past its own edge. Slimmer top and bottom
	# too, and a touch see-through, so the bar sits over the world rather than
	# walling it off.
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box: StyleBox = theme.get_stylebox(state, "Button")
		if box != null:
			box.content_margin_left = roundf(14.0 * ui_scale)
			box.content_margin_right = roundf(14.0 * ui_scale)
			box.content_margin_top = roundf(8.0 * ui_scale)
			box.content_margin_bottom = roundf(8.0 * ui_scale)
			if box is StyleBoxFlat and state == "normal":
				(box as StyleBoxFlat).bg_color.a = 0.88
	_hud.theme = theme
	# The speed buttons are drawn, not typed, so the theme does not size them.
	# Sized in canvas units alone they came out 19 pixels tall on a 1024-wide
	# window, under the 24 a mouse can reliably hit.
	var window: Window = _hud.get_window()
	var view: Vector2 = _hud.get_viewport_rect().size
	var render_scale: float = float(window.size.x) / view.x if window != null and view.x > 0.0 else 1.0
	var target: Vector2 = Vector2(40, 28) / maxf(render_scale, 0.01)
	for b in _speed_buttons:
		b.custom_minimum_size = Vector2(maxf(34.0, target.x), maxf(24.0, target.y))
	_queue_layout()


func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	_layout_top.call_deferred()


## Stack the bar under the header, and everything that hangs from the top of
## the screen under the bar -- from their real sizes. Hand-placed at 83 and
## 134, the bar overlapped the header by a pixel at every size and the
## checklist overlapped the bar whenever the text scale grew.
func _layout_top() -> void:
	_layout_queued = false
	if _header == null or _bar == null:
		return
	var header_bottom: float = _header.offset_top + _header.get_combined_minimum_size().y
	_bar.offset_top = header_bottom + 6.0
	_bar.offset_bottom = _bar.offset_top + _bar.get_combined_minimum_size().y
	_below_top = _bar.offset_bottom + 8.0
	if _objectives_panel != null:
		_objectives_panel.offset_top = _below_top
	if _production_panel != null:
		_production_panel.offset_top = _below_top
	for panel in [_land_panel, _details_panel, _supply_panel]:
		if panel != null:
			panel.position.y = _below_top
	if _paused_label != null:
		_paused_label.offset_top = _below_top + 6.0
		_paused_label.offset_bottom = _paused_label.offset_top
	if _briefing_panel != null:
		_briefing_panel.offset_top = _below_top + 40.0  # clear of the "PAUSED" notice
	refresh_stats()


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("29271ff0")
	style.border_color = Color("85704b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 2)
	style.anti_aliasing = true
	return style


## Panels fade in rather than pop, over about a tenth of a second.
func _fade_in_when_shown(panel: Control) -> void:
	panel.visibility_changed.connect(func() -> void:
		if not panel.visible:
			return
		panel.modulate.a = 0.0
		var tween: Tween = panel.create_tween()
		tween.tween_property(panel, "modulate:a", 1.0, 0.12)
	)


func _stock_chip(parent: Container, icon: String, hint: String) -> Label:
	var row := HBoxContainer.new()
	row.tooltip_text = hint
	row.custom_minimum_size.x = 70
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	if icon.begins_with("item:"):
		# The goods themselves, in their own colours, as on every card.
		row.add_child(IconStudio.rect(IconStudio.item(StringName(icon.trim_prefix("item:"))), 30.0))
	else:
		var picture := TextureRect.new()
		if icon.begins_with("pixel:"):
			# Drawn from the thought-bubble art.
			picture.texture = ThoughtBubble.icon(icon.trim_prefix("pixel:"))
			picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		else:
			picture.texture = load("res://assets/prototype/ui/game_icons/%s.svg" % icon)
		picture.custom_minimum_size = Vector2(22, 22)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.modulate = Color("d7b568")
		row.add_child(picture)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 17)
	row.add_child(label)
	return label


func _show_speed(speed: int) -> void:
	for b in _speed_buttons:
		b.set_pressed_no_signal(b.speed == speed)
		b.queue_redraw()
	if _paused_label != null:
		_paused_label.visible = speed == 0
		_place_paused_label()
		# Above panels opened since (the level's briefing is added late), but
		# still beneath the day summary, which is modal.
		if _paused_label.visible and _day_summary != null:
			_hud.move_child(_paused_label, _day_summary.get_index())


## A HUD button with a shortcut. `in_label` puts the key on the button itself
## ("Build [B]"); otherwise it goes in the tooltip, which keeps the bar inside
## 1280 pixels. Either way it follows a rebinding.
func _keyed_button(text: String, action: String, handler: Callable, in_label: bool = true) -> Button:
	var b: Button = _hud_button(text, handler)
	b.set_meta("base", text)
	b.set_meta("action", action)
	b.set_meta("in_label", in_label)
	_keyed.append(b)
	_label_keyed(b)
	return b


func _label_keyed(b: Button) -> void:
	var action: String = b.get_meta("action")
	var base: String = b.get_meta("base")
	if b.get_meta("in_label"):
		b.text = base + KeyBindings.tag(action)
	var tip: String = String(b.get_meta("tip", KeyBindings.label_of(action)))
	var key: String = KeyBindings.text_for(action)
	b.tooltip_text = tip + ("  (%s)" % key if not key.is_empty() else "")


func _on_bindings_changed() -> void:
	for b in _keyed:
		if is_instance_valid(b):
			_label_keyed(b)
	_write_help()
	_paused_label.text = "PAUSED  ·  %s to resume" % KeyBindings.first("pause")
	# The rooms button says "Rooms: on" while the overlay is up.
	if world.room_overlay != null and world.room_overlay.visible:
		_rooms_button.text = "Rooms: on"


## Stepped in or out as the keeper: the button says where it goes, and the
## corner says what the mouse does now.
func on_play_changed(playing: bool) -> void:
	if _play_button != null:
		_play_button.set_meta("base", "Manage" if playing else "Take control")
		_label_keyed(_play_button)
	if playing and _build_bar != null and _build_bar.visible:
		_toggle_build_bar()
	_write_help()


## The two lines of controls in the corner, from the player's own keys.
func _write_help() -> void:
	if _help == null:
		return
	if world != null and world.keeper_controls != null and world.keeper_controls.playing:
		_help.text = "click to walk or use   ·   right-click options   ·   middle-drag or arrows turn   ·   wheel zoom" + char(10) + \
			"%s manage   ·   %s pause   ·   %s-%s speed   ·   Esc close" % [
			_first("play_keeper"), _first("pause"), _first("speed_1"), _first("speed_4")]
		return
	var move: String = KeyBindings.move_keys(0)
	if move.is_empty():
		move = KeyBindings.move_keys(1)
	_help.text = "%s move   ·   wheel zoom   ·   %s / %s turn   ·   %s change view" % [
		move, _first("cam_turn_left"), _first("cam_turn_right"), _first("cam_mode")] + char(10) + \
		"click to inspect   ·   %s follow   ·   Alt stack counts   ·   %s pause   ·   %s-%s speed   ·   Esc close" % [
		_first("cam_follow"), _first("pause"), _first("speed_1"), _first("speed_4")]


func _first(id: String) -> String:
	var keys: Array = KeyBindings.keys_of(id)
	return KeyBindings.key_name(int(keys[0])) if int(keys[0]) != 0 else "-"


func toggle_supplies() -> void:
	_land_panel.visible = false
	_details_panel.visible = false
	_supply_panel.toggle()


func toggle_land() -> void:
	_land_panel.visible = not _land_panel.visible
	_supply_panel.visible = false
	_refresh_land_panel()


func toggle_ledger() -> void:
	_details_panel.visible = not _details_panel.visible
	_supply_panel.visible = false
	if _details_panel.visible and inspector != null:
		inspector.clear()


func toggle_cutaway() -> void:
	world.cutaway.enabled = not world.cutaway.enabled
	_walls_button.set_meta("base", "Cutaway" if world.cutaway.enabled else "Full walls")
	_walls_button.text = _walls_button.get_meta("base")


func quick_save() -> void:
	if GameState.active_slot < 0:
		flash("No slot to save to")
	elif world.save_now():
		flash("Saved")


## Demolish mode, from a key: opens the build bar if it is shut, and presses
## the same toggle the player would.
func toggle_demolish() -> void:
	if _build_bar == null:
		return
	if not _build_bar.visible:
		_toggle_build_bar()
	_build_bar._demolish_button.button_pressed = not _build_bar._demolish_button.button_pressed


## A picture of the screen, into the game's own folder.
func take_screenshot() -> void:
	var dir: String = "user://screenshots"
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var path: String = dir.path_join("tavern_%s.png" % stamp)
	var image: Image = get_viewport().get_texture().get_image()
	if image != null and image.save_png(path) == OK:
		flash("Screenshot saved: %s" % ProjectSettings.globalize_path(path))
		AudioDirector.play("ui_click")


## The HUD is drawn a size smaller than the menus: it shares the screen with
## the tavern, and the tavern is the thing being looked at.
const HUD_SCALE: float = 0.72


func _hud_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 32
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.pressed.connect(handler)
	b.pressed.connect(func() -> void: AudioDirector.play("ui_click"))
	return b


var _keyed: Array[Button] = []
var _fish_label: Label
var _fish_chip: Control
var _lemonade_label: Label
var _lemonade_chip: Control
var _day_bar: DayBar


## "6 staff, 2 idle  ·  11 guests, 3 waiting": the two numbers that say whether
## the house is keeping up.
func _people_line() -> String:
	var idle: int = 0
	for worker in world.workers:
		if is_instance_valid(worker) and worker.current == null:
			idle += 1
	var guests: int = 0
	var waiting: int = 0
	if world.customers != null:
		for brain in world.customers.customers:
			if not is_instance_valid(brain):
				continue
			guests += 1
			if brain.state in [CustomerBrain.State.SEEKING_SEAT, CustomerBrain.State.READY_TO_ORDER,
					CustomerBrain.State.WAITING_FOR_ORDER, CustomerBrain.State.WAITING_FOR_BILL]:
				waiting += 1
	return "%d staff%s  ·  %d guest%s%s" % [world.pawns.size(), ", %d idle" % idle if idle > 0 else "",
		guests, "" if guests == 1 else "s", ", %d waiting" % waiting if waiting > 0 else ""]
var _help: Label


func _on_camera_mode_changed(mode: int) -> void:
	_mode_button.text = "View: locked" if mode == CameraRig.Mode.LOCKED else "View: free"


## Take over a bench. Refuses quietly when the ingredients are not there, which
## is also when the inspector will not be offering the button.
func open_hands_on(placement_index: int, recipe: Recipe) -> bool:
	if _hands_on == null:
		return false
	AudioDirector.play("ui_click")
	return _hands_on.begin(world, placement_index, recipe)


## The last few verdicts, so the reasons stay readable at any time rather than
## only in the one second between days when the reckoning is up.
## The level's target, if this run has one. Sits with the objectives because it
## is the same kind of thing: something to do, checked against the world.
## Close the most recently relevant open panel. Returns false when there was
## nothing to close, so Escape can fall through to leaving the game -- which it
## used to do even with a panel open, taking the player to the main menu when
## they only meant to dismiss the inspector.
func close_top_panel() -> bool:
	if is_instance_valid(_character_creator):
		_character_creator.cancel_changes()
		return true
	# Swallowed rather than acted on: the hands-on bench has its own cancel,
	# and neither closing it nor leaving the game mid-bake should be an accident.
	if _hands_on != null and _hands_on.visible:
		return true
	for panel in [_supply_panel, _priority_panel, _production_panel, _land_panel, _details_panel]:
		if panel != null and panel.visible:
			if panel == _production_panel:
				_production_panel.toggle()
			else:
				panel.visible = false
			return true
	if inspector != null and inspector.visible:
		inspector.clear()
		return true
	if _build_bar != null and _build_bar.visible:
		_toggle_build_bar()
		return true
	return false


func _goal_line() -> String:
	if world.level == null:
		return ""
	# The goal on one line and the running tally under it. Joined with a dash
	# it wrapped wherever it happened to, and the dash ended up stranded.
	return world.level.progress_text(world).replace(" — ", "\n")


func _review_summary() -> String:
	if world.customers == null:
		return ""
	var standing: Reputation = world.customers.reputation
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Standing: %s" % standing.summary())
	if standing.reviews.is_empty():
		lines.append("Nobody has been in yet.")
		return "\n".join(lines)
	for review in standing.reviews.slice(0, 4):
		lines.append("%s %s - \"%s\"" % [review.star_text(), review.patron, review.quote])
	return "\n".join(lines)


## One row per side, saying what it costs or why it cannot be bought.
##
## Four buttons rather than a map: the plot grows as strips off its sides, so
## there is nothing to point at that a direction does not already say.
func _refresh_land_panel() -> void:
	if _land_panel == null or not _land_panel.visible:
		return
	for child in _land_rows.get_children():
		child.queue_free()

	var heading := Label.new()
	heading.text = "Your land: %d x %d" % [world.plot.size.x, world.plot.size.y]
	heading.add_theme_color_override("font_color", TavernTheme.CANDLE)
	_land_rows.add_child(heading)

	for side in [
		[TavernWorld.SIDE_NORTH, "North, towards the river"],
		[TavernWorld.SIDE_EAST, "East"],
		[TavernWorld.SIDE_SOUTH, "South, towards the road"],
		[TavernWorld.SIDE_WEST, "West"],
	]:
		var direction: int = side[0]
		var problem: String = world.parcel_problem(direction)
		var price: int = world.parcel_price(direction)
		var button := Button.new()
		button.text = "%s - %dg" % [side[1], price]
		# Shown greyed with the reason rather than hidden: "why can I not build
		# that way" is a question the player will otherwise ask the manual.
		button.disabled = problem != ""
		button.tooltip_text = problem if problem != "" else "Adds %d tiles" % [
			world.parcel(direction).size.x * world.parcel(direction).size.y
			- world.plot.size.x * world.plot.size.y
		]
		if problem != "":
			button.text = "%s - %s" % [side[1], problem]
		button.pressed.connect(func() -> void:
			if world.buy_land(direction):
				_refresh_land_panel()
		)
		_land_rows.add_child(button)


## What the player has inherited, said once.
##
## Shown on opening a level and dismissed by hand. Not a tutorial and not a
## hint: it says what the place *is*, and leaves working out what is wrong with
## it as the game.
func show_briefing(level: LevelDef) -> void:
	if level == null or level.briefing.is_empty():
		return
	if _briefing_panel != null:
		_briefing_panel.queue_free()

	_briefing_panel = PanelContainer.new()
	_briefing_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_briefing_panel.offset_left = -300
	_briefing_panel.offset_right = 300
	_briefing_panel.offset_top = _below_top + 40.0  # clear of the "PAUSED" notice
	_briefing_panel.add_theme_stylebox_override("panel", _panel_style())
	_hud.add_child(_briefing_panel)
	# Beneath the day summary, not over it. Added last, it drew on top of the
	# reckoning for any player who had not yet dismissed it at closing time.
	if _day_summary != null:
		_hud.move_child(_briefing_panel, _day_summary.get_index())

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_briefing_panel.add_child(box)

	var title := Label.new()
	title.text = level.display_name.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", TavernTheme.CANDLE)
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)

	var body := Label.new()
	body.text = level.briefing
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", TavernTheme.PARCHMENT)
	box.add_child(body)

	if not level.goal_text.is_empty():
		var goal := Label.new()
		goal.text = level.goal_text
		goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		goal.add_theme_color_override("font_color", TavernTheme.CANDLE)
		box.add_child(goal)

	var button := Button.new()
	button.text = "Right you are"
	button.pressed.connect(func() -> void:
		AudioDirector.play("ui_click")
		_briefing_panel.visible = false
	)
	box.add_child(button)
	button.call_deferred("grab_focus")


## Centred in the open view between the panels down each side. Centred on the
## screen, it sat over the corner of the wider Stores panel, close button and all.
func _place_paused_label() -> void:
	if _paused_label == null or not _paused_label.visible or _hud == null:
		return
	var width: float = _hud.size.x
	var left: float = 0.0
	for panel in [_supply_panel, _land_panel, _details_panel]:
		if panel != null and panel.visible:
			left = maxf(left, panel.position.x + panel.size.x)
	var right: float = width
	for panel in [_objectives_panel, _production_panel]:
		if is_instance_valid(panel) and panel.visible:
			right = minf(right, panel.get_global_rect().position.x - _hud.get_global_rect().position.x)
	var centre: float = width * 0.5
	if left > centre - 170.0 or right < centre + 170.0:
		centre = (left + right) * 0.5
	_paused_label.offset_left = centre - width * 0.5 - 160.0
	_paused_label.offset_right = centre - width * 0.5 + 160.0


func refresh_stats() -> void:
	if _title_label == null:
		return
	_place_paused_label()
	_title_label.text = _tavern_name()
	if _owner_button != null:
		var owner_name: String = GameState.owner_profile.name if GameState.owner_profile != null else "Your tavern keeper"
		_owner_button.tooltip_text = "%s: appearance and wardrobe" % owner_name
	_clock_label.text = _clock_summary()
	_gold_label.text = "%dg" % GameState.gold
	var running: int = world.ledger.profit()
	_today_label.text = "%s%dg today" % ["+" if running >= 0 else "", running]
	_today_label.add_theme_color_override("font_color", Color("9fcf7a") if running >= 0 else Color("e08a72"))
	_bread_label.text = str(world.stock_of(&"bread"))
	_beer_label.text = str(world.stock_of(&"beer"))
	# Fish only once the tavern has something to do with it.
	var fish: int = world.stock_of(&"grilled_fish") + world.stock_of(&"fish_soup")
	_fish_chip.visible = fish > 0 or (world.build != null and world.build.grid.count_built([&"fishing_spot"]) > 0)
	_fish_label.text = str(fish)
	# Lemonade likewise, once there is a bar to press it at.
	var lemonade: int = world.stock_of(&"lemonade")
	_lemonade_chip.visible = lemonade > 0 or (world.build != null and world.build.grid.count_built([&"bar_table"]) > 0)
	_lemonade_label.text = str(lemonade)
	_staff_label.text = _people_line()
	if _day_bar != null and world.clock != null:
		_day_bar.fraction = clampf((world.clock.hour() - DayClock.OPEN_HOUR) / (DayClock.CLOSE_HOUR - DayClock.OPEN_HOUR), 0.0, 1.0)
	# Live figures behind every number in the header. Refreshed with the header
	# itself, which is often enough for a tooltip read at a glance.
	# Only for the one under the pointer: the stock breakdowns walk every stack
	# and bench, and in a big tavern building all four, four times a second,
	# was a visible stutter for tooltips nobody was reading.
	if _gold_chip != null and world.generator != null:
		var at: Vector2 = _hud.get_global_mouse_position()
		if _gold_chip.get_global_rect().has_point(at):
			_gold_chip.tooltip_text = WorldStats.purse_breakdown(world)
		if _bread_chip.get_global_rect().has_point(at):
			_bread_chip.tooltip_text = WorldStats.stock_breakdown(world, &"bread")
		if _beer_chip.get_global_rect().has_point(at):
			_beer_chip.tooltip_text = WorldStats.stock_breakdown(world, &"beer")
		if _lemonade_chip.visible and _lemonade_chip.get_global_rect().has_point(at):
			_lemonade_chip.tooltip_text = WorldStats.stock_breakdown(world, &"lemonade")
		if _fish_chip.visible and _fish_chip.get_global_rect().has_point(at):
			_fish_chip.tooltip_text = WorldStats.stock_breakdown(world, &"grilled_fish") + "\n\n" \
				+ WorldStats.stock_breakdown(world, &"fish_soup")
		if _staff_label.get_global_rect().has_point(at):
			_staff_label.tooltip_text = WorldStats.people_breakdown(world)
	if world.customers != null:
		var standing: Reputation = world.customers.reputation
		_reputation_label.text = standing.label()
		_reputation_label.tooltip_text = "Reputation %d/100. Footfall x%.2f." % [
			int(round(standing.score)), standing.footfall_multiplier()
		]
		if _reputation_stars != null:
			_reputation_stars.stars = standing.stars()
			_reputation_stars.tooltip_text = _reputation_label.tooltip_text
	_stats_label.text = "%s\n\n%d built · %d jobs waiting · %d working\n\n%s\n\n%s\n\n%s" % [
		_stock_summary(), _built_count(), world.board.open_count(), world.board.active_count(),
		world.customers.summary() if world.customers != null else "", _worker_summary(),
		_review_summary()]
	# Settings > Tutorial hints: the checklist and the goal line, together. The
	# tutorial replaces the checklist while it runs.
	if is_instance_valid(_objectives_panel):
		var hinting: bool = GameSettings.show_hints and not (_production_panel != null and _production_panel.visible) \
			and tutorial == null
		if _objectives_panel.visible != hinting:
			_objectives_panel.visible = hinting
	if _goal_label != null:
		_goal_label.text = _goal_line() if GameSettings.show_hints else ""
		# Follows the checklist rather than sitting at a fixed offset: the panel
		# grows and shrinks as steps are ticked off, and a fixed position
		# collided with it as soon as the list got long.
		if _objectives_panel != null:
			_goal_label.offset_top = _objectives_panel.offset_top + (
				_objectives_panel.size.y + 10 if _objectives_panel.visible else 0.0)
	# The production panel takes the right-hand column, as the checklist does
	# when it steps aside for it; the goal and the warning go with it.
	var column_free: bool = _production_panel == null or not _production_panel.visible
	if _goal_label != null:
		_goal_label.visible = column_free
	if _trouble_panel != null:
		var trouble: String = Trouble.diagnose(world)
		_trouble_panel.visible = column_free and not trouble.is_empty()
		_trouble_label.text = trouble
		if _trouble_panel.visible:
			var below: float = _objectives_panel.offset_top if is_instance_valid(_objectives_panel) else _below_top
			if is_instance_valid(_objectives_panel) and _objectives_panel.visible:
				below += _objectives_panel.size.y + 10
			if _goal_label != null and not _goal_label.text.is_empty():
				below = _goal_label.offset_top + _goal_label.get_minimum_size().y + 8
			# Under the tutorial's panel, not on top of it.
			if tutorial != null and tutorial._panel != null and tutorial._panel.visible:
				below = maxf(below, tutorial._panel.offset_top + tutorial._panel.size.y + 10)
			_trouble_panel.offset_top = below
			_trouble_panel.offset_bottom = below
	if OS.is_debug_build():
		_stats_label.text += "\n\n%d fps · %d draw calls" % [Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)]


## Transient message near the cursor's side of the screen. The build bar has its
## own status line, so this only appears when the bar is closed.
var _flash_tween: Tween


## A line near the bottom of the screen that fades. `hold` for how long it stays
## before fading: warnings worth reading get longer than "Saved".
func flash(text: String, hold: float = 1.4) -> void:
	if _flash_label == null:
		return
	# The previous message's fade must not cut this one short.
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_label.text = text
	_flash_label.modulate.a = 1.0
	_flash_tween = create_tween()
	_flash_tween.tween_interval(hold)
	_flash_tween.tween_property(_flash_label, "modulate:a", 0.0, 0.6)


func _tavern_name() -> String:
	return GameState.tavern_name if not GameState.tavern_name.is_empty() else "The Wayfarer’s Rest"


func _built_count() -> int:
	return world.build.grid.live_count() if world.build != null else 0


## Day, clock and the part of the day. Where the day's profit stands is beside
## the purse, so the player can see trouble coming rather than only being told
## about it at closing time.
func _clock_summary() -> String:
	if world.clock == null:
		return ""
	return "Day %d · %s · %s" % [world.clock.day, world.clock.clock_text(), world.clock.phase_text()]


## Everything physically present, so the economy is readable while it runs.
## Zero-count kinds are omitted rather than listed as 0, which keeps the line
## short and makes new goods appearing genuinely noticeable.
func _stock_summary() -> String:
	if world.items == null:
		return ""
	# Goods in a pawn's hands still belong to the tavern, so count them. Showing
	# only what is on the ground makes stock visibly dip whenever anyone picks
	# something up, which reads as a bug even though nothing is lost.
	var carried: Dictionary = {}
	for worker in world.workers:
		var def: ItemDef = worker.carried_def()
		if def != null:
			carried[def.id] = carried.get(def.id, 0) + worker.carried_count()

	var parts: PackedStringArray = PackedStringArray()
	for def in ItemCatalog.all():
		var n: int = world.items.total_of(def.id) + carried.get(def.id, 0)
		if n > 0:
			parts.append("%s %d" % [def.display_name.split(" ")[0].to_lower(), n])
	return "stock: " + (", ".join(parts) if parts.size() > 0 else "empty")


## What each pawn is up to, so the job system is legible while it runs rather
## than only inspectable in a debugger.
func _worker_summary() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for i in range(mini(world.workers.size(), 4)):
		lines.append("%s: %s" % [world.pawns[i].pawn_name, world.workers[i].status_text()])
	# Patrons marked with a dot, so staff and customers are tellable apart in
	# the readout as well as in the world.
	if world.customers != null:
		for i in range(mini(world.customers.customers.size(), 3)):
			var brain: CustomerBrain = world.customers.customers[i]
			if is_instance_valid(brain):
				lines.append("· %s: %s" % [brain.pawn.pawn_name, brain.status_text()])
	return "\n".join(lines)


func _physics_process(_delta: float) -> void:
	if _stats_label == null or Engine.get_physics_frames() % 15 != 0:
		return
	if _production_panel != null and _production_panel.visible:
		_production_panel.refresh()
	if world.objectives != null:
		world.objectives.refresh(world)
	refresh_stats()


func _toggle_build_bar() -> void:
	if _build_bar == null:
		return
	_build_bar.visible = not _build_bar.visible
	if _build_bar.visible and _production_panel != null:
		_production_panel.hide()
	if not _build_bar.visible and world.build != null:
		world.build.mode = BuildController.Mode.OFF


func open_pause_menu() -> void:
	if pause_menu != null:
		close_top_panel()
		pause_menu.open()


func pause_menu_open() -> bool:
	return is_instance_valid(_character_creator) or (pause_menu != null and pause_menu.is_open())


## A personal profile, without making the owner a second simulation pawn.
func open_owner_profile() -> void:
	if is_instance_valid(_character_creator) or (pause_menu != null and pause_menu.is_open()):
		return
	if (_hands_on != null and _hands_on.visible) or (_day_summary != null and _day_summary.visible):
		return
	close_top_panel()
	if _build_bar != null and _build_bar.visible:
		_toggle_build_bar()
	if world.build != null:
		world.build.mode = BuildController.Mode.OFF
	_profile_previous_hold = world.sim.menu_held
	_profile_previous_lock = world.rig.locked if world.rig != null else false
	world.sim.menu_held = true
	if world.rig != null:
		world.rig.locked = true
	if hover != null:
		hover.dismiss()
	var profile: CharacterProfile = GameState.owner_profile
	if profile == null:
		profile = CharacterProfile.default_owner(GameState.world_seed)
	_character_creator = CharacterCreator.open(_hud, profile, true)
	_character_creator.accepted.connect(func(chosen: CharacterProfile) -> void:
		GameState.owner_profile = chosen
		refresh_stats()
		flash("Appearance updated. Save to keep your changes.", 2.5)
	)
	_character_creator.closed.connect(func() -> void:
		_character_creator = null
		world.sim.menu_held = _profile_previous_hold
		if world.rig != null:
			world.rig.locked = _profile_previous_lock
	)


## Before the day summary: close the working panels and leave build mode, so
## nothing half-finished sits behind the reckoning.
func close_for_summary() -> void:
	for panel in [_supply_panel, _land_panel, _details_panel, _priority_panel]:
		if panel != null:
			panel.visible = false
	if _production_panel != null and _production_panel.visible:
		_production_panel.toggle()
	if _build_bar != null and _build_bar.visible:
		_toggle_build_bar()
	if world.build != null:
		world.build.mode = BuildController.Mode.OFF


## Begin, or resume, the tutorial at `step`.
func start_tutorial(step: int = 0) -> void:
	if tutorial != null:
		tutorial.queue_free()
	tutorial = TutorialDirector.new()
	tutorial.name = "Tutorial"
	world.add_child(tutorial)
	tutorial.setup(world, step)
	refresh_stats()


## A hairline showing how far through the trading day it is, with the lunch
## and evening rushes marked, so the next busy spell is never a surprise.
class DayBar:
	extends Control
	var fraction: float = 0.0:
		set(value):
			if not is_equal_approx(value, fraction):
				fraction = value
				queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		draw_rect(Rect2(0, h * 0.25, w, h * 0.5), Color(0.1, 0.08, 0.05, 0.8))
		var span: float = DayClock.CLOSE_HOUR - DayClock.OPEN_HOUR
		for rush in [[12.0, 14.0], [18.0, 21.0]]:
			var x0: float = (rush[0] - DayClock.OPEN_HOUR) / span * w
			var x1: float = (rush[1] - DayClock.OPEN_HOUR) / span * w
			draw_rect(Rect2(x0, h * 0.25, x1 - x0, h * 0.5), Color(0.6, 0.35, 0.2, 0.55))
		draw_rect(Rect2(0, h * 0.25, w * fraction, h * 0.5), Color(0.91, 0.71, 0.35, 0.9))
		draw_rect(Rect2(w * fraction - 1.0, 0, 2.0, h), TavernTheme.PARCHMENT)
