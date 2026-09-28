class_name Raster
extends RefCounted

## A tiny software rasteriser for building sprite atlases at load time.
##
## The wallpaper draws its trees and ground cover with Canvas2D calls
## (fillRect / arc / ellipse) into offscreen canvases, then uploads the result
## as an atlas. Godot's equivalent -- drawing into a SubViewport -- forces us to
## await render frames mid-build and makes atlas construction asynchronous and
## order-dependent. Since every sprite here is tiny (16x16 ground cover, 48x64
## trees), rasterising into a byte buffer ourselves is both simpler and faster,
## and it stays fully synchronous so an atlas is ready the moment it is asked for.
##
## Writes go straight into a PackedByteArray rather than through
## Image.set_pixel(), which matters: set_pixel() has per-call overhead that shows
## up badly across the ~350k blended writes a full atlas build performs.

var width: int
var height: int
var _buf: PackedByteArray


func _init(w: int, h: int) -> void:
	width = w
	height = h
	_buf = PackedByteArray()
	_buf.resize(w * h * 4)
	_buf.fill(0)


## Source-over alpha blend of one pixel. Out of bounds writes are dropped.
func blend_pixel(x: int, y: int, col: Color, alpha_scale: float = 1.0) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	var sa: float = col.a * alpha_scale
	if sa <= 0.0:
		return
	var o: int = (y * width + x) * 4
	if sa >= 1.0:
		_buf[o] = int(col.r * 255.0)
		_buf[o + 1] = int(col.g * 255.0)
		_buf[o + 2] = int(col.b * 255.0)
		_buf[o + 3] = 255
		return

	var da: float = float(_buf[o + 3]) / 255.0
	var out_a: float = sa + da * (1.0 - sa)
	if out_a <= 0.0:
		return
	var inv: float = 1.0 / out_a
	var dr: float = float(_buf[o]) / 255.0
	var dg: float = float(_buf[o + 1]) / 255.0
	var db: float = float(_buf[o + 2]) / 255.0
	_buf[o] = int(clampf((col.r * sa + dr * da * (1.0 - sa)) * inv, 0.0, 1.0) * 255.0)
	_buf[o + 1] = int(clampf((col.g * sa + dg * da * (1.0 - sa)) * inv, 0.0, 1.0) * 255.0)
	_buf[o + 2] = int(clampf((col.b * sa + db * da * (1.0 - sa)) * inv, 0.0, 1.0) * 255.0)
	_buf[o + 3] = int(clampf(out_a, 0.0, 1.0) * 255.0)


func fill_rect(x: int, y: int, w: int, h: int, col: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			blend_pixel(xx, yy, col)


## Filled ellipse with a ~1px antialiased rim, matching the soft edge that
## Canvas2D's arc()/ellipse() produce. Used heavily for canopy leaf dabs.
func fill_ellipse(cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	var x0: int = int(floor(cx - rx - 1.0))
	var x1: int = int(ceil(cx + rx + 1.0))
	var y0: int = int(floor(cy - ry - 1.0))
	var y1: int = int(ceil(cy + ry + 1.0))
	# Feather width in normalised units: one pixel measured on the tighter axis.
	var feather: float = 1.0 / maxf(rx, ry)
	for yy in range(y0, y1 + 1):
		for xx in range(x0, x1 + 1):
			var dx: float = (float(xx) + 0.5 - cx) / rx
			var dy: float = (float(yy) + 0.5 - cy) / ry
			var d: float = sqrt(dx * dx + dy * dy)
			if d > 1.0 + feather:
				continue
			var cover: float = 1.0 if d <= 1.0 - feather else 1.0 - (d - (1.0 - feather)) / (2.0 * feather)
			blend_pixel(xx, yy, col, clampf(cover, 0.0, 1.0))


func fill_circle(cx: float, cy: float, r: float, col: Color) -> void:
	fill_ellipse(cx, cy, r, r, col)


## Axis-agnostic 1px-wide line, used for grass blades, twigs and stems.
func draw_line_px(x0: float, y0: float, x1: float, y1: float, col: Color) -> void:
	var dx: float = x1 - x0
	var dy: float = y1 - y0
	var steps: int = int(ceil(maxf(absf(dx), absf(dy))))
	if steps <= 0:
		blend_pixel(int(x0), int(y0), col)
		return
	for s in range(steps + 1):
		var t: float = float(s) / float(steps)
		blend_pixel(int(round(x0 + dx * t)), int(round(y0 + dy * t)), col)


## Convert to an Image ready for ImageTexture.create_from_image().
func to_image() -> Image:
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, _buf)


## Filled triangle via barycentric coverage test over the bounding box.
## The conifer tiers are built from three stacked triangles each.
func fill_triangle(ax: float, ay: float, bx: float, by: float, cx: float, cy: float, col: Color) -> void:
	var min_x: int = int(floor(minf(ax, minf(bx, cx))))
	var max_x: int = int(ceil(maxf(ax, maxf(bx, cx))))
	var min_y: int = int(floor(minf(ay, minf(by, cy))))
	var max_y: int = int(ceil(maxf(ay, maxf(by, cy))))
	var area: float = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
	if absf(area) < 0.0001:
		return
	var inv_area: float = 1.0 / area
	for yy in range(min_y, max_y + 1):
		for xx in range(min_x, max_x + 1):
			var px: float = float(xx) + 0.5
			var py: float = float(yy) + 0.5
			var w0: float = ((bx - px) * (cy - py) - (cx - px) * (by - py)) * inv_area
			var w1: float = ((cx - px) * (ay - py) - (ax - px) * (cy - py)) * inv_area
			var w2: float = 1.0 - w0 - w1
			if w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0:
				blend_pixel(xx, yy, col)


## Thick line with round caps -- the Canvas2D `lineCap = "round"` equivalent,
## used for the dead tree's branching skeleton. Stamps overlapping discs.
func draw_line_thick(x0: float, y0: float, x1: float, y1: float, thickness: float, col: Color) -> void:
	var r: float = maxf(0.5, thickness * 0.5)
	var dx: float = x1 - x0
	var dy: float = y1 - y0
	var dist: float = sqrt(dx * dx + dy * dy)
	var steps: int = maxi(1, int(ceil(dist / maxf(0.35, r * 0.5))))
	for s in range(steps + 1):
		var t: float = float(s) / float(steps)
		fill_circle(x0 + dx * t, y0 + dy * t, r, col)


## Copy this raster into a destination raster at (dx, dy) with source-over blending.
func blit_into(dst: Raster, dx: int, dy: int) -> void:
	for yy in range(height):
		for xx in range(width):
			var o: int = (yy * width + xx) * 4
			var a: int = _buf[o + 3]
			if a == 0:
				continue
			dst.blend_pixel(
				dx + xx,
				dy + yy,
				Color(float(_buf[o]) / 255.0, float(_buf[o + 1]) / 255.0, float(_buf[o + 2]) / 255.0, float(a) / 255.0)
			)
