class_name CameraRig
extends Node3D

## Orbit camera with two modes, switchable at runtime.
##
## The mode switch exists because the choice between them is a real design
## decision that is much easier to make by looking than by arguing:
##
##   LOCKED   pitch fixed, yaw snapping to 45 degree steps. The management-sim
##            answer (Two Point Hospital, Prison Architect) -- consistent
##            readability, every object always presented the same way, and walls
##            can be occluded reliably because there are only eight views.
##   FREE     pitch and yaw dragged freely within limits. The RuneScape answer --
##            more immersive and better for looking at things up close, but the
##            player can always find an angle where the scene reads badly.
##
## Both share one focus point, distance and smoothing, so switching does not
## teleport the view.

enum Mode { LOCKED, FREE }

## Emitted when the camera starts or stops following someone, including when a
## pan takes the view back, so the inspector's Follow button can say which.
signal follow_changed(target: Node3D)

const YAW_SNAP_DEGREES: float = 45.0
const PITCH_LOCKED: float = 52.0
const PITCH_FREE_MIN: float = 14.0
const PITCH_FREE_MAX: float = 78.0
const DISTANCE_MIN: float = 6.0
const DISTANCE_MAX: float = 52.0
const PAN_SPEED: float = 14.0
const ZOOM_STEP: float = 0.12
## Higher converges faster. Smoothing is framerate-independent via exp decay.
const SMOOTHING: float = 12.0

signal mode_changed(mode: int)

@export var mode: int = Mode.LOCKED:
	set = set_mode

var camera: Camera3D
## Set by the world so the rig can keep the focus point on the ground and cast
## rays against the heightfield.
var terrain: TerrainMeshBuilder

var _focus := Vector3.ZERO
var _focus_target := Vector3.ZERO
var _yaw: float = 45.0
var _yaw_target: float = 45.0
var _pitch: float = PITCH_LOCKED
var _pitch_target: float = PITCH_LOCKED
var _distance: float = 26.0
var _distance_target: float = 26.0

var _orbiting: bool = false
var _panning: bool = false
## Active touches, so pinch and twist can be told apart from a one-finger pan.
## Somebody the view keeps centred on, or null. Any pan hands the view back to
## the player at once: a camera that fights the keys it is given is worse than
## no follow at all.
##
## Cleared the moment the followed node leaves the tree, not on the camera's
## next frame: in between, anything reading `follow` was handed a freed object,
## and the inspector's Follow button errored on exactly that.
var follow: Node3D = null:
	set(value):
		if follow == value:
			return
		if is_instance_valid(follow) and follow.tree_exiting.is_connected(_on_follow_leaving):
			follow.tree_exiting.disconnect(_on_follow_leaving)
		follow = value if is_instance_valid(value) else null
		if follow != null:
			follow.tree_exiting.connect(_on_follow_leaving, CONNECT_ONE_SHOT)
		follow_changed.emit(follow)

var _touches: Dictionary = {}
var _last_pinch_distance: float = 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.near = 0.1
	camera.far = 400.0
	add_child(camera)
	_apply_transform(true)


func set_mode(value: int) -> void:
	mode = value
	if mode == Mode.LOCKED:
		_pitch_target = PITCH_LOCKED
		# Snap to the nearest allowed step rather than swinging to a fixed yaw,
		# so switching modes keeps roughly the view the player already had.
		_yaw_target = round(_yaw_target / YAW_SNAP_DEGREES) * YAW_SNAP_DEGREES
	mode_changed.emit(mode)


func focus_on(point: Vector3) -> void:
	_focus_target = point
	_focus = point
	_apply_transform(true)


func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)
	if follow != null:
		if is_instance_valid(follow) and follow.is_inside_tree():
			_focus_target = follow.global_position
			_clamp_focus()
		else:
			follow = null

	# Exponential smoothing: frame-rate independent, unlike a raw lerp factor.
	var t: float = 1.0 - exp(-SMOOTHING * delta)
	_focus = _focus.lerp(_focus_target, t)
	_yaw = lerpf(_yaw, _yaw_target, t)
	_pitch = lerpf(_pitch, _pitch_target, t)
	_distance = lerpf(_distance, _distance_target, t)
	_apply_transform(false)


func _apply_transform(_immediate: bool) -> void:
	if camera == null:
		return
	var yaw_rad: float = deg_to_rad(_yaw)
	var pitch_rad: float = deg_to_rad(_pitch)
	var offset := Vector3(
		cos(pitch_rad) * sin(yaw_rad),
		sin(pitch_rad),
		cos(pitch_rad) * cos(yaw_rad)
	) * _distance
	camera.global_position = _focus + offset
	camera.look_at(_focus, Vector3.UP)


## How close to the window's edge the pointer must be to scroll, in pixels.
## Small, so the header's buttons a few pixels in never set the view moving.
const EDGE_MARGIN: float = 4.0

## Set while a menu is open over the game: no panning under the pause menu, and
## none while typing a tavern's name.
var locked: bool = false


func _handle_keyboard_pan(delta: float) -> void:
	if locked:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	# The game's own cam_* actions (KeyBindings), never the ui_* ones: those
	# drive Control focus navigation, and would move the view every time the
	# player arrows around a menu.
	var input := Vector2(
		Input.get_action_strength("cam_right") - Input.get_action_strength("cam_left"),
		Input.get_action_strength("cam_down") - Input.get_action_strength("cam_up"))
	if input == Vector2.ZERO and GameSettings.edge_scroll:
		input = _edge_input()
	if input == Vector2.ZERO:
		return
	# Pan relative to where the camera is looking, and scale with zoom so the
	# same keypress moves the same fraction of the screen at any distance.
	_pan(input * PAN_SPEED * GameSettings.camera_speed * delta * (_distance / 20.0))


