class_name GroundAtlas
extends RefCounted

## Builds the ground-cover sprite sheet: grass tufts, wildflowers, fungi and
## forest-floor clutter, drawn procedurally at load time.
##
## Variant indices deliberately match ForestFirewallpaper's numbering, which runs
## to 59. Not all 59 are ported yet -- this is the representative subset that
## carries the look. Unported indices fall back to lush grass, and `pick_variant`
## only rolls implemented ones, so adding a new variant is a two-line change:
## write its draw function, add it to the dispatch and to the picker weights.

const VARIANT_COUNT: int = 59

## Set by build(). Tiles are rasterised at exactly one grid cell so the ground
## baker can blit them straight into the terrain image with no rescaling.
var tile: int = 16

# Implemented variants, original indices preserved.
const LUSH_FIRST: int = 0        # 0-9   ten shade/density variations
const TALL_FIRST: int = 10       # 10-12 fewer, longer blades
const DRY_FIRST: int = 13        # 13-15 tan, sparse, bent
const FLOWER_FIRST: int = 16     # 16-21 six blossom colours
const FERN: int = 23
const MUSHROOM: int = 26
const PEBBLES: int = 41
const LITTER: int = 42
const TOADSTOOL: int = 48
const LOG: int = 49
const STUMP: int = 50
const BOULDER: int = 56

# Written as float components rather than Color8() because a const expression
# has to be constant-foldable, and a helper-function call is not.
const FLOWER_COLORS: Array[Color] = [
	Color(0.941, 0.941, 0.922),  # white
	Color(0.973, 0.839, 0.275),  # yellow
	Color(0.863, 0.275, 0.275),  # red
	Color(0.941, 0.510, 0.706),  # pink
	Color(0.667, 0.431, 0.863),  # purple
	Color(0.353, 0.588, 0.922),  # blue
]

const LITTER_COLORS: Array[Color] = [
	Color(0.588, 0.337, 0.149),
	Color(0.690, 0.471, 0.157),
	Color(0.518, 0.251, 0.118),
	Color(0.431, 0.361, 0.157),
]

## Like the tree atlas, the ground sprite library is seed-independent so it can
## be cached. Where cover is *placed* still varies per world.
const ATLAS_SEED: int = 0x63A55

var texture: ImageTexture
## One Image per variant, ready to blit into the baked terrain. Sliced out of
## the sheet so the cached and freshly-built paths produce identical data.
var tile_images: Array[Image] = []

var _rng: RandomNumberGenerator


func build(_unused_rng: RandomNumberGenerator, tile_size: int) -> void:
	tile = maxi(4, tile_size)
	# Tile size follows the quality setting, so it has to be part of the key.
	var cache_key: String = "ground_atlas_%d" % tile

	var sheet_img: Image = AtlasCache.load_image(cache_key)
	if sheet_img == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = ATLAS_SEED
		var sheet := Raster.new(tile * VARIANT_COUNT, tile)
		for v in range(VARIANT_COUNT):
			var r := Raster.new(tile, tile)
			_render(r, v)
			r.blit_into(sheet, v * tile, 0)
		sheet_img = sheet.to_image()
		AtlasCache.store(cache_key, sheet_img)

	texture = ImageTexture.create_from_image(sheet_img)
	tile_images.clear()
	for v in range(VARIANT_COUNT):
		var region: Image = sheet_img.get_region(Rect2i(v * tile, 0, tile, tile))
		# Image.blend_rect needs matching formats, and a PNG round-trip can come
		# back in a narrower one, so pin it explicitly.
		if region.get_format() != Image.FORMAT_RGBA8:
			region.convert(Image.FORMAT_RGBA8)
		tile_images.append(region)


## Weighted roll over the implemented variants, holding roughly the original
## proportions: grass-dominant, with flowers as accents and clutter as rare
## punctuation.
func pick_variant(rng: RandomNumberGenerator) -> int:
	var r: float = rng.randf()
	if r < 0.42:
		return LUSH_FIRST + rng.randi_range(0, 9)
	if r < 0.50:
		return TALL_FIRST + rng.randi_range(0, 2)
	if r < 0.56:
		return DRY_FIRST + rng.randi_range(0, 2)
	if r < 0.70:
		return FLOWER_FIRST + rng.randi_range(0, 5)
	if r < 0.75:
		return FERN
	if r < 0.78:
		return MUSHROOM
	if r < 0.83:
		return TOADSTOOL
	if r < 0.88:
		return LITTER
	if r < 0.92:
		return PEBBLES
	if r < 0.95:
		return BOULDER
	if r < 0.98:
		return LOG
	return STUMP


