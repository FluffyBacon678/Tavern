class_name Pawn
extends Node3D

## A person in the world: walks a path, idles, and can carry something.
##
## Deliberately generic. The design notes are explicit that workers and
## customers should be the same underlying entity with different behaviour on
## top, so nothing here knows what a cook or a waiter is. It exposes "go to this
## tile", "are you there yet", and "hold this" -- which is the whole surface the
## job system will need in M3.
##
## Movement is tile-to-tile but rendered continuously: the pawn interpolates
## between tile centres and turns to face the way it is going, so the grid never
## shows in the animation.

enum State { IDLE, WALKING }

## Tiles per second.
const MOVE_SPEED: float = 2.4
const TURN_SPEED: float = 9.0
## Radians of limb swing at full stride.
const SWING: float = 0.85
## How far the pawn walks through one full stride cycle, in tiles. Tying the
## cycle to distance rather than to time is what stops the feet skating when the
## pawn speeds up or slows down.
const STRIDE_LENGTH: float = 0.9

const IDLE_WANDER_MIN: float = 4.0
const IDLE_WANDER_MAX: float = 11.0
## How often an idle wander heads for a built floor rather than anywhere.
const IDLE_ON_FLOORS: float = 0.75

## How close two people get before they start giving each other room, and how
## far a body may be nudged from where it logically stands.
const SEPARATION_RADIUS: float = 0.62
const SEPARATION_MAX: float = 0.26
const SEPARATION_EASE: float = 6.0

## Everyone currently in the world, staff and patrons alike.
##
## A plain static list rather than a physics layer or an area query: separation
## here is cosmetic, the counts are in the dozens, and the alternative drags a
## whole collision system into a game whose movement is deliberately tile-based.
static var all: Array[Pawn] = []

const FIRST_NAMES: Array[String] = [
	"Anna", "Borin", "Erik", "Hilda", "Gerta", "Mattias", "Sigrun", "Tobias",
	"Ilse", "Rurik", "Magda", "Osric", "Brenna", "Halvar", "Petra", "Dagny",
]
const SURNAMES: Array[String] = [
	"Ironhand", "Fairbrook", "Stonewell", "Ashdown", "Mildmay", "Thornbury",
	"Greaves", "Blackmoor", "Wystan", "Holloway",
]

signal arrived(tile: Vector2i)
signal path_failed(target: Vector2i)

var pawn_name: String = ""
## What they are wearing, in words: "a mithril-clad warrior".
var look: String = ""
## Staff only: the cloth colour of their position, set before setup().
## Transparent means the plain house uniform.
var uniform: Color = Color(0, 0, 0, 0)
## Render context supplied by Worker; its existing saved role is authoritative.
var staff_role_id: StringName = &""
## Stored cosmetics, independent of role, habits and the customer's tastes.
var appearance: CharacterAppearance
var equipped: Dictionary = {}
var _pawn_material: Material
var state: int = State.IDLE
var tile := Vector2i.ZERO

var nav: NavGrid
var terrain: TerrainMeshBuilder
## Where this pawn wanders when it has nothing to do. An unemployed pawn
## standing perfectly still reads as broken.
var wander_area: Rect2i
## Cleared by a Worker while it has a job, so an idle wander cannot pull the
## pawn away from work it has already committed to.
var autonomous_idle: bool = true

var _rig: PawnMesh.Rig
## Behaviour archetype chosen once at spawn; wardrobe changes cannot alter it.
var adventurer: int = 0
var _is_customer: bool = false
var _bubble: ThoughtBubble


## The faint staff-or-guest outline, on or off.
func set_outline(on: bool) -> void:
	if _rig != null and _rig.body != null:
		_rig.body.material_overlay = PawnMesh.outline_material(_is_customer) if on else null


## What the bubble over their head shows: a ThoughtBubble icon, or "" for none.
func think(icon: String, urgent: bool = false) -> void:
	if _bubble != null:
		_bubble.show_icon(icon, urgent)