## Which way the pointer at the window's edge asks the view to move.
func _edge_input() -> Vector2:
	if DisplayServer.get_name() == "headless" or not get_window().has_focus():
		return Vector2.ZERO
	var at: Vector2 = get_viewport().get_mouse_position()
	var size: Vector2 = get_viewport().get_visible_rect().size
	if at.x < 0.0 or at.y < 0.0 or at.x > size.x or at.y > size.y:
		return Vector2.ZERO
	var margin: float = EDGE_MARGIN * size.x / maxf(float(get_window().size.x), 1.0)
	return Vector2(
		float(at.x >= size.x - margin) - float(at.x <= margin),
		float(at.y >= size.y - margin) - float(at.y <= margin))


func _on_follow_leaving() -> void:
	follow = null


func _pan(amount: Vector2) -> void:
	follow = null
	var yaw_rad: float = deg_to_rad(_yaw)
	var forward := Vector3(-sin(yaw_rad), 0.0, -cos(yaw_rad))
	var right := Vector3(cos(yaw_rad), 0.0, -sin(yaw_rad))
	_focus_target += right * amount.x + forward * -amount.y
	_clamp_focus()


func _clamp_focus() -> void:
	if terrain == null or terrain.grid == null:
		return
	var max_x: float = float(terrain.grid.cols) * TerrainMeshBuilder.TILE
	var max_z: float = float(terrain.grid.rows) * TerrainMeshBuilder.TILE
	_focus_target.x = clampf(_focus_target.x, 0.0, max_x)
	_focus_target.z = clampf(_focus_target.z, 0.0, max_z)
	# Ride the terrain so the view does not sink into a hill or float over a valley.
	_focus_target.y = terrain.sample_height(_focus_target.x, _focus_target.z)


func zoom_by(steps: float) -> void:
	_distance_target = clampf(_distance_target * (1.0 + ZOOM_STEP * steps), DISTANCE_MIN, DISTANCE_MAX)


func orbit_by(delta_yaw: float, delta_pitch: float) -> void:
	if mode == Mode.LOCKED:
		return
	_yaw_target = fmod(_yaw_target + delta_yaw, 360.0)
	_pitch_target = clampf(_pitch_target + delta_pitch, PITCH_FREE_MIN, PITCH_FREE_MAX)


## Rotate a quarter turn. In locked mode this is the only way to turn, which is
## the point: eight fixed views instead of a continuum.
func rotate_step(direction: int) -> void:
	if mode == Mode.LOCKED:
		_yaw_target = round(_yaw_target / YAW_SNAP_DEGREES) * YAW_SNAP_DEGREES + YAW_SNAP_DEGREES * float(direction)
	else:
		_yaw_target += YAW_SNAP_DEGREES * float(direction)


func _unhandled_input(event: InputEvent) -> void:
	if locked:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("cam_turn_left"):
			rotate_step(-1)
		elif event.is_action_pressed("cam_turn_right"):
			rotate_step(1)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			zoom_by(-1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0)
		MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _orbiting:
		orbit_by(-event.relative.x * 0.3, event.relative.y * 0.25)
	elif _panning:
		_pan(Vector2(-event.relative.x, event.relative.y) * 0.035 * (_distance / 20.0))


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
	else:
		_touches.erase(event.index)
	# Reset the pinch baseline whenever the finger count changes, or the next
	# pinch delta is measured against a stale distance and the view jumps.
	_last_pinch_distance = 0.0


func _handle_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position

	if _touches.size() == 1:
		_pan(Vector2(-event.relative.x, event.relative.y) * 0.03 * (_distance / 20.0))
		return

	if _touches.size() >= 2:
		var points: Array = _touches.values()
		var d: float = points[0].distance_to(points[1])
		if _last_pinch_distance > 0.0:
			var diff: float = d - _last_pinch_distance
			zoom_by(-diff * 0.02)
			if mode == Mode.FREE:
				# Two-finger horizontal drag orbits, so free mode stays usable
				# without a right mouse button.
				orbit_by(-event.relative.x * 0.15, 0.0)
		_last_pinch_distance = d


## Ray-march the heightfield to find where a screen point meets the ground.
## Returns false if the ray leaves the map without hitting anything -- a plane
## intersection would happily return a point behind the camera or off the map.
func ground_point_at(screen_pos: Vector2, out: Array) -> bool:
	if camera == null or terrain == null:
		return false
	var origin: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	if dir.y >= -0.0001:
		return false  # pointing at or above the horizon

	var step: float = 0.35
	var travelled: float = 0.0
	var max_travel: float = DISTANCE_MAX * 3.0
	var prev: Vector3 = origin

	while travelled < max_travel:
		travelled += step
		var p: Vector3 = origin + dir * travelled
		if p.y <= terrain.sample_height(p.x, p.z):
			# Bisect between the last point above ground and this one below it.
			var lo: Vector3 = prev
			var hi: Vector3 = p
			for i in range(12):
				var mid: Vector3 = (lo + hi) * 0.5
				if mid.y <= terrain.sample_height(mid.x, mid.z):
					hi = mid
				else:
					lo = mid
			out.append((lo + hi) * 0.5)
			return true
		prev = p
		# Coarser steps further out; precision only matters near the hit.
		step = minf(step * 1.04, 1.5)
	return false
