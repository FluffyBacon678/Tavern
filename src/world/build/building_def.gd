class_name BuildingDef
extends Resource

## One buildable thing: a wall, a floor, a table, an oven.
##
## A Resource with exported fields rather than a hardcoded class per item, so new
## content is data. Today the catalog builds these in code; the moment it is
## worth authoring them in the inspector they can be saved as .tres with no code
## change. The design notes are explicit that content must be replaceable without
## rewriting systems, and this is where that starts.
##
## Nothing here names a mesh file or a texture. `shape` selects a procedural
## builder and `palette` tints it, so swapping the prototype look for final art
## means changing the mesh library, not every definition.

enum Layer {
	## Ground covering. One per tile, sits under objects.
	FLOOR = 0,
	## Everything that stands on a tile: walls, doors, furniture, workstations.
	OBJECT = 1,
}

enum Shape {
	FLOOR_SLAB,
	WALL,
	DOOR,
	TABLE,
	CHAIR,
	COUNTER,
	OVEN,
	VAT,
	SHELF,
	BARREL,
	SINK,
	LECTERN,
	WELL,
	JETTY,
	FARM,
	PUMP,
	GARDEN_TILE,
	GARDEN_PROP,
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: String = "Structure"
@export var layer: int = Layer.OBJECT
@export var shape: int = Shape.WALL
## Footprint in tiles. Rotation swaps the axes.
@export var size: Vector2i = Vector2i.ONE
## Gold. Placeholder economy values, per the design notes.
@export var cost: int = 5
## Blocks pawn movement. Doors are passable; walls are not.
@export var blocks_movement: bool = false
## Primary and accent colours for the procedural mesh.
@export var palette: Array[Color] = []
## Height above the floor, in tiles.
@export var height: float = 1.0
## Display height for stock resting on this piece, above its ground origin.
## -1 leaves loose goods on the floor. This never affects item ownership or
## walkability; it is an art anchor, not another inventory or storage rule.
@export var item_surface_height: float = -1.0
## Only this ItemDef.Category may be put down on this piece's tiles. -1 means
## no restriction, which is almost everything.
##
## A wash basin needs it: without a restriction a cook spilling a tray of bread
## onto the basin fills the one place refuse can be taken, and the tavern
## silently stops clearing tables -- a failure that looks like understaffing and
## is not.
@export var accepts_category: int = -1
## Must be built within this many tiles of open water. 0 means anywhere.
##
## The only placement rule in the game that looks at the landscape rather than
## the grid, and it exists to give the back of the plot a reason to matter: the
## river is the one thing out there you can build against.
@export var needs_water_within: int = 0
## Closes a room off. Walls and doors do; a table standing in the middle of the
## floor does not, however solid it is to walk through.
##
## A flag rather than "blocks_movement", because those are different questions
## and conflating them would make every oven a wall.
@export var encloses: bool = false
## Items may be stored on this piece's tiles, and haulers will bring goods here.
## Whether a piece is a *workstation* is not a flag: it is whether the recipe
## catalog has anything for its id, so adding a recipe is the only step needed
## to make an existing piece useful.
@export var is_storage: bool = false
## Walking pace over this floor, as a cost: 1.0 is the quickest floor. A flower
## bed is slow going, so people keep to the paths and lawns.
@export var walk_cost: float = 1.0
## Turned a random quarter per tile (by its position), so a lawn of one tile
## kind does not repeat. Looks only; the footprint is 1 x 1 either way.
@export var vary_rotation: bool = false
## Storage that only ever holds these (the well: water), whatever is ticked.
@export var stores_only: Array[StringName] = []


static func make(
	p_id: String,
	p_name: String,
	p_category: String,
	p_layer: int,
	p_shape: int,
	p_size: Vector2i,
	p_cost: int,
	p_blocks: bool,
	p_height: float,
	p_palette: Array[Color]
) -> BuildingDef:
	var d := BuildingDef.new()
	d.id = StringName(p_id)
	d.display_name = p_name
	d.category = p_category
	d.layer = p_layer
	d.shape = p_shape
	d.size = p_size
	d.cost = p_cost
	d.blocks_movement = p_blocks
	d.height = p_height
	d.palette = p_palette
	return d


## Footprint after rotation. Rotation is in quarter turns.
func rotated_size(quarter_turns: int) -> Vector2i:
	return Vector2i(size.y, size.x) if quarter_turns % 2 == 1 else size


## Seconds of work to build this, derived from cost rather than authored.
##
## Derived on purpose for now: an expensive thing taking longer is the right
## first approximation, and one formula beats thirteen hand-tuned numbers that
## nobody has playtested. Promote it to an exported field the moment build times
## need to differ from price -- a cheap-but-fiddly item would be the trigger.
func work_amount() -> float:
	return clampf(float(cost) * 0.14, 0.5, 6.0)
