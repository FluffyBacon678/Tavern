class_name TreeAtlas
extends RefCounted

## Builds the forest's tree sprite sheet procedurally at load time.
##
## Ported from ForestFirewallpaper's side-view tree renderers. Nine species,
## each in a small and a large variant, drawn once into a single horizontal
## atlas. Trees are rendered from that atlas through a MultiMesh so thousands of
## them cost one draw call and can sway individually in the shader.
##
## Variant encoding matches the original: (species << 1) | size_index.

## Species identity, ordering and weighting all live in TreeSpecies, which the
## 3D world reads too. This class is only the 2D sprite renderer for them.
const VARIANT_COUNT: int = TreeSpecies.VARIANT_COUNT

## Per-sprite cell in the atlas. Trees are drawn tall: the sprite bottom edge is
## the trunk base, which is what the renderer anchors to a grid cell.
const TILE_W: int = 48
const TILE_H: int = 72

## The sprite library is deliberately seed-independent: these 18 variants are the
## forest's species, not a property of any one world. Fixing the seed keeps a
## pine looking like the same pine everywhere, and makes the atlas cacheable.
const ATLAS_SEED: int = 0x7A1E27

const CACHE_KEY := "tree_atlas"

var texture: ImageTexture
var tile_size: Vector2i = Vector2i(TILE_W, TILE_H)

var _rng: RandomNumberGenerator


## Build the atlas, or load it from the disk cache if one is already there.
func build(_unused_rng: RandomNumberGenerator = null) -> void:
	var cached: Image = AtlasCache.load_image(CACHE_KEY)
	if cached != null:
		texture = ImageTexture.create_from_image(cached)
		return

	_rng = RandomNumberGenerator.new()
	_rng.seed = ATLAS_SEED

	var sheet := Raster.new(TILE_W * VARIANT_COUNT, TILE_H)
	for variant in range(VARIANT_COUNT):
		var tile := Raster.new(TILE_W, TILE_H)
		_render_variant(tile, variant)
		tile.blit_into(sheet, variant * TILE_W, 0)

	var img: Image = sheet.to_image()
	AtlasCache.store(CACHE_KEY, img)
	texture = ImageTexture.create_from_image(img)


## UV rect of one variant inside the atlas, in 0..1 space.
func uv_rect(variant: int) -> Rect2:
	var w: float = 1.0 / float(VARIANT_COUNT)
	return Rect2(float(variant % VARIANT_COUNT) * w, 0.0, w, 1.0)


func _render_variant(c: Raster, variant: int) -> void:
	var species: int = TreeSpecies.kind_of(variant)
	var size_idx: int = TreeSpecies.size_of(variant)
	var w: float = float(TILE_W)
	var h: float = float(TILE_H)
	var cx: float = w * 0.5
	var base_y: float = h - 1.0

	match species:
		TreeSpecies.Kind.PINE:
			_draw_conifer(c, cx, base_y, w, h, size_idx)
		TreeSpecies.Kind.FIR:
			_draw_fir(c, cx, base_y, w, h, size_idx)
		TreeSpecies.Kind.POPLAR:
			_draw_poplar(c, cx, base_y, w, h, size_idx)
		TreeSpecies.Kind.WILLOW:
			_draw_willow(c, cx, base_y, w, h, size_idx)
		TreeSpecies.Kind.BIRCH:
			_draw_broadleaf(c, cx, base_y, w, h, size_idx, "birch")
		TreeSpecies.Kind.MAPLE:
			_draw_broadleaf(c, cx, base_y, w, h, size_idx, "maple")
		TreeSpecies.Kind.AUTUMN:
			_draw_broadleaf(c, cx, base_y, w, h, size_idx, "autumn")
		TreeSpecies.Kind.CHERRY:
			_draw_broadleaf(c, cx, base_y, w, h, size_idx, "cherry")
		TreeSpecies.Kind.DEAD:
			_draw_dead(c, cx, base_y, w, h, size_idx)


