extends Control

## The title screen: a picture of the tavern, the menu down the left, and the
## chosen page -- a new game, your saved taverns, the credits -- on the right.
##
## Built in code, like the rest of the UI, from UiKit's pieces, so it looks and
## behaves like the pause menu and the settings: pointing focuses, Enter does
## what is lit, Esc backs out one level.
##
## Slot rules carried over from the old menu, each of which was a real bug:
##   * Continue and Load go through GameState.request_continue(), which says
##     "load this". Setting the slot alone started a fresh tavern over the save.
##   * A new tavern is written only to the slot the player chose, and a refusal
##     is shown, not swallowed.
##   * A slot holding a file this build cannot read is shown as such, never as
##     empty, and can be cleared.

const WORLD_SCENE := "res://src/world/world3d/world_3d.tscn"
const BACKDROP := "res://assets/final/ui/title_backdrop.png"

const GAME_TITLE := "MOBILE TAVERN"
const GAME_SUBTITLE := "a medieval tavern simulation"
## Shown in the corner, so screenshots and bug reports say which build. From
## the project settings (application/config/version), so it cannot go stale
## the way a typed "demo build 0.9" did, three feature rounds after 0.9.
static func build_label() -> String:
	return "build %s" % String(ProjectSettings.get_setting("application/config/version", "dev"))

enum Page { NONE, NEW, LOAD, CREDITS }

var _s: float = 1.0
var _page: int = Page.NONE
var _backdrop: TextureRect
var _menu: VBoxContainer
var _menu_title: Label
var _menu_margin: MarginContainer
var _page_panel: PanelContainer
var _buttons: Array[Button] = []
var _page_buttons: Dictionary = {}

# New game
## "tutorial", "demo" or "sandbox". The tutorial first: it is where a new
## player should start, and it teaches everything the other two assume.
var _scenario: String = "tutorial"
var _name_field: LineEdit
var _seed_field: LineEdit
var _chosen_slot: int = 0
var _new_warning: Label
## New-game choices survive rebuilding the page and opening the creator.
var _draft_tavern_name: String = ""
var _draft_seed: String = ""
var _character_creator: CharacterCreator


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_rebuild)
	GameSettings.changed.connect(_rebuild)
	_rebuild()
	if not GameState.load_error.is_empty():
		var reason: String = GameState.load_error
		GameState.load_error = ""
		ModalDialog.ask(self, "Could not resume tavern", reason + " Your save files have been kept.", [["close", "Close", "primary"]])


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_remember_new_fields()
	for child in get_children():
		if child != _character_creator:
			child.queue_free()
	_buttons.clear()
	_page_buttons.clear()
	_s = TavernTheme.scale_for_control(self)
	theme = TavernTheme.build(_s)
	_build_backdrop()
	_build_menu()
	_build_footer()
	_page_panel = null
	if _page != Page.NONE:
		_open_page(_page, false)
	else:
		_focus_first.call_deferred()
	if is_instance_valid(_character_creator):
		move_child(_character_creator, get_child_count() - 1)


# --- backdrop -------------------------------------------------------------------

## The tavern itself, rendered from the game, drifting slowly -- shifted right so
## the building sits beside the menu rather than under it.
func _build_backdrop() -> void:
	var night := ColorRect.new()
	night.color = TavernTheme.NIGHT
	night.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(night)

	_backdrop = TextureRect.new()
	_backdrop.texture = load(BACKDROP) if ResourceLoader.exists(BACKDROP) else null
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	var view: Vector2 = get_viewport_rect().size
	_backdrop.pivot_offset = view * 0.5
	# Scaled about the middle, a picture s times the screen overhangs each side
	# by (s - 1) / 2; the shift right must stay inside that, or the left edge
	# shows. 1.24 allows 12%; the drift keeps within it at both ends.
	_backdrop.position = Vector2(view.x * 0.10, 0.0)
	_backdrop.scale = Vector2.ONE * 1.24
	if GameSettings.animated_background:
		# Resizing rebuilds this texture. Bind its looping animation to the
		# texture itself so deleting it also stops the old loop.
		var drift: Tween = _backdrop.create_tween().set_loops()
		drift.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		drift.tween_property(_backdrop, "scale", Vector2.ONE * 1.32, 26.0)
		drift.parallel().tween_property(_backdrop, "position", Vector2(view.x * 0.13, -view.y * 0.03), 26.0)
		drift.tween_property(_backdrop, "scale", Vector2.ONE * 1.24, 26.0)
		drift.parallel().tween_property(_backdrop, "position", Vector2(view.x * 0.10, 0.0), 26.0)

	# Dark on the left where the menu is, clear on the right where the tavern is.
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.03, 0.03, 0.02, 0.92))
	gradient.set_color(1, Color(0.03, 0.03, 0.02, 0.0))
	gradient.add_point(0.42, Color(0.03, 0.03, 0.02, 0.72))
	var ramp := GradientTexture2D.new()
	ramp.gradient = gradient
	ramp.width = 256
	ramp.height = 4
	shade.texture = ramp
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = view.x * 0.75
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)


