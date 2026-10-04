class_name BuildingMeshLibrary
extends RefCounted

## Procedural low-poly meshes for every entry in the catalog.
##
## Built once and cached by definition id. Each mesh is authored in *tile space*
## with its origin at the minimum corner of its footprint and Y=0 on the floor,
## so the placement code can position it with a plain translation plus a quarter
## turn about the footprint centre.
##
## Definitions never name a mesh. They name a `shape`, and this picks the
## builder -- which is the seam that lets final art replace the prototype look
## without touching a single definition.

const TILE: float = 1.0

var _meshes: Dictionary = {}


func mesh_for(def: BuildingDef) -> ArrayMesh:
	if _meshes.has(def.id):
		return _meshes[def.id]
	var mesh: ArrayMesh = _build(def)
	_meshes[def.id] = mesh
	return mesh


## A joining piece's mesh for one shape of joint (see BuildController.link_mask).
func linked_mesh_for(def: BuildingDef, mask: int, variant: int = 0) -> ArrayMesh:
	var key := StringName("%s#%d#%d" % [def.id, mask, variant])
	if _meshes.has(key):
		return _meshes[key]
	var mb := MeshBuilder.new()
	mb.use_textures = true
	var main: Color = def.palette[0] if def.palette.size() > 0 else Color.WHITE
	var accent: Color = def.palette[1] if def.palette.size() > 1 else main
	if def.shape == BuildingDef.Shape.GARDEN_TILE:
		GardenArt.path(mb, def.id, mask, variant)
	else:
		GardenArt.fence(mb, mask, main, accent)
	var mesh: ArrayMesh = mb.commit()
	_meshes[key] = mesh
	return mesh


func _build(def: BuildingDef) -> ArrayMesh:
	var mb := MeshBuilder.new()
	mb.use_textures = true
	var w: float = float(def.size.x) * TILE
	var d: float = float(def.size.y) * TILE
	var main: Color = def.palette[0] if def.palette.size() > 0 else Color.WHITE
	var accent: Color = def.palette[1] if def.palette.size() > 1 else main

	match def.shape:
		BuildingDef.Shape.FLOOR_SLAB:
			_floor_slab(mb, w, d, def.height, main, accent, def.id == &"wood_floor")
		BuildingDef.Shape.WALL:
			var infill: Color = def.palette[2] if def.palette.size() > 2 else main
			_wall(mb, w, d, def.height, main, accent, infill)
		BuildingDef.Shape.DOOR:
			_door(mb, w, d, def.height, main, accent)
		BuildingDef.Shape.TABLE:
			_table(mb, w, d, def.height, main, accent)
		BuildingDef.Shape.CHAIR:
			_chair(mb, w, d, def.height, main, accent)
		BuildingDef.Shape.COUNTER:
			if def.id == &"prep_table":
				_prep_table(mb, w, d, def.height, main, accent)
			else:
				_counter(mb, w, d, def.height, main, accent)
		BuildingDef.Shape.OVEN:
			_oven(mb, w, d, def.height, main, accent)
		BuildingDef.Shape.VAT:
			_vat(mb, w, d, def.height, main, accent)
		BuildingDef.Shape.SHELF:
			_shelf(mb, w, d, def.height, main, accent)
		BuildingDef.Shape.SINK:
			_sink(mb, w, d, def.height, main, accent)
		BuildingDef.Shape.LECTERN:
			_lectern(mb, w, d, def.height, main, accent)
		BuildingDef.Shape.WELL:
			_well(mb, w, d, def.height, main, accent)
		BuildingDef.Shape.JETTY:
			_jetty(mb, w, d, def.height, main, accent)
		BuildingDef.Shape.GARDEN_TILE, BuildingDef.Shape.GARDEN_PROP:
			GardenArt.build(mb, def.id, w, d, def.height, main, accent)
		BuildingDef.Shape.FARM:
			_farm_plot(mb, w, d, def.height, main, accent)
		BuildingDef.Shape.PUMP:
			_pump(mb, w, d, def.height, main, accent)
		BuildingDef.Shape.BARREL:
			_barrel(mb, w, d, def.height, main, accent)
	return mb.commit()


## Fine seams keep the floor legible as a continuous room, instead of making
## every simulation tile look like a giant checkerboard square. Material-specific
## detailing belongs here at the art seam; it never changes grid occupancy.
func _floor_slab(mb: MeshBuilder, w: float, d: float, h: float, main: Color, accent: Color, wood: bool) -> void:
	mb.surface_style = TavernMaterials.Surface.WOOD if wood else TavernMaterials.Surface.STONE
	mb.add_box(Vector3.ZERO, Vector3(w, h - 0.004, d), accent)
	if wood:
		# Broad boards and quiet end joints keep the room behind its contents.
		_planks(mb, Vector3(0.0, h, 0.0), w, d, main.darkened(0.15), 2)
	else:
		for row in range(2):
			var split: float = w * (0.42 if row == 0 else 0.65)
			var bounds: Array[float] = [0.0, split, w]
			for col in range(2):
				var tint: Color = main.lightened(float((row + col) % 3) * 0.035)
				_top(mb, Vector3(bounds[col] + 0.009, h, float(row) * d * 0.5 + 0.009), bounds[col + 1] - bounds[col] - 0.018, d * 0.5 - 0.018, tint)


