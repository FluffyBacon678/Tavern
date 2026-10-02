class_name ThoughtBubble
extends Sprite3D

## A tiny bubble over someone's head saying what they are doing: a hammer for
## building, a pot for cooking, an hourglass for a guest waiting on food. Its
## rim goes red when a guest is running out of patience.
##
## Pixel art drawn from the masks below at start-up, so there is no image file
## to license or lose. Kept the same size on screen at any zoom, and drawn over
## walls: the point is to see what is going on inside.

## Height above a person's feet.
const HEIGHT: float = 1.5
const INK := Color("2b2118")
const FILL := Color("f6efdc")
const ALARM := Color("c8402e")

## name -> [rows, accent colour, second colour]. 'a' ink, 'b' accent, 'c' second.
const ICONS: Dictionary = {
	"build": [[
		"..aaaaaaa..",
		"..abbbbba..",
		"..aaaaaaa..",
		".....a.....",
		".....c.....",
		".....c.....",
		".....c.....",
		".....c.....",
		".....a.....",
	], Color("8d99a6"), Color("8a5a2b")],
	"haul": [[
		".aaaaaaaaa.",
		".abbbbbbba.",
		".accccccca.",
		".abbbbbbba.",
		".accccccca.",
		".abbbbbbba.",
		".aaaaaaaaa.",
	], Color("b07a3c"), Color("8a5a2b")],
	"cook": [[
		"...c...c...",
		"..c...c....",
		"...........",
		".aaaaaaaaa.",
		"aabbbbbbbaa",
		".abbbbbbba.",
		".abbbbbbba.",
		"..abbbbba..",
		"...aaaaa...",
	], Color("6b6f78"), Color("c9ccd3")],
	"serve": [[
		".....a.....",
		"...aaaaa...",
		"..abbbbba..",
		".abbbbbbba.",
		".abbbbbbba.",
		"aaaaaaaaaaa",
		"...........",
	], Color("d9d2bf"), Color("d9d2bf")],
	"order": [[
		".aaaaaaa...",
		".abbbbba...",
		".accccca...",
		".abbbbba...",
		".accccca.a.",
		".abbbbbaac.",
		".aaaaaaacc.",
		"........a..",
	], Color("f2e6c4"), Color("8a7a60")],
	"clean": [[
		".....a.....",
		"....aba....",
		"..aabbbaa..",
		"....aba....",
		".....a..a..",
		".a.....aba.",
		"aba.....a..",
		".a.........",
	], Color("8fd0ff"), Color("8fd0ff")],
	"clear": [[
		"...........",
		".aaaaaaaaa.",
		"..abbbbba..",
		".aaaaaaaaa.",
		"..abbbbba..",
		".aaaaaaaaa.",
		"..abbbbba..",
		"...aaaaa...",
	], Color("d9d2bf"), Color("d9d2bf")],
	"coin": [[
		"...aaaaa...",
		"..abbbbba..",
		".abbcccbba.",
		".abcbbbbba.",
		".abbcccbba.",
		".abbbbbcba.",
		".abbcccbba.",
		"..abbbbba..",
		"...aaaaa...",
	], Color("e8c04a"), Color("9a7420")],
	"host": [[
		".....a.....",
		"....aba....",
		"...abbba...",
		"...abbba...",
		"..abbbbba..",
		".abbbbbbba.",
		".aaaaaaaaa.",
		".....c.....",
	], Color("e8c04a"), Color("9a7420")],
	"gather": [[
		"..aaaaaaa..",
		".a.......a.",
		".aaaaaaaaa.",
		".abbbbbbba.",
		".accccccca.",
		"..abbbbba..",
		"..abbbbba..",
		"...aaaaa...",
	], Color("8a5a2b"), Color("5a9fd6")],
	"fish": [[
		"...........",
		"....aaa..a.",
		"..aabbbaaa.",
		".acbbbbbba.",
		"..aabbbaaa.",
		"....aaa..a.",
	], Color("7f9a86"), Color("1a120b")],
	"farm": [[
		".....b.....",
		"...b.b.b...",
		"....bbb....",
		".....b.....",
		".....b.....",
		"aaaaaaaaaaa",
		"acacacacaca",
	], Color("6f9a3c"), Color("5a3d24")],
	"idle": [[
		"......aaaa.",
		".........a.",
		"........a..",
		".......aaaa",
		".aaa.......",
		"...a.......",
		"..a........",
		".aaa.......",
	], Color("8a7a60"), Color("8a7a60")],
	"seat": [[
		".a.........",
		".a.........",
		".a.........",
		".abbbbbbb..",
		".aaaaaaaa..",
		".a......a..",
		".a......a..",
	], Color("b07a3c"), Color("b07a3c")],
	"menu": [[
		"..aaaaaaa..",
		".abbbbbbba.",
		".abcccccba.",
		".abbbbbbba.",
		".abcccccba.",
		".abbbbbbba.",
		"..aaaaaaa..",
	], Color("f2e6c4"), Color("8a7a60")],
	"hand": [[
		"...a.a.a...",
		"..abababa..",
		"..abababa..",
		"..abbbbba.a",
		"..abbbbbaba",
		"..abbbbbba.",
		"...abbbba..",
		"...aaaaaa..",
	], Color("e8b98f"), Color("e8b98f")],
	"wait": [[
		"..aaaaaaa..",
		"...abbba...",
		"....aba....",
		".....a.....",
		"....aca....",
		"...accca...",
		"..aaaaaaa..",
	], Color("e8c04a"), Color("e8c04a")],
	"eat": [[
		"...aaaaa...",
		"..abbbbba..",
		".abcbcbcba.",
		".abbbbbbba.",
		"..aaaaaaa..",
		"...........",
		"aaaaaaaaaaa",
	], Color("c98a3e"), Color("8a5a2b")],
	"happy": [[
		"..aa...aa..",
		".abba.abba.",
		".abbbabbba.",
		"..abbbbba..",
		"...abbba...",
		"....aba....",
		".....a.....",
	], Color("d8546a"), Color("d8546a")],
	"angry": [[
		"...aaaaa...",
		".aabbbbbaa.",
		"abbbbbbbbba",
		".aaaaaaaaa.",
		"....cc.....",
		"...cc......",
		"....cc.....",
		".....c.....",
	], Color("6b6f78"), Color("e8c04a")],
}