# --- the menu -------------------------------------------------------------------

func _build_menu() -> void:
	var margin := MarginContainer.new()
	_menu_margin = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	margin.offset_right = 520.0 * _s
	margin.add_theme_constant_override("margin_left", int(72.0 * _s))
	margin.add_theme_constant_override("margin_top", int(84.0 * _s))
	margin.add_theme_constant_override("margin_bottom", int(64.0 * _s))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(4.0 * _s))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var title := UiKit.heading(GAME_TITLE, _s, 64.0, TavernTheme.PARCHMENT)
	_menu_title = title
	title.clip_text = true
	title.add_theme_color_override("font_outline_color", TavernTheme.INK)
	title.add_theme_constant_override("outline_size", int(6.0 * _s))
	column.add_child(title)
	var subtitle := UiKit.heading(GAME_SUBTITLE, _s, 20.0, TavernTheme.CANDLE)
	column.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size.y = 44.0 * _s
	column.add_child(gap)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", int(2.0 * _s))
	column.add_child(_menu)

	var recent: int = GameState.most_recent_slot()
	if recent >= 0:
		var summary: Dictionary = GameState.slot_summary(recent)
		_add_entry("Continue", _on_continue)
		var about := UiKit.caption("%s  ·  day %d  ·  %s" % [String(summary.get("tavern_name", "Unnamed")),
			int(summary.get("day", 1)), UiKit.ago(int(summary.get("saved_at", 0)))], _s, 14.0)
		if summary.get("backup_recovered", false):
			about.text += "\nPrevious backup available; latest save unreadable."
		about.add_theme_color_override("font_color", TavernTheme.CANDLE_DIM)
		var indent := MarginContainer.new()
		indent.add_theme_constant_override("margin_left", int(24.0 * _s))
		indent.add_theme_constant_override("margin_bottom", int(8.0 * _s))
		indent.add_child(about)
		_menu.add_child(indent)
	_page_buttons[Page.NEW] = _add_entry("New game", func() -> void: _open_page(Page.NEW))
	var load: Button = _add_entry("Load game", func() -> void: _open_page(Page.LOAD))
	load.disabled = not GameState.has_any_slot_data()
	_page_buttons[Page.LOAD] = load
	_add_entry("Settings", _on_settings)
	_page_buttons[Page.CREDITS] = _add_entry("Credits", func() -> void: _open_page(Page.CREDITS))
	_add_entry("Quit", _on_quit)


func _add_entry(text: String, handler: Callable) -> Button:
	var b: Button = UiKit.menu_button(text, _s)
	b.custom_minimum_size.x = 340.0 * _s
	b.pressed.connect(handler)
	_menu.add_child(b)
	_buttons.append(b)
	return b


func _build_footer() -> void:
	var version := UiKit.caption(build_label(), _s, 13.0)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	version.offset_left = 72.0 * _s
	version.offset_top = -40.0 * _s
	version.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(version)
	var hint := UiKit.caption("Enter  select   ·   Esc  back   ·   F11  fullscreen", _s, 13.0)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	# Over the picture, not a panel: outlined so it reads on light grass.
	for label in [hint, version]:
		label.add_theme_color_override("font_color", TavernTheme.PARCHMENT)
		label.add_theme_color_override("font_outline_color", TavernTheme.INK)
		label.add_theme_constant_override("outline_size", int(5.0 * _s))
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.offset_right = -40.0 * _s
	hint.offset_top = -40.0 * _s
	add_child(hint)


