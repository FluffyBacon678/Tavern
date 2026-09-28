class_name AtlasCache
extends RefCounted

## Disk cache for procedurally rasterised sprite atlases.
##
## Building the tree and ground atlases means hundreds of thousands of blended
## pixel writes in GDScript. That is a second or two on desktop and noticeably
## worse on a phone -- fine once, unacceptable every time the player opens the
## menu. The atlases are built from a fixed seed, so they are identical on every
## run and safe to cache as PNGs under user://.
##
## Bump VERSION whenever a draw function changes, or players will keep seeing
## sprites from the previous build.

const CACHE_DIR := "user://cache"
const VERSION: int = 1


static func path_for(key: String) -> String:
	return "%s/%s_v%d.png" % [CACHE_DIR, key, VERSION]


## Returns the cached image, or null on a miss or an unreadable file.
static func load_image(key: String) -> Image:
	var path: String = path_for(key)
	if not FileAccess.file_exists(path):
		return null
	var img: Image = Image.load_from_file(path)
	if img == null or img.is_empty():
		# A truncated or corrupt cache entry should just mean "rebuild it",
		# never a hard failure on the way to the menu.
		push_warning("AtlasCache: discarding unreadable cache entry '%s'." % key)
		return null
	return img


static func store(key: String, img: Image) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var err: int = img.save_png(path_for(key))
	if err != OK:
		push_warning("AtlasCache: could not write '%s' (error %d)." % [key, err])


## Drop every cached atlas. Useful from a debug key while iterating on sprites.
static func clear() -> void:
	var dir: DirAccess = DirAccess.open(CACHE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".png"):
			dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()