static var _cache: Dictionary = {}

var _shown: String = ""


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fixed_size = true
	pixel_size = 0.0019
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	shaded = false
	no_depth_test = true
	render_priority = 10
	position = Vector3(0.0, HEIGHT, 0.0)
	visible = false


## Show `icon` (a key of ICONS), or nothing for "". `urgent` reddens the rim.
func show_icon(icon: String, urgent: bool = false) -> void:
	var key: String = icon + ("!" if urgent else "")
	if key == _shown:
		return
	_shown = key
	if icon.is_empty() or not ICONS.has(icon):
		visible = false
		return
	texture = art(icon, urgent)
	visible = true


static func art(icon: String, urgent: bool = false) -> Texture2D:
	var key: String = icon + ("!" if urgent else "")
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(17, 17, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rim: Color = ALARM if urgent else INK
	# The bubble: a rounded box, and a little tail down towards the head.
	for y in range(14):
		for x in range(17):
			if (x == 0 or x == 16) and (y == 0 or y == 13):
				continue
			var edge: bool = x == 0 or x == 16 or y == 0 or y == 13
			img.set_pixel(x, y, rim if edge else FILL)
	img.set_pixel(5, 13, FILL)
	img.set_pixel(6, 13, FILL)
	for p in [Vector2i(4, 14), Vector2i(7, 14), Vector2i(5, 15), Vector2i(6, 15)]:
		img.set_pixel(p.x, p.y, rim)
	img.set_pixel(5, 14, FILL)
	img.set_pixel(6, 14, FILL)
	var entry: Array = ICONS[icon]
	var rows: Array = entry[0]
	var top: int = 2 + (10 - rows.size()) / 2
	for y in range(rows.size()):
		var row: String = rows[y]
		for x in range(mini(row.length(), 11)):
			var ch: String = row[x]
			var colour := Color(0, 0, 0, 0)
			match ch:
				"a":
					colour = INK
				"b":
					colour = entry[1]
				"c":
					colour = entry[2]
			if colour.a > 0.0:
				img.set_pixel(3 + x, top + y, colour)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Just the picture, no bubble, for the HUD's stock chips.
static func icon(name: String) -> Texture2D:
	var key: String = "icon:" + name
	if _cache.has(key):
		return _cache[key]
	var entry: Array = ICONS[name]
	var rows: Array = entry[0]
	var img := Image.create(11, 11, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var top: int = (11 - rows.size()) / 2
	for y in range(rows.size()):
		for x in range(mini(rows[y].length(), 11)):
			var colour := Color(0, 0, 0, 0)
			match rows[y][x]:
				"a":
					colour = Color("d7b568")
				"b":
					colour = Color("d7b568").darkened(0.25)
				"c":
					colour = Color("d7b568").lightened(0.3)
			if colour.a > 0.0:
				img.set_pixel(x, top + y, colour)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex