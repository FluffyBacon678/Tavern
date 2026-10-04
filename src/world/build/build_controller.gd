class_name BuildController
extends Node3D

## Placement: ghost preview, validation, commit, demolish.
##
## Rendering is one MultiMesh per definition, rebuilt when that definition's set
## changes. A tavern of a few hundred pieces therefore costs about as many draw
## calls as the catalog has entries, not as many as it has objects -- and
## rebuilding one MultiMesh on a click is far cheaper than it sounds.

enum Mode { OFF, PLACE, DEMOLISH }

signal mode_changed(mode: int)
signal selection_changed(def: BuildingDef)
signal placed(def: BuildingDef)
signal refused(reason: String)
## How much ground the current drag covers, for the player to read before they
## commit to it.
signal drag_changed(tiles: int, cost: int)

const GHOST_VALID := Color(0.55, 1.0, 0.55, 0.55)
const GHOST_INVALID := Color(1.0, 0.42, 0.36, 0.5)

var grid := BuildGrid.new()
var terrain: TerrainMeshBuilder
## Where construction jobs are posted. Without one, pieces are built instantly.
var board: JobBoard
## Floor height the plot was flattened to. Everything is built on this plane, so
## a level tavern does not need per-tile height handling yet.
var plot_height: float = 0.0

var mode: int = Mode.OFF:
	set = set_mode
var selected: BuildingDef = null
var rotation_steps: int = 0

var _library := BuildingMeshLibrary.new()
var _instances: Dictionary = {}    ## def id -> MultiMeshInstance3D, finished
var _blueprints: Dictionary = {}   ## def id -> MultiMeshInstance3D, not yet built
var _blueprint_material: StandardMaterial3D
var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D
var _highlight: MeshInstance3D
var _material: Material
var _hover_tile := Vector2i(-1, -1)
var _last_ghost_key: String = ""
## Where an area drag started. Flooring a room a tile at a time is forty clicks
## for one decision, so a 1x1 floor piece is painted by dragging a rectangle
## instead. Deliberately limited to the floor layer: dragging a rectangle of
## tables or ovens is not a thing anybody means to do, and a wall wants a line
## rather than a fill.
var _drag_from := Vector2i(-1, -1)


func setup(cols: int, rows: int, plot: Rect2i, p_terrain: TerrainMeshBuilder, p_plot_height: float) -> void:
	terrain = p_terrain
	plot_height = p_plot_height
	grid.setup(cols, rows, plot)

	for child in _instances.values():
		child.queue_free()
	_instances.clear()
	for child in _blueprints.values():
		child.queue_free()
	_blueprints.clear()

	if _material == null:
		_material = TavernMaterials.shared()
	if _blueprint_material == null:
		# Blueprints read as a pale wireframe-ish shell: unshaded so they do not
		# pick up the sun, and translucent so a pawn standing behind one is
		# still visible while it works.
		_blueprint_material = StandardMaterial3D.new()
		_blueprint_material.albedo_color = Color(0.62, 0.86, 1.0, 0.38)
		_blueprint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blueprint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blueprint_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_build_ghost()


func _build_ghost() -> void:
	if _ghost != null:
		return
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.vertex_color_use_as_albedo = true
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_ghost = MeshInstance3D.new()
	_ghost.name = "Ghost"
	_ghost.material_override = _ghost_material
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)

	# Separate flat quad under the ghost: a footprint outline reads far better
	# than tinting the object alone, especially for tall pieces like walls.
	_highlight = MeshInstance3D.new()
	_highlight.name = "FootprintHighlight"
	var hm := StandardMaterial3D.new()
	hm.vertex_color_use_as_albedo = true
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.no_depth_test = true
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_highlight.material_override = hm
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_highlight.visible = false
	add_child(_highlight)


func set_mode(value: int) -> void:
	if value != mode:
		cancel_drag()
	mode = value
	if mode != Mode.PLACE:
		selected = null
		selection_changed.emit(null)
	_ghost.visible = false
	_highlight.visible = false
	mode_changed.emit(mode)


func select(def: BuildingDef) -> void:
	selected = def
	rotation_steps = 0
	mode = Mode.PLACE if def != null else Mode.OFF
	selection_changed.emit(def)


func rotate_selection() -> void:
	if selected == null:
		return
	rotation_steps = (rotation_steps + 1) % 4
	_last_ghost_key = ""  # force the ghost mesh to re-pose


## What a drag does with the selected piece. Floors fill the rectangle; walls
## go round its edge, so one drag walls a room -- and a drag one tile wide is a
## straight run. Walls used to take a click per tile: forty for a small room.
enum DragShape { NONE, FILL, OUTLINE }


