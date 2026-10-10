class_name LevelCatalog
extends RefCounted

## The levels the game ships with. One so far.
##
## Written as data in code for the same reason the building catalog is: the
## moment it is worth authoring these in the inspector they become .tres files
## and this function is the only thing that changes.

static var _levels: Array[LevelDef] = []
static var _by_id: Dictionary = {}


static func all() -> Array[LevelDef]:
	if _levels.is_empty():
		_build()
	return _levels


static func get_level(id: StringName) -> LevelDef:
	if _levels.is_empty():
		_build()
	return _by_id.get(id, null)


## The tutorial, which is not one of the scenarios: all() lists those.
static func tutorial() -> LevelDef:
	return get_level(&"tutorial")


static func _build() -> void:
	_levels = [_the_wayfarers_rest()] as Array[LevelDef]
	_by_id.clear()
	for level in _levels:
		_by_id[level.id] = level
	var lessons: LevelDef = _the_tutorial()
	_by_id[lessons.id] = lessons


## An empty plot, a purse for the whole plan with room for a mistake or two,
## and the TutorialDirector giving one instruction at a time. The seed is the
## demo level's, whose road, river and yard are known to work.
static func _the_tutorial() -> LevelDef:
	var level := LevelDef.new()
	level.id = &"tutorial"
	level.display_name = "Tutorial"
	level.tavern_name = "The Practice House"
	level.world_seed = 493774
	level.starting_gold = 1500
	level.is_tutorial = true
	return level


## The demo level: an inherited roadside tavern with three things wrong with it.
##
## Deliberately not a working business. It has a brewing vat and malt, so beer
## sells from the first minute and the player is never stuck watching an empty
## room -- and then it has three gaps that each teach a different rule, and only
## enough gold to close two of them:
##
##   * An oven but no prep table. Bread is a two-stage chain (§8) and the oven
##     alone cannot start it, which is not guessable from looking at an oven.
##   * One shelf. Storage runs out on the first delivery, goods heap up round
##     the benches and the kitchen starts to stall -- the failure that is
##     hardest to diagnose and so the most worth meeting early, while the tavern
##     is small enough to see it happen.
##   * No wash basin. Dishes accumulate on the tables and seats quietly stop
##     being seats.
##
## Four tables is enough to trade and not enough to grow, so expanding seating
## competes with fixing the three faults. That is the whole decision.
static func _the_wayfarers_rest() -> LevelDef:
	var level := LevelDef.new()
	level.id = &"wayfarers_rest"
	level.display_name = "The Wayfarer's Rest"
	level.tavern_name = "The Wayfarer's Rest"
	level.world_seed = 493774
	level.starting_gold = 260
	level.briefing = "Your aunt's roadside tavern, left to you as it stood. There is ale in the cellar and a fire in the grate, but she was not a tidy woman and the place has gaps in it. Find them before your custom does."
	# Measured at the ten-minute day with staff positions and doubled wages
	# (2026-09-28, dev/level_smoke.tscn): fixing all three faults at once
	# reaches 1918g by day 6, fixing them on day 3 1401g, and never fixing them
	# ends in debt at -124g. A player who finds the gaps within two days wins
	# with ~200g to spare -- the fixture restocks perfectly, a person will not
	# -- and one who only restocks cannot.
	# Re-measured after per-counter plating and the service scan (2026-09-28):
	# 1821g / 1229g / -124g. 1200 left a day-3 repairer 29g; 1100 leaves ~130g.
	# Bulk goods, auto restock and a crew of two waiters and a cook made the
	# repaired tavern far richer (2026-10-07): 4430g / 2659g / -80g, so 1100 was
	# met by day 3 and taught nothing. 2500 leaves a day-3 repairer ~160g, the
	# same margin the goal was first set to give.
	level.goal_gold = 2500
	level.goal_days = 6
	level.goal_text = "Take the tavern to 2500g by the end of day 6"

	var pieces: Array[LevelDef.Piece] = []
	# Near the road, whatever the plot's size: the new land is behind the
	# tavern, towards the river, and to the east.
	var o := Vector2i(7, 6 + TavernWorld.PLOT_SIZE.y - TavernWorld.LEVEL_AUTHORED_PLOT.y)
	level.origin = o

	# A floored room, walled, with a door onto the road.
	for y in range(9):
		for x in range(12):
			pieces.append(LevelDef.Piece.new("wood_floor", o + Vector2i(x, y)))
	for x in range(12):
		pieces.append(LevelDef.Piece.new("timber_wall", o + Vector2i(x, 0)))
		# The doorway faces the road the cart and the customers come up.
		if x == 6:
			pieces.append(LevelDef.Piece.new("door", o + Vector2i(x, 8)))
		else:
			pieces.append(LevelDef.Piece.new("timber_wall", o + Vector2i(x, 8)))
	for y in range(1, 8):
		pieces.append(LevelDef.Piece.new("timber_wall", o + Vector2i(0, y)))
		pieces.append(LevelDef.Piece.new("timber_wall", o + Vector2i(11, y)))

	# Four tables, which is enough to trade and not enough to grow.
	for spot in [Vector2i(2, 2), Vector2i(2, 5), Vector2i(6, 2), Vector2i(6, 5)]:
		pieces.append(LevelDef.Piece.new("table", o + spot))
		pieces.append(LevelDef.Piece.new("chair", o + spot + Vector2i(-1, 0)))
		pieces.append(LevelDef.Piece.new("chair", o + spot + Vector2i(2, 0)))

	# The kitchen your aunt left: a vat, an oven, and one shelf.
	pieces.append(LevelDef.Piece.new("brewing_vat", o + Vector2i(9, 1)))
	pieces.append(LevelDef.Piece.new("oven", o + Vector2i(9, 4)))
	pieces.append(LevelDef.Piece.new("storage_shelf", o + Vector2i(9, 6)))
	level.pieces = pieces

	# Enough to brew with from the first minute, and enough flour to make the
	# missing prep table obviously the problem rather than a mystery.
	# In bulk units: two brews (twenty beers) and a batch of dough (ten loaves).
	level.stock = {
		&"malt": 2,
		&"hops": 2,
		&"water": 4,
		&"flour": 1,
		&"yeast": 1,
		&"beer": 4,
	}
	return level