## An optional third palette colour is plaster infill. The same shape supports
## dressed stone without requiring a new construction or collision definition.
func _wall(mb: MeshBuilder, w: float, d: float, h: float, main: Color, accent: Color, infill: Color) -> void:
	if infill != main:
		mb.surface_style = TavernMaterials.Surface.PLASTER
		mb.add_box(Vector3(0.025, 0.0, 0.025), Vector3(w - 0.05, h, d - 0.05), infill)
		mb.surface_style = TavernMaterials.Surface.STONE
		mb.add_box(Vector3.ZERO, Vector3(w, h * 0.17, d), Color("777465"))
		mb.surface_style = TavernMaterials.Surface.WOOD
		for px in [0.0, w - 0.11]:
			for pz in [0.0, d - 0.11]:
				mb.add_box(Vector3(px, 0.0, pz), Vector3(0.11, h, 0.11), accent)
		for y in [h * 0.23, h * 0.63, h - 0.11]:
			for z in [0.0, d - 0.065]:
				mb.add_box(Vector3(0.0, y, z), Vector3(w, 0.075, 0.065), main)
			for x in [0.0, w - 0.065]:
				mb.add_box(Vector3(x, y, 0.0), Vector3(0.065, 0.075, d), main)
		# Braces use the same four-sided prisms as branches, sharing the material.
		for z in [0.018, d - 0.018]:
			mb.add_limb(Vector3(0.12, h * 0.3, z), Vector3(w - 0.12, h * 0.62, z), 0.042, 0.042, 4, accent)
		for x in [0.018, w - 0.018]:
			mb.add_limb(Vector3(x, h * 0.3, 0.12), Vector3(x, h * 0.62, d - 0.12), 0.042, 0.042, 4, accent)
	else:
		mb.surface_style = TavernMaterials.Surface.STONE
		mb.add_box(Vector3.ZERO, Vector3(w, h, d), accent)
		_masonry_faces(mb, Vector3.ZERO, Vector3(w, h - 0.1, d), main, 4)
	# The cap must sit above the plaster/posts, not share their top plane.
	# Coplanar surfaces flicker into bright stripes, especially after cutaway.
	mb.add_box(Vector3(0.0, h, 0.0), Vector3(w, 0.06, d), accent)


## Two jambs and a lintel, leaving a walkable gap. Deliberately an opening
## rather than a swinging leaf: the gap is the thing the pawn AI will path through.
func _door(mb: MeshBuilder, w: float, d: float, h: float, main: Color, accent: Color) -> void:
	mb.surface_style = TavernMaterials.Surface.WOOD
	var jamb: float = w * 0.18
	mb.add_box(Vector3.ZERO, Vector3(jamb, h, d), main)
	mb.add_box(Vector3(w - jamb, 0.0, 0.0), Vector3(jamb, h, d), main)
	mb.add_box(Vector3(0.0, h * 0.82, 0.0), Vector3(w, h * 0.18, d), main)
	# A threshold and iron straps identify an opening without a rail through the
	# pawn's chest: the old centre bar visually contradicted a passable doorway.
	mb.surface_style = TavernMaterials.Surface.STONE
	mb.add_box(Vector3(jamb, 0.0, 0.0), Vector3(w - jamb * 2.0, 0.035, d), Color("837c67"))
	mb.surface_style = TavernMaterials.Surface.METAL
	for x in [0.0, w - jamb]:
		for y in [h * 0.19, h * 0.69]:
			mb.add_box(Vector3(x, y, -0.008), Vector3(jamb, 0.065, d + 0.016), accent)
	mb.surface_style = TavernMaterials.Surface.WOOD
	for z in [0.035, d - 0.035]:
		mb.add_limb(Vector3(jamb, h * 0.66, z), Vector3(w * 0.34, h * 0.84, z), 0.05, 0.05, 4, main)
		mb.add_limb(Vector3(w - jamb, h * 0.66, z), Vector3(w * 0.66, h * 0.84, z), 0.05, 0.05, 4, main)


func _table(mb: MeshBuilder, w: float, d: float, h: float, main: Color, accent: Color) -> void:
	mb.surface_style = TavernMaterials.Surface.WOOD
	var top_t: float = 0.09
	var inset: float = 0.08
	_bevel_slab(mb, Vector3(inset, h - top_t, inset), Vector3(w - inset * 2.0, top_t, d - inset * 2.0), main.darkened(0.10), 0.025)
	_planks(mb, Vector3(inset + 0.08, h + 0.001, inset + 0.026), w - inset * 2.0 - 0.16, d - inset * 2.0 - 0.052, main, 4, false)
	# End boards and pegs make the top read as joinery, with no decorative
	# plates or mugs that could be mistaken for real stock waiting for service.
	for x in [inset + 0.043, w - inset - 0.043]:
		for z in [d * 0.28, d * 0.72]:
			_top(mb, Vector3(x - 0.013, h + 0.002, z - 0.013), 0.026, 0.026, accent)
	for x in [w * 0.23, w * 0.77]:
		mb.add_box(Vector3(x - 0.09, 0.03, d * 0.14), Vector3(0.18, 0.1, d * 0.72), accent)
		mb.add_box(Vector3(x - 0.065, 0.11, d * 0.5 - 0.065), Vector3(0.13, h - top_t - 0.11, 0.13), accent)
		mb.add_limb(Vector3(x, h * 0.36, d * 0.5), Vector3(x, h - top_t, d * 0.21), 0.045, 0.045, 4, accent)
		mb.add_limb(Vector3(x, h * 0.36, d * 0.5), Vector3(x, h - top_t, d * 0.79), 0.045, 0.045, 4, accent)
	mb.add_box(Vector3(w * 0.2, h * 0.26, d * 0.5 - 0.04), Vector3(w * 0.6, 0.08, 0.08), accent)