var _path: Array[Vector2i] = []
var _path_index: int = 0
var _move_from: Vector3
var _move_to: Vector3
var _move_t: float = 0.0
var _move_duration: float = 0.0
var _facing: float = 0.0
var _stride_phase: float = 0.0
var _idle_timer: float = 0.0
var _carried: Node3D = null
var _rng := RandomNumberGenerator.new()
## Cosmetic offset from the tile centre, so a crowd does not stack into one
## body. Never fed back into `tile` or pathing.
var _crowd_offset := Vector2.ZERO
var _floor_lift: float = 0.0


func _enter_tree() -> void:
	if not all.has(self):
		all.append(self)


func _exit_tree() -> void:
	all.erase(self)


func setup(p_nav: NavGrid, p_terrain: TerrainMeshBuilder, start_tile: Vector2i, material: Material, rng_seed: int, is_customer: bool = false) -> void:
	nav = p_nav
	terrain = p_terrain
	_rng.seed = rng_seed
	pawn_name = "%s %s" % [
		FIRST_NAMES[_rng.randi_range(0, FIRST_NAMES.size() - 1)],
		SURNAMES[_rng.randi_range(0, SURNAMES.size() - 1)],
	]

	_pawn_material = material
	appearance = PawnMesh.generate_appearance(_rng, is_customer, uniform)
	_rig = PawnMesh.build_appearance(appearance, material, equipped, staff_role_id)
	add_child(_rig.root)
	look = _rig.description
	adventurer = appearance.family
	_is_customer = is_customer
	set_outline(GameSettings.outline_people)
	_bubble = ThoughtBubble.new()
	_bubble.name = "Thought"
	add_child(_bubble)

	tile = start_tile
	position = world_position_of(start_tile)
	_facing = _rng.randf() * TAU
	_rig.root.rotation.y = _facing
	_reset_idle_timer()


## Replace only the body. Path, habits, cargo, name and behaviour survive;
## no call here consumes a random number or touches simulation state.
func set_appearance(next: CharacterAppearance, equipment: Variant = null) -> void:
	if next == null:
		return
	appearance = next.clone()
	if equipment is Dictionary:
		equipped = CharacterProfile.equipment_from_save(equipment)
	if _rig == null:
		return
	var previous: PawnMesh.Rig = _rig
	_rig = PawnMesh.build_appearance(appearance, _pawn_material, equipped, staff_role_id)
	add_child(_rig.root)
	_rig.root.transform = previous.root.transform
	var old_parts: Array[Node3D] = [previous.torso, previous.head, previous.arm_l,
		previous.arm_r, previous.leg_l, previous.leg_r]
	var new_parts: Array[Node3D] = [_rig.torso, _rig.head, _rig.arm_l,
		_rig.arm_r, _rig.leg_l, _rig.leg_r]
	for i in range(old_parts.size()):
		# Keep the animation offset, not the old body type's shoulder/hip
		# spacing. The new rig retains the matching mesh bind positions.
		new_parts[i].position += old_parts[i].position - previous.skeleton.get_bone_rest(i).origin
		new_parts[i].quaternion = old_parts[i].quaternion
	if is_instance_valid(_carried):
		_carried.reparent(_rig.carry_anchor, false)
	previous.root.queue_free()
	look = _rig.description
	set_outline(GameSettings.outline_people)
	_rig.sync_pose()


func set_staff_role(role_id: StringName) -> void:
	if staff_role_id == role_id:
		return
	staff_role_id = role_id
	if _rig != null and appearance != null:
		set_appearance(appearance)


func world_position_of(t: Vector2i) -> Vector3:
	var x: float = (float(t.x) + 0.5) * TerrainMeshBuilder.TILE
	var z: float = (float(t.y) + 0.5) * TerrainMeshBuilder.TILE
	return Vector3(x, terrain.sample_height(x, z), z)


## Walk to a tile. Returns false and emits path_failed if there is no route,
## so a caller can pick a different target rather than assuming success.
func goto(target: Vector2i) -> bool:
	var route: Array[Vector2i] = nav.find_path(tile, target)
	if route.is_empty():
		path_failed.emit(target)
		return false
	_path = route
	_path_index = 0
	state = State.WALKING
	_begin_step()
	return true


func stop() -> void:
	_path.clear()
	state = State.IDLE
	_reset_idle_timer()


func is_busy() -> bool:
	return state == State.WALKING