func drag_shape() -> int:
	if selected == null or selected.size != Vector2i.ONE:
		return DragShape.NONE
	if selected.layer == BuildingDef.Layer.FLOOR:
		return DragShape.FILL
	if selected.shape == BuildingDef.Shape.WALL or selected.drag_outline:
		return DragShape.OUTLINE
	return DragShape.NONE


## Can the current selection be painted over an area rather than placed once?
func supports_area() -> bool:
	return drag_shape() != DragShape.NONE


## The tile under the pointer, as the builder last saw it.
func hover_tile() -> Vector2i:
	return _hover_tile


func is_dragging() -> bool:
	return _drag_from != Vector2i(-1, -1)


func begin_drag(tile: Vector2i) -> bool:
	if mode != Mode.PLACE or not supports_area() or tile.x < 0:
		return false
	_drag_from = tile
	_emit_drag()
	return true


func cancel_drag() -> void:
	if not is_dragging():
		return
	_drag_from = Vector2i(-1, -1)
	drag_changed.emit(0, 0)


## Every tile the drag rectangle covers that could actually take the piece, in
## reading order so a partly affordable area fills from one corner rather than
## in a scatter.
func drag_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not is_dragging() or selected == null or _hover_tile.x < 0:
		return out
	var x0: int = mini(_drag_from.x, _hover_tile.x)
	var x1: int = maxi(_drag_from.x, _hover_tile.x)
	var y0: int = mini(_drag_from.y, _hover_tile.y)
	var y1: int = maxi(_drag_from.y, _hover_tile.y)
	var outline: bool = drag_shape() == DragShape.OUTLINE
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if outline and x != x0 and x != x1 and y != y0 and y != y1:
				continue
			var tile := Vector2i(x, y)
			if grid.can_place(selected, tile, 0):
				out.append(tile)
	return out


func _emit_drag() -> void:
	var tiles: Array[Vector2i] = drag_tiles()
	drag_changed.emit(tiles.size(), tiles.size() * (selected.cost if selected != null else 0))


## Called each frame by the world with the tile currently under the pointer.
func update_hover(tile: Vector2i, valid_tile: bool) -> void:
	var moved: bool = tile != _hover_tile
	_hover_tile = tile if valid_tile else Vector2i(-1, -1)

	if is_dragging():
		if not valid_tile:
			_ghost.visible = false
			return
		var area: Array[Vector2i] = drag_tiles()
		_ghost.visible = true
		_pose_ghost(tile, GHOST_VALID if not area.is_empty() else GHOST_INVALID)
		_highlight.visible = true
		_show_footprint(area, GHOST_VALID if not area.is_empty() else GHOST_INVALID)
		if moved:
			_emit_drag()
		return

	if mode == Mode.OFF or not valid_tile:
		_ghost.visible = false
		_highlight.visible = false
		return

	if mode == Mode.DEMOLISH:
		_ghost.visible = false
		var index: int = grid.placement_at(tile)
		if index < 0:
			_highlight.visible = false
			return
		_highlight.visible = true
		_show_footprint(grid.placements[index]["tiles"], GHOST_INVALID)
		return

	if selected == null:
		_ghost.visible = false
		_highlight.visible = false
		return

	var origin: Vector2i = tile
	# Red when the purse cannot cover it, before the click rather than after.
	var ok: bool = grid.can_place(selected, origin, rotation_steps) and selected.cost <= GameState.gold
	var tint: Color = GHOST_VALID if ok else GHOST_INVALID

	_ghost.visible = true
	_highlight.visible = true
	_pose_ghost(origin, tint)
	_show_footprint(grid.footprint(selected, origin, rotation_steps), tint)


func _pose_ghost(origin: Vector2i, tint: Color) -> void:
	var key: String = "%s:%d" % [selected.id, rotation_steps]
	if key != _last_ghost_key:
		_ghost.mesh = _library.mesh_for(selected)
		_last_ghost_key = key
	_ghost_material.albedo_color = tint
	_ghost.transform = _placement_transform(selected, origin, rotation_steps)


func _show_footprint(tiles: Array, tint: Color) -> void:
	var mb := MeshBuilder.new()
	var y: float = plot_height + 0.05
	var c := Color(tint.r, tint.g, tint.b, 0.4)
	for t in tiles:
		var fx: float = float(t.x)
		var fz: float = float(t.y)
		mb.add_quad(
			Vector3(fx + 0.04, y, fz + 0.04),
			Vector3(fx + 0.04, y, fz + 0.96),
			Vector3(fx + 0.96, y, fz + 0.96),
			Vector3(fx + 0.96, y, fz + 0.04),
			c
		)
	_highlight.mesh = mb.commit()