# --- shared pieces -------------------------------------------------------

## Soft contact shadow where the trunk meets the ground, nudged right to imply a
## light source up and to the left. Every species shares it so the lighting
## reads consistently across the forest.
func _ground_shadow(c: Raster, cx: float, base_y: float, rx: float) -> void:
	c.fill_ellipse(cx + rx * 0.12, base_y, rx, maxf(1.0, rx * 0.32), Color(0, 0, 0, 0.22))


func _trunk(c: Raster, cx: float, base_y: float, tw: float, th: float, birch: bool) -> void:
	var x0: int = int(round(cx - tw * 0.5))
	var wq: int = maxi(1, int(round(tw)))
	var top: int = int(base_y - th)
	var hh: int = maxi(1, int(th))
	if birch:
		c.fill_rect(x0, top, wq, hh, Color("d9d3c4"))
		c.fill_rect(x0 + wq - 1, top, 1, hh, Color(0.588, 0.580, 0.529, 0.55))
		var marks: int = maxi(2, int(th * 0.22))
		for m in range(marks):
			c.fill_rect(
				x0 + _rng.randi_range(0, wq - 1),
				top + int(_rng.randf() * th),
				1 + (1 if _rng.randf() < 0.4 else 0),
				1,
				Color(0.157, 0.137, 0.110, 0.85)
			)
	else:
		c.fill_rect(x0, top, wq, hh, Color("5b3d23"))
		c.fill_rect(x0, top, 1, hh, Color(0.439, 0.314, 0.180, 0.6))
		c.fill_rect(x0 + wq - 1, top, 1, hh, Color(0.133, 0.086, 0.047, 0.6))
		for m in range(maxi(2, int(th * 0.18))):
			c.fill_rect(
				x0 + _rng.randi_range(0, wq - 1),
				top + int(_rng.randf() * th),
				1,
				1,
				Color(0.118, 0.071, 0.039, 0.45)
			)


## Scatter n leaf dabs inside an ellipse for a dappled canopy. `fill` shrinks the
## scatter radius so successive passes stack inward instead of flattening out.
func _leaf_cluster(c: Raster, cx: float, cy: float, rx: float, ry: float, col: Color, n: int, fill: float) -> void:
	var br: float = maxf(1.1, rx * 0.17)
	for i in range(n):
		var a: float = _rng.randf() * TAU
		var rr: float = sqrt(_rng.randf()) * fill
		c.fill_circle(cx + cos(a) * rx * rr, cy + sin(a) * ry * rr, br, col)


# --- species -------------------------------------------------------------

func _draw_broadleaf(c: Raster, cx: float, base_y: float, w: float, h: float, size_idx: int, kind: String) -> void:
	var trunk_h: float = h * (0.30 + float(size_idx) * 0.02)
	var trunk_w: float = maxf(2.0, w * 0.14)
	var birch: bool = kind == "birch"

	# Palette order is [silhouette, mid fill, lit side, highlight].
	var dark: Color
	var mid: Color
	var lite: Color
	var hi: Color
	match kind:
		"birch":
			dark = Color("274d1c")
			mid = Color("3c7a2a")
			lite = Color("5fa843")
			hi = Color("84c662")
		"maple":
			dark = Color("5f5018")
			mid = Color("9c8327")
			lite = Color("caa53c")
			hi = Color("e6cb63")
		"autumn":
			dark = Color("742612")
			mid = Color("a8451c")
			lite = Color("cc6a2a")
			hi = Color("e8a24e")
		"cherry":
			dark = Color("a8567a")
			mid = Color("d98ab0")
			lite = Color("efb2cd")
			hi = Color("fbe1ed")
		_:
			dark = Color("1f4a1b")
			mid = Color("2f6e27")
			lite = Color("4e9a3a")
			hi = Color("74c057")

	_ground_shadow(c, cx, base_y, w * 0.32)
	_trunk(c, cx, base_y, trunk_w, trunk_h, birch)

	var can_rx: float = w * (0.44 + float(size_idx) * 0.03)
	var can_ry: float = h * (0.31 + float(size_idx) * 0.03)
	var can_cy: float = base_y - trunk_h * 0.55 - can_ry * 0.92

	_leaf_cluster(c, cx, can_cy, can_rx, can_ry, dark, 30, 1.0)
	_leaf_cluster(c, cx, can_cy, can_rx * 0.9, can_ry * 0.9, mid, 34, 0.94)
	_leaf_cluster(c, cx - can_rx * 0.22, can_cy - can_ry * 0.24, can_rx * 0.62, can_ry * 0.62, lite, 24, 0.9)
	_leaf_cluster(c, cx - can_rx * 0.30, can_cy - can_ry * 0.30, can_rx * 0.4, can_ry * 0.4, hi, 11, 0.85)
	_leaf_cluster(c, cx + can_rx * 0.24, can_cy + can_ry * 0.22, can_rx * 0.3, can_ry * 0.3, dark, 7, 0.7)