func _focus_first() -> void:
	for b in _buttons:
		if is_instance_valid(b) and not b.disabled:
			b.grab_focus()
			return


# --- pages ----------------------------------------------------------------------

func _open_page(page: int, sound: bool = true) -> void:
	_remember_new_fields()
	if is_instance_valid(_page_panel):
		_page_panel.queue_free()
	_page = page
	_menu_margin.offset_right = 520.0 * _s
	# Keep the brand inside the left column while the right page is open.
	# Its natural width otherwise stretches the saved-game description beneath
	# the page, especially with long tavern names at 4:3.
	_menu_title.add_theme_font_size_override("font_size", int(round((64.0 if page == Page.NONE else 44.0) * _s)))
	for key in _page_buttons:
		var b: Button = _page_buttons[key]
		b.add_theme_color_override("font_color", TavernTheme.CANDLE if key == page else TavernTheme.PARCHMENT)
	if page == Page.NONE:
		return
	if sound:
		AudioDirector.play("ui_click")
	_page_panel = PanelContainer.new()
	_page_panel.add_theme_stylebox_override("panel", UiKit.panel_style(_s, 0.95))
	var view: Vector2 = get_viewport_rect().size
	var width: float = minf(560.0 * _s, view.x - 560.0 * _s)
	width = maxf(width, 380.0 * _s)
	_menu_margin.offset_right = minf(520.0 * _s, view.x - width - 88.0 * _s)
	_page_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_page_panel.offset_left = -width - 64.0 * _s
	_page_panel.offset_right = -64.0 * _s
	_page_panel.offset_top = 84.0 * _s
	_page_panel.offset_bottom = -84.0 * _s
	add_child(_page_panel)
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", int(12.0 * _s))
	_page_panel.add_child(frame)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", int(10.0 * _s))
	scroll.add_child(body)
	# The page's buttons stay put below whatever scrolls.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", int(10.0 * _s))
	frame.add_child(footer)
	match page:
		Page.NEW:
			if sound:
				# Opened afresh: the first free slot, not whatever was picked last.
				_chosen_slot = _first_free_slot()
			_page_new_game(body, footer)
		Page.LOAD:
			_page_load(body, footer)
		Page.CREDITS:
			_page_credits(body, footer)
	# Slide in from the right: a quick, small movement reads as responsive.
	_page_panel.modulate.a = 0.0
	var slide: Tween = _page_panel.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var rest: float = _page_panel.offset_left
	_page_panel.offset_left = rest + 40.0 * _s
	slide.tween_property(_page_panel, "offset_left", rest, 0.18)
	slide.parallel().tween_property(_page_panel, "modulate:a", 1.0, 0.18)


func _close_page() -> void:
	AudioDirector.play("ui_back")
	var was: int = _page
	_open_page(Page.NONE)
	if _page_buttons.has(was):
		_page_buttons[was].grab_focus()
	else:
		_focus_first()