func _render(c: Raster, variant: int) -> void:
	var w: float = float(tile)
	var h: float = float(tile)
	if variant < 10:
		_lush(c, w, h, variant)
	elif variant < 13:
		_tall(c, w, h)
	elif variant < 16:
		_dry(c, w, h)
	elif variant < 22:
		_wildflowers(c, w, h, variant - FLOWER_FIRST)
	elif variant == FERN:
		_fern(c, w, h)
	elif variant == MUSHROOM:
		_mushrooms(c, w, h)
	elif variant == PEBBLES:
		_pebbles(c, w, h)
	elif variant == LITTER:
		_leaf_litter(c, w, h)
	elif variant == TOADSTOOL:
		_toadstools(c, w, h)
	elif variant == LOG:
		_fallen_log(c, w, h)
	elif variant == STUMP:
		_stump(c, w, h)
	elif variant == BOULDER:
		_boulder(c, w, h)
	else:
		# Not yet ported -- render as plain lush grass so the world still fills in.
		_lush(c, w, h, variant % 10)


# --- primitives ----------------------------------------------------------

## A single blade: a 1px vertical streak that leans as it rises and brightens
## from base to tip, which is what gives the ground its soft dappled texture.
func _blade(c: Raster, x: float, y: float, hgt: float, lean: float, rb: float, gb: float, bb: float, a: float) -> void:
	var steps: int = maxi(2, int(hgt))
	for s in range(steps):
		var t: float = float(s) / float(steps)
		var px: float = x + lean * t
		var py: float = y - float(s)
		c.blend_pixel(
			int(px),
			int(py),
			Color(
				minf(1.0, (rb + t * 45.0) / 255.0),
				minf(1.0, (gb + t * 55.0) / 255.0),
				minf(1.0, (bb + t * 25.0) / 255.0),
				a
			)
		)


# --- variants ------------------------------------------------------------

func _lush(c: Raster, w: float, h: float, v: int) -> void:
	# v shifts the tuft between greener/yellower and darker/lighter, and also
	# scales density, so the ten variants tile without visible repetition.
	var yellow: float = float(v % 3) * 0.07
	var dark: float = float((v >> 1) % 2) * 14.0
	var rb: float = 34.0 + yellow * 55.0 - dark
	var gb: float = 108.0 + yellow * 26.0 - dark
	var bb: float = 32.0 + yellow * 8.0 - dark * 0.4
	var count: int = 9 + (v % 4) + int(w / 3.0)
	for i in range(count):
		var x: float = 1.0 + _rng.randf() * (w - 2.0)
		var y: float = h - 1.0 - _rng.randf() * (h * 0.35)
		var hgt: float = 2.0 + _rng.randf() * (h * 0.42)
		var lean: float = (_rng.randf() - 0.5) * 2.2
		_blade(c, x, y, hgt, lean, rb, gb, bb, 0.78 + _rng.randf() * 0.22)


func _tall(c: Raster, w: float, h: float) -> void:
	_lush(c, w, h, 2)
	var count: int = 5 + int(w / 4.0)
	for i in range(count):
		var x: float = 1.0 + _rng.randf() * (w - 2.0)
		var hgt: float = h * (0.6 + _rng.randf() * 0.38)
		var lean: float = (_rng.randf() - 0.5) * 3.2
		_blade(c, x, h - 1.0, hgt, lean, 46.0, 96.0, 30.0, 0.85)


func _dry(c: Raster, w: float, h: float) -> void:
	var count: int = 6 + int(w / 4.0)
	for i in range(count):
		var x: float = 1.0 + _rng.randf() * (w - 2.0)
		var y: float = h - 1.0 - _rng.randf() * (h * 0.3)
		var hgt: float = 2.0 + _rng.randf() * (h * 0.4)
		var lean: float = (_rng.randf() - 0.5) * 3.0
		var golden: float = 0.5 + _rng.randf() * 0.5
		_blade(
			c, x, y, hgt, lean,
			120.0 + golden * 50.0, 95.0 + golden * 40.0, 35.0 + golden * 20.0,
			0.7 + _rng.randf() * 0.25
		)


func _wildflowers(c: Raster, w: float, h: float, color_idx: int) -> void:
	_lush(c, w, h, 1)
	var col: Color = FLOWER_COLORS[color_idx % FLOWER_COLORS.size()]
	var blooms: int = 2 + _rng.randi_range(0, 2)
	for i in range(blooms):
		var cx: float = 2.0 + _rng.randf() * (w - 4.0)
		var cy: float = 2.0 + _rng.randf() * (h - 4.0)
		var pr: float = maxf(1.0, w * 0.12)
		c.fill_circle(cx, cy, pr, Color(col.r, col.g, col.b, 0.95))
		c.fill_rect(int(cx - 0.5), int(cy - 0.5), 1, 1, Color(1.0, 0.941, 0.470, 0.95))