func _draw_conifer(c: Raster, cx: float, base_y: float, w: float, h: float, size_idx: int) -> void:
	var trunk_h: float = h * 0.14
	_ground_shadow(c, cx, base_y, w * 0.28)
	_trunk(c, cx, base_y, maxf(2.0, w * 0.12), trunk_h, false)

	var dark := Color("163d18")
	var mid := Color("235c24")
	var lite := Color("3f8138")
	var top_y: float = base_y - h * 0.97
	var bot_y: float = base_y - trunk_h * 0.5
	var tiers: int = 4 + size_idx
	var tier_h: float = (bot_y - top_y) / float(tiers)

	for t in range(tiers):
		var ty: float = top_y + float(t) * tier_h
		# Tiers widen toward the base, giving the classic pine silhouette.
		var tw: float = w * (0.16 + (float(t) / float(tiers)) * 0.40)
		c.fill_triangle(cx, ty - tier_h * 0.35, cx + tw, ty + tier_h * 1.05, cx - tw, ty + tier_h * 1.05, dark)
		c.fill_triangle(cx, ty - tier_h * 0.2, cx + tw * 0.82, ty + tier_h * 0.92, cx - tw * 0.82, ty + tier_h * 0.92, mid)
		c.fill_triangle(cx - tw * 0.15, ty, cx - tw * 0.78, ty + tier_h * 0.88, cx - tw * 0.30, ty + tier_h * 0.88, lite)
	c.fill_rect(int(cx - 0.5), int(top_y), 1, 2, lite)


func _draw_fir(c: Raster, cx: float, base_y: float, w: float, h: float, size_idx: int) -> void:
	var trunk_h: float = h * 0.13
	_ground_shadow(c, cx, base_y, w * 0.30)
	_trunk(c, cx, base_y, maxf(2.0, w * 0.12), trunk_h, false)

	var dark := Color("143f20")
	var mid := Color("236d33")
	var lite := Color("3f9a4c")
	var hi := Color("63bd6a")
	var top_y: float = base_y - h * 0.96
	var bot_y: float = base_y - trunk_h * 0.5
	var tiers: int = 4 + size_idx
	var tier_h: float = (bot_y - top_y) / float(tiers)

	for t in range(tiers):
		var ty: float = top_y + float(t) * tier_h
		var tw: float = w * (0.14 + (float(t) / float(tiers)) * 0.42)
		# Rounded lobes instead of a sharp triangle: the fir's scalloped branch
		# tips. More lobes lower down, where the tier is wider.
		var lobes: int = 2 + t
		var lobe_r: float = (tw / float(maxi(1, lobes))) * 1.30
		var by: float = ty + tier_h
		for l in range(lobes + 1):
			var lx: float = cx - tw + (2.0 * tw) * (float(l) / float(lobes))
			c.fill_circle(lx, by, lobe_r, dark)
		var fcy: float = by - tier_h * 0.30
		_leaf_cluster(c, cx, fcy, tw * 0.95, tier_h * 0.62, mid, 9 + t * 3, 0.98)
		_leaf_cluster(c, cx - tw * 0.34, fcy - tier_h * 0.16, tw * 0.55, tier_h * 0.48, lite, 5 + t * 2, 0.9)
		_leaf_cluster(c, cx - tw * 0.44, fcy - tier_h * 0.22, tw * 0.30, tier_h * 0.30, hi, 2 + t, 0.85)
		_leaf_cluster(c, cx + tw * 0.42, by - tier_h * 0.06, tw * 0.30, tier_h * 0.30, dark, 3 + t, 0.7)

	_leaf_cluster(c, cx, top_y + tier_h * 0.32, w * 0.12, tier_h * 0.5, mid, 6, 0.95)
	_leaf_cluster(c, cx - w * 0.04, top_y + tier_h * 0.22, w * 0.07, tier_h * 0.34, lite, 3, 0.85)
	c.fill_rect(int(cx - 0.5), int(top_y), 1, 2, hi)


