class_name WardrobeSlotIcons
extends RefCounted

## Ten original silhouettes drawn for the equipment paper doll. Each SVG is
## rasterized once and shared by every creator; there is no animation or idle
## redraw work. Coordinates and shapes are authored here, without outside art.
const SHAPES: Dictionary = {
	"head": '<path d="M3 15 L6 14 L8 6 H16 L18 14 L21 15 V18 H3 Z"/><path d="M7 12 H17" fill="none"/>',
	"body": '<path d="M8 4 L10 7 H14 L16 4 L21 8 L18 13 L16 11 V21 H8 V11 L6 13 L3 8 Z"/><path d="M8 4 Q12 10 16 4" fill="none"/>',
	"outer": '<path d="M8 9 V6 Q8 3 12 3 Q16 3 16 6 V9" fill="none" stroke="#cfb782" stroke-width="2"/><path d="M7 8 H17 L18 21 H6 Z"/><path d="M7 13 H17 M9 15 H15 V18 H9 Z" fill="none"/>',
	"legs": '<path d="M6 3 H18 L17 21 H13 L12 11 L11 21 H7 Z"/><path d="M6 7 H18" fill="none"/>',
	"feet": '<path d="M6 3 H13 V13 L20 17 V21 H5 V13 Z"/><path d="M6 7 H13 M5 18 H20" fill="none"/>',
	"hands": '<path d="M7 21 V15 L3 11 Q2 9 4 8 L7 11 V5 Q7 3 9 4 V10 V3 Q11 1 12 3 V10 V4 Q14 2 15 4 V11 V6 Q17 4 18 6 V15 L16 21 Z"/><path d="M7 18 H17" fill="none"/>',
	"neck": '<path d="M6 3 C6 12 9 14 12 17 C15 14 18 12 18 3" fill="none" stroke="#cfb782" stroke-width="2.2"/><path d="M12 15 L16 19 L12 23 L8 19 Z"/>',
	"ring": '<circle cx="12" cy="14" r="6.5" fill="none" stroke="#cfb782" stroke-width="3"/><path d="M12 2 L16 6 L12 10 L8 6 Z"/>',
	"cape": '<path d="M8 4 H16 L21 21 L16 19 L12 22 L8 19 L3 21 Z"/><path d="M12 6 L10 19 M8 7 H16" fill="none"/>',
	"backpack": '<path d="M9 6 V3 Q12 0 15 3 V6" fill="none" stroke="#cfb782" stroke-width="2"/><rect x="5" y="5" width="14" height="17" rx="3"/><path d="M5 10 H19 M8 14 H16 V19 H8 Z" fill="none"/><rect x="11" y="9" width="2" height="4" fill="#ead5a6"/>',
}

static var _textures: Dictionary = {}


static func texture(slot: String) -> Texture2D:
	if _textures.has(slot):
		return _textures[slot]
	if not SHAPES.has(slot):
		return null
	var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="#cfb782" stroke="#574931" stroke-width="1.2" stroke-linejoin="round" stroke-linecap="round">%s</g></svg>' % String(SHAPES[slot])
	var pixels := Image.new()
	if pixels.load_svg_from_string(svg, 2.0) != OK:
		push_error("Could not build original wardrobe icon: %s" % slot)
		return null
	var icon := ImageTexture.create_from_image(pixels)
	_textures[slot] = icon
	return icon
