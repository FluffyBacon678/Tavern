class_name TreeMeshLibrary
extends RefCounted

## Low-poly 3D meshes for every tree variant, built once at load.
##
## The 2D backdrop draws these species as sprites; here the same nine species and
## the same species hues from TreeSpecies become geometry. Three silhouettes carry
## all nine: stacked cones for the evergreens, clustered crowns for the
## broadleaves (stretched tall for poplar, squashed wide for willow), and a bare
## branching skeleton for the dead ones. Colour is what separates a maple from a
## cherry, exactly as in the sprite version.
##
## Each variant is its own mesh so it can be drawn with a MultiMesh -- eighteen
## draw calls for an entire forest, regardless of tree count.

## Mature tree height in world units, i.e. in tiles.
const HEIGHT_SMALL: float = 2.8
const HEIGHT_LARGE: float = 3.8

## Deliberately coarse. Bumping these past ~7 loses the faceted read and costs
## triangles for nothing at the distances this camera works at.
const TRUNK_SEGMENTS: int = 5
const CANOPY_SEGMENTS: int = 6
const CANOPY_RINGS: int = 3

var meshes: Array[ArrayMesh] = []

var _rng := RandomNumberGenerator.new()


func build(seed_value: int = 0x7A1E27) -> void:
	_rng.seed = seed_value
	meshes.clear()
	for variant in range(TreeSpecies.VARIANT_COUNT):
		meshes.append(_build_variant(variant))


func _build_variant(variant: int) -> ArrayMesh:
	var kind: int = TreeSpecies.kind_of(variant)
	var size_idx: int = TreeSpecies.size_of(variant)
	var h: float = HEIGHT_SMALL if size_idx == 0 else HEIGHT_LARGE
	var palette: Array = _world_palette(kind)
	var trunk: Color = TreeSpecies.trunk_color(kind)
	if kind == TreeSpecies.Kind.BIRCH:
		trunk = Color("b8b09a")
	elif kind == TreeSpecies.Kind.DEAD:
		trunk = Color("8b806b")

	var mb := MeshBuilder.new()
	match kind:
		TreeSpecies.Kind.PINE:
			_conifer(mb, h, palette, trunk, 3 + size_idx, 0.68)
		TreeSpecies.Kind.FIR:
			_conifer(mb, h, palette, trunk, 3 + size_idx, 0.76)
		TreeSpecies.Kind.POPLAR:
			# Narrow and tall: the columnar silhouette.
			_broadleaf(mb, h, palette, trunk, Vector3(0.42, 1.05, 0.42), 0.52)
		TreeSpecies.Kind.WILLOW:
			# Wide and low, crown sitting close over the trunk.
			_broadleaf(mb, h, palette, trunk, Vector3(1.05, 0.52, 1.05), 0.40)
		TreeSpecies.Kind.DEAD:
			_dead(mb, h, trunk, palette[1])
		_:
			_broadleaf(mb, h, palette, trunk, Vector3(0.88, 0.72, 0.88), 0.45)
	return mb.commit()


func _world_palette(kind: int) -> Array:
	var source: Array = TreeSpecies.foliage_palette(kind)
	# The sprite palette already paints in sunlight. Real directional lighting
	# on those highlight swatches turned 3D foliage mint-white; use the middle
	# values and let the faceted normals provide the highlights in this renderer.
	var mid: Color = source[1]
	var lit: Color = source[2]
	var warm := Color("756242")
	return [source[0], mid.lerp(warm, 0.10), mid.lerp(lit, 0.22).lerp(warm, 0.10), mid.lerp(lit, 0.55).lerp(warm, 0.10)]


func _trunk(mb: MeshBuilder, height: float, radius: float, trunk: Color) -> void:
	mb.add_cylinder(Vector3.ZERO, radius, radius * 0.68, height, TRUNK_SEGMENTS, trunk)
	# Three buttress roots anchor the silhouette without extra scene nodes or
	# materials. The hidden underside needs no triangles.
	for root in range(3):
		var a: float = float(root) * TAU / 3.0
		var forward := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-sin(a), 0.0, cos(a)) * radius * 0.42
		var outer: Vector3 = forward * radius * 2.35 + Vector3.UP * 0.025
		var upper: Vector3 = forward * radius * 0.45 + Vector3.UP * height * 0.24
		mb.add_tri(outer, upper, forward * radius + side, trunk)
		mb.add_tri(forward * radius - side, upper, outer, trunk)