func _fern(c: Raster, w: float, h: float) -> void:
	var fronds: int = 2 + _rng.randi_range(0, 1)
	var col := Color(0.157, 0.412, 0.149, 0.92)
	for f in range(fronds):
		var base_x: float = 2.0 + _rng.randf() * (w - 4.0)
		var base_y: float = h - 1.0
		var top_y: float = 1.0 + _rng.randf() * (h * 0.2)
		var curve: float = (_rng.randf() - 0.5) * 3.0
		var steps: int = int(base_y - top_y)
		if steps <= 0:
			continue
		for s in range(steps + 1):
			var t: float = float(s) / float(steps)
			# Quadratic curve so the frond arches over rather than leaning flat.
			var sx: float = base_x + curve * t * t
			var sy: float = base_y - float(s)
			c.blend_pixel(int(sx), int(sy), col)
			if s % 2 == 0:
				var ll: float = (1.0 - t) * w * 0.28
				c.blend_pixel(int(sx - ll), int(sy), col)
				c.blend_pixel(int(sx + ll), int(sy), col)


func _mushrooms(c: Raster, w: float, h: float) -> void:
	_lush(c, w, h, 0)
	var n: int = 2 + _rng.randi_range(0, 2)
	for i in range(n):
		var cx: float = 2.0 + _rng.randf() * (w - 4.0)
		var cy: float = h * 0.4 + _rng.randf() * (h * 0.4)
		var cr: float = maxf(1.0, w * 0.13)
		c.fill_rect(int(cx), int(cy), 1, maxi(1, int(cr)), Color(0.882, 0.843, 0.765, 0.95))
		var red: bool = _rng.randf() < 0.55
		var cap: Color = Color(0.784, 0.235, 0.176, 0.97) if red else Color(0.647, 0.470, 0.314, 0.97)
		# Half-dome cap: an ellipse squashed upward from the stem top.
		c.fill_ellipse(cx, cy - cr * 0.25, cr, cr * 0.7, cap)
		if red:
			c.fill_rect(int(cx - cr * 0.4), int(cy - cr * 0.3), 1, 1, Color(1, 1, 1, 0.9))


func _toadstools(c: Raster, w: float, h: float) -> void:
	_lush(c, w, h, 4)
	var n: int = 2 + _rng.randi_range(0, 2)
	for i in range(n):
		var cx: float = 2.0 + _rng.randf() * (w - 4.0)
		var base: float = h - 1.0 - _rng.randf() * (h * 0.15)
		var ch: float = maxf(3.0, h * (0.18 + _rng.randf() * 0.14))
		var cr: float = maxf(1.5, w * (0.10 + _rng.randf() * 0.05))
		c.fill_ellipse(cx, base, cr * 0.9, cr * 0.4, Color(0, 0, 0, 0.22))
		c.fill_rect(int(cx - cr * 0.25), int(base - ch), maxi(1, int(cr * 0.5)), int(ch), Color(0.933, 0.910, 0.839, 0.95))
		c.fill_ellipse(cx, base - ch, cr, cr * 0.62, Color(0.769, 0.157, 0.125, 0.97))
		c.fill_ellipse(cx - cr * 0.3, base - ch - cr * 0.18, cr * 0.4, cr * 0.26, Color(0.910, 0.376, 0.290, 0.85))
		for s in range(3):
			c.fill_rect(
				int(cx + (_rng.randf() - 0.5) * cr * 1.4),
				int(base - ch + (_rng.randf() - 0.5) * cr * 0.7),
				1, 1,
				Color(0.965, 0.941, 0.886, 0.92)
			)


func _pebbles(c: Raster, w: float, h: float) -> void:
	_lush(c, w, h, 3)
	var n: int = 3 + _rng.randi_range(0, 2)
	for i in range(n):
		var cx: float = 2.0 + _rng.randf() * (w - 4.0)
		var cy: float = 2.0 + _rng.randf() * (h - 4.0)
		var r: float = maxf(1.0, w * (0.08 + _rng.randf() * 0.08))
		var g: float = (120.0 + float(_rng.randi_range(0, 49))) / 255.0
		c.fill_ellipse(cx + 0.5, cy + 0.8, r, r * 0.7, Color(0, 0, 0, 0.2))
		c.fill_ellipse(cx, cy, r, r * 0.75, Color(g, g - 0.031, g - 0.078))
		c.fill_rect(int(cx - r * 0.3), int(cy - r * 0.3), 1, 1, Color(1, 1, 1, 0.25))


