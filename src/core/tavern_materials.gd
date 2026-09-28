class_name TavernMaterials
extends RefCounted

## One original detail atlas for furniture and goods. Material selection lives
## in the art builders, while colour stays in the existing vertex palette.
## Meshes retain one surface even when wood, cloth and iron meet on one prop.
enum Surface { PLAIN, WOOD, STONE, PLASTER, CLOTH, CRUST, METAL, CERAMIC }

static var _shared: ShaderMaterial


static func shared() -> ShaderMaterial:
	if _shared == null:
		_shared = ShaderMaterial.new()
		_shared.shader = load("res://src/core/tavern_surface.gdshader")
		var source: Texture2D = load("res://assets/prototype/materials/tavern_detail_atlas.svg")
		var pixels: Image = source.get_image()
		# Small goods and long floors need mips even when the SVG importer has not
		# inferred 3D use through this custom shader. Build once, share everywhere.
		pixels.generate_mipmaps()
		_shared.set_shader_parameter("detail_atlas", ImageTexture.create_from_image(pixels))
	return _shared