func _chair(mb: MeshBuilder, w: float, d: float, h: float, main: Color, accent: Color) -> void:
	mb.surface_style = TavernMaterials.Surface.WOOD
	var seat_h: float = h * 0.5
	var seat := Vector3(w * 0.52, 0.07, d * 0.52)
	_bevel_slab(mb, Vector3(w * 0.24, seat_h, d * 0.24), seat, main, 0.018)
	for x in [w * 0.24, w * 0.7]:
		for z in [d * 0.24, d * 0.7]:
			mb.add_box(Vector3(x, 0.0, z), Vector3(0.06, seat_h, 0.06), accent)
		mb.add_box(Vector3(x, seat_h, d * 0.24), Vector3(0.06, h - seat_h, 0.06), accent)
		mb.add_box(Vector3(x + 0.01, seat_h * 0.40, d * 0.28), Vector3(0.04, 0.045, d * 0.42), main.darkened(0.18))
	# Open space between back slats keeps seated characters readable.
	for y in [h * 0.69, h * 0.86]:
		mb.add_box(Vector3(w * 0.24, y, d * 0.24), Vector3(w * 0.52, h * 0.12, 0.07), main)
	# A restrained painted strip picks up the cool cloth colours on guests.
	mb.surface_style = TavernMaterials.Surface.PLAIN
	for z in [d * 0.24 - 0.002, d * 0.24 + 0.071]:
		mb.add_box(Vector3(w * 0.34, h * 0.895, z), Vector3(w * 0.32, 0.026, 0.001), Color("42645c"))


func _counter(mb: MeshBuilder, w: float, d: float, h: float, main: Color, accent: Color) -> void:
	mb.surface_style = TavernMaterials.Surface.WOOD
	var inset: float = 0.06
	mb.add_box(Vector3(inset, 0.0, inset), Vector3(w - inset * 2.0, h - 0.08, d - inset * 2.0), main.darkened(0.16))
	for i in range(6):
		var x: float = inset + float(i) * (w - inset * 2.0) / 6.0
		var panel_w: float = (w - inset * 2.0) / 6.0 - 0.015
		for z in [inset - 0.008, d - inset]:
			mb.add_box(Vector3(x, 0.1, z), Vector3(panel_w, h - 0.23, 0.008), main.lightened(float(i % 3) * 0.025))
	for y in [0.04, h - 0.17]:
		for z in [inset - 0.018, d - inset]:
			mb.add_box(Vector3(inset, y, z), Vector3(w - 2.0 * inset, 0.075, 0.02), main.darkened(0.27))
	_bevel_slab(mb, Vector3(0.0, h - 0.08, 0.0), Vector3(w, 0.08, d), accent, 0.025)
	# Broad painted panels and brass studs remain legible from the management
	# camera; detail is baked into the same cached surface as the timber.
	for z in [inset - 0.019, d - inset + 0.01]:
		mb.surface_style = TavernMaterials.Surface.WOOD
		for i in range(3):
			_face_mark(mb, Vector3(0.18 + i * (w - 0.36) / 3.0, 0.20, z), Vector2((w - 0.36) / 3.0 - 0.06, h - 0.48), Color("3f665c").lightened(0.025 * (i % 2)), z > d * 0.5)
		mb.surface_style = TavernMaterials.Surface.METAL
		for x in [0.15, w - 0.17]:
			for y in [0.15, h - 0.25]:
				_face_mark(mb, Vector3(x, y, z), Vector2(0.025, 0.025), Color("b69455"), z > d * 0.5)
	mb.surface_style = TavernMaterials.Surface.WOOD
	mb.add_box(Vector3(0.16, 0.13, d - 0.07), Vector3(w - 0.32, 0.06, 0.06), main.darkened(0.32))


func _prep_table(mb: MeshBuilder, w: float, d: float, h: float, main: Color, accent: Color) -> void:
	# Open workbench, pale stone slab and fixed tools distinguish preparation
	# from the enclosed painted serving bar. Tile centres stay clear for goods.
	mb.surface_style = TavernMaterials.Surface.WOOD
	for x in [0.12, w - 0.23]:
		for z in [0.12, d - 0.23]:
			mb.add_box(Vector3(x, 0.0, z), Vector3(0.11, h - 0.08, 0.11), main.darkened(0.3))
	for z in [0.12, d - 0.18]:
		mb.add_box(Vector3(0.12, h - 0.25, z), Vector3(w - 0.24, 0.17, 0.06), main)
	mb.add_box(Vector3(0.12, 0.16, 0.12), Vector3(w - 0.24, 0.055, d - 0.24), main.darkened(0.22))
	_planks(mb, Vector3(0.12, 0.216, 0.12), w - 0.24, d - 0.24, main.darkened(0.12), 3, false)
	mb.surface_style = TavernMaterials.Surface.STONE
	_bevel_slab(mb, Vector3(0, h - 0.08, 0), Vector3(w, 0.08, d), accent, 0.025)
	mb.surface_style = TavernMaterials.Surface.WOOD
	# The inset chopping board is flush with the support plane used by items.
	_top(mb, Vector3(w * 0.60, h + 0.001, 0.07), w * 0.27, d * 0.25, main.lightened(0.15))
	mb.add_limb(Vector3(0.18, h + 0.045, 0.15), Vector3(0.75, h + 0.045, 0.15), 0.021, 0.021, 6, main.darkened(0.2))
	mb.add_limb(Vector3(0.27, h + 0.045, 0.15), Vector3(0.66, h + 0.045, 0.15), 0.043, 0.043, 8, main.lightened(0.16))
	for x in [0.27, 0.66]:
		var centre := Vector3(x, h + 0.045, 0.15)
		for i in range(8):
			var a: float = TAU * i / 8.0
			var b: float = TAU * (i + 1) / 8.0
			var first := centre + Vector3(0, cos(a), sin(a)) * 0.043
			var second := centre + Vector3(0, cos(b), sin(b)) * 0.043
			mb.add_tri(centre, first if x > 0.5 else second, second if x > 0.5 else first, main.lightened(0.12))
	# A folded towel on the front apron adds cloth, not another ingredient.
	mb.surface_style = TavernMaterials.Surface.CLOTH
	mb.add_box(Vector3(w * 0.70, h - 0.39, d - 0.173), Vector3(w * 0.16, 0.26, 0.018), Color("b5b8a1"))
	mb.surface_style = TavernMaterials.Surface.PLAIN
	mb.add_box(Vector3(w * 0.70, h - 0.355, d - 0.153), Vector3(w * 0.16, 0.035, 0.003), Color("4e6c6c"))