## Meshes are authored with their origin at the footprint's minimum corner, so a
## quarter turn has to rotate about the footprint centre and then be re-anchored.
func _placement_transform(def: BuildingDef, origin: Vector2i, rotation: int) -> Transform3D:
	var size: Vector2i = def.size
	var basis := Basis(Vector3.UP, deg_to_rad(-90.0 * float(rotation)))
	# Offset from the rotated footprint's min corner back to the mesh origin.
	var local_centre := Vector3(float(size.x) * 0.5, 0.0, float(size.y) * 0.5)
	var rotated_size: Vector2i = def.rotated_size(rotation)
	var world_centre := Vector3(float(rotated_size.x) * 0.5, 0.0, float(rotated_size.y) * 0.5)
	var offset: Vector3 = world_centre - basis * local_centre
	return Transform3D(basis, Vector3(float(origin.x), plot_height, float(origin.y)) + offset)


func try_place() -> bool:
	if mode != Mode.PLACE or selected == null or _hover_tile.x < 0:
		return false
	var problem: String = grid.placement_problem(selected, _hover_tile, rotation_steps)
	if problem != "":
		refused.emit(problem)
		return false
	if not _place_one(_hover_tile):
		return false
	_close_batch()
	_rebuild_instances(selected)
	placed.emit(selected)
	return true


## Finish an area drag, putting the piece down on up to `limit` of the tiles it
## covers. Returns how many went down.
##
## The caller caps it because the purse is the world's business, not the
## builder's -- and it is capped rather than refused outright so that dragging
## across more ground than you can pay for floors what you *can* afford instead
## of doing nothing at all.
func finish_drag(limit: int) -> int:
	var tiles: Array[Vector2i] = drag_tiles()
	cancel_drag()
	if selected == null or tiles.is_empty() or limit <= 0:
		return 0

	var done: int = 0
	for tile in tiles:
		if done >= limit:
			break
		if _place_one(tile):
			done += 1
	_close_batch()
	if done > 0:
		_rebuild_instances(selected)
		placed.emit(selected)
	return done


## One piece, no complaints. Silence is the point: a drag across ground that is
## already floored should quietly skip those tiles rather than refuse forty
## times.
func _place_one(origin: Vector2i) -> bool:
	# Without a board there is nobody to do the work, so the piece appears
	# finished. With one, it lands as a blueprint and waits for a builder.
	var instant: bool = board == null
	var index: int = grid.place(selected, origin, rotation_steps, instant)
	if index < 0:
		return false
	if not instant:
		_post_build_job(index)
	_batch.append({"index": index, "def": selected, "origin": origin})
	return true


## What each placing action put down, newest last: one click, or one whole
## drag. Undo (C in the build bar) takes back the latest that still stands.
## Kept by what was placed where, not by index alone -- an index can be
## reused once its piece is gone.
var history: Array = []
var _batch: Array = []
const HISTORY_MOST: int = 30


func _close_batch() -> void:
	if not _batch.is_empty():
		history.append(_batch)
		_batch = []
		if history.size() > HISTORY_MOST:
			history.pop_front()


## The latest action's pieces that are still where they were put.
func pop_batch() -> Array:
	while not history.is_empty():
		var standing: Array = []
		for record in history.pop_back():
			var index: int = int(record["index"])
			if index < grid.placements.size():
				var entry = grid.placements[index]
				if entry != null and entry["def"] == record["def"] and entry["origin"] == record["origin"]:
					standing.append(record)
		if not standing.is_empty():
			return standing
	return []


## Place without going through the cursor. Used by scripted setups and, later,
## by anything that builds on the player's behalf.
func place_programmatic(def: BuildingDef, origin: Vector2i, rotation: int, as_blueprint: bool) -> int:
	var index: int = grid.place(def, origin, rotation, not as_blueprint)
	if index >= 0 and as_blueprint and board != null:
		_post_build_job(index)
	return index


func _post_build_job(index: int) -> void:
	var entry: Dictionary = grid.placements[index]
	var def: BuildingDef = entry["def"]
	var job := Job.new()
	job.kind = WorkType.Kind.CONSTRUCT
	# Work happens at the centre of the footprint, so a worker building a 2x2
	# vat stands beside its middle rather than beside one arbitrary corner.
	var size: Vector2i = def.rotated_size(entry["rotation"])
	job.target = entry["origin"] + Vector2i(size.x / 2, size.y / 2)
	job.work_amount = def.work_amount()
	job.label = "Build %s" % def.display_name
	job.subject = index
	job.on_complete = _on_build_job_complete
	board.post(job)


func _on_build_job_complete(job: Job) -> void:
	var index: int = job.subject
	if index < 0 or index >= grid.placements.size() or grid.placements[index] == null:
		return
	var def: BuildingDef = grid.placements[index]["def"]
	grid.mark_built(index)
	_rebuild_instances(def)


func try_demolish() -> bool:
	if mode != Mode.DEMOLISH or _hover_tile.x < 0:
		return false
	return demolish_index(grid.placement_at(_hover_tile))


