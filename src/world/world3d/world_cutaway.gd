class_name WorldCutaway
extends RefCounted

## Presentation only: lower camera-facing walls, leaving the BuildGrid intact.
## Reusing each definition's MultiMesh preserves batching and opaque shadows.
var enabled: bool = true
var _elapsed: float = 0.0


func update(delta: float, build: BuildController, camera: Vector3, focus: Vector3) -> void:
	_elapsed += delta
	if _elapsed < 0.1 or build == null:
		return
	_elapsed = 0.0
	var view := Vector2(camera.x - focus.x, camera.z - focus.z).normalized()
	for piece in BuildingCatalog.all():
		if piece.shape != BuildingDef.Shape.WALL and piece.shape != BuildingDef.Shape.DOOR:
			continue
		# Each look (timber, stone) is its own batch, filled in the order the
		# builder lists that look's pieces.
		for def in BuildingCatalog.styles_of(piece):
			_cut(build, def, view, focus)


func _cut(build: BuildController, def: BuildingDef, view: Vector2, focus: Vector3) -> void:
	var instance: MultiMeshInstance3D = build._instances.get(BuildController.batch_key(def))
	if instance == null:
		return
	var entries: Array = build.batch_entries(def, true)
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var transform: Transform3D = build._placement_transform(def, entry["origin"], entry["rotation"])
		var size: Vector2i = def.rotated_size(entry["rotation"])
		var centre := Vector2(entry["origin"].x + size.x * 0.5, entry["origin"].y + size.y * 0.5)
		var near_side: bool = (centre - Vector2(focus.x, focus.z)).dot(view) > 0.5
		if enabled and near_side:
			transform.basis.y *= minf(0.42 / def.height, 1.0)
		if not instance.multimesh.get_instance_transform(i).is_equal_approx(transform):
			instance.multimesh.set_instance_transform(i, transform)