func _oven(mb: MeshBuilder, w: float, d: float, h: float, main: Color, accent: Color) -> void:
	mb.surface_style = TavernMaterials.Surface.STONE
	var soot := Color("231d18")
	mb.add_box(Vector3.ZERO, Vector3(w, h * 0.17, d), main.darkened(0.15))
	# Real recess: the rear firebox and side piers leave an open mouth, so the
	# ember bed can be seen from the playing camera without an extra material.
	mb.add_box(Vector3(0.06, h * 0.17, 0.04), Vector3(w - 0.12, h * 0.46, d * 0.48), soot)
	# The dark lining belongs inside the oven, not on its exposed rear wall.
	var rear := Vector3(w, h * 0.43, 0.055)
	mb.add_box(Vector3(0, h * 0.17, 0), rear, main)
	_masonry_faces(mb, Vector3(0, h * 0.17, 0), rear, main, 3)
	for x in [0.0, w * 0.79]:
		var origin := Vector3(x, h * 0.17, 0.0)
		var size := Vector3(w * 0.21, h * 0.43, d)
		mb.add_box(origin, size, main.darkened(0.2))
		_masonry_faces(mb, origin, size, main, 3)
	mb.add_box(Vector3(0.0, h * 0.6, 0.0), Vector3(w, h * 0.16, d), main)
	# Radial wedge stones give the mouth an actual arch, with dark joints and
	# inward-facing soffits. Each wedge stays within the existing firebox.
	for i in range(7):
		var a: float = PI * i / 7.0 + 0.012
		var b: float = PI * (i + 1) / 7.0 - 0.012
		var centre := Vector3(w * 0.5, h * 0.41, d + 0.001)
		var inner_a := centre + Vector3(cos(a) * w * 0.29, sin(a) * h * 0.19, 0)
		var inner_b := centre + Vector3(cos(b) * w * 0.29, sin(b) * h * 0.19, 0)
		var outer_a := centre + Vector3(cos(a) * w * 0.39, sin(a) * h * 0.32, 0)
		var outer_b := centre + Vector3(cos(b) * w * 0.39, sin(b) * h * 0.32, 0)
		var tint: Color = main.lightened(0.07 if i == 3 else 0.025 * (i % 2))
		mb.add_quad(inner_a, outer_a, outer_b, inner_b, tint)
		mb.add_quad(inner_b, inner_b - Vector3(0, 0, 0.09), inner_a - Vector3(0, 0, 0.09), inner_a, tint.darkened(0.2))
	mb.add_box(Vector3(w * 0.21, h * 0.175, d * 0.5), Vector3(w * 0.58, 0.035, d * 0.43), soot)
	mb.surface_style = TavernMaterials.Surface.PLAIN
	for i in range(7):
		var x: float = w * 0.27 + float(i) * w * 0.072
		var z: float = d * (0.6 + float(i % 2) * 0.14)
		mb.add_box(Vector3(x, h * 0.2, z), Vector3(w * 0.055, 0.032, d * 0.085), Color("df7a2b") if i % 2 == 0 else Color("a34420"))
	mb.surface_style = TavernMaterials.Surface.STONE
	var chimney_origin := Vector3(w * 0.68, h * 0.76, d * 0.13)
	var chimney_size := Vector3(w * 0.22, h * 0.2, d * 0.42)
	mb.add_box(chimney_origin, chimney_size, main.darkened(0.22))
	_masonry_faces(mb, chimney_origin, chimney_size, main, 2)
	mb.surface_style = TavernMaterials.Surface.METAL
	mb.add_box(Vector3(w * 0.66, h * 0.96, d * 0.11), Vector3(w * 0.26, h * 0.04, d * 0.46), accent)


func _vat(mb: MeshBuilder, w: float, d: float, h: float, main: Color, accent: Color) -> void:
	var cx: float = w * 0.5
	var cz: float = d * 0.5
	var r: float = minf(w, d) * 0.42
	mb.surface_style = TavernMaterials.Surface.WOOD
	_staves(mb, Vector3(cx, 0.08, cz), r * 0.82, r, h * 0.76, 10, main)
	mb.surface_style = TavernMaterials.Surface.METAL
	_hoop(mb, Vector3(cx, h * 0.15, cz), r * 0.87, 0.045, h * 0.07, 10, accent)
	_hoop(mb, Vector3(cx, h * 0.66, cz), r * 0.98, 0.045, h * 0.065, 10, accent)
	mb.surface_style = TavernMaterials.Surface.WOOD
	_hoop(mb, Vector3(cx, h * 0.79, cz), r * 1.025, r * 0.15, h * 0.075, 10, main.lightened(0.08))
	mb.surface_style = TavernMaterials.Surface.PLAIN
	mb.add_cylinder(Vector3(cx, h * 0.77, cz), r * 0.88, r * 0.88, 0.012, 10, Color("644721"))
	mb.surface_style = TavernMaterials.Surface.WOOD
	mb.add_limb(Vector3(cx - r * 0.35, h * 0.77, cz), Vector3(cx + r * 0.42, h * 0.99, cz + r * 0.18), 0.035, 0.028, 5, Color("b29359"))
	mb.add_box(Vector3(cx - r * 0.36, h * 0.765, cz - 0.07), Vector3(0.19, 0.045, 0.14), Color("9a793e"))
	mb.surface_style = TavernMaterials.Surface.METAL
	mb.add_box(Vector3(cx - 0.06, h * 0.24, cz + r * 0.9), Vector3(0.12, 0.09, 0.16), accent)
	mb.add_box(Vector3(cx - 0.045, h * 0.205, cz + r * 0.9 + 0.11), Vector3(0.09, 0.085, 0.075), Color("a7814b"))
	mb.add_box(Vector3(cx - 0.09, h * 0.305, cz + r * 0.9 + 0.055), Vector3(0.18, 0.035, 0.035), Color("a7814b"))


