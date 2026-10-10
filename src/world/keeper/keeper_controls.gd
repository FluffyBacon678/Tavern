class_name KeeperControls
extends Node3D

## Playing the keeper: one button (Tab) to step in and out, and the mouse moving
## them the way RuneScape does. Left-click does the first thing on offer -- walk
## there, take that, put it here -- and right-click opens "Choose option" with
## everything on offer. The camera follows them; the middle button and the
## arrow keys turn it round them. Stepping out puts the management view back
## exactly where it was.
##
## On a phone, a tap is a left-click and a long press opens the options.

## How long a finger rests before the options open.
const LONG_PRESS: float = 0.45
## How far it may wander and still be a press, in pixels.
const PRESS_SLOP: float = 14.0
## The view while playing: closer in than managing, looking down on them.
const PLAY_DISTANCE: float = 11.0
const PLAY_PITCH: float = 48.0

var world  ## TavernWorld
var playing: bool = false
var menu: KeeperMenu

var _saved_view: Dictionary = {}
var _marker: MeshInstance3D
var _marker_age: float = 0.0
var _touch_at := Vector2.ZERO
var _touch_time: float = -1.0
var _touch_index: int = -1


func setup(p_world) -> void:
	world = p_world
	name = "KeeperControls"
	_marker = MeshInstance3D.new()
	_marker.name = "WalkMarker"
	_marker.mesh = _cross_mesh()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = Color(1.0, 0.86, 0.2, 0.95)
	_marker.material_override = mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)


func toggle() -> void:
	if playing:
		stop()
	else:
		start()


## Step in as the keeper, calling them into the world the first time.
func start() -> bool:
	# spawn_keeper keeps a keeper who is there and replaces one whose body is gone.
	if not world.spawn_keeper():
		world.hud.flash("There's nowhere for your keeper to stand.")
		return false
	if playing:
		return true
	var rig: CameraRig = world.rig
	_saved_view = {"focus": rig._focus_target, "distance": rig._distance_target, "yaw": rig._yaw_target,
		"pitch": rig._pitch_target, "mode": rig.mode, "follow": rig.follow}
	playing = true
	if world.build != null:
		world.build.mode = BuildController.Mode.OFF
	world.hud.inspector.clear()
	rig.play = true
	rig.follow = world.keeper.pawn
	rig._distance_target = PLAY_DISTANCE
	rig._pitch_target = PLAY_PITCH
	world.hud.on_play_changed(true)
	return true


## Back to managing, the view as it was.
func stop() -> void:
	if not playing:
		return
	playing = false
	close_menu()
	var rig: CameraRig = world.rig
	rig.play = false
	rig.follow = _saved_view.get("follow", null) if is_instance_valid(_saved_view.get("follow", null)) else null
	if rig.follow == null:
		rig._focus_target = _saved_view.get("focus", rig._focus_target)
	rig._distance_target = _saved_view.get("distance", rig._distance_target)
	rig._yaw_target = _saved_view.get("yaw", rig._yaw_target)
	rig._pitch_target = _saved_view.get("pitch", rig._pitch_target)
	rig.set_mode(_saved_view.get("mode", rig.mode))
	world.hud.on_play_changed(false)


# --- input -------------------------------------------------------------------------