## Two ways to start: the designed scenario, or an empty plot. Then a name, a
## seed for a sandbox, and which slot to write -- replacing a saved tavern only
## when that is plainly what was chosen.
func _page_new_game(body: VBoxContainer, footer: HBoxContainer) -> void:
	body.add_child(UiKit.heading("New game", _s, 28.0))
	var level: LevelDef = LevelCatalog.all()[0] if not LevelCatalog.all().is_empty() else null
	var options: Array = []
	if LevelCatalog.tutorial() != null:
		options.append(["tutorial", "Tutorial", "Every part of the game, one step at a time: building, the kitchen, staff, service and money. About an hour; time waits while you learn."])
	if level != null:
		options.append(["demo", level.display_name, "%s %s" % [level.briefing, level.goal_text + "."]])
	options.append(["sandbox", "Sandbox", "A big finished tavern with one of everything, every position on the staff and %dg, for trying it all out. No goal but your own." % TestHouse.GOLD])
	var ids: Array = options.map(func(o) -> String: return String(o[0]))
	if not ids.has(_scenario):
		_scenario = String(ids[0])
	var first: Button = null
	for i in range(options.size()):
		var id: String = String(options[i][0])
		var card: Button = UiKit.menu_button(String(options[i][1]), _s * 0.9)
		card.toggle_mode = true
		card.button_pressed = id == _scenario
		card.pressed.connect(func() -> void:
			_scenario = id
			_open_page(Page.NEW, false)
		)
		body.add_child(card)
		if first == null:
			first = card
		if id == _scenario:
			var about := UiKit.caption(String(options[i][2]), _s, 14.0)
			var indent := MarginContainer.new()
			indent.add_theme_constant_override("margin_left", int(24.0 * _s))
			indent.add_child(about)
			body.add_child(indent)

	body.add_child(UiKit.rule(_s))
	if _scenario == "sandbox":
		body.add_child(UiKit.caption("Tavern name", _s, 14.0))
		# A different name offered for each new tavern, and another on request.
		if _draft_tavern_name.is_empty():
			_draft_tavern_name = TavernNames.pick(TavernNames.in_saves())
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", int(8.0 * _s))
		body.add_child(name_row)
		_name_field = LineEdit.new()
		_name_field.text = _draft_tavern_name
		_name_field.placeholder_text = "Name your tavern"
		_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name_field.text_changed.connect(func(value: String) -> void: _draft_tavern_name = value)
		_name_field.text_submitted.connect(func(_t: String) -> void: _on_start())
		name_row.add_child(_name_field)
		var another: Button = UiKit.button("Another name", _s)
		another.tooltip_text = "Suggest a different name"
		another.pressed.connect(func() -> void:
			var taken: Array = TavernNames.in_saves()
			taken.append(_name_field.text)
			_draft_tavern_name = TavernNames.pick(taken)
			_name_field.text = _draft_tavern_name
		)
		name_row.add_child(another)
		body.add_child(UiKit.caption("World seed", _s, 14.0))
		_seed_field = LineEdit.new()
		_seed_field.text = _draft_seed
		_seed_field.placeholder_text = "Blank for a random forest; any word or number"
		_seed_field.text_changed.connect(func(value: String) -> void: _draft_seed = value)
		_seed_field.text_submitted.connect(func(_t: String) -> void: _on_start())
		body.add_child(_seed_field)

	body.add_child(UiKit.caption("Save slot", _s, 14.0))
	if not _slot_is_choice(_chosen_slot):
		_chosen_slot = _first_free_slot()
	for slot in range(GameState.MAX_SLOTS):
		var summary: Dictionary = GameState.slot_summary(slot)
		var text: String
		if summary.is_empty():
			text = "Slot %d  ·  %s" % [slot + 1, "unreadable, will be replaced" if GameState.has_slot_data(slot) else "empty"]
		else:
			text = "Slot %d  ·  replaces %s, day %d" % [slot + 1, String(summary.get("tavern_name", "Unnamed")),
				int(summary.get("day", 1))]
		var pick := CheckBox.new()
		pick.text = text
		pick.button_pressed = slot == _chosen_slot
		pick.focus_mode = Control.FOCUS_ALL
		if not summary.is_empty():
			pick.add_theme_color_override("font_color", TavernTheme.DANGER.lightened(0.2))
		var chosen: int = slot
		pick.pressed.connect(func() -> void:
			_chosen_slot = chosen
			_open_page(Page.NEW, false)
		)
		UiKit.wire(pick)
		body.add_child(pick)
	_new_warning = UiKit.caption("", _s, 14.0)
	_new_warning.add_theme_color_override("font_color", TavernTheme.DANGER)
	_new_warning.visible = false
	body.add_child(_new_warning)

	var back: Button = UiKit.button("Back", _s)
	back.pressed.connect(_close_page)
	footer.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var start: Button = UiKit.button("Create character", _s, true)
	start.pressed.connect(_on_start)
	footer.add_child(start)
	if is_instance_valid(_character_creator):
		return
	if _name_field != null and _scenario == "sandbox" and is_instance_valid(_name_field):
		_name_field.call_deferred("grab_focus")
	elif first != null:
		start.call_deferred("grab_focus")


func _slot_is_choice(slot: int) -> bool:
	return slot >= 0 and slot < GameState.MAX_SLOTS


func _first_free_slot() -> int:
	for slot in range(GameState.MAX_SLOTS):
		if not GameState.has_slot_data(slot):
			return slot
	return 0