func _shelf(mb: MeshBuilder, w: float, d: float, h: float, main: Color, accent: Color) -> void:
	mb.surface_style = TavernMaterials.Surface.WOOD
	var post: float = 0.09
	for px in [0.0, w - post]:
		for pz in [0.0, d - post]:
			mb.add_box(Vector3(px, 0.0, pz), Vector3(post, h, post), accent)
	# Three shelves, the lowest just off the floor.
	for i in range(3):
		var y: float = h * (0.18 + float(i) * 0.34)
		mb.add_box(Vector3(0.0, y, 0.0), Vector3(w, 0.06, d), main)
	mb.add_limb(Vector3(0.08, h * 0.15, 0.05), Vector3(w - 0.08, h * 0.93, 0.05), 0.045, 0.045, 4, accent)
	mb.add_limb(Vector3(w - 0.08, h * 0.15, 0.05), Vector3(0.08, h * 0.93, 0.05), 0.045, 0.045, 4, accent)


func _barrel(mb: MeshBuilder, w: float, d: float, h: float, main: Color, accent: Color) -> void:
	var cx: float = w * 0.5
	var cz: float = d * 0.5
	var r: float = minf(w, d) * 0.36
	mb.surface_style = TavernMaterials.Surface.WOOD
	_staves(mb, Vector3(cx, 0.0, cz), r * 0.86, r, h * 0.5, 10, main)
	_staves(mb, Vector3(cx, h * 0.5, cz), r, r * 0.86, h * 0.5, 10, main)
	mb.surface_style = TavernMaterials.Surface.METAL
	for band in [0.12, 0.46, 0.8]:
		var radius: float = r * (1.02 if band == 0.46 else 0.94)
		_hoop(mb, Vector3(cx, h * band, cz), radius, 0.03, h * 0.075, 10, accent)
	mb.surface_style = TavernMaterials.Surface.WOOD
	mb.add_cylinder(Vector3(cx, h - 0.025, cz), r * 0.855, r * 0.855, 0.025, 10, main.darkened(0.06))
	for xoff in [-0.11, 0.08]:
		_top(mb, Vector3(cx + xoff, h + 0.001, cz - r * 0.7), 0.008, r * 1.4, main.darkened(0.38))


func _top(mb: MeshBuilder, at: Vector3, w: float, d: float, col: Color) -> void:
	mb.add_quad(at, at + Vector3(0.0, 0.0, d), at + Vector3(w, 0.0, d), at + Vector3(w, 0.0, 0.0), col)


## Paint and flush studs need only their outward face, not six hidden sides.
func _face_mark(mb: MeshBuilder, at: Vector3, size: Vector2, col: Color, front: bool) -> void:
	var right := at + Vector3(size.x, 0, 0)
	var upper := Vector3(0, size.y, 0)
	if front:
		mb.add_quad(at, right, right + upper, at + upper, col)
	else:
		mb.add_quad(right, at, at + upper, right + upper, col)


## Small bevels catch the light without extra materials. The top plane remains
## at at.y + size.y so existing item-support heights need no special offsets.
func _bevel_slab(mb: MeshBuilder, at: Vector3, size: Vector3, col: Color, bevel: float) -> void:
	var corner: float = bevel * 1.5
	var ring: Array[Vector2] = [Vector2(corner, 0), Vector2(0, corner), Vector2(0, size.z - corner), Vector2(corner, size.z), Vector2(size.x - corner, size.z), Vector2(size.x, size.z - corner), Vector2(size.x, corner), Vector2(size.x - corner, 0)]
	var centre := at + Vector3(size.x * 0.5, size.y, size.z * 0.5)
	for i in range(ring.size()):
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		var ia := Vector2(lerpf(bevel, size.x - bevel, a.x / size.x), lerpf(bevel, size.z - bevel, a.y / size.z))
		var ib := Vector2(lerpf(bevel, size.x - bevel, b.x / size.x), lerpf(bevel, size.z - bevel, b.y / size.z))
		var low_a := at + Vector3(a.x, 0, a.y)
		var low_b := at + Vector3(b.x, 0, b.y)
		var shoulder_a := low_a + Vector3(0, size.y - bevel * 0.55, 0)
		var shoulder_b := low_b + Vector3(0, size.y - bevel * 0.55, 0)
		var top_a := at + Vector3(ia.x, size.y, ia.y)
		var top_b := at + Vector3(ib.x, size.y, ib.y)
		mb.add_quad(low_a, low_b, shoulder_b, shoulder_a, col.darkened(0.16))
		mb.add_quad(shoulder_a, shoulder_b, top_b, top_a, col.lightened(0.04))
		mb.add_tri(centre, top_a, top_b, col)
		mb.add_tri(centre - Vector3(0, size.y, 0), low_b, low_a, col.darkened(0.2))


func _planks(mb: MeshBuilder, at: Vector3, w: float, d: float, col: Color, count: int, joints: bool = true) -> void:
	var depth: float = d / float(count)
	for i in range(count):
		var z: float = float(i) * depth + 0.004
		var tint: Color = col.lightened(float(i % 3) * 0.014)
		_top(mb, at + Vector3(0.003, 0.0, z), w - 0.006, depth - 0.008, tint)
		if joints:
			var x: float = w * (0.32 if i % 2 == 0 else 0.73)
			_top(mb, at + Vector3(x, 0.001, z), 0.010, depth - 0.008, col.darkened(0.08))
		# Grain now comes from the shared mipmapped atlas, so distant tables do
		# not shimmer with thin geometric scratches.