func _leaf_litter(c: Raster, w: float, h: float) -> void:
	_lush(c, w, h, 4)
	var leaves: int = 4 + _rng.randi_range(0, 3)
	for i in range(leaves):
		var cx: float = 1.0 + _rng.randf() * (w - 2.0)
		var cy: float = 1.0 + _rng.randf() * (h - 2.0)
		var lc: Color = LITTER_COLORS[_rng.randi_range(0, LITTER_COLORS.size() - 1)]
		var lr: float = maxf(1.0, w * 0.1)
		c.fill_ellipse(cx, cy, lr, lr * 0.55, Color(lc.r, lc.g, lc.b, 0.9))
	if _rng.randf() < 0.7:
		var tx: float = 2.0 + _rng.randf() * (w - 4.0)
		var ty: float = 2.0 + _rng.randf() * (h - 4.0)
		c.draw_line_px(
			tx, ty,
			tx + (_rng.randf() - 0.5) * w * 0.5,
			ty + (_rng.randf() - 0.5) * h * 0.4,
			Color(0.361, 0.251, 0.149, 0.85)
		)


func _fallen_log(c: Raster, w: float, h: float) -> void:
	_lush(c, w, h, 6)
	var ly: float = h * 0.5 + _rng.randf() * h * 0.22
	var lx0: float = w * 0.08
	var lw: float = w * 0.84
	var lh: float = maxf(2.0, h * 0.16)
	c.fill_rect(int(lx0), int(ly + lh * 0.7), int(lw), maxi(1, int(lh * 0.5)), Color(0, 0, 0, 0.2))
	c.fill_rect(int(lx0), int(ly), int(lw), int(lh), Color("6b4a2c"))
	c.fill_rect(int(lx0), int(ly + lh * 0.6), int(lw), maxi(1, int(lh * 0.4)), Color(0.157, 0.102, 0.055, 0.5))
	# Exposed end grain, read as concentric rings.
	c.fill_circle(lx0, ly + lh * 0.5, lh * 0.55, Color("8a6038"))
	c.fill_circle(lx0, ly + lh * 0.5, lh * 0.28, Color("5b3d22"))
	var moss: int = maxi(3, int(lw * 0.22))
	for m in range(moss):
		c.fill_rect(
			int(lx0 + _rng.randf() * lw),
			int(ly - _rng.randf() * 1.6),
			1 + (1 if _rng.randf() < 0.35 else 0),
			1,
			Color(0.282, 0.486, 0.204, 0.85)
		)


func _stump(c: Raster, w: float, h: float) -> void:
	_lush(c, w, h, 5)
	var cx: float = w * 0.5
	var base: float = h - 2.0
	var sh: float = maxf(3.0, h * 0.22)
	var sr: float = maxf(2.0, w * 0.22)
	c.fill_ellipse(cx, base, sr * 1.1, sr * 0.4, Color(0, 0, 0, 0.22))
	c.fill_rect(int(cx - sr), int(base - sh), int(sr * 2.0), int(sh), Color("5b3d22"))
	c.fill_rect(int(cx), int(base - sh), int(sr), int(sh), Color(0.157, 0.102, 0.055, 0.4))
	c.fill_ellipse(cx, base - sh, sr, sr * 0.5, Color("8a6038"))
	# Two growth rings, then a single sprout: the stump is still alive.
	for ring in range(1, 3):
		var f: float = float(ring) / 3.0
		c.fill_ellipse(cx, base - sh, sr * f, sr * 0.5 * f, Color(0.357, 0.239, 0.133, 0.7))
	c.fill_rect(int(cx - 1), int(base - sh - 3), 1, 3, Color(0.275, 0.510, 0.216, 0.9))


func _boulder(c: Raster, w: float, h: float) -> void:
	_lush(c, w, h, 5)
	var cx: float = w * 0.5
	var cy: float = h * 0.6
	var r: float = maxf(3.0, w * 0.26)
	c.fill_ellipse(cx, cy + r * 0.5, r * 1.1, r * 0.4, Color(0, 0, 0, 0.28))
	c.fill_ellipse(cx, cy, r, r * 0.85, Color("7d7a72"))
	c.fill_ellipse(cx + r * 0.2, cy + r * 0.15, r * 0.6, r * 0.5, Color("6a675f"))
	c.fill_ellipse(cx - r * 0.25, cy - r * 0.3, r * 0.4, r * 0.3, Color(0.675, 0.667, 0.627, 0.7))
	c.draw_line_px(cx - r * 0.3, cy - r * 0.2, cx + r * 0.1, cy + r * 0.4, Color(0.157, 0.149, 0.133, 0.5))
	var moss: int = maxi(4, int(r * 0.8))
	for m in range(moss):
		c.fill_rect(
			int(cx + (_rng.randf() - 0.5) * r * 1.6),
			int(cy - r * 0.55 + _rng.randf() * r * 0.35),
			1 + (1 if _rng.randf() < 0.3 else 0),
			1,
			Color(0.290, 0.486, 0.204, 0.9)
		)