## A press while playing. Returns whether it was used.
func handle(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return _handle_touch(event)
	if not (event is InputEventMouseButton) or not event.pressed:
		return false
	# A finger's own presses are read from the touch, so a tap is one action.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return false
	if event.button_index == MOUSE_BUTTON_LEFT:
		var options: Array = options_at(event.position)
		close_menu()
		if not options.is_empty():
			_run(options[0])
		return true
	if event.button_index == MOUSE_BUTTON_RIGHT:
		open_menu(event.position)
		return true
	return false


func _handle_touch(event: InputEventScreenTouch) -> bool:
	if event.pressed:
		_touch_at = event.position
		_touch_time = 0.0
		_touch_index = event.index
		return true
	if event.index != _touch_index or _touch_time < 0.0:
		return false
	var short: bool = _touch_time < LONG_PRESS
	_touch_time = -1.0
	if short and event.position.distance_to(_touch_at) <= PRESS_SLOP:
		var options: Array = options_at(event.position)
		close_menu()
		if not options.is_empty():
			_run(options[0])
	return true


func _process(delta: float) -> void:
	if _marker.visible:
		_marker_age += delta
		var fade: float = clampf(1.0 - _marker_age / 1.2, 0.0, 1.0)
		(_marker.material_override as StandardMaterial3D).albedo_color.a = 0.95 * fade
		_marker.visible = fade > 0.0
	if _touch_time >= 0.0:
		_touch_time += delta
		if _touch_time >= LONG_PRESS:
			_touch_time = -1.0
			open_menu(_touch_at)
	# The keeper can leave the tree (a load); stop following a ghost.
	if playing and (world.keeper == null or not is_instance_valid(world.keeper.pawn)):
		stop()
	_sign_timer -= delta
	if _sign_timer <= 0.0:
		_sign_timer = 0.5
		_refresh_till_signs()


# --- where guests pay --------------------------------------------------------------

var _signs: Dictionary = {}  ## placement index -> Sprite3D
var _sign_timer: float = 0.0
static var _till_badge: ImageTexture


## HUD timber and candle-gold, readable without hovering. One cached texture.
static func _till_texture() -> ImageTexture:
	if _till_badge == null:
		var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		for y in range(48):
			for x in range(48):
				var distance: float = Vector2(x - 23.5, y - 23.5).length()
				if distance <= 23.0:
					img.set_pixel(x, y, TavernTheme.CANDLE_DIM if distance > 20.5 else TavernTheme.TIMBER)
				if distance <= 14.5:
					img.set_pixel(x, y, TavernTheme.CANDLE_DIM if distance > 12.0 else TavernTheme.CANDLE)
		# A simple stamped coin, kept bold at management size.
		for y in range(15, 32):
			for x in range(21, 26):
				img.set_pixel(x, y, TavernTheme.TIMBER)
		for y in [16, 29]:
			for x in range(18, 29):
				img.set_pixel(x, y, TavernTheme.TIMBER)
		_till_badge = ImageTexture.create_from_image(img)
	return _till_badge


## A gold coin over every till, so the player can see where guests pay.
func _refresh_till_signs() -> void:
	if world.build == null:
		return
	var wanted: Dictionary = {}
	var placements: Array = world.build.grid.placements
	for i in range(placements.size()):
		var entry = placements[i]
		if entry == null or not entry["built"] or not entry.get("till", false):
			continue
		wanted[i] = true
		var sign: Sprite3D = _signs.get(i, null)
		if sign == null:
			sign = Sprite3D.new()
			sign.name = "TillSign"
			sign.texture = _till_texture()
			sign.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sign.pixel_size = 0.011
			sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(sign)
			_signs[i] = sign
		var middle := Vector2.ZERO
		for t in entry["tiles"]:
			middle += Vector2(t) + Vector2(0.5, 0.5)
		middle /= float(entry["tiles"].size())
		sign.position = Vector3(middle.x * TerrainMeshBuilder.TILE,
			world.terrain.plot_height + maxf(entry["def"].height + 0.5, 1.70), middle.y * TerrainMeshBuilder.TILE)
	for i in _signs.keys():
		if not wanted.has(i):
			_signs[i].queue_free()
			_signs.erase(i)


func open_menu(at: Vector2) -> void:
	var options: Array = options_at(at)
	if options.is_empty():
		return
	# Made on first use and kept in the HUD from then: made up front and never
	# opened, it outlived the world and leaked at exit.
	if menu == null:
		menu = KeeperMenu.new()
		menu.name = "KeeperMenu"
		world.hud._hud.add_child(menu)
	menu.open(options, at, _run)


func close_menu() -> void:
	if menu != null and menu.get_parent() != null:
		menu.close()


func _run(option: Dictionary) -> void:
	var tile: Vector2i = option.get("tile", Vector2i(-1, -1))
	if tile.x >= 0:
		_mark(tile)
	option["run"].call()


# --- what is on offer --------------------------------------------------------------

## Everything the keeper could do with what is under `screen_pos`, the first
## being what a left-click does: {text, run, tile}.
func options_at(screen_pos: Vector2) -> Array:
	var keeper: Keeper = world.keeper
	if keeper == null or not is_instance_valid(keeper.pawn):
		return []
	var hit: Array = []
	if world.rig == null or not world.rig.ground_point_at(screen_pos, hit):
		return []
	var point: Vector3 = hit[0]
	var tile := Vector2i(int(floor(point.x / TerrainMeshBuilder.TILE)), int(floor(point.z / TerrainMeshBuilder.TILE)))
	var piece: Vector2i = _piece_under(screen_pos)
	if piece.x >= 0:
		tile = piece
	if tile.x < 0 or tile.y < 0 or tile.x >= world.grid.cols or tile.y >= world.grid.rows:
		return []
	return options_for(tile, world.input.pawn_near(point))


## The tile of the built piece the pointer is on, or (-1, -1): the ray from
## the camera tested against each piece's height, nearest first. The ground
## point alone lands behind anything tall -- the bar's awning, a shelf -- and
## picked the floor beyond it. Walls are looked through, as the cutaway does.
func _piece_under(screen_pos: Vector2) -> Vector2i:
	var cam: Camera3D = world.rig.camera
	if cam == null:
		return Vector2i(-1, -1)
	var origin: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var base: float = world.terrain.plot_height
	var t: float = 0.0
	while t < 250.0:
		var p: Vector3 = origin + dir * t
		t += 0.08
		if p.y < base - 0.2:
			break
		var at := Vector2i(int(floor(p.x / TerrainMeshBuilder.TILE)), int(floor(p.z / TerrainMeshBuilder.TILE)))
		if at.x < 0 or at.y < 0 or at.x >= world.grid.cols or at.y >= world.grid.rows:
			continue
		var index: int = world.build.grid.object_index_at(at)
		if index < 0 or world.build.grid.placements[index] == null:
			continue
		var def: BuildingDef = world.build.grid.placements[index]["def"]
		if not def.encloses and p.y <= base + def.height:
			return at
	return Vector2i(-1, -1)


## The options for one tile, and whoever is standing on it, best first: a
## left-click does the first. For someone: what they need (an order taken,
## their dish, the bill), or a look at them. For a bench: its recipes, an
## ingredient in hand first. For goods: take them. For open ground: walk.
func options_for(tile: Vector2i, person: Pawn = null) -> Array:
	var keeper: Keeper = world.keeper
	var first: Array = []
	var rest: Array = []
	var walk: Dictionary = _option("Walk here", func() -> void: keeper.walk_to(tile), tile)
	var someone: bool = person != null and is_instance_valid(person) and person != keeper.pawn
	if person != null and person == keeper.pawn:
		first.append_array(_self_options())
	if someone:
		var guest: CustomerBrain = _guest_of(person)
		if guest != null:
			first.append_array(_guest_options(guest))

	var index: int = world.build.grid.object_index_at(tile)
	var entry = world.build.grid.placements[index] if index >= 0 else null
	# Beds and floors are their own layer: a farm plot, or a floor still a blueprint.
	if entry == null:
		var floor_index: int = world.build.grid.floor_index_at(tile)
		var floor_entry = world.build.grid.placements[floor_index] if floor_index >= 0 else null
		if floor_entry != null and (not floor_entry["built"] or floor_entry["def"].id == &"farm_plot"):
			index = floor_index
			entry = floor_entry
	var goods: ItemDef = world.items.def_at(tile)
	var on_table: bool = entry != null and entry["def"].furniture_role == &"table"
	var take: Array = []
	# Counted whole: a job nobody has set out on gives way to the keeper.
	if goods != null and world.items.count_at(tile) > 0:
		if on_table and goods.category == ItemDef.Category.REFUSE:
			# A guest's own plate is theirs; the dirty dishes they left are not.
			take.append(_option("Clear the table", func() -> void: keeper.take(tile), tile, IconStudio.item(goods.id)))
		elif not on_table:
			take.append(_option("Take %s" % goods.display_name, func() -> void: keeper.take(tile), tile, IconStudio.item(goods.id)))

	if entry != null and not entry["built"]:
		# A blueprint: build it, as the porters would.
		first.append_array(_piece_jobs(index, entry))
		first.append_array(take)
		rest.append(_examine_piece(index, entry, tile))
	elif entry != null:
		first.append_array(_built_options(index, entry, tile, take))
		if on_table:
			for guest in _guests_at(tile):
				for option in _guest_options(guest):
					if not first.any(func(o: Dictionary) -> bool: return o["text"] == option["text"]):
						first.append(option)
		if entry["def"].takes_payments:
			var till: bool = bool(entry.get("till", false))
			rest.append(_option("Stop taking payments here" if till else "Take payments here",
				func() -> void: world.set_till(index, not till), tile, ThoughtBubble.icon("coin")))
		rest.append(_examine_piece(index, entry, tile))
	else:
		# Open ground, or a floor: walking comes first, unless there are goods
		# lying there, which a click picks up -- as in RuneScape.
		first.append_array(take)
		if first.is_empty():
			first.append(walk)
		if keeper.carry_def != null:
			rest.append(_option("Put %s down here" % keeper.carry_def.display_name, func() -> void: keeper.put(tile), tile,
				IconStudio.item(keeper.carry_def.id)))
	if goods != null:
		rest.append(_option("Examine %s" % goods.display_name,
			func() -> void: _examine({"kind": WorldStats.Kind.ITEMS, "tile": tile}), tile, IconStudio.item(goods.id)))
	if someone:
		var look: Dictionary = _option("Examine %s" % person.pawn_name,
			func() -> void: _examine({"kind": WorldStats.Kind.PAWN, "pawn": person}), tile, ThoughtBubble.icon("hand"))
		look.erase("tile")
		# Somebody under the pointer is what was clicked, not the chair they sit on.
		if first.is_empty():
			first.append(look)
		else:
			rest.push_front(look)
	if not first.has(walk):
		rest.append(walk)
	return first + rest


## A built piece: wash up, its recipes (the one using what is in hand first),
## putting down what is held, its jobs, then its goods.
func _built_options(index: int, entry: Dictionary, tile: Vector2i, take: Array) -> Array:
	var keeper: Keeper = world.keeper
	var def: BuildingDef = entry["def"]
	var out: Array = []
	# Dirty dishes standing in a basin can be washed up there.
	if def.id == &"sink":
		for t in entry["tiles"]:
			var in_basin: ItemDef = world.items.def_at(t)
			if in_basin != null and in_basin.category == ItemDef.Category.REFUSE:
				var basin: Vector2i = t
				out.append(_option("Wash up", func() -> void: keeper.wash(basin), basin, ThoughtBubble.icon("clean")))
				break
	var with_held: Array = []
	var recipes: Array = []
	for recipe in RecipeCatalog.for_station(def.id):
		var chosen: Recipe = recipe
		var option: Dictionary = _option("Fish (basic rod)" if not recipe.pick_from.is_empty() else recipe.display_name,
			func() -> void: keeper.work(index, chosen), tile, IconStudio.recipe(recipe))
		var uses_held: bool = keeper.carry_def != null and recipe.inputs.any(
			func(need: Dictionary) -> bool: return need["id"] == keeper.carry_def.id)
		(with_held if uses_held else recipes).append(option)
	out.append_array(with_held)
	if keeper.carry_def != null and def.furniture_role != &"table":
		out.append(_option("Put %s on %s" % [keeper.carry_def.display_name, def.display_name],
			func() -> void: keeper.put(tile), tile, IconStudio.item(keeper.carry_def.id)))
	out.append_array(recipes)
	out.append_array(_piece_jobs(index, entry))
	# On a bench its ingredients come second to what it makes; on a shelf or
	# in the yard, taking is the point.
	if recipes.is_empty() and with_held.is_empty():
		var at: int = 1 if not out.is_empty() and out[0]["text"] == "Wash up" else 0
		for i in range(take.size()):
			out.insert(at + i, take[i])
	else:
		out.append_array(take)
	return out


## The board's work at a piece that the keeper can do in person: build a
## blueprint, plant or harvest a bed, greet the guests at the host's stand.
func _piece_jobs(index: int, entry: Dictionary) -> Array:
	var keeper: Keeper = world.keeper
	var out: Array = []
	for job in world.board.jobs:
		if job.kind == WorkType.Kind.SERVE or job.kind == WorkType.Kind.BILL:
			continue
		if job.subject != index and not entry["tiles"].has(job.target):
			continue
		if not keeper.can_do(job):
			continue
		var chosen: Job = job
		var icon: Texture2D = IconStudio.building(entry["def"]) if job.kind == WorkType.Kind.CONSTRUCT \
			else ThoughtBubble.icon(ThoughtDirector.job_icon(job))
		out.append(_option(job.label, func() -> void: keeper.do_job(chosen), job.target, icon))
	return out


## What a guest needs that the keeper can give: the order taken, what they
## are waiting for brought to the table, the bill.
func _guest_options(brain: CustomerBrain) -> Array:
	var out: Array = []
	if brain.seat == Seating.NO_SEAT:
		return out
	var keeper: Keeper = world.keeper
	var name: String = brain.pawn.pawn_name
	match brain.state:
		CustomerBrain.State.READY_TO_ORDER:
			var job: Job = world.board.job_with_key("take:%d,%d" % [brain.seat.x, brain.seat.y])
			if keeper.can_do(job):
				out.append(_option("Take %s's order" % name, func() -> void: keeper.do_job(job), job.target,
					ThoughtBubble.icon("order")))
		CustomerBrain.State.WAITING_FOR_BILL:
			var job: Job = world.board.job_with_key("bill:%d,%d" % [brain.seat.x, brain.seat.y])
			if keeper.can_do(job):
				out.append(_option("Bring %s the bill" % name, func() -> void: keeper.do_job(job), job.target,
					ThoughtBubble.icon("coin")))
		CustomerBrain.State.WAITING_FOR_ORDER:
			var table: Vector2i = brain.seating.table_for(brain.seat)
			for line in brain.unserved():
				var option: Dictionary = _serve_option(table, StringName(line["id"]), int(line["count"]), name)
				if not option.is_empty():
					out.append(option)
	return out


## Bring a guest's dish or drink: from the keeper's hands, or fetched from the
## nearest stack of it. Not if a waiter is already bringing it.
func _serve_option(table: Vector2i, id: StringName, count: int, name: String) -> Dictionary:
	var keeper: Keeper = world.keeper
	var def: ItemDef = ItemCatalog.get_def(id)
	if def == null:
		return {}
	var text: String = "Serve %s to %s" % [def.display_name, name]
	if keeper.carry_def == def and keeper.carry_count > 0:
		return _option(text, func() -> void: keeper.serve(table, count), table, IconStudio.item(id))
	if keeper.carry_def != null:
		return {}
	var waiter: Job = world.board.job_with_key("serve:%d,%d:%s" % [table.x, table.y, id])
	if waiter != null and waiter.claimant != null:
		return {}
	var source: Vector2i = _serving_source(id, table)
	if source.x < 0:
		return {}
	return _option(text, func() -> void: keeper.fetch_and_serve(source, table, count), source, IconStudio.item(id))


## The nearest stack of something that is not on a guest's table, free to take
## before any that a job is holding.
func _serving_source(id: StringName, from: Vector2i) -> Vector2i:
	var tables: Dictionary = {}
	for seat in world.customers.seating.seats:
		tables[seat["table"]] = true
	var held := Vector2i(-1, -1)
	for tile in world.items.tiles_with(id, from):
		if tables.has(tile):
			continue
		if world.items.available_at(tile) > 0:
			return tile
		if held.x < 0:
			held = tile
	return held


## The keeper clicked on themselves: put down what is held, or stop.
func _self_options() -> Array:
	var keeper: Keeper = world.keeper
	var out: Array = []
	if keeper.carry_def != null:
		out.append(_option("Put down %s" % keeper.carry_def.display_name, keeper.drop, keeper.pawn.tile,
			IconStudio.item(keeper.carry_def.id)))
	if keeper.is_busy():
		out.append(_option("Stop %s" % keeper.status_text(), keeper.stop, keeper.pawn.tile, ThoughtBubble.icon("idle")))
	return out


## The guests sitting at the table on `tile`.
func _guests_at(tile: Vector2i) -> Array:
	var out: Array = []
	if world.customers == null:
		return out
	var index: int = world.build.grid.object_index_at(tile)
	var tiles: Array = world.build.grid.placements[index]["tiles"] if index >= 0 else [tile]
	for brain in world.customers.customers:
		if is_instance_valid(brain) and brain.seat != Seating.NO_SEAT and tiles.has(brain.seating.table_for(brain.seat)):
			out.append(brain)
	return out


## The guest whose body this is, or null for staff and passers-by.
func _guest_of(person: Pawn) -> CustomerBrain:
	if world.customers == null:
		return null
	for brain in world.customers.customers:
		if is_instance_valid(brain) and brain.pawn == person:
			return brain
	return null


func _examine_piece(index: int, entry: Dictionary, tile: Vector2i) -> Dictionary:
	return _option("Examine %s" % entry["def"].display_name,
		func() -> void: _examine({"kind": WorldStats.Kind.BUILDING, "index": index, "tile": tile}), tile,
		IconStudio.building(entry["def"]))


## One row of the menu: what it says, what it does, where the yellow cross
## goes, and its picture.
static func _option(text: String, run: Callable, tile: Vector2i, icon: Texture2D = null) -> Dictionary:
	var out: Dictionary = {"text": text, "run": run, "tile": tile}
	if icon != null:
		out["icon"] = icon
	return out


func _examine(subject: Dictionary) -> void:
	world.hud.inspector.show_subject(subject)


# --- the yellow cross --------------------------------------------------------------

func _mark(tile: Vector2i) -> void:
	_marker.position = Vector3((float(tile.x) + 0.5) * TerrainMeshBuilder.TILE,
		world.terrain.sample_height((float(tile.x) + 0.5) * TerrainMeshBuilder.TILE, (float(tile.y) + 0.5) * TerrainMeshBuilder.TILE) + 0.08,
		(float(tile.y) + 0.5) * TerrainMeshBuilder.TILE)
	_marker_age = 0.0
	_marker.visible = true


static func _cross_mesh() -> Mesh:
	var mb := MeshBuilder.new()
	for angle in [PI * 0.25, -PI * 0.25]:
		var along := Vector3(cos(angle), 0.0, sin(angle)) * 0.32
		var across := Vector3(-sin(angle), 0.0, cos(angle)) * 0.055
		var a: Vector3 = -along - across
		var b: Vector3 = along - across
		var c: Vector3 = along + across
		var d: Vector3 = -along + across
		mb.add_tri(a, c, b, Color.WHITE)
		mb.add_tri(a, d, c, Color.WHITE)
		mb.add_tri(a, b, c, Color.WHITE)
		mb.add_tri(a, c, d, Color.WHITE)
	return mb.commit()