func _masonry_faces(mb: MeshBuilder, at: Vector3, size: Vector3, col: Color, rows: int) -> void:
	var course: float = size.y / float(rows)
	for row in range(rows):
		var y: float = at.y + float(row) * course + 0.008
		var split: float = 0.43 if row % 2 == 0 else 0.65
		var bounds: Array[float] = [0.0, split, 1.0]
		for i in range(2):
			var tint: Color = col.lightened(float((row + i) % 3) * 0.04)
			var x0: float = at.x + size.x * bounds[i] + 0.008
			var x1: float = at.x + size.x * bounds[i + 1] - 0.008
			var y1: float = y + course - 0.016
			var z0: float = at.z - 0.001
			var z1: float = at.z + size.z + 0.001
			mb.add_quad(Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), tint)
			mb.add_quad(Vector3(x1, y, z0), Vector3(x0, y, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), tint)
			z0 = at.z + size.z * bounds[i] + 0.008
			z1 = at.z + size.z * bounds[i + 1] - 0.008
			x0 = at.x - 0.001
			x1 = at.x + size.x + 0.001
			mb.add_quad(Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), tint)
			mb.add_quad(Vector3(x1, y, z1), Vector3(x1, y, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), tint)


func _staves(mb: MeshBuilder, at: Vector3, lower: float, upper: float, h: float, sides: int, col: Color) -> void:
	for i in range(sides):
		var a0: float = TAU * float(i) / float(sides)
		var a1: float = TAU * float(i + 1) / float(sides)
		var b0: Vector3 = at + Vector3(cos(a0) * lower, 0.0, sin(a0) * lower)
		var b1: Vector3 = at + Vector3(cos(a1) * lower, 0.0, sin(a1) * lower)
		var t0: Vector3 = at + Vector3(cos(a0) * upper, h, sin(a0) * upper)
		var t1: Vector3 = at + Vector3(cos(a1) * upper, h, sin(a1) * upper)
		mb.add_quad(b0.lerp(b1, 0.018), t0.lerp(t1, 0.018), t1, b1, col.lightened(float(i % 3) * 0.04))
		mb.add_quad(b0, t0, t0.lerp(t1, 0.018), b0.lerp(b1, 0.018), col.darkened(0.22))


## Hollow rings avoid the capped cylinders that used to cover the entire vat.
func _hoop(mb: MeshBuilder, at: Vector3, radius: float, thickness: float, h: float, sides: int, col: Color) -> void:
	var inner: float = radius - thickness
	for i in range(sides):
		var a0: float = TAU * float(i) / float(sides)
		var a1: float = TAU * float(i + 1) / float(sides)
		var r0 := Vector3(cos(a0), 0.0, sin(a0))
		var r1 := Vector3(cos(a1), 0.0, sin(a1))
		var b0: Vector3 = at + r0 * radius
		var b1: Vector3 = at + r1 * radius
		var t0: Vector3 = b0 + Vector3.UP * h
		var t1: Vector3 = b1 + Vector3.UP * h
		var i0: Vector3 = at + r0 * inner
		var i1: Vector3 = at + r1 * inner
		var it0: Vector3 = i0 + Vector3.UP * h
		var it1: Vector3 = i1 + Vector3.UP * h
		mb.add_quad(b0, t0, t1, b1, col)
		mb.add_quad(i1, it1, it0, i0, col.darkened(0.15))
		mb.add_quad(t0, it0, it1, t1, col.lightened(0.05))


## A stone ring with a timber roof over it, and a bucket on the winch.
##
## Round rather than square, which nothing else on the plot is -- at a glance
## across a busy yard that silhouette is the only thing it could be.
func _well(mb: MeshBuilder, w: float, d: float, h: float, main: Color, accent: Color) -> void:
	var cx: float = w * 0.5
	var cz: float = d * 0.5
	var r: float = minf(w, d) * 0.36
	var wall: float = h * 0.32

	# The ring must be hollow: a capped cylinder would hide the pool beneath it.
	mb.surface_style = TavernMaterials.Surface.STONE
	_hoop(mb, Vector3(cx, 0.0, cz), r, r * 0.27, wall, 12, main)
	mb.surface_style = TavernMaterials.Surface.PLAIN
	mb.add_cylinder(Vector3(cx, wall * 0.5, cz), r * 0.7, r * 0.7, 0.02, 12, Color("2c4a58"))

	# Two posts and the beam they carry.
	mb.surface_style = TavernMaterials.Surface.WOOD
	var post_h: float = h - wall
	for sx in [-1.0, 1.0]:
		mb.add_box(
			Vector3(cx + sx * r * 0.82 - 0.06, wall, cz - 0.06),
			Vector3(0.12, post_h * 0.74, 0.12),
			accent
		)
	var beam_y: float = wall + post_h * 0.74
	mb.add_limb(
		Vector3(cx - r * 0.86, beam_y, cz), Vector3(cx + r * 0.86, beam_y, cz),
		0.055, 0.055, 8, accent.lightened(0.1)
	)

	# Open to rainfall, with a winding drum and crank instead of a solid roof.
	mb.add_limb(Vector3(cx - 0.16, beam_y, cz), Vector3(cx + 0.16, beam_y, cz), 0.085, 0.085, 8, Color("b19c70"))
	mb.surface_style = TavernMaterials.Surface.METAL
	mb.add_limb(Vector3(cx + r, beam_y, cz), Vector3(cx + r, beam_y - 0.17, cz), 0.024, 0.024, 5, Color("596169"))
	mb.add_limb(Vector3(cx + r, beam_y - 0.17, cz), Vector3(cx + r + 0.14, beam_y - 0.17, cz), 0.032, 0.032, 5, accent)
	mb.surface_style = TavernMaterials.Surface.WOOD
	_hoop(mb, Vector3(cx, beam_y - 0.34, cz), 0.13, 0.025, 0.2, 8, accent.lightened(0.18))
	mb.surface_style = TavernMaterials.Surface.PLAIN
	mb.add_cylinder(Vector3(cx, beam_y - 0.30, cz), 0.10, 0.10, 0.01, 8, Color("2c4a58"))
	mb.surface_style = TavernMaterials.Surface.CLOTH
	mb.add_limb(Vector3(cx, beam_y - 0.14, cz), Vector3(cx, beam_y, cz), 0.014, 0.014, 4, Color("b19c70"))