func _on_start() -> void:
	if is_instance_valid(_character_creator):
		return
	_remember_new_fields()
	var seed: int = _requested_seed()
	if _scenario == "tutorial" and LevelCatalog.tutorial() != null:
		seed = LevelCatalog.tutorial().world_seed
	elif _scenario == "demo" and not LevelCatalog.all().is_empty():
		seed = LevelCatalog.all()[0].world_seed
	_character_creator = CharacterCreator.open(self, CharacterProfile.default_owner(seed))
	_character_creator.accepted.connect(_start_with_character)
	_character_creator.cancelled.connect(func() -> void:
		_character_creator = null
		if _page_buttons.has(Page.NEW):
			_page_buttons[Page.NEW].call_deferred("grab_focus")
	)


func _requested_seed() -> int:
	var raw: String = _draft_seed.strip_edges()
	if raw.is_empty():
		return -1
	return int(raw) if raw.is_valid_int() else abs(raw.hash()) % 1_000_000


func _remember_new_fields() -> void:
	if is_instance_valid(_name_field):
		_draft_tavern_name = _name_field.text
	if is_instance_valid(_seed_field):
		_draft_seed = _seed_field.text


func _start_with_character(profile: CharacterProfile) -> void:
	_character_creator = null
	AudioDirector.play("ui_start")
	var started: bool = false
	var chosen_level: LevelDef = null
	if _scenario == "tutorial":
		chosen_level = LevelCatalog.tutorial()
	elif _scenario == "demo" and not LevelCatalog.all().is_empty():
		chosen_level = LevelCatalog.all()[0]
	if chosen_level != null:
		GameState.pending_level = chosen_level.id
		started = GameState.start_new_run(chosen_level.tavern_name, chosen_level.world_seed, _chosen_slot, true)
		if not started:
			GameState.pending_level = &""
	else:
		GameState.full_house_start = true
		started = GameState.start_new_run(_draft_tavern_name, _requested_seed(), _chosen_slot, true)
	if not started:
		_new_warning.text = "That slot could not be opened. Pick another."
		_new_warning.visible = true
		return
	profile.person_id = "owner_%s" % str(GameState.world_seed)
	GameState.owner_profile = profile
	GameState.start_paused = true
	SceneRouter.change_scene(WORLD_SCENE)


## Every slot: what is in it, when it was saved, and Load or Delete.
func _page_load(body: VBoxContainer, footer: HBoxContainer) -> void:
	body.add_child(UiKit.heading("Load game", _s, 28.0))
	var focus: Button = null
	for slot in range(GameState.MAX_SLOTS):
		var summary: Dictionary = GameState.slot_summary(slot)
		var card := PanelContainer.new()
		var box: StyleBoxFlat = UiKit.panel_style(_s * 0.6, 0.6)
		box.shadow_size = 0
		card.add_theme_stylebox_override("panel", box)
		body.add_child(card)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", int(8.0 * _s))
		card.add_child(content)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(info)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(10.0 * _s))
		content.add_child(row)
		if summary.is_empty():
			var stale: bool = GameState.has_slot_data(slot)
			info.add_child(UiKit.heading("Slot %d" % (slot + 1), _s, 17.0, TavernTheme.PARCHMENT_DIM))
			info.add_child(UiKit.caption("Unreadable — damaged or unsupported save" if stale else "Empty", _s, 14.0))
			if stale:
				row.add_child(_delete_button(slot, "an unreadable save"))
			continue
		var name: String = String(summary.get("tavern_name", "Unnamed"))
		var title: Label = UiKit.heading(name, _s, 19.0, TavernTheme.PARCHMENT)
		title.clip_text = true
		title.tooltip_text = name
		info.add_child(title)
		var kind: String = SaveSlotDetails.kind(summary)
		info.add_child(UiKit.caption("Day %d  ·  %dg  ·  %s  ·  slot %d  ·  saved %s" % [
			int(summary.get("day", 1)), int(summary.get("gold", 0)), kind, slot + 1,
			UiKit.ago(int(summary.get("saved_at", 0)))], _s, 13.0))
		info.add_child(UiKit.caption(SaveSlotDetails.contents(summary), _s, 13.0))
		var recovered: bool = summary.get("backup_recovered", false)
		if recovered:
			info.add_child(UiKit.caption("Latest save unreadable. This is your previous backup.", _s, 13.0))
		var open: Button = UiKit.button("Load backup" if recovered else "Load", _s, true)
		var chosen: int = slot
		open.pressed.connect(func() -> void:
			AudioDirector.play("ui_start")
			# Through request_continue, which says "load this" -- setting the
			# slot alone started a fresh tavern in it.
			if GameState.request_continue(chosen):
				SceneRouter.change_scene(WORLD_SCENE)
		)
		row.add_child(open)
		row.add_child(_delete_button(slot, name))
		if focus == null:
			focus = open
	var back: Button = UiKit.button("Back", _s)
	back.pressed.connect(_close_page)
	footer.add_child(back)
	(focus if focus != null else back).call_deferred("grab_focus")