func _draw_poplar(c: Raster, cx: float, base_y: float, w: float, h: float, size_idx: int) -> void:
	var trunk_h: float = h * 0.16
	_ground_shadow(c, cx, base_y, w * 0.18)
	_trunk(c, cx, base_y, maxf(2.0, w * 0.09), trunk_h, false)

	var dark := Color("244e19")
	var mid := Color("3a7c2a")
	var lite := Color("5cab42")
	var hi := Color("88c863")
	var cw: float = w * 0.27
	var top_y: float = base_y - h * 0.99
	var bot_y: float = base_y - trunk_h * 0.55
	var col_h: float = bot_y - top_y
	var segs: int = 5 + size_idx

	# Stacked vertical clusters, narrow at the crown and widening downward: a
	# flame/column silhouette quite unlike the round broadleaf.
	for s in range(segs):
		var f: float = float(s) / float(segs - 1)
		var cy: float = top_y + col_h * (0.08 + f * 0.84)
		var rx: float = cw * (0.32 + f * 0.82)
		var ry: float = col_h * 0.17
		_leaf_cluster(c, cx, cy, rx, ry, dark, 16, 1.0)
		_leaf_cluster(c, cx, cy - ry * 0.10, rx * 0.86, ry * 0.90, mid, 16, 0.95)
		_leaf_cluster(c, cx - rx * 0.34, cy - ry * 0.28, rx * 0.50, ry * 0.55, lite, 9, 0.9)
		_leaf_cluster(c, cx - rx * 0.44, cy - ry * 0.34, rx * 0.28, ry * 0.32, hi, 4, 0.85)
		_leaf_cluster(c, cx + rx * 0.34, cy + ry * 0.20, rx * 0.30, ry * 0.34, dark, 4, 0.7)
	_leaf_cluster(c, cx - cw * 0.12, top_y + col_h * 0.16, cw * 0.36, col_h * 0.14, hi, 5, 0.8)