## A standing desk with a sloped top: the thing a host keeps the book on.
##
## Narrow and tall rather than waist-high and square, so it reads as furniture
## somebody stands *behind* rather than another counter, which is the whole job
## of the silhouette here.
func _lectern(mb: MeshBuilder, w: float, d: float, h: float, main: Color, accent: Color) -> void:
	var post_w: float = w * 0.16
	var foot: float = h * 0.06
	# Splayed foot, so it does not look like a fencepost driven into the floor.
	mb.surface_style = TavernMaterials.Surface.METAL
	mb.add_box(Vector3(w * 0.24, 0.0, d * 0.24), Vector3(w * 0.52, foot, d * 0.52), accent)
	mb.surface_style = TavernMaterials.Surface.WOOD
	mb.add_box(
		Vector3(w * 0.5 - post_w * 0.5, foot, d * 0.5 - post_w * 0.5),
		Vector3(post_w, h - foot - h * 0.18, post_w),
		main.darkened(0.1)
	)

	# The sloped writing top, built as two stacked slabs of different depth --
	# cheaper than a real wedge and reads the same at this size.
	var top_y: float = h - h * 0.18
	mb.add_box(Vector3(w * 0.12, top_y, d * 0.16), Vector3(w * 0.76, h * 0.06, d * 0.68), main)
	mb.add_box(Vector3(w * 0.12, top_y + h * 0.06, d * 0.16), Vector3(w * 0.76, h * 0.05, d * 0.40), main.lightened(0.06))
	# A lip along the front edge, to stop the ledger sliding off.
	mb.surface_style = TavernMaterials.Surface.METAL
	mb.add_box(Vector3(w * 0.12, top_y + h * 0.06, d * 0.14), Vector3(w * 0.76, h * 0.03, d * 0.05), accent)
	# A small bound ledger identifies the host's desk from the playing camera.
	var book_y: float = top_y + h * 0.11 + 0.003
	mb.surface_style = TavernMaterials.Surface.CLOTH
	mb.add_box(Vector3(w * 0.28, book_y, d * 0.24), Vector3(w * 0.36, 0.009, d * 0.25), Color("663b30"))
	mb.surface_style = TavernMaterials.Surface.PLAIN
	mb.add_box(Vector3(w * 0.29, book_y + 0.009, d * 0.25), Vector3(w * 0.34, 0.025, d * 0.23), Color("c7b896"))
	mb.surface_style = TavernMaterials.Surface.CLOTH
	mb.add_box(Vector3(w * 0.28, book_y + 0.034, d * 0.24), Vector3(w * 0.36, 0.009, d * 0.25), Color("754337"))


## Four rim pieces leave a real opening over the water, so the basin does not
## read as another solid preparation counter from above.
func _sink(mb: MeshBuilder, w: float, d: float, h: float, main: Color, accent: Color) -> void:
	var inset: float = 0.06
	var body: float = h - 0.10
	mb.surface_style = TavernMaterials.Surface.STONE
	mb.add_box(Vector3(inset, 0.0, inset), Vector3(w - inset * 2.0, body - 0.16, d - inset * 2.0), main)
	_masonry_faces(mb, Vector3(inset, 0.0, inset), Vector3(w - inset * 2.0, body, d - inset * 2.0), main.darkened(0.18), 3)

	# Basin walls, then the water inside them.
	var bx: float = w * 0.22
	var bz: float = d * 0.22
	var bw: float = w - bx * 2.0
	var bd: float = d - bz * 2.0
	for z in [0.0, d - bz]:
		mb.add_box(Vector3(0.0, body - 0.16, z), Vector3(w, 0.17, bz), main.lightened(0.08))
	for x in [0.0, w - bx]:
		mb.add_box(Vector3(x, body - 0.16, bz), Vector3(bx, 0.17, bd), main.lightened(0.04))
	mb.surface_style = TavernMaterials.Surface.METAL
	_top(mb, Vector3(bx, body - 0.155, bz), bw, bd, accent.darkened(0.45))
	mb.surface_style = TavernMaterials.Surface.PLAIN
	_top(mb, Vector3(bx, body - 0.065, bz), bw, bd, Color("4f7887"))
	# A slatted draining board occupies the unused left rim, clear of the two
	# tile-centre dish positions. Broad boards stay readable without shimmer.
	mb.surface_style = TavernMaterials.Surface.WOOD
	for i in range(5):
		mb.add_box(Vector3(0.07, body + 0.012, 0.1 + i * (d - 0.2) / 5.0), Vector3(bx - 0.14, 0.018, (d - 0.2) / 5.0 - 0.025), Color("8d704a"))


