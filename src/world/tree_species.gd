class_name TreeSpecies
extends RefCounted

## The forest's species table: which trees exist, how common each is, and what
## colour it is.
##
## This is world data, not renderer data. The 2D menu backdrop draws these as
## sprite atlases and the 3D world builds them as low-poly meshes, but both read
## the same distribution and the same palettes -- so a birch is the same shade of
## green in the title screen and in the game, and changing the forest's makeup is
## a one-file edit rather than two renderers drifting apart.
##
## Variant encoding is (kind << 1) | size_index, matching the original wallpaper.

enum Kind {
	PINE = 0,
	FIR = 1,
	POPLAR = 2,
	WILLOW = 3,
	BIRCH = 4,
	MAPLE = 5,
	AUTUMN = 6,
	CHERRY = 7,
	DEAD = 8,
}

const KIND_COUNT: int = 9
const SIZE_COUNT: int = 2
const VARIANT_COUNT: int = KIND_COUNT * SIZE_COUNT


## Weighted roll preserving the wallpaper's forest composition: conifer-dominant,
## with birch/maple/autumn as the broadleaf body, and cherry and dead trees rare
## enough to read as accents rather than noise.
static func pick_variant(rng: RandomNumberGenerator) -> int:
	var r: float = rng.randf()
	var kind: int
	if r < 0.24:
		kind = Kind.PINE
	elif r < 0.40:
		kind = Kind.FIR
	elif r < 0.48:
		kind = Kind.POPLAR
	elif r < 0.55:
		kind = Kind.WILLOW
	elif r < 0.68:
		kind = Kind.BIRCH
	elif r < 0.79:
		kind = Kind.MAPLE
	elif r < 0.89:
		kind = Kind.AUTUMN
	elif r < 0.94:
		kind = Kind.CHERRY
	else:
		kind = Kind.DEAD
	var size_idx: int = 0 if rng.randf() < 0.5 else 1
	return (kind << 1) | size_idx


static func kind_of(variant: int) -> int:
	return (variant >> 1) & 15


static func size_of(variant: int) -> int:
	return variant & 1


## True for the stacked-tier evergreens, which both renderers build differently
## from the round-canopy broadleaves.
static func is_conifer(kind: int) -> bool:
	return kind == Kind.PINE or kind == Kind.FIR


## Foliage palette, ordered [silhouette, mid fill, lit side, highlight].
## The 2D renderer uses all four for dappling; the 3D renderer uses the mid and
## lit entries and lets real lighting do the rest.
static func foliage_palette(kind: int) -> Array:
	match kind:
		Kind.PINE:
			return [Color("163d18"), Color("235c24"), Color("3f8138"), Color("5a9c50")]
		Kind.FIR:
			return [Color("143f20"), Color("236d33"), Color("3f9a4c"), Color("63bd6a")]
		Kind.POPLAR:
			return [Color("244e19"), Color("3a7c2a"), Color("5cab42"), Color("88c863")]
		Kind.WILLOW:
			return [Color("33571f"), Color("588534"), Color("86b657"), Color("aed079")]
		Kind.BIRCH:
			return [Color("274d1c"), Color("3c7a2a"), Color("5fa843"), Color("84c662")]
		Kind.MAPLE:
			return [Color("5f5018"), Color("9c8327"), Color("caa53c"), Color("e6cb63")]
		Kind.AUTUMN:
			return [Color("742612"), Color("a8451c"), Color("cc6a2a"), Color("e8a24e")]
		Kind.CHERRY:
			return [Color("a8567a"), Color("d98ab0"), Color("efb2cd"), Color("fbe1ed")]
		_:
			# Dead trees have no foliage; the palette stands in as bare limb tones.
			return [Color("6e3b2a"), Color("84513a"), Color("cfc9bb"), Color("e7e2d6")]


static func trunk_color(kind: int) -> Color:
	if kind == Kind.BIRCH:
		return Color("d9d3c4")
	if kind == Kind.DEAD:
		return Color("cfc9bb")
	return Color("5b3d23")