## Attach a node to the carry anchor. Passing null drops whatever is held.
func carry(item: Node3D) -> void:
	if _carried != null:
		_carried.queue_free()
		_carried = null
	if item == null:
		return
	_carried = item
	_rig.carry_anchor.add_child(item)


func is_carrying() -> bool:
	return _carried != null


func _begin_step() -> void:
	var next: Vector2i = _path[_path_index]
	_move_from = position
	_move_to = world_position_of(next)
	# Diagonal steps are longer, so time them by distance or the pawn visibly
	# speeds up when cutting corners.
	var horizontal: float = Vector2(_move_to.x - _move_from.x, _move_to.z - _move_from.z).length()
	# And by what is underfoot. A laid floor is quicker than a beaten path, and
	# a beaten path quicker than grass, which is what finally makes flooring
	# worth the gold it costs -- it was a third of the opening spend and bought
	# nothing but a colour before this.
	var going: float = nav.cost_at(next) if nav != null else 1.0
	_move_duration = maxf(horizontal * going / MOVE_SPEED, 0.0001)
	_move_t = 0.0


## Game time arrives here from the world's SimClock, in fixed steps, rather
## than per frame. The processing flag stays the switch that freezes one node --
## tests and letting staff go both use it -- and the summary's hold disables
## the node outright.
func _ready() -> void:
	set_process(true)


func sim_step(delta: float) -> void:
	if not is_processing() or not can_process():
		return
	match state:
		State.WALKING:
			_process_walk(delta)
		State.IDLE:
			_process_idle(delta)
	# Posing the body is for the eye, so it happens once per drawn frame, over
	# all the game time the frame covered. Done per step, at 5x it ran five
	# times for every frame anybody saw.
	_pending_anim += delta


## Game time not yet shown in the pose.
var _pending_anim: float = 0.0


func _process(_real_delta: float) -> void:
	if _pending_anim <= 0.0 or _rig == null:
		return
	_animate(minf(_pending_anim, 0.25))
	_pending_anim = 0.0


func _process_walk(delta: float) -> void:
	_move_t += delta / _move_duration
	if _move_t >= 1.0:
		# Land exactly on the tile centre, then take the next step. Carrying the
		# overshoot forward would drift the pawn off-grid over a long path.
		position = _move_to
		tile = _path[_path_index]
		_path_index += 1
		if _path_index >= _path.size():
			_path.clear()
			state = State.IDLE
			_reset_idle_timer()
			arrived.emit(tile)
			return
		_begin_step()
		return

	position = _move_from.lerp(_move_to, _move_t)
	# Ride the surface rather than interpolating height, so the pawn follows
	# slopes instead of cutting through them.
	position.y = terrain.sample_height(position.x, position.z)

	var dir := Vector2(_move_to.x - _move_from.x, _move_to.z - _move_from.z)
	if dir.length_squared() > 0.0001:
		_facing = atan2(dir.x, dir.y)
	_stride_phase += (delta / _move_duration) * TerrainMeshBuilder.TILE / STRIDE_LENGTH * PI


func _process_idle(delta: float) -> void:
	if not autonomous_idle or wander_area.size == Vector2i.ZERO:
		return
	_idle_timer -= delta
	if _idle_timer > 0.0:
		return
	_reset_idle_timer()
	# Mostly on a good floor, but not only: staff hang about the tavern, and
	# now and then step outside it.
	var target := Vector2i(-1, -1)
	if _rng.randf() < IDLE_ON_FLOORS:
		target = nav.random_floor_in(wander_area, _rng)
	if target == Vector2i(-1, -1):
		target = nav.random_walkable_in(wander_area, _rng)
	if target != Vector2i(-1, -1) and target != tile:
		goto(target)


func _reset_idle_timer() -> void:
	_idle_timer = _rng.randf_range(IDLE_WANDER_MIN, IDLE_WANDER_MAX)


## Shuffle sideways when someone is standing where you are.
##
## Deliberately cosmetic: it moves the *body*, never `tile` or the path. Real
## avoidance would mean re-pathing around other pawns, which in a tile game
## produces jitter and deadlocks at doorways for a problem that is purely
## visual — five people told to fetch from the same shelf genuinely are all
## going to the same tile, and should look like a queue rather than one person.
## Who is standing where, rebuilt once per frame and shared by every pawn:
## tile -> the pawns on it. Crowding asks its own tile and the eight round it
## instead of every pawn in the world, which grew with the square of the head
## count and was most of the frame in a big tavern.
static var _crowd_tiles: Dictionary = {}
static var _crowd_frame: int = -1