## Remove one placement, whatever mode the builder is in -- a door replacing a
## wall must not drop the door the player is holding.
func demolish_index(index: int) -> bool:
	if index < 0 or index >= grid.placements.size() or grid.placements[index] == null:
		return false
	# Cancel any outstanding work on this piece first, or a builder keeps
	# walking toward something that no longer exists.
	if board != null:
		board.cancel_for_subject(index)
	var def: BuildingDef = grid.remove(index)
	if def != null:
		_rebuild_instances(def)
	return true


## Rebuild both MultiMeshes for one definition -- finished pieces and blueprints.
##
## Cheap enough to do on every click, and it keeps the renderer a pure function
## of the grid rather than a second source of truth that can drift out of sync.
func _rebuild_instances(def: BuildingDef) -> void:
	_rebuild_set(def, true, _instances, _material)
	_rebuild_set(def, false, _blueprints, _blueprint_material)
	# A joining piece changes how its group's other pieces are drawn: a new
	# stone path takes the verge off the dirt path beside it.
	if def.links and def.link_group != &"":
		for other in BuildingCatalog.all():
			if other != def and other.link_group == def.link_group:
				_rebuild_set(other, true, _instances, _material)
				_rebuild_set(other, false, _blueprints, _blueprint_material)


## A tile's own quarter turn, from its position: the same every time, so a
## lawn looks the same after a reload.
static func tile_turn(origin: Vector2i) -> int:
	return absi((origin.x * 73856093) ^ (origin.y * 19349663)) % 4


func _rebuild_set(def: BuildingDef, built: bool, store: Dictionary, material: Material) -> void:
	var entries: Array = grid.live_of(def.id, built)
	if def.links:
		_rebuild_linked(def, entries, store, material, built)
		return
	var mmi: MultiMeshInstance3D = store.get(def.id, null)

	if entries.is_empty():
		if mmi != null:
			mmi.queue_free()
			store.erase(def.id)
		return

	if mmi == null:
		mmi = MultiMeshInstance3D.new()
		mmi.name = "%s_%s" % [def.id, "built" if built else "blueprint"]
		mmi.material_override = material
		if not built:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		store[def.id] = mmi

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _library.mesh_for(def)
	mm.instance_count = entries.size()
	for i in range(entries.size()):
		var turns: int = int(entries[i]["rotation"])
		if def.vary_rotation:
			turns = (turns + tile_turn(entries[i]["origin"])) % 4
		mm.set_instance_transform(i, _placement_transform(def, entries[i]["origin"], turns))
	mmi.multimesh = mm


## A piece that joins its neighbours (a fence, a path) is drawn for the sides
## that have another of it, so corners, ends and crossings all meet cleanly.
## One MultiMesh per shape of joint, keyed "id#shape"; a tile that varies its
## turn varies its detail instead, four ways per joint.
const LINK_SIDES: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


func link_mask(def: BuildingDef, tile: Vector2i) -> int:
	var mask: int = 0
	for i in range(LINK_SIDES.size()):
		var at: Vector2i = tile + LINK_SIDES[i]
		var index: int = grid.floor_index_at(at) if def.layer == BuildingDef.Layer.FLOOR else grid.object_index_at(at)
		if index < 0 or grid.placements[index] == null:
			continue
		var other: BuildingDef = grid.placements[index]["def"]
		if other.id == def.id or (def.link_group != &"" and other.link_group == def.link_group):
			mask |= 1 << i
	return mask


func _rebuild_linked(def: BuildingDef, entries: Array, store: Dictionary, material: Material, built: bool) -> void:
	var variants: int = 4 if def.vary_rotation else 1
	var by_mask: Dictionary = {}
	for entry in entries:
		var mask: int = link_mask(def, entry["origin"]) * variants
		if variants > 1:
			mask += tile_turn(entry["origin"])
		if not by_mask.has(mask):
			by_mask[mask] = []
		by_mask[mask].append(entry)
	for mask in range(16 * variants):
		var key := StringName("%s#%d" % [def.id, mask])
		var mmi: MultiMeshInstance3D = store.get(key, null)
		if not by_mask.has(mask):
			if mmi != null:
				mmi.queue_free()
				store.erase(key)
			continue
		if mmi == null:
			mmi = MultiMeshInstance3D.new()
			mmi.name = "%s_%d_%s" % [def.id, mask, "built" if built else "blueprint"]
			mmi.material_override = material
			if not built:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			store[key] = mmi
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _library.linked_mesh_for(def, mask / variants, mask % variants)
		mm.instance_count = by_mask[mask].size()
		for i in range(by_mask[mask].size()):
			mm.set_instance_transform(i, _placement_transform(def, by_mask[mask][i]["origin"], 0))
		mmi.multimesh = mm