## Deleting cannot be undone, so it asks, naming what goes.
func _delete_button(slot: int, what: String) -> Button:
	var remove: Button = UiKit.button("Delete", _s, false, true)
	remove.pressed.connect(func() -> void:
		var dialog := ModalDialog.ask(self, "Delete %s?" % what,
			"Slot %d will be emptied. This cannot be undone." % (slot + 1),
			[["delete", "Delete", "danger"], ["cancel", "Keep it", ""]])
		if await dialog.chosen == "delete":
			GameState.delete_slot(slot)
			_rebuild()
			_open_page(Page.LOAD, false)
	)
	return remove


func _page_credits(body: VBoxContainer, footer: HBoxContainer) -> void:
	body.add_child(UiKit.heading("Credits", _s, 28.0))
	var lines: Array = [
		["Mobile Tavern", "Version %s. Made with Godot 4." % String(ProjectSettings.get_setting("application/config/version", "dev"))],
		["Icons", "Beer stein by Lorc; Bread and Coins by Delapouite. game-icons.net, CC BY 3.0."],
		["Forest", "Terrain and forest generation after ForestFirewallpaper, MIT licence."],
		["Art", "Characters, buildings and goods are original procedural models. No RuneScape or Jagex assets are used, and no endorsement is implied."],
	]
	for line in lines:
		body.add_child(UiKit.heading(String(line[0]), _s, 17.0, TavernTheme.CANDLE))
		var text := UiKit.caption(String(line[1]), _s, 14.0)
		text.add_theme_color_override("font_color", TavernTheme.PARCHMENT)
		body.add_child(text)
	var back: Button = UiKit.button("Back", _s)
	back.pressed.connect(_close_page)
	footer.add_child(back)
	back.call_deferred("grab_focus")


# --- actions --------------------------------------------------------------------

func _on_continue() -> void:
	var slot: int = GameState.most_recent_slot()
	if slot < 0 or not GameState.request_continue(slot):
		return
	AudioDirector.play("ui_start")
	SceneRouter.change_scene(WORLD_SCENE)


func _on_settings() -> void:
	var screen := SettingsScreen.open(self)
	await screen.closed
	_focus_first()


func _on_quit() -> void:
	var dialog := ModalDialog.ask(self, "Quit to desktop?", "Your taverns are saved.",
		[["quit", "Quit", "primary"], ["cancel", "Cancel", ""]])
	if await dialog.chosen == "quit":
		SceneRouter.quit_game()
	else:
		_focus_first()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Back closes the open page first, and only then offers to quit -- on
	# Android this is the system back gesture.
	get_viewport().set_input_as_handled()
	if _page != Page.NONE:
		_close_page()
	else:
		_on_quit()


## Dev hook, matching the world's. The harness has no cursor, so a page that is
## normally opened by a click has to be opened directly for a capture.
func screenshot_setup(opts: Dictionary) -> void:
	if not OS.is_debug_build():
		return
	match String(opts.get("panel", "")):
		"new":
			_open_page(Page.NEW)
		"sandbox":
			_scenario = "sandbox"
			_open_page(Page.NEW)
		"load":
			_open_page(Page.LOAD, false)
		"credits":
			_open_page(Page.CREDITS, false)
		"settings":
			var screen := SettingsScreen.open(self)
			screen._show_tab(int(opts.get("tab", "0")))
		"quit":
			_on_quit()