## Trunk plus stacked cones, widest at the bottom.
func _conifer(mb: MeshBuilder, h: float, palette: Array, trunk: Color, tiers: int, base_radius: float) -> void:
	var trunk_h: float = h * 0.25
	_trunk(mb, trunk_h + h * 0.13, 0.14, trunk)

	var canopy_h: float = h - trunk_h
	var tier_h: float = canopy_h / (float(tiers - 1) * 0.78 + 1.45)
	for t in range(tiers):
		var f: float = float(t) / float(tiers)
		var y: float = trunk_h + float(t) * tier_h * 0.78
		var radius: float = base_radius * (h / HEIGHT_SMALL) * (1.0 - f * 0.74)
		# Gradual crown lightening reads as foliage, unlike alternating bright
		# and dark tiers which made every evergreen look striped.
		var col: Color = (palette[1] as Color).lerp(palette[3], f)
		mb.add_cone(Vector3(0.0, y, 0.0), radius, tier_h * 1.45, CANOPY_SEGMENTS, col)


## Three coarse crown masses and visible boughs. Three-ring blobs cost the same
## canopy triangles as the old pair of four-ring blobs, with a fuller silhouette.
func _broadleaf(mb: MeshBuilder, h: float, palette: Array, trunk: Color, shape: Vector3, trunk_frac: float) -> void:
	var trunk_h: float = h * trunk_frac
	_trunk(mb, trunk_h, 0.17, trunk)

	var canopy_h: float = h - trunk_h
	var r: Vector3 = shape * canopy_h * 0.55
	var centre := Vector3(0.0, trunk_h + r.y * 0.86, 0.0)
	var angle: float = _rng.randf() * TAU
	var spread := Vector3(cos(angle) * r.x, 0.0, sin(angle) * r.z)
	for side in [-1.0, 1.0]:
		var crown: Vector3 = centre + spread * side * 0.42
		mb.add_limb(Vector3(0.0, trunk_h * 0.65, 0.0), crown, 0.075, 0.025, 4, trunk)
		mb.add_blob(crown, r * Vector3(0.80, 0.80, 0.80), CANOPY_RINGS, CANOPY_SEGMENTS, palette[2])
	mb.add_blob(centre + Vector3(0.0, r.y * 0.46, 0.0) - spread * 0.12, r * 0.72, CANOPY_RINGS, CANOPY_SEGMENTS, palette[3])


## A bare forking skeleton. Same recursive shape as the 2D dead tree, in 3D.
func _dead(mb: MeshBuilder, h: float, trunk: Color, tip: Color) -> void:
	var trunk_h: float = h * 0.45
	_trunk(mb, trunk_h, 0.15, trunk)
	_branch(mb, Vector3(0.0, trunk_h, 0.0), Vector3(0.0, 1.0, 0.0), h * 0.30, 0.075, 3, trunk, tip)


func _branch(mb: MeshBuilder, from: Vector3, dir: Vector3, length: float, radius: float, depth: int, limb: Color, tip: Color) -> void:
	if depth <= 0 or length < 0.12:
		return
	var to: Vector3 = from + dir.normalized() * length
	mb.add_limb(from, to, radius, radius * 0.62, 4, tip if depth == 1 else limb)

	# Two or three shoots, each tilted off the parent direction by a random
	# amount around a random axis, so the skeleton does not sit in one plane.
	var shoots: int = 2 if _rng.randf() < 0.55 else 3
	for i in range(shoots):
		var axis := Vector3(_rng.randf() - 0.5, _rng.randf() * 0.2, _rng.randf() - 0.5).normalized()
		var tilt: float = deg_to_rad(28.0 + _rng.randf() * 26.0)
		var new_dir: Vector3 = dir.normalized().rotated(axis, tilt)
		_branch(mb, to, new_dir, length * 0.7, radius * 0.62, depth - 1, limb, tip)