static func _crowd_near(at: Vector3) -> Array:
	var frame: int = Engine.get_process_frames()
	if frame != _crowd_frame:
		_crowd_frame = frame
		_crowd_tiles.clear()
		for pawn in all:
			if is_instance_valid(pawn):
				var key := Vector2i(floori(pawn.position.x), floori(pawn.position.z))
				if not _crowd_tiles.has(key):
					_crowd_tiles[key] = []
				_crowd_tiles[key].append(pawn)
	var out: Array = []
	var centre := Vector2i(floori(at.x), floori(at.z))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			out.append_array(_crowd_tiles.get(centre + Vector2i(dx, dy), []))
	return out


func _update_crowding(delta: float) -> void:
	var push := Vector2.ZERO
	for other in _crowd_near(position):
		if other == self or not is_instance_valid(other):
			continue
		var away := Vector2(position.x - other.position.x, position.z - other.position.z)
		var distance: float = away.length()
		if distance >= SEPARATION_RADIUS:
			continue
		if distance < 0.0001:
			# Exactly co-located: pick a deterministic direction from identity so
			# the pair separates instead of both jittering on the same axis.
			var a: float = float(get_instance_id() % 628) * 0.01
			push += Vector2(cos(a), sin(a))
			continue
		push += (away / distance) * (1.0 - distance / SEPARATION_RADIUS)

	if push.length() > 1.0:
		push = push.normalized()
	_crowd_offset = _crowd_offset.lerp(push * SEPARATION_MAX, minf(1.0, SEPARATION_EASE * delta))
	var support: float = 0.0
	if nav != null and nav._build != null:
		var underfoot := Vector2i(floori(position.x / TerrainMeshBuilder.TILE), floori(position.z / TerrainMeshBuilder.TILE))
		support = nav._build.visual_floor_height(underfoot)
	_floor_lift = lerpf(_floor_lift, support, minf(1.0, 12.0 * delta))
	_rig.root.position = Vector3(_crowd_offset.x, _floor_lift, _crowd_offset.y)


func _animate(delta: float) -> void:
	_update_crowding(delta)
	# Turn toward the facing direction rather than snapping, so corners read as
	# the pawn turning rather than teleporting to a new orientation.
	_rig.root.rotation.y = lerp_angle(_rig.root.rotation.y, _facing, minf(1.0, TURN_SPEED * delta))

	if state == State.WALKING:
		var swing: float = sin(_stride_phase) * SWING
		_rig.leg_l.rotation.x = swing
		_rig.leg_r.rotation.x = -swing
		# Arms counter-swing, and less than the legs. Carrying pins them forward
		# instead, which is what makes a hauling pawn read differently at a glance.
		if is_carrying():
			_rig.arm_l.rotation.x = -1.15
			_rig.arm_r.rotation.x = -1.15
		else:
			_rig.arm_l.rotation.x = -swing * 0.7
			_rig.arm_r.rotation.x = swing * 0.7
		# A slight bob at twice stride frequency, peaking mid-step.
		_rig.torso.position.y = PawnMesh.LEG_H + absf(sin(_stride_phase)) * 0.02
	else:
		var settle: float = minf(1.0, 8.0 * delta)
		_rig.leg_l.rotation.x = lerpf(_rig.leg_l.rotation.x, 0.0, settle)
		_rig.leg_r.rotation.x = lerpf(_rig.leg_r.rotation.x, 0.0, settle)
		var arm_rest: float = -1.15 if is_carrying() else 0.0
		_rig.arm_l.rotation.x = lerpf(_rig.arm_l.rotation.x, arm_rest, settle)
		_rig.arm_r.rotation.x = lerpf(_rig.arm_r.rotation.x, arm_rest, settle)
		_rig.torso.position.y = lerpf(_rig.torso.position.y, PawnMesh.LEG_H, settle)
	_rig.sync_pose()