func _draw_willow(c: Raster, cx: float, base_y: float, w: float, h: float, size_idx: int) -> void:
	var trunk_h: float = h * 0.24
	_ground_shadow(c, cx, base_y, w * 0.34)
	_trunk(c, cx, base_y, maxf(2.0, w * 0.12), trunk_h, false)

	var dark := Color("33571f")
	var mid := Color("588534")
	var lite := Color("86b657")
	var hi := Color("aed079")
	var can_rx: float = w * (0.46 + float(size_idx) * 0.03)
	var can_ry: float = h * 0.15
	# Crown sits high so the weeping curtain has room to drape beneath it.
	var can_cy: float = base_y - h * 0.72

	_leaf_cluster(c, cx, can_cy, can_rx, can_ry, dark, 30, 1.0)
	_leaf_cluster(c, cx, can_cy - can_ry * 0.10, can_rx * 0.92, can_ry * 0.88, mid, 28, 0.96)
	_leaf_cluster(c, cx, can_cy + can_ry * 0.55, can_rx * 0.86, can_ry * 0.70, mid, 16, 1.0)
	_leaf_cluster(c, cx - can_rx * 0.26, can_cy - can_ry * 0.22, can_rx * 0.55, can_ry * 0.52, lite, 16, 0.9)
	_leaf_cluster(c, cx - can_rx * 0.34, can_cy - can_ry * 0.30, can_rx * 0.30, can_ry * 0.32, hi, 7, 0.85)

	# Weeping skirt: a curtain of tendrils, longest at the centre and shortest at
	# the edges, wobbling as they fall. Left-side strands catch the light.
	var br: float = maxf(1.0, w * 0.05)
	var sy: float = can_cy + can_ry * 0.85
	var bottom: float = base_y - trunk_h * 0.25
	var span: float = can_rx * 1.7
	var nt: int = maxi(8, int(round(span / (br * 1.2))))
	for i in range(nt + 1):
		var fx: float = cx - span * 0.5 + span * (float(i) / float(nt)) + (_rng.randf() - 0.5) * br
		var mid01: float = 1.0 - absf(fx - cx) / (span * 0.55)
		var length: float = (0.30 + 0.70 * maxf(0.0, mid01)) * (bottom - sy) * (0.70 + _rng.randf() * 0.6)
		if length <= 0.0:
			continue
		var left_lit: bool = fx < cx
		var wob: float = 0.0
		var step: float = br * 1.15
		var d: float = 0.0
		while d < length:
			var t: float = d / length
			wob += (_rng.randf() - 0.5) * br * 0.6
			wob = clampf(wob, -w * 0.05, w * 0.05)
			var rnd: float = _rng.randf()
			var col: Color = lite if (left_lit and rnd < 0.5) else (mid if rnd < 0.8 else dark)
			c.fill_circle(fx + wob, sy + d, br * (1.0 - t * 0.4), col)
			d += step


func _draw_dead(c: Raster, cx: float, base_y: float, w: float, h: float, size_idx: int) -> void:
	# size_idx doubles as a colour switch here, so the two variants read as two
	# different dead trees: a pale grey skeleton and a reddish-brown one.
	var reddish: bool = size_idx == 1
	var limb: Color = Color("6e3b2a") if reddish else Color("cfc9bb")
	var tip_col: Color = Color("84513a") if reddish else Color("e7e2d6")
	_ground_shadow(c, cx, base_y, w * 0.22)
	_branch(c, cx, base_y, -PI * 0.5, h * 0.42, maxf(2.0, w * 0.15), 5 + size_idx, limb, tip_col)


## Recursive forking branch. Each fork splits left and right, with a 45% chance
## of a third middle shoot, thinning and shortening with depth. The outermost
## twigs switch to the lighter tip colour.
func _branch(c: Raster, x: float, y: float, ang: float, length: float, wdt: float, depth: int, limb: Color, tip_col: Color) -> void:
	if depth <= 0 or length < 2.0:
		return
	var ex: float = x + cos(ang) * length
	var ey: float = y + sin(ang) * length
	c.draw_line_thick(x, y, ex, ey, maxf(1.0, wdt), tip_col if depth <= 1 else limb)
	_branch(c, ex, ey, ang - 0.35 - _rng.randf() * 0.35, length * 0.72, wdt * 0.66, depth - 1, limb, tip_col)
	_branch(c, ex, ey, ang + 0.35 + _rng.randf() * 0.35, length * 0.72, wdt * 0.66, depth - 1, limb, tip_col)
	if _rng.randf() < 0.45:
		_branch(c, ex, ey, ang + (_rng.randf() - 0.5) * 0.4, length * 0.6, wdt * 0.6, depth - 1, limb, tip_col)