## A fishing spot: a short plank stage on stubby posts, a stool, a rod
## propped over the water and a creel for the catch.
func _jetty(mb: MeshBuilder, w: float, d: float, h: float, main: Color, accent: Color) -> void:
	mb.surface_style = TavernMaterials.Surface.WOOD
	for corner in [Vector2(0.08, 0.08), Vector2(w - 0.2, 0.08), Vector2(0.08, d - 0.2), Vector2(w - 0.2, d - 0.2)]:
		mb.add_box(Vector3(corner.x, 0.0, corner.y), Vector3(0.12, 0.16, 0.12), accent)
	var planks: int = 5
	for i in range(planks):
		var x0: float = w * float(i) / float(planks)
		mb.add_box(Vector3(x0 + 0.01, 0.16, 0.04), Vector3(w / float(planks) - 0.02, 0.05, d - 0.08),
			main if i % 2 == 0 else main.darkened(0.08))
	# A narrow walk out past the front edge, over the bank to the water: the
	# spot is built facing the river, and fishes from the end of it.
	var walk_x: float = w * 0.56
	mb.add_box(Vector3(walk_x, 0.13, -0.92 * d), Vector3(0.5, 0.05, 0.96 * d), main.darkened(0.04))
	for x in [walk_x + 0.03, walk_x + 0.39]:
		mb.add_box(Vector3(x, -0.4, -0.86 * d), Vector3(0.08, 0.53, 0.08), accent)
	mb.add_box(Vector3(w * 0.26, 0.21, d * 0.3), Vector3(0.22, 0.22, 0.22), accent.lightened(0.1))
	var tip := Vector3(w * 0.78, h, -0.75 * d)
	mb.add_limb(Vector3(w * 0.34, 0.32, d * 0.42), tip, 0.018, 0.012, 4, accent.darkened(0.2))
	mb.add_limb(tip, Vector3(w * 0.84, -0.2, -1.25 * d), 0.004, 0.004, 3, Color("d8d0b8"))
	mb.surface_style = TavernMaterials.Surface.PLAIN
	mb.add_cylinder(Vector3(w * 0.14, 0.21, d * 0.58), 0.13, 0.15, 0.2, 7, Color("8a6a3a"))


## Tilled earth: a dark bed with three raised furrows.
func _farm_plot(mb: MeshBuilder, w: float, d: float, h: float, main: Color, accent: Color) -> void:
	mb.surface_style = TavernMaterials.Surface.PLAIN
	mb.add_box(Vector3(0.02, 0.0, 0.02), Vector3(w - 0.04, h * 0.6, d - 0.04), accent)
	for i in range(3):
		var x0: float = w * (0.12 + 0.3 * float(i))
		mb.add_box(Vector3(x0, h * 0.6, 0.06), Vector3(w * 0.16, h * 0.4, d - 0.12), main)
		for clod in range(4):
			mb.add_blob(Vector3(x0 + w * 0.08, h * 0.85, 0.15 + clod * 0.23), Vector3(0.075, h * 0.3, 0.075), 2, 4, main.lightened(0.06 * float(clod % 2)))


## A hand pump on a stone footing, a spout, and a pipe down to the river.
func _pump(mb: MeshBuilder, w: float, d: float, h: float, main: Color, accent: Color) -> void:
	mb.surface_style = TavernMaterials.Surface.STONE
	mb.add_box(Vector3(w * 0.1, 0.0, d * 0.1), Vector3(w * 0.8, 0.18, d * 0.8), Color("8c8577"))
	mb.surface_style = TavernMaterials.Surface.PLAIN
	mb.add_cylinder(Vector3(w * 0.5, 0.18, d * 0.5), 0.09, 0.08, h * 0.62, 8, main)
	mb.add_box(Vector3(w * 0.5, h * 0.62, d * 0.46), Vector3(0.28, 0.06, 0.08), main)
	mb.add_limb(Vector3(w * 0.5, h * 0.8, d * 0.5), Vector3(w * 0.05, h, d * 0.5), 0.025, 0.02, 4, accent)
	mb.add_cylinder(Vector3(w * 0.5, 0.0, d * 0.05), 0.04, 0.04, 0.18, 6, main.darkened(0.2))
	mb.surface_style = TavernMaterials.Surface.METAL
	# Bolted foot and collars make the mechanism read as worked iron.
	mb.add_cylinder(Vector3(w * 0.5, 0.18, d * 0.5), 0.15, 0.15, 0.055, 8, main.lightened(0.12))
	for y in [0.34, h * 0.65]:
		_hoop(mb, Vector3(w * 0.5, y, d * 0.5), 0.105, 0.016, 0.045, 8, main.lightened(0.24))
	for dx in [-0.1, 0.1]:
		mb.add_cylinder(Vector3(w * 0.5 + dx, 0.235, d * 0.5), 0.018, 0.018, 0.025, 6, Color("aa9b7d"))
	mb.add_limb(Vector3(w * 0.75, h * 0.64, d * 0.5), Vector3(w * 0.78, h * 0.55, d * 0.5), 0.038, 0.042, 6, main)
	mb.add_limb(Vector3(w * 0.07, h * 0.98, d * 0.42), Vector3(w * 0.07, h * 0.98, d * 0.58), 0.035, 0.035, 6, accent.lightened(0.2))
	mb.surface_style = TavernMaterials.Surface.WOOD
	_hoop(mb, Vector3(w * 0.76, 0.18, d * 0.5), 0.13, 0.025, 0.2, 8, accent.lightened(0.15))
	mb.surface_style = TavernMaterials.Surface.PLAIN
	mb.add_cylinder(Vector3(w * 0.76, 0.2, d * 0.5), 0.102, 0.102, 0.015, 8, accent.darkened(0.4))
	mb.surface_style = TavernMaterials.Surface.METAL
	_hoop(mb, Vector3(w * 0.76, 0.22, d * 0.5), 0.135, 0.012, 0.025, 8, main)
