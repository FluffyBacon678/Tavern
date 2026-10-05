class_name GoodsStrip
extends HBoxContainer

## Goods as pictures with counts, in place of "3 flour sack, 2 water barrel":
## a sack and a 3, a barrel and a 2. Every panel draws goods through this, so
## a thing looks the same in the stores, on a card and in the keeper's menu.
## The name is the tooltip.
##
## One row, never wrapped: a wrapping row only knows its height a frame after
## it is laid out, and the cards size themselves from the first measurement.
## Past `most`, the rest are a "+3" whose tooltip names them.

const ARROW := "→"


## `entries` is a list of [id, count]; a count below zero shows no number,
## and a count given as text ("1/2") is shown as it is.
static func of(entries: Array, points: float = 26.0, font_size: int = 13,
		colour: Color = TavernTheme.PARCHMENT, most: int = 4) -> GoodsStrip:
	var strip := _strip(points)
	var shown: int = entries.size() if entries.size() <= most else most - 1
	for i in range(shown):
		strip.add_child(chip(StringName(entries[i][0]), _count_text(entries[i][1]), points, font_size, colour))
	if shown < entries.size():
		var rest: PackedStringArray = PackedStringArray()
		for i in range(shown, entries.size()):
			var def: ItemDef = ItemCatalog.get_def(StringName(entries[i][0]))
			var count: String = _count_text(entries[i][1])
			rest.append(("%s %s" % [count, def.display_name if def != null else String(entries[i][0])]).strip_edges())
		var more := Label.new()
		more.text = "+%d" % (entries.size() - shown)
		more.tooltip_text = "\n".join(rest)
		more.mouse_filter = Control.MOUSE_FILTER_STOP
		more.add_theme_font_size_override("font_size", font_size)
		more.add_theme_color_override("font_color", TavernTheme.CANDLE_DIM)
		more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		strip.add_child(more)
	return strip


## What goes in and what comes out: [sack]1 [cask]1 → [loaf]2.
static func recipe(r: Recipe, points: float = 24.0, font_size: int = 12,
		colour: Color = TavernTheme.PARCHMENT) -> GoodsStrip:
	var strip := _strip(points)
	for need in r.inputs:
		strip.add_child(chip(StringName(need["id"]), str(need["count"]), points, font_size, colour))
	var arrow := Label.new()
	arrow.text = ARROW
	arrow.add_theme_font_size_override("font_size", font_size + 2)
	arrow.add_theme_color_override("font_color", TavernTheme.CANDLE_DIM)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(arrow)
	for id in r.pick_from:
		strip.add_child(chip(StringName(id), "", points, font_size, colour))
	for out in r.outputs:
		strip.add_child(chip(StringName(out["id"]), str(out["count"]), points, font_size, colour))
	return strip


## One picture and its count, with the name as a tooltip.
static func chip(id: StringName, count: String, points: float = 26.0, font_size: int = 13,
		colour: Color = TavernTheme.PARCHMENT) -> HBoxContainer:
	var def: ItemDef = ItemCatalog.get_def(id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.tooltip_text = def.display_name if def != null else String(id)
	row.add_child(IconStudio.rect(IconStudio.item(id), points))
	if not count.is_empty():
		var n := Label.new()
		n.text = count
		n.add_theme_font_size_override("font_size", font_size)
		n.add_theme_color_override("font_color", colour)
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(n)
	return row


## Counts by id from a dictionary, most first, for "holding" lists.
static func entries_from(counts: Dictionary) -> Array:
	var out: Array = []
	for id in counts:
		out.append([id, int(counts[id])])
	out.sort_custom(func(a: Array, b: Array) -> bool:
		return a[1] > b[1] if a[1] != b[1] else String(a[0]) < String(b[0]))
	return out


static func _strip(points: float) -> GoodsStrip:
	var strip := GoodsStrip.new()
	strip.mouse_filter = Control.MOUSE_FILTER_PASS
	strip.add_theme_constant_override("separation", int(round(points * 0.3)))
	return strip


static func _count_text(count) -> String:
	if count is String:
		return count
	return str(int(count)) if int(count) >= 0 else ""
