class_name StackLabels
extends Node3D

## A number over every stack of goods, so a shelf can be read at a glance.
##
## The item meshes suggest quantity with up to three copies, which tells a sack
## from a pile but never 4 from 9 -- and "is there enough flour for tomorrow?"
## is a question about 4 and 9. Hovering answers it for one stack; this answers
## it for the whole room.
##
## Shown when zoomed in, or at any distance while Alt is held. At the default
## distance forty numbers over a busy tavern would be noise.
##
## Resynced from the item world on a timer rather than kept in step by signals:
## a load or a clear() replaces stacks without announcing each one, and a label
## left over a stack that has gone is exactly the stale figure this game keeps
## finding. Deriving it costs a few dozen lookups twice a second.

const SHOW_WITHIN: float = 18.0
const RESYNC_INTERVAL: float = 0.5
## Above the tallest pile of copies.
const LIFT: float = 0.95

var world  ## TavernWorld

var _labels: Dictionary = {}  ## Vector2i -> Label3D
var _timer: float = 0.0
## Set whenever any stack changes, so the numbers follow on the very next
## frame rather than up to half a second later. The timed resync stays, for
## the changes that come without a signal -- a load, a clear().
var _dirty: bool = true
var _bound: bool = false


func setup(p_world) -> void:
	world = p_world
	name = "StackLabels"


func _process(delta: float) -> void:
	if world == null or world.items == null or world.rig == null:
		return
	if not _bound:
		_bound = true
		world.items.stack_changed.connect(func(_tile: Vector2i) -> void: _dirty = true)
	var wanted: bool = world.rig._distance <= SHOW_WITHIN or Input.is_key_pressed(KEY_ALT)
	if visible != wanted:
		visible = wanted
		_timer = 0.0
	if not visible:
		return
	_timer -= delta
	if _timer > 0.0 and not _dirty:
		return
	_timer = RESYNC_INTERVAL
	_dirty = false
	_resync()


func _resync() -> void:
	var seen: Dictionary = {}
	for tile in world.items.all_tiles():
		var count: int = world.items.count_at(tile)
		var def: ItemDef = world.items.def_at(tile)
		# One of anything needs no number, and plates are read by the table.
		if def == null or count < 2 or def.category == ItemDef.Category.REFUSE:
			continue
		seen[tile] = true
		var label: Label3D = _labels.get(tile)
		if label == null:
			label = _make_label()
			add_child(label)
			_labels[tile] = label
		label.text = str(count)
		# A full stack reads in candle-yellow: that tile will take no more.
		label.modulate = TavernTheme.CANDLE if count >= def.stack_size else TavernTheme.PARCHMENT
		label.position = world.items._visual_stack_position(tile) + Vector3(0.0, LIFT, 0.0)
	for tile in _labels.keys():
		if not seen.has(tile):
			_labels[tile].queue_free()
			_labels.erase(tile)


func _make_label() -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.pixel_size = 0.006
	l.font_size = 40
	l.outline_size = 12
	l.outline_modulate = TavernTheme.INK
	l.render_priority = 2
	l.outline_render_priority = 1
	return l
